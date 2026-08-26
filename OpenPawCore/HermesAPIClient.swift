import Foundation

public final class HermesAPIClient: AgentHarness, @unchecked Sendable {
    public static let sessionIDHeader = "X-Hermes-Session-Id"

    private let config: HermesConfig
    private let storeURL: URL
    private let pinnedID: String
    private var task: URLSessionDataTask?
    private let clearGate = BackgroundClearGate()

    public init(config: HermesConfig, storeURL: URL = PinnedSessionStore.defaultURL()) {
        self.config = config
        self.storeURL = storeURL
        self.pinnedID = PinnedSessionStore.hermesPinnedID
        var store = PinnedSessionStore.load(from: storeURL)
        if store.hermes != pinnedID {
            store.hermes = pinnedID
            try? store.save(to: storeURL)
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    public func resetSession() {}

    /// `{origin}/api/sessions/{id}` — strips a trailing `/v1` from the OpenAI base URL.
    public static func sessionDeleteURL(
        baseURL: String,
        sessionID: String = PinnedSessionStore.hermesPinnedID
    ) -> URL? {
        var base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1") {
            base = String(base.dropLast(3))
            base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return URL(string: base + "/api/sessions/\(sessionID)")
    }

    public static func completionsURL(baseURL: String) -> URL? {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
    }

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void = { _ in },
        onUsage: @escaping (Int) -> Void = { _ in }
    ) async throws -> StreamResult {
        await clearGate.awaitIfNeeded()

        guard let url = Self.completionsURL(baseURL: config.baseURL) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(pinnedID, forHTTPHeaderField: Self.sessionIDHeader)
        req.timeoutInterval = config.sseTimeoutSeconds

        let body: [String: Any] = [
            "model": config.model,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": try HermesSystemPrompt.withSystem(messages).map { try jsonObject($0) },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.sseTimeoutSeconds
        cfg.timeoutIntervalForResource = config.sseTimeoutSeconds

        defer { scheduleClear() }

        return try await withCheckedThrowingContinuation { cont in
            let delegate = StreamDelegate(
                onDelta: onDelta,
                onTool: onTool,
                onProgress: onProgress,
                onUsage: onUsage
            ) { result in
                cont.resume(with: result)
            }
            let s = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            let t = s.dataTask(with: req)
            self.task = t
            delegate.retainSession = s
            t.resume()
        }
    }

    private func scheduleClear() {
        let apiKey = config.apiKey
        guard let deleteURL = Self.sessionDeleteURL(baseURL: config.baseURL, sessionID: pinnedID) else { return }
        clearGate.schedule {
            var req = URLRequest(url: deleteURL)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 30
            // ponytail: fire-and-forget; 404 = already empty
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func jsonObject(_ msg: ChatMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(msg)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate {
    var retainSession: URLSession?
    private var buffer = ""
    private var text = ""
    private var reply = HermesReplyFilter()
    private var sawTool = false
    private var sseEvent: String?
    private var httpStatus: Int?
    private let onDelta: (String) -> Void
    private let onTool: (ToolCallDelta) -> Void
    private let onProgress: (String) -> Void
    private let onUsage: (Int) -> Void
    private let finish: (Result<StreamResult, Error>) -> Void
    private var finished = false

    init(
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void,
        onUsage: @escaping (Int) -> Void,
        finish: @escaping (Result<StreamResult, Error>) -> Void
    ) {
        self.onDelta = onDelta
        self.onTool = onTool
        self.onProgress = onProgress
        self.onUsage = onUsage
        self.finish = finish
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        httpStatus = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer += String(data: data, encoding: .utf8) ?? ""
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                sseEvent = nil
                continue
            }
            if trimmed.hasPrefix("event:") {
                sseEvent = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let ev = HermesSSEParser.parse(line: line, event: sseEvent) {
                if !ev.textDelta.isEmpty {
                    let shown = reply.push(ev.textDelta)
                    if !shown.isEmpty {
                        text += shown
                        onDelta(shown)
                    }
                }
                for t in ev.toolCalls {
                    sawTool = true
                    onTool(t)
                }
                if !ev.progress.isEmpty {
                    sawTool = true
                    onProgress(ev.progress)
                }
                if let tokens = ev.outputTokens {
                    onUsage(tokens)
                }
                if ev.finished {
                    emitFlush()
                    complete(.success(.init(text: text, sawToolEvents: sawTool)))
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            complete(.failure(error))
            return
        }
        if let status = httpStatus ?? (task.response as? HTTPURLResponse)?.statusCode,
           let httpErr = HermesHTTPError.parse(body: buffer, status: status) {
            complete(.failure(httpErr))
            return
        }
        emitFlush()
        complete(.success(.init(text: text, sawToolEvents: sawTool)))
    }

    private func emitFlush() {
        let rest = reply.flush()
        if !rest.isEmpty {
            text += rest
            onDelta(rest)
        }
    }

    private func complete(_ result: Result<StreamResult, Error>) {
        guard !finished else { return }
        finished = true
        finish(result)
        retainSession?.finishTasksAndInvalidate()
        retainSession = nil
    }
}

import Foundation

public final class HermesAPIClient: AgentHarness, @unchecked Sendable {
    private let config: HermesConfig
    private var task: URLSessionDataTask?

    public init(config: HermesConfig) {
        self.config = config
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void = { _ in }
    ) async throws -> StreamResult {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = config.sseTimeoutSeconds

        let body: [String: Any] = [
            "model": config.model,
            "stream": true,
            "messages": try HermesSystemPrompt.withSystem(messages).map { try jsonObject($0) },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.sseTimeoutSeconds
        cfg.timeoutIntervalForResource = config.sseTimeoutSeconds

        return try await withCheckedThrowingContinuation { cont in
            let delegate = StreamDelegate(onDelta: onDelta, onTool: onTool, onProgress: onProgress) { result in
                cont.resume(with: result)
            }
            let s = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            let t = s.dataTask(with: req)
            self.task = t
            delegate.retainSession = s
            t.resume()
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
    private let finish: (Result<StreamResult, Error>) -> Void
    private var finished = false

    init(
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void,
        finish: @escaping (Result<StreamResult, Error>) -> Void
    ) {
        self.onDelta = onDelta
        self.onTool = onTool
        self.onProgress = onProgress
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

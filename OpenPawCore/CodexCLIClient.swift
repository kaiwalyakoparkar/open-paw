import Foundation

public final class CodexCLIClient: AgentHarness, @unchecked Sendable {
    private let config: CLIHarnessConfig
    private let executable: URL
    private let storeURL: URL
    private var sessionID: String?
    private let workProc = CLIProcess()
    private let clearProc = CLIProcess()
    private let clearGate = BackgroundClearGate()
    private var sawPartial = false

    public init(config: CLIHarnessConfig, storeURL: URL = PinnedSessionStore.defaultURL()) throws {
        self.config = config
        self.storeURL = storeURL
        guard let url = CLIBinary.resolve(config.bin) else {
            throw AgentHarnessError.missingBinary(config.bin)
        }
        executable = url
        let store = PinnedSessionStore.load(from: storeURL)
        sessionID = store.codex.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func cancel() { workProc.cancel() }

    /// Pin survives sleep/cancel — clear is post-stream background.
    public func resetSession() {}

    public static func cliArgs(prompt: String, sessionID: String?, model: String? = nil) -> [String] {
        var args = ["exec"]
        if let sessionID {
            args += ["resume", sessionID]
        }
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        args.append("--json")
        if sessionID == nil {
            args.append("--skip-git-repo-check")
        }
        args.append(prompt)
        return args
    }

    public static func clearArgs(sessionID: String, model: String? = nil) -> [String] {
        cliArgs(prompt: "/clear", sessionID: sessionID, model: model)
    }

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void
    ) async throws -> StreamResult {
        await clearGate.awaitIfNeeded()

        let prompt = messages.lastUserText()
        guard !prompt.isEmpty else { throw AgentHarnessError.emptyPrompt }

        let args = Self.cliArgs(prompt: prompt, sessionID: sessionID, model: config.model)

        sawPartial = false
        var text = ""
        var sawTool = false
        var streamError: String?

        defer { scheduleClear() }

        let (status, stderr) = try await workProc.run(
            executable: executable,
            arguments: args,
            cwd: config.expandedCwd
        ) { [weak self] line in
            guard let self, let ev = CodexStreamParser.parse(line: line) else { return }
            if let sid = ev.sessionID {
                self.persistSessionID(sid)
            }
            if !ev.textDelta.isEmpty {
                if ev.isPartial {
                    self.sawPartial = true
                    text += ev.textDelta
                    onDelta(ev.textDelta)
                } else if !self.sawPartial {
                    text += ev.textDelta
                    onDelta(ev.textDelta)
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
            if let err = ev.errorMessage { streamError = err }
        }

        if let streamError { throw AgentHarnessError.processFailed(status: status, stderr: streamError) }
        if status != 0 && text.isEmpty {
            throw AgentHarnessError.processFailed(status: status, stderr: stderr)
        }
        return StreamResult(text: text, sawToolEvents: sawTool)
    }

    private func persistSessionID(_ sid: String) {
        guard sid != sessionID else { return }
        sessionID = sid
        var store = PinnedSessionStore.load(from: storeURL)
        store.codex = sid
        try? store.save(to: storeURL)
    }

    private func scheduleClear() {
        guard let sid = sessionID else { return }
        let cwd = config.expandedCwd
        let exe = executable
        clearGate.schedule { [weak self] in
            guard let self else { return }
            let args = Self.clearArgs(sessionID: sid, model: self.config.model)
            _ = try? await self.clearProc.run(
                executable: exe,
                arguments: args,
                cwd: cwd
            ) { line in
                guard let ev = CodexStreamParser.parse(line: line), let newID = ev.sessionID else { return }
                if newID != sid {
                    self.persistSessionID(newID)
                }
            }
        }
    }
}

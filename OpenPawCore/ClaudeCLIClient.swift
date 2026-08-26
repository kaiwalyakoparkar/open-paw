import Foundation

public final class ClaudeCLIClient: AgentHarness, @unchecked Sendable {
    private let config: CLIHarnessConfig
    private let executable: URL
    private let storeURL: URL
    private var sessionID: String
    /// True when a transcript exists for the pin (use --resume). False → --session-id create.
    private var knownExists: Bool
    private let workProc = CLIProcess()
    private let clearGate = BackgroundClearGate()
    private var sawPartial = false

    public init(config: CLIHarnessConfig, storeURL: URL = PinnedSessionStore.defaultURL()) throws {
        self.config = config
        self.storeURL = storeURL
        guard let url = CLIBinary.resolve(config.bin) else {
            throw AgentHarnessError.missingBinary(config.bin)
        }
        executable = url
        var store = PinnedSessionStore.load(from: storeURL)
        if let existing = store.claude, !existing.isEmpty {
            sessionID = existing
            knownExists = ClaudeSessionFiles.transcriptExists(cwd: config.expandedCwd, sessionID: existing)
        } else {
            sessionID = UUID().uuidString.lowercased()
            knownExists = false
            store.claude = sessionID
            try? store.save(to: storeURL)
        }
    }

    public func cancel() { workProc.cancel() }

    /// Pin survives sleep/cancel — clear is post-stream transcript wipe.
    public func resetSession() {}

    // ponytail: Claude -p + stream-json rejects without --verbose
    // Claude forbids --session-id with --resume unless --fork-session (new ID).
    // Create: --session-id only. Continue: --resume only. Never /clear (forks a new session).
    public static func cliArgs(
        prompt: String,
        permissionMode: String,
        pinnedID: String,
        resume: Bool,
        addDir: String,
        name: String = PinnedSessionStore.claudeDisplayName,
        model: String? = nil
    ) -> [String] {
        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", permissionMode,
            "-n", name,
        ]
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if resume {
            args += ["--resume", pinnedID]
        } else {
            args += ["--session-id", pinnedID]
        }
        args += ["--add-dir", addDir]
        return args
    }

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void,
        onUsage: @escaping (Int) -> Void
    ) async throws -> StreamResult {
        await clearGate.awaitIfNeeded()

        let prompt = messages.lastUserText()
        guard !prompt.isEmpty else { throw AgentHarnessError.emptyPrompt }

        // After a wipe, recreate with the same --session-id; if transcript still there, resume.
        knownExists = ClaudeSessionFiles.transcriptExists(cwd: config.expandedCwd, sessionID: sessionID)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("open-paw", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let args = Self.cliArgs(
            prompt: prompt,
            permissionMode: config.permissionMode,
            pinnedID: sessionID,
            resume: knownExists,
            addDir: tmp.path,
            model: config.model
        )

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
            guard let self, let ev = ClaudeStreamParser.parse(line: line) else { return }
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
            if let tokens = ev.outputTokens {
                // Skip bare message_delta usage — the following assistant snapshot repeats it.
                let bareUsage = ev.textDelta.isEmpty && ev.toolCalls.isEmpty
                    && ev.progress.isEmpty && !ev.finished
                if !bareUsage {
                    onUsage(tokens)
                }
            }
            if let err = ev.errorMessage { streamError = err }
        }

        knownExists = true
        if let streamError { throw AgentHarnessError.processFailed(status: status, stderr: streamError) }
        if status != 0 && text.isEmpty {
            throw AgentHarnessError.processFailed(status: status, stderr: stderr)
        }
        return StreamResult(text: text, sawToolEvents: sawTool)
    }

    private func persistSessionID(_ sid: String) {
        guard sid != sessionID else {
            knownExists = true
            return
        }
        // Keep the pin stable. If Claude somehow emits a different id, still record it —
        // but prefer the store pin when wiping.
        sessionID = sid
        knownExists = true
        var store = PinnedSessionStore.load(from: storeURL)
        store.claude = sid
        try? store.save(to: storeURL)
    }

    private func scheduleClear() {
        let sid = sessionID
        let cwd = config.expandedCwd
        clearGate.schedule { [weak self] in
            // Wipe transcript in place — do NOT run claude -p /clear (that forks a new session).
            ClaudeSessionFiles.wipe(cwd: cwd, sessionID: sid)
            self?.knownExists = false
        }
    }
}

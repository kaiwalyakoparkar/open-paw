import Foundation

public final class ClaudeCLIClient: AgentHarness, @unchecked Sendable {
    private let config: CLIHarnessConfig
    private let executable: URL
    private var sessionID: String?
    private let proc = CLIProcess()
    private var sawPartial = false

    public init(config: CLIHarnessConfig) throws {
        self.config = config
        guard let url = CLIBinary.resolve(config.bin) else {
            throw AgentHarnessError.missingBinary(config.bin)
        }
        executable = url
    }

    public func cancel() { proc.cancel() }

    public func resetSession() { sessionID = nil }

    // ponytail: Claude -p + stream-json rejects without --verbose
    public static func cliArgs(
        prompt: String,
        permissionMode: String,
        sessionID: String?,
        addDir: String
    ) -> [String] {
        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", permissionMode,
        ]
        if let sessionID {
            args += ["--resume", sessionID]
        }
        args += ["--add-dir", addDir]
        return args
    }

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void
    ) async throws -> StreamResult {
        let prompt = messages.lastUserText()
        guard !prompt.isEmpty else { throw AgentHarnessError.emptyPrompt }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("open-paw", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let args = Self.cliArgs(
            prompt: prompt,
            permissionMode: config.permissionMode,
            sessionID: sessionID,
            addDir: tmp.path
        )

        sawPartial = false
        var text = ""
        var sawTool = false
        var streamError: String?

        let (status, stderr) = try await proc.run(
            executable: executable,
            arguments: args,
            cwd: config.expandedCwd
        ) { line in
            guard let ev = ClaudeStreamParser.parse(line: line) else { return }
            if let sid = ev.sessionID { self.sessionID = sid }
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
}

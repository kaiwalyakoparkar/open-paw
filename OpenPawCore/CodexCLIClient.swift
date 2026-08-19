import Foundation

public final class CodexCLIClient: AgentHarness, @unchecked Sendable {
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

    public func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void
    ) async throws -> StreamResult {
        let prompt = messages.lastUserText()
        guard !prompt.isEmpty else { throw AgentHarnessError.emptyPrompt }

        var args: [String]
        if let sessionID {
            args = ["exec", "resume", sessionID, "--json", prompt]
        } else {
            args = ["exec", "--json", "--skip-git-repo-check", prompt]
        }

        sawPartial = false
        var text = ""
        var sawTool = false
        var streamError: String?

        let (status, stderr) = try await proc.run(
            executable: executable,
            arguments: args,
            cwd: config.expandedCwd
        ) { line in
            guard let ev = CodexStreamParser.parse(line: line) else { return }
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

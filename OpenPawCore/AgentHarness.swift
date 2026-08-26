import Foundation

public struct StreamResult: Equatable {
    public var text: String
    public var sawToolEvents: Bool

    public init(text: String, sawToolEvents: Bool) {
        self.text = text
        self.sawToolEvents = sawToolEvents
    }
}

public protocol AgentHarness: AnyObject {
    func cancel()
    func resetSession()
    func stream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onTool: @escaping (ToolCallDelta) -> Void,
        onProgress: @escaping (String) -> Void,
        onUsage: @escaping (Int) -> Void
    ) async throws -> StreamResult
}

extension AgentHarness {
    public func resetSession() {}
}

public enum AgentHarnessError: Error, LocalizedError {
    case missingBinary(String)
    case emptyPrompt
    case processFailed(status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .missingBinary(let name):
            return "\(name) not found — install it or set bin in ~/.config/open-paw/config.json"
        case .emptyPrompt:
            return "Empty prompt"
        case .processFailed(let status, let stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty { return "Agent exited \(status)" }
            return "Agent exited \(status): \(tail)"
        }
    }
}

public enum AgentHarnessFactory {
    public static func make(config: AppConfig) throws -> AgentHarness {
        switch config.harness {
        case .hermes:
            return HermesAPIClient(config: config.hermes)
        case .claude:
            return try ClaudeCLIClient(config: config.claude)
        case .codex:
            return try CodexCLIClient(config: config.codex)
        }
    }
}

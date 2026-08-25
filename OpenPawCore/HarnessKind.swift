import Foundation

public enum HarnessKind: String, Codable, Equatable {
    case hermes
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .hermes: return "Hermes"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Last `--claude` / `--codex` / `--hermes` wins. Nil if none present.
    public static func fromArgv(_ args: [String]) -> HarnessKind? {
        ProcessArgv.parse(args).harness
    }
}

/// Process-only overrides. Last flag wins.
public struct ProcessArgv: Equatable {
    public var harness: HarnessKind?
    public var model: String?

    public init(harness: HarnessKind? = nil, model: String? = nil) {
        self.harness = harness
        self.model = model
    }

    public static func parse(_ args: [String]) -> ProcessArgv {
        var found = ProcessArgv()
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--claude": found.harness = .claude
            case "--codex": found.harness = .codex
            case "--hermes": found.harness = .hermes
            case "--opus": found.harness = .claude; found.model = "opus"
            case "--sonnet": found.harness = .claude; found.model = "sonnet"
            case "--haiku": found.harness = .claude; found.model = "haiku"
            case "--fable": found.harness = .claude; found.model = "fable"
            case "--sol": found.harness = .codex; found.model = "gpt-5.6-sol"
            case "--terra": found.harness = .codex; found.model = "gpt-5.6-terra"
            case "--luna": found.harness = .codex; found.model = "gpt-5.6-luna"
            case "--model":
                let n = i + 1
                if n < args.count, !args[n].hasPrefix("-") {
                    found.model = args[n]
                    i = n
                }
            default:
                if a.hasPrefix("--model="), a.count > 8 {
                    found.model = String(a.dropFirst(8))
                }
            }
            i += 1
        }
        return found
    }

    public func apply(to config: inout AppConfig) {
        if let harness { config.harness = harness }
        guard let model else { return }
        switch config.harness {
        case .claude: config.claude.model = model
        case .codex: config.codex.model = model
        case .hermes: config.hermes.model = model
        }
    }
}

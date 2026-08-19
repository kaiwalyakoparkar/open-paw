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
        var found: HarnessKind?
        for a in args {
            switch a {
            case "--claude": found = .claude
            case "--codex": found = .codex
            case "--hermes": found = .hermes
            default: break
            }
        }
        return found
    }
}

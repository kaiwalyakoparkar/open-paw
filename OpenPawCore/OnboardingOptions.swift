import Foundation

/// Pure pick lists + apply for first-run setup. No AppKit.
public struct OnboardingDraft: Equatable {
    public var harness: HarnessKind
    /// Empty string → CLI default (`nil` model) for claude/codex.
    public var model: String
    public var gradiumApiKey: String
    public var hermesApiKey: String
    public var permissionMode: String
    public var holdKey: String
    public var cwd: String
    public var buddyPosition: String

    public init(
        harness: HarnessKind = .hermes,
        model: String = "hermes-agent",
        gradiumApiKey: String = "",
        hermesApiKey: String = "change-me-local-dev",
        permissionMode: String = "acceptEdits",
        holdKey: String = OnboardingOptions.recommendedHoldKey,
        cwd: String = "~",
        buddyPosition: String = "bottom-right"
    ) {
        self.harness = harness
        self.model = model
        self.gradiumApiKey = gradiumApiKey
        self.hermesApiKey = hermesApiKey
        self.permissionMode = permissionMode
        self.holdKey = holdKey
        self.cwd = cwd
        self.buddyPosition = buddyPosition
    }

    public static func from(config: AppConfig) -> OnboardingDraft {
        let model: String
        switch config.harness {
        case .hermes: model = config.hermes.model
        case .claude: model = config.claude.model ?? ""
        case .codex: model = config.codex.model ?? ""
        }
        return OnboardingDraft(
            harness: config.harness,
            model: model,
            gradiumApiKey: config.gradium.apiKey,
            hermesApiKey: config.hermes.apiKey,
            permissionMode: config.claude.permissionMode,
            holdKey: config.hotkey.hold.key,
            cwd: config.harness == .codex ? config.codex.cwd : config.claude.cwd,
            buddyPosition: config.ui.defaultPosition
        )
    }

    public func apply(to config: inout AppConfig) {
        config.harness = harness
        config.gradium.apiKey = gradiumApiKey
        config.hotkey.hold = KeyCombo(modifiers: [], key: holdKey)
        config.ui.defaultPosition = buddyPosition
        switch harness {
        case .hermes:
            config.hermes.apiKey = hermesApiKey
            config.hermes.model = model.isEmpty ? "hermes-agent" : model
        case .claude:
            config.claude.model = model.isEmpty ? nil : model
            config.claude.permissionMode = permissionMode
            config.claude.cwd = cwd.isEmpty ? "~" : cwd
        case .codex:
            config.codex.model = model.isEmpty ? nil : model
            config.codex.cwd = cwd.isEmpty ? "~" : cwd
        }
        config.onboarded = true
    }
}

public enum OnboardingOptions {
    public static let recommendedHoldKey = "right_option"

    public struct HoldOption: Equatable {
        public let key: String
        public let label: String
        public let recommended: Bool
    }

    public static let holdOptions: [HoldOption] = [
        HoldOption(key: "right_option", label: "Right Option (⌥)", recommended: true),
        HoldOption(key: "left_option", label: "Left Option (⌥)", recommended: false),
        HoldOption(key: "fn", label: "Fn", recommended: false),
    ]

    public static let positions: [(id: String, label: String)] = [
        ("bottom-left", "Bottom left"),
        ("bottom-center", "Bottom center"),
        ("bottom-right", "Bottom right"),
    ]

    public static let permissionModes: [(id: String, label: String)] = [
        ("acceptEdits", "Accept edits"),
        ("bypassPermissions", "Bypass permissions (YOLO)"),
    ]

    /// First entry empty = CLI default for claude/codex.
    public static func models(for harness: HarnessKind) -> [(id: String, label: String)] {
        switch harness {
        case .hermes:
            return [("hermes-agent", "hermes-agent")]
        case .claude:
            return [
                ("", "CLI default"),
                ("opus", "opus"),
                ("sonnet", "sonnet"),
                ("haiku", "haiku"),
                ("fable", "fable"),
            ]
        case .codex:
            return [
                ("", "CLI default"),
                ("gpt-5.6-sol", "gpt-5.6-sol"),
                ("gpt-5.6-terra", "gpt-5.6-terra"),
                ("gpt-5.6-luna", "gpt-5.6-luna"),
            ]
        }
    }

    public static func defaultModel(for harness: HarnessKind) -> String {
        switch harness {
        case .hermes: return "hermes-agent"
        case .claude, .codex: return ""
        }
    }
}

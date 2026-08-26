import CoreGraphics
import Foundation

public struct AppConfig: Codable, Equatable {
    public var gradium: GradiumConfig
    public var hermes: HermesConfig
    public var hotkey: HotkeyConfig
    public var ui: UIConfig
    public var harness: HarnessKind
    public var claude: CLIHarnessConfig
    public var codex: CLIHarnessConfig
    /// False until first-run setup Continue; missing key in JSON → true (legacy installs).
    public var onboarded: Bool

    public init(
        gradium: GradiumConfig,
        hermes: HermesConfig,
        hotkey: HotkeyConfig,
        ui: UIConfig,
        harness: HarnessKind = .hermes,
        claude: CLIHarnessConfig = .claudeDefault,
        codex: CLIHarnessConfig = .codexDefault,
        onboarded: Bool = true
    ) {
        self.gradium = gradium
        self.hermes = hermes
        self.hotkey = hotkey
        self.ui = ui
        self.harness = harness
        self.claude = claude
        self.codex = codex
        self.onboarded = onboarded
    }

    enum CodingKeys: String, CodingKey {
        case gradium, hermes, hotkey, ui, harness, claude, codex, onboarded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gradium = try c.decode(GradiumConfig.self, forKey: .gradium)
        hermes = try c.decode(HermesConfig.self, forKey: .hermes)
        hotkey = try c.decode(HotkeyConfig.self, forKey: .hotkey)
        ui = try c.decode(UIConfig.self, forKey: .ui)
        harness = try c.decodeIfPresent(HarnessKind.self, forKey: .harness) ?? .hermes
        claude = (try c.decodeIfPresent(CLIHarnessConfig.self, forKey: .claude) ?? .claudeDefault)
            .filled(defaultBin: "claude")
        codex = (try c.decodeIfPresent(CLIHarnessConfig.self, forKey: .codex) ?? .codexDefault)
            .filled(defaultBin: "codex")
        // Missing key → already configured by hand (INSTALL copy).
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? true
    }

    public static func load(from url: URL = defaultURL()) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        var cfg = try JSONDecoder().decode(AppConfig.self, from: data)
        cfg.resolveSecretsFromEnvIfEmpty()
        return cfg
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/open-paw/config.json")
    }

    public static func needsOnboarding(_ config: AppConfig, argv: ProcessArgv = ProcessArgv()) -> Bool {
        argv.onboard || !config.onboarded
    }

    public func save(to url: URL = defaultURL()) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public mutating func resolveSecretsFromEnvIfEmpty() {
        if gradium.apiKey.isEmpty, let env = ProcessInfo.processInfo.environment["GRADIUM_API_KEY"] {
            gradium.apiKey = env
        }
        if hermes.apiKey.isEmpty, let env = ProcessInfo.processInfo.environment["HERMES_API_KEY"] {
            hermes.apiKey = env
        }
    }
}

public struct GradiumConfig: Codable, Equatable {
    public var apiKey: String
    public var stt: STTConfig
    public var tts: TTSConfig

    public init(apiKey: String, stt: STTConfig, tts: TTSConfig) {
        self.apiKey = apiKey
        self.stt = stt
        self.tts = tts
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case stt, tts
    }
}

public struct STTConfig: Codable, Equatable {
    public var modelName: String
    public var delayInFrames: Int
    public var vadHorizonIndex: Int
    public var vadThreshold: Double
    public var vadConsecutiveFrames: Int

    public init(
        modelName: String,
        delayInFrames: Int,
        vadHorizonIndex: Int,
        vadThreshold: Double,
        vadConsecutiveFrames: Int
    ) {
        self.modelName = modelName
        self.delayInFrames = delayInFrames
        self.vadHorizonIndex = vadHorizonIndex
        self.vadThreshold = vadThreshold
        self.vadConsecutiveFrames = vadConsecutiveFrames
    }

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case delayInFrames = "delay_in_frames"
        case vadHorizonIndex = "vad_horizon_index"
        case vadThreshold = "vad_threshold"
        case vadConsecutiveFrames = "vad_consecutive_frames"
    }
}

public struct TTSConfig: Codable, Equatable {
    public var voiceId: String
    public var outputFormat: String

    public init(voiceId: String, outputFormat: String) {
        self.voiceId = voiceId
        self.outputFormat = outputFormat
    }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case outputFormat = "output_format"
    }
}

public struct CLIHarnessConfig: Codable, Equatable {
    public var bin: String
    public var cwd: String
    public var permissionMode: String
    /// Nil → harness CLI default. Claude aliases: opus/sonnet/haiku/fable. Codex: gpt-5.6-sol/terra/luna.
    public var model: String?

    public static let claudeDefault = CLIHarnessConfig(bin: "claude", cwd: "~", permissionMode: "acceptEdits")
    public static let codexDefault = CLIHarnessConfig(bin: "codex", cwd: "~", permissionMode: "acceptEdits")

    public init(bin: String, cwd: String, permissionMode: String, model: String? = nil) {
        self.bin = bin
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case bin, cwd, model
        case permissionMode = "permission_mode"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bin = try c.decodeIfPresent(String.self, forKey: .bin) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? "~"
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? "acceptEdits"
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }

    func filled(defaultBin: String) -> CLIHarnessConfig {
        var copy = self
        if copy.bin.isEmpty { copy.bin = defaultBin }
        return copy
    }

    public var expandedCwd: URL {
        URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath, isDirectory: true)
    }
}

public struct HermesConfig: Codable, Equatable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var sseTimeoutSeconds: TimeInterval

    public init(baseURL: String, apiKey: String, model: String, sseTimeoutSeconds: TimeInterval) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.sseTimeoutSeconds = sseTimeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKey = "api_key"
        case model
        case sseTimeoutSeconds = "sse_timeout_seconds"
    }
}

public struct HotkeyConfig: Codable, Equatable {
    public var hold: KeyCombo
    /// Legacy toggle hotkey; ignored when hold is configured.
    public var toggle: KeyCombo?

    public init(hold: KeyCombo, toggle: KeyCombo? = nil) {
        self.hold = hold
        self.toggle = toggle
    }

    enum CodingKeys: String, CodingKey {
        case hold, toggle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hold = try c.decodeIfPresent(KeyCombo.self, forKey: .hold)
            ?? KeyCombo(modifiers: [], key: "right_option")
        toggle = try c.decodeIfPresent(KeyCombo.self, forKey: .toggle)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hold, forKey: .hold)
        try c.encodeIfPresent(toggle, forKey: .toggle)
    }
}

public struct KeyCombo: Codable, Equatable {
    public var modifiers: [String]
    public var key: String
    public init(modifiers: [String], key: String) {
        self.modifiers = modifiers
        self.key = key
    }
}

public struct UIConfig: Codable, Equatable {
    public var buddySize: CGFloat
    public var defaultPosition: String
    public var idleTimeoutSeconds: TimeInterval

    public init(buddySize: CGFloat, defaultPosition: String, idleTimeoutSeconds: TimeInterval) {
        self.buddySize = buddySize
        self.defaultPosition = defaultPosition
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case buddySize = "buddy_size"
        case defaultPosition = "default_position"
        case idleTimeoutSeconds = "idle_timeout_seconds"
    }
}

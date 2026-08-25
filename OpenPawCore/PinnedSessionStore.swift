import Foundation

/// Persists one session ID per harness under ~/.config/open-paw/sessions.json.
public struct PinnedSessionStore: Equatable, Codable {
    public var claude: String?
    public var hermes: String?
    public var codex: String?

    public init(claude: String? = nil, hermes: String? = nil, codex: String? = nil) {
        self.claude = claude
        self.hermes = hermes
        self.codex = codex
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/open-paw/sessions.json")
    }

    public static func load(from url: URL = defaultURL()) -> PinnedSessionStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(PinnedSessionStore.self, from: data)
        else { return PinnedSessionStore() }
        return store
    }

    public func save(to url: URL = defaultURL()) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static let hermesPinnedID = "open-paw"
    public static let claudeDisplayName = "Open Paw"
}

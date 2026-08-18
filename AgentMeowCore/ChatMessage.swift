import Foundation

public struct ChatMessage: Codable, Equatable {
    public var role: String
    public var content: ChatContent

    public init(role: String, content: ChatContent) {
        self.role = role
        self.content = content
    }

    public static func text(role: String, _ text: String) -> ChatMessage {
        ChatMessage(role: role, content: .string(text))
    }
}

public enum ChatContent: Equatable {
    case string(String)
    case parts([ContentPart])
}

public struct ContentPart: Codable, Equatable {
    public var type: String
    public var text: String?
    public var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    public struct ImageURL: Codable, Equatable {
        public var url: String
        public init(url: String) { self.url = url }
    }

    public static func text(_ s: String) -> ContentPart {
        ContentPart(type: "text", text: s, imageURL: nil)
    }

    public static func imageURL(_ url: String) -> ContentPart {
        ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: url))
    }
}

extension ChatContent: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        self = .parts(try c.decode([ContentPart].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .parts(let p): try c.encode(p)
        }
    }
}

public struct ToolCallDelta: Equatable {
    public var index: Int
    public var id: String?
    public var name: String?
    public var arguments: String

    public init(index: Int, id: String?, name: String?, arguments: String) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

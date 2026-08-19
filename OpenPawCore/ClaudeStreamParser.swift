import Foundation

public struct CLIStreamEvent: Equatable {
    public var textDelta: String
    public var toolCalls: [ToolCallDelta]
    public var progress: String
    public var sessionID: String?
    public var finished: Bool
    public var isPartial: Bool
    public var errorMessage: String?

    public init(
        textDelta: String = "",
        toolCalls: [ToolCallDelta] = [],
        progress: String = "",
        sessionID: String? = nil,
        finished: Bool = false,
        isPartial: Bool = false,
        errorMessage: String? = nil
    ) {
        self.textDelta = textDelta
        self.toolCalls = toolCalls
        self.progress = progress
        self.sessionID = sessionID
        self.finished = finished
        self.isPartial = isPartial
        self.errorMessage = errorMessage
    }

    var isEmpty: Bool {
        textDelta.isEmpty && toolCalls.isEmpty && progress.isEmpty && sessionID == nil
            && !finished && errorMessage == nil
    }
}

public enum ClaudeStreamParser {
    public static func parse(line: String) -> CLIStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parseObject(obj)
    }

    private static func parseObject(_ obj: [String: Any]) -> CLIStreamEvent? {
        if let event = obj["event"] as? [String: Any], obj["type"] as? String == "stream_event" {
            return parseObject(event)
        }
        let type = obj["type"] as? String ?? ""
        let session = obj["session_id"] as? String
        switch type {
        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any] else { return nil }
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                return CLIStreamEvent(textDelta: text, sessionID: session, isPartial: true)
            }
            return nil
        case "assistant":
            return parseAssistant(obj, session: session)
        case "result":
            let err = obj["is_error"] as? Bool == true
            let resultText = obj["result"] as? String
            return CLIStreamEvent(
                sessionID: session,
                finished: true,
                errorMessage: err ? (resultText ?? "error") : nil
            )
        default:
            if let content = obj["content"] as? [[String: Any]] {
                return parseAssistant(obj, session: session, content: content)
            }
            return nil
        }
    }

    private static func parseAssistant(
        _ obj: [String: Any],
        session: String?,
        content: [[String: Any]]? = nil
    ) -> CLIStreamEvent? {
        let blocks = content
            ?? (obj["message"] as? [String: Any]).flatMap { $0["content"] as? [[String: Any]] }
            ?? []
        var text = ""
        var tools: [ToolCallDelta] = []
        var progress = ""
        for (i, block) in blocks.enumerated() {
            let t = block["type"] as? String ?? ""
            if t == "text", let s = block["text"] as? String {
                text += s
            } else if t == "tool_use" {
                let name = block["name"] as? String
                tools.append(ToolCallDelta(index: i, id: block["id"] as? String, name: name, arguments: ""))
                if let name { progress = name }
            }
        }
        let ev = CLIStreamEvent(
            textDelta: text,
            toolCalls: tools,
            progress: progress,
            sessionID: session,
            isPartial: false
        )
        return ev.isEmpty ? nil : ev
    }
}

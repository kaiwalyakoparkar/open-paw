import Foundation

public enum CodexStreamParser {
    public static func parse(line: String) -> CLIStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let type = obj["type"] as? String ?? ""
        let thread = obj["thread_id"] as? String
        switch type {
        case "thread.started":
            return thread.map { CLIStreamEvent(sessionID: $0) }
        case "item.delta":
            return parseDelta(obj, session: thread)
        case "item.completed":
            return parseItem(obj["item"] as? [String: Any], session: thread, finished: false)
        case "agent_message":
            if let text = obj["text"] as? String ?? obj["message"] as? String, !text.isEmpty {
                return CLIStreamEvent(textDelta: text, sessionID: thread)
            }
            return nil
        case "turn.completed", "turn.failed":
            let err = type == "turn.failed" ? (Self.errorMessage(obj["error"]) ?? "turn failed") : nil
            return CLIStreamEvent(sessionID: thread, finished: true, errorMessage: err)
        case "error":
            let msg = Self.errorMessage(obj["message"] ?? obj["error"]) ?? "error"
            return CLIStreamEvent(sessionID: thread, finished: true, errorMessage: msg)
        default:
            return parseItem(obj["item"] as? [String: Any], session: thread, finished: false)
        }
    }

    private static func errorMessage(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let obj = value as? [String: Any] {
            if let s = obj["message"] as? String, !s.isEmpty { return s }
            if let s = obj["error"] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func parseDelta(_ obj: [String: Any], session: String?) -> CLIStreamEvent? {
        let delta = obj["delta"] as? [String: Any] ?? obj
        if let text = delta["text"] as? String, !text.isEmpty {
            return CLIStreamEvent(textDelta: text, sessionID: session, isPartial: true)
        }
        return nil
    }

    private static func parseItem(_ item: [String: Any]?, session: String?, finished: Bool) -> CLIStreamEvent? {
        guard let item else { return nil }
        let kind = item["type"] as? String ?? ""
        if kind == "agent_message" || kind == "message" {
            let text = item["text"] as? String ?? item["content"] as? String ?? ""
            return CLIStreamEvent(textDelta: text, sessionID: session, finished: finished, isPartial: false)
        }
        if kind.contains("mcp") || kind.contains("command") || kind.contains("tool") {
            let name = item["name"] as? String ?? item["command"] as? String ?? kind
            return CLIStreamEvent(
                toolCalls: [ToolCallDelta(index: 0, id: item["id"] as? String, name: name, arguments: "")],
                progress: name,
                sessionID: session
            )
        }
        return nil
    }
}

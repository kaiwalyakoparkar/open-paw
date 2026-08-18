import Foundation

/// Parses OpenAI-compatible SSE lines (`data: {...}`) plus Hermes
/// `event: hermes.tool.progress` payloads.
public enum HermesSSEParser {
    public struct Event: Equatable {
        public var textDelta: String
        public var toolCalls: [ToolCallDelta]
        public var finished: Bool
        public var progress: String = ""
    }

    public static func parse(line: String, event: String? = nil) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return Event(textDelta: "", toolCalls: [], finished: true)
        }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let err = obj["error"], !(err is NSNull) {
            return Event(textDelta: "\n[hermes error: \(errorMessage(err))]", toolCalls: [], finished: true)
        }

        if event == "hermes.tool.progress" || (obj["choices"] == nil && obj["tool"] != nil) {
            return Event(textDelta: "", toolCalls: [], finished: false, progress: progressText(obj))
        }

        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first
        else { return Event(textDelta: "", toolCalls: [], finished: false) }

        let finish = first["finish_reason"] as? String
        let delta = first["delta"] as? [String: Any] ?? [:]
        let text = delta["content"] as? String ?? ""
        var tools: [ToolCallDelta] = []
        if let tcs = delta["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                let idx = tc["index"] as? Int ?? 0
                let id = tc["id"] as? String
                let fn = tc["function"] as? [String: Any]
                tools.append(ToolCallDelta(
                    index: idx,
                    id: id,
                    name: fn?["name"] as? String,
                    arguments: fn?["arguments"] as? String ?? ""
                ))
            }
        }
        return Event(textDelta: text, toolCalls: tools, finished: finish != nil && finish != "null")
    }

    static func errorMessage(_ err: Any) -> String {
        if let d = err as? [String: Any], let m = d["message"] as? String { return m }
        if let s = err as? String { return s }
        return "\(err)"
    }

    public static func progressText(_ obj: [String: Any]) -> String {
        let status = obj["status"] as? String ?? ""
        let tool = obj["tool"] as? String ?? "tool"
        if status == "completed" { return "\(tool) done" }
        let label = obj["label"] as? String ?? tool
        let emoji = obj["emoji"] as? String ?? ""
        return emoji.isEmpty ? label : "\(emoji) \(label)"
    }
}

public enum HermesProgress {
    public static func waitBubble(prompt: String, status: String, seconds: Int) -> String {
        var parts: [String] = []
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { parts.append(p) }
        if !status.isEmpty { parts.append(status) }
        parts.append("Working… \(seconds)s")
        return parts.joined(separator: "\n\n")
    }
}

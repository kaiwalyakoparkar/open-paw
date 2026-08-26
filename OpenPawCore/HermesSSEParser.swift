import Foundation

/// Parses OpenAI-compatible SSE lines (`data: {...}`) plus Hermes
/// `event: hermes.tool.progress` payloads.
public enum HermesSSEParser {
    public struct Event: Equatable {
        public var textDelta: String
        public var toolCalls: [ToolCallDelta]
        public var finished: Bool
        public var progress: String = ""
        public var outputTokens: Int? = nil
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

        let tokens = outputTokens(from: obj["usage"])

        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first
        else {
            return Event(textDelta: "", toolCalls: [], finished: false, outputTokens: tokens)
        }

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
        return Event(
            textDelta: text,
            toolCalls: tools,
            finished: finish != nil && finish != "null",
            outputTokens: tokens
        )
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

    /// OpenAI-style `completion_tokens` or Claude-style `output_tokens`.
    public static func outputTokens(from usage: Any?) -> Int? {
        guard let u = usage as? [String: Any] else { return nil }
        if let n = u["completion_tokens"] as? Int { return n }
        if let n = u["output_tokens"] as? Int { return n }
        if let n = u["completion_tokens"] as? Double { return Int(n) }
        if let n = u["output_tokens"] as? Double { return Int(n) }
        return nil
    }
}

public enum HermesProgress {
    /// Cat-themed wait verbs; rotate by elapsed seconds.
    public static let thinkingVerbs = ["Kneading…", "Pawing…", "Pondering…", "Hunting…"]
    /// Seconds each verb stays before the next.
    public static let thinkingVerbInterval = 3

    public static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    public static func formatTokens(_ count: Int) -> String {
        let n = max(0, count)
        if n < 1000 { return "\(n)" }
        let tenths = (n + 50) / 100
        if tenths % 10 == 0 { return "\(tenths / 10)k" }
        return "\(tenths / 10).\(tenths % 10)k"
    }

    public static func thinkingVerb(atSeconds seconds: Int) -> String {
        let verbs = thinkingVerbs
        let idx = max(0, seconds) / thinkingVerbInterval % verbs.count
        return verbs[idx]
    }

    public static func thinkingStatus(seconds: Int, outputTokens: Int?) -> String {
        var meta = formatDuration(seconds)
        if let tokens = outputTokens {
            meta += " · ↓ \(formatTokens(tokens)) tokens"
        }
        return "\(thinkingVerb(atSeconds: seconds)) (\(meta))"
    }
}

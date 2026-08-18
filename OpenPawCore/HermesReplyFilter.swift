import Foundation

/// Hermes CLI hides tool-arg JSON that models leak into `delta.content`.
/// The API server forwards that leak; we drop it so it is not spoken/shown.
public struct HermesReplyFilter {
    private var hold = ""

    public init() {}

    public static func isToolLeak(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"),
              let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["command"] != nil
    }

    public mutating func push(_ delta: String) -> String {
        if hold.isEmpty {
            let t = delta.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return delta }
            if !t.hasPrefix("{") { return delta }
        }
        hold += delta
        let t = hold.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") else {
            let out = hold
            hold = ""
            return out
        }
        guard Self.isCompleteJSONObject(t) else { return "" }
        if Self.isToolLeak(t) {
            hold = ""
            return ""
        }
        let out = hold
        hold = ""
        return out
    }

    public mutating func flush() -> String {
        let t = hold.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = Self.isToolLeak(t) ? "" : hold
        hold = ""
        return out
    }

    static func isCompleteJSONObject(_ s: String) -> Bool {
        var depth = 0
        var inString = false
        var escape = false
        for ch in s {
            if inString {
                if escape { escape = false; continue }
                if ch == "\\" { escape = true; continue }
                if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true; continue }
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return true }
            }
        }
        return false
    }
}

import Foundation

public enum HermesHTTPError: LocalizedError {
    case unauthorized
    case payloadTooLarge
    case status(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid API key — set hermes.api_key in ~/.config/open-paw/config.json to match API_SERVER_KEY"
        case .payloadTooLarge:
            return "Screenshot too large for Hermes (10 MB limit) — retry after rebuild with latest Open Paw"
        case .status(let code, let message):
            return "HTTP \(code): \(message)"
        }
    }

    public static func parse(body: String, status: Int) -> HermesHTTPError? {
        guard !(200 ... 299).contains(status) else { return nil }
        if status == 401 { return .unauthorized }
        if status == 413 { return .payloadTooLarge }
        let msg = openAIMessage(body) ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = msg.isEmpty ? "request failed" : msg
        return .status(status, trimmed)
    }

    static func openAIMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? [String: Any],
              let msg = err["message"] as? String
        else { return nil }
        return msg
    }
}

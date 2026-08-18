import Foundation

/// Layered on Hermes API `platform=api_server` prompt, which says
/// "treat this like a conversation" and makes the model ask for paths
/// instead of using file/terminal tools the way the CLI does.
public enum HermesSystemPrompt {
    public static let text = """
    You have filesystem tools, but macOS blocks the Hermes gateway from ~/Documents. If the user message includes a "Local notes" block, use it and never ask the user to paste files. Otherwise search what you can, then answer. Call tools as function calls; never print tool-argument JSON.
    """

    public static func withSystem(_ messages: [ChatMessage]) -> [ChatMessage] {
        if messages.contains(where: { $0.role == "system" }) { return messages }
        return [.text(role: "system", text)] + messages
    }
}

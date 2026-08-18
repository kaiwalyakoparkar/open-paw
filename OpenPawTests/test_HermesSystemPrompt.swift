import OpenPawCore
import Foundation

enum HermesSystemPromptChecks {
    static func run() {
        let user = ChatMessage.text(role: "user", "two action items from my last meeting with derek")
        let out = HermesSystemPrompt.withSystem([user])
        assert(out.count == 2, "prepend system: \(out.count)")
        assert(out[0].role == "system", out[0].role)
        guard case .string(let s) = out[0].content else {
            assertionFailure("system prompt must be text")
            return
        }
        assert(s.contains("Local notes"), s)
        assert(s.lowercased().contains("paste"), s)
        assert(out[1].role == "user", out[1].role)

        let again = HermesSystemPrompt.withSystem(out)
        assert(again.count == 2, "do not duplicate system: \(again.count)")
        print("HermesSystemPrompt OK")
    }
}

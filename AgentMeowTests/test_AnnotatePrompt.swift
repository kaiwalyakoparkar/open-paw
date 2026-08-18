import AgentMeowCore
import Foundation

enum AnnotatePromptChecks {
    static func run() {
        let silent = AnnotatePrompt.userText()
        assert(silent.contains("full screenshot as context"), silent)
        assert(silent.contains("highlighted/circled"), silent)
        assert(silent.contains("1–2 short lines") || silent.contains("1-2 short lines"), silent)
        assert(!silent.contains("User:"), silent)

        let spoken = AnnotatePrompt.userText(spoken: "what's the price")
        assert(spoken.hasPrefix(silent), spoken)
        assert(spoken.contains("what's the price"), spoken)

        assert(AnnotatePrompt.userText(spoken: "   ") == silent)
        print("AnnotatePrompt OK")
    }
}

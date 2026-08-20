import OpenPawCore
import Foundation

enum AnnotatePromptChecks {
    static func run() {
        let silent = AnnotatePrompt.userText()
        assert(silent.lowercased().contains("purple"), silent)
        assert(silent.contains("exact object") || silent.contains("sits on"), silent)
        assert(silent.contains("not the biggest") || silent.contains("nearby caption"), silent)
        assert(silent.contains("do not know") || silent.contains("don't know"), silent)
        assert(silent.lowercased().contains("decode"), silent)
        assert(silent.contains("inside the highlight"), silent)
        assert(silent.contains("No Todo") || silent.contains("no Todo"), silent)
        assert(!silent.contains("1–2 short lines") && !silent.contains("1-2 short lines"), silent)
        assert(!silent.contains("User:"), silent)

        assert(AnnotatePrompt.spokenOrNil("") == nil)
        assert(AnnotatePrompt.spokenOrNil("   ") == nil)
        assert(AnnotatePrompt.spokenOrNil("what is this pin") == "what is this pin")

        let spoken = AnnotatePrompt.userText(spoken: "what's the price")
        assert(spoken.hasPrefix(silent), spoken)
        assert(spoken.contains("what's the price"), spoken)

        assert(AnnotatePrompt.userText(spoken: "   ") == silent)

        let withPath = AnnotatePrompt.userText(screenshotPath: "/tmp/open-paw/explain-test.jpg")
        assert(withPath.contains("/tmp/open-paw/explain-test.jpg"), withPath)
        assert(withPath.lowercased().contains("vision"), withPath)
        print("AnnotatePrompt OK")
    }
}

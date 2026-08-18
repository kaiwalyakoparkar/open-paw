import AgentMeowCore
import Foundation

enum SentenceBufferChecks {
    static func run() {
        var buf = SentenceBuffer()
        let a = buf.push("Hello. World")
        assert(a == ["Hello."], "period split: \(a)")
        assert(buf.flush() == "World")

        buf = SentenceBuffer()
        let b = buf.push("Go?\nYes! leftover")
        assert(b == ["Go?", "Yes!"], "q/nl: \(b)")
        assert(buf.flush() == "leftover")

        buf = SentenceBuffer()
        assert(buf.flush() == nil)
        print("SentenceBuffer OK")
    }
}

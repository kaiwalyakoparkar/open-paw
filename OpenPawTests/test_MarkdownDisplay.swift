import OpenPawCore
import Foundation

enum MarkdownDisplayChecks {
    static func run() {
        let bold = MarkdownDisplay.attributed("**Highlight** line")
        assert(
            String(bold.characters) == "Highlight line",
            "bold markers must drop, got \(String(bold.characters))"
        )

        let mixed = MarkdownDisplay.attributed(
            #""Paytm" = contraction of **Pay T**hrough **M**obile"#
        )
        let mixedPlain = String(mixed.characters)
        assert(mixedPlain.contains("Pay Through Mobile"), "got \(mixedPlain)")
        assert(!mixedPlain.contains("**"), "asterisks leaked: \(mixedPlain)")

        let plain = MarkdownDisplay.attributed("no markup here")
        assert(String(plain.characters) == "no markup here")

        let paras = MarkdownDisplay.attributed("line one\n\nline two")
        let paraPlain = String(paras.characters)
        assert(paraPlain.contains("line one") && paraPlain.contains("line two"), "got \(paraPlain)")

        print("MarkdownDisplay OK")
    }
}

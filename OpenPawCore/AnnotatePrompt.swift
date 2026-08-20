import Foundation

/// Text sent with an annotated screenshot. Full screen = context; highlight = the thing to explain.
public enum AnnotatePrompt {
    public static let instruction = """
    The purple highlight is the target. Identify the exact object it sits on (photo, board, icon, or text) — not the biggest thing on screen and not a nearby caption.

    Assume I do not know it. Decode names and teach that specific object: what it is, what each part of the name means, how it differs from lookalikes nearby, and what it is used for.

    Add or total numbers only when those numbers are inside the highlight. Ignore figures sitting next to it.

    A few sentences of explanation only. No Todo, plan, checklist, or restatement of these instructions.
    """

    /// Empty / whitespace → silent explain (`nil`). Else the spoken Ask line.
    public static func spokenOrNil(_ transcript: String) -> String? {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public static func userText(spoken: String? = nil, screenshotPath: String? = nil) -> String {
        var blocks = [instruction]
        if let screenshotPath, !screenshotPath.isEmpty {
            blocks.append("""
            Screenshot file — read this path with your vision/image tool (do not ask the user to re-upload):
            \(screenshotPath)
            """)
        }
        let extra = spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !extra.isEmpty { blocks.append(extra) }
        return blocks.joined(separator: "\n\n")
    }
}

import Foundation

/// Text sent with an annotated screenshot. Full screen = context; highlight = the thing to explain.
public enum AnnotatePrompt {
    public static let instruction = """
    Use the full screenshot as context. Explain only the highlighted/circled part.

    In 1–2 short lines:
    - say what that highlight actually is, given the rest of the screen
    - if there are numbers, add them into the amount that matters (price + tax, total, leftover, etc.)
    """

    public static func userText(spoken: String? = nil) -> String {
        let extra = spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if extra.isEmpty { return instruction }
        return instruction + "\n\n" + extra
    }
}

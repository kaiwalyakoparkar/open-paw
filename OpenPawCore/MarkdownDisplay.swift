import Foundation

/// LLM replies often include `**bold**` / `_italic_`. Speech bubble used to show the markers.
public enum MarkdownDisplay {
    public static func attributed(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        // ponytail: Foundation markdown, not a custom parser. Full CommonMark if headers/lists land in the pill.
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}

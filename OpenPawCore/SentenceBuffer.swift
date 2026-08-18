import Foundation

/// Accumulates SSE text deltas and yields complete sentences at `.!?` or newline.
public struct SentenceBuffer {
    private var pending = ""

    public init() {}

    /// Returns zero or more complete sentences. Remainder stays buffered.
    public mutating func push(_ chunk: String) -> [String] {
        pending += chunk
        var out: [String] = []
        while let idx = pending.firstIndex(where: { ".!?\n".contains($0) }) {
            let end = pending.index(after: idx)
            let sentence = String(pending[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[end...])
            if !sentence.isEmpty {
                out.append(sentence)
            }
        }
        return out
    }

    /// Remaining partial sentence at stream end.
    public mutating func flush() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return rest.isEmpty ? nil : rest
    }
}

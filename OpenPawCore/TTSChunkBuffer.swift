import Foundation

/// Coalesces sentence-sized TTS fragments into fewer API requests.
public struct TTSChunkBuffer {
    public var minChars: Int
    public var maxChars: Int
    private var pending = ""

    public init(minChars: Int = 80, maxChars: Int = 420) {
        self.minChars = minChars
        self.maxChars = maxChars
    }

    /// First chunk: emit as soon as a sentence completes (low latency).
    public mutating func pushFirst(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        pending += chunk
        if let taken = takeThroughLastSentence(maxLen: pending.count) {
            return [taken]
        }
        return []
    }

    /// Later chunks: batch until minChars or maxChars.
    public mutating func push(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return emitReady() }
        pending += chunk
        return emitReady()
    }

    /// Timer fired — emit a batch if enough text accumulated.
    public mutating func emitReady() -> [String] {
        var out: [String] = []
        while pending.count >= maxChars {
            if let taken = takeThroughLastSentence(maxLen: maxChars) {
                out.append(taken)
            } else {
                let slice = String(pending.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
                pending = String(pending.dropFirst(maxChars))
                if !slice.isEmpty { out.append(slice) }
            }
        }
        if let taken = takeThroughLastSentence(maxLen: pending.count), taken.count >= minChars {
            out.append(taken)
        }
        return out
    }

    public mutating func flush() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return rest.isEmpty ? nil : rest
    }

    private mutating func takeThroughLastSentence(maxLen: Int) -> String? {
        let slice = String(pending.prefix(maxLen))
        guard let idx = slice.lastIndex(where: { ".!?\n".contains($0) }) else { return nil }
        let end = pending.index(pending.startIndex, offsetBy: slice.distance(from: slice.startIndex, to: idx) + 1)
        let taken = String(pending[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        pending = String(pending[end...])
        return taken.isEmpty ? nil : taken
    }
}

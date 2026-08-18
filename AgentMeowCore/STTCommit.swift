import Foundation

/// When to leave the orange processing bubble and start Hermes.
///
/// Gradium `end_text` only re-emits `latestText` already streamed via `.text`.
/// After `flushed`, the delay buffer is drained — waiting 2.5–3s more is dead time.
public enum STTCommit {
    public enum Event: Equatable {
        case userReleased
        case flushed
        case endText
        case fallbackFired
    }

    public enum Action: Equatable {
        case sendNow
        case wait(ns: UInt64)
    }

    /// 80 ms Gradium PCM chunk.
    public static let frameNs: UInt64 = 80_000_000
    /// Slack if flush/end_text never arrive.
    public static let slackNs: UInt64 = 300_000_000

    public static func action(_ event: Event, delayInFrames: Int) -> Action {
        switch event {
        case .flushed, .endText, .fallbackFired:
            return .sendNow
        case .userReleased:
            let frames = UInt64(max(delayInFrames, 0))
            return .wait(ns: frames * frameNs + slackNs)
        }
    }

    /// Key-up can land while Gradium connect is still in flight. Flushing
    /// then yields empty transcript + "No mic input detected".
    public static func canFlushAfterRelease(captureStarted: Bool) -> Bool {
        captureStarted
    }

    /// Gradium `.text` is the current utterance, not a delta. After `end_text`
    /// a new fragment can replace the phrase already shown. Keep the longer
    /// transcript; append when the incoming chunk is a new tail word.
    public static func mergeTranscript(_ existing: String, _ incoming: String) -> String {
        let a = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if b.hasPrefix(a) { return b }
        if a.hasPrefix(b) { return a }
        let al = a.lowercased()
        let bl = b.lowercased()
        if al.contains(bl) { return a }
        if bl.contains(al) { return b }
        return a + " " + b
    }
}

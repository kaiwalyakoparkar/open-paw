import OpenPawCore
import Foundation

enum STTCommitChecks {
    static func run() {
        // Gradium `flushed` means the delay buffer is drained. Waiting 2.5s
        // more for `end_text` stalls the orange processing bubble; end_text
        // only re-emits latestText already received via `.text`.
        assert(STTCommit.action(.flushed, delayInFrames: 16) == .sendNow)
        assert(STTCommit.action(.endText, delayInFrames: 16) == .sendNow)
        assert(STTCommit.action(.fallbackFired, delayInFrames: 16) == .sendNow)

        let wait = STTCommit.action(.userReleased, delayInFrames: 16)
        let expected = UInt64(16) * STTCommit.frameNs + STTCommit.slackNs
        assert(wait == .wait(ns: expected), "userReleased wait: \(wait)")
        assert(expected < 2_000_000_000, "fallback must be under 2s, not 2.5–3s")

        assert(STTCommit.action(.userReleased, delayInFrames: 0) == .wait(ns: STTCommit.slackNs))

        // Key-up during Gradium connect must not flush before the mic graph runs.
        assert(!STTCommit.canFlushAfterRelease(captureStarted: false))
        assert(STTCommit.canFlushAfterRelease(captureStarted: true))

        // Growing hypothesis replaces; a later fragment must not wipe the phrase.
        assert(STTCommit.mergeTranscript("", "What is") == "What is")
        assert(STTCommit.mergeTranscript("What is", "What is api management") == "What is api management")
        assert(STTCommit.mergeTranscript("What is api management", "API") == "What is api management")
        assert(STTCommit.mergeTranscript("What is api", "management") == "What is api management")
        assert(STTCommit.mergeTranscript("What is api management", "What is") == "What is api management")
        print("STTCommit OK")
    }
}

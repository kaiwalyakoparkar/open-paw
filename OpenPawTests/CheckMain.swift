@main
enum CheckMain {
    static func main() {
        SentenceBufferChecks.run()
        VADLogicChecks.run()
        HermesSSEParserChecks.run()
        HotkeyKeyMapChecks.run()
        GradiumSTTChunkingChecks.run()
        STTCommitChecks.run()
        BuddyLayoutChecks.run()
        AnnotateOverlayChecks.run()
        AnnotatePromptChecks.run()
        HermesSystemPromptChecks.run()
        HermesReplyFilterChecks.run()
        HermesHTTPErrorChecks.run()
        ObsidianNotesChecks.run()
        print("all checks passed")
    }
}

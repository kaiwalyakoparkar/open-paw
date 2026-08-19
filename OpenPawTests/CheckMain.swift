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
        HarnessKindChecks.run()
        AppConfigHarnessChecks.run()
        LastUserTextChecks.run()
        CLIBinaryChecks.run()
        ClaudeStreamParserChecks.run()
        ClaudeCLIArgsChecks.run()
        CodexStreamParserChecks.run()
        print("all checks passed")
    }
}

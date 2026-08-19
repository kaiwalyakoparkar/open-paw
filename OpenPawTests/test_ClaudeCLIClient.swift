import OpenPawCore
import Foundation

enum ClaudeCLIArgsChecks {
    static func run() {
        let args = ClaudeCLIClient.cliArgs(
            prompt: "hi",
            permissionMode: "acceptEdits",
            sessionID: nil,
            addDir: "/tmp"
        )
        assert(args.contains("-p"))
        assert(args.contains("stream-json"))
        assert(args.contains("--verbose"), "claude --print + stream-json requires --verbose")
        print("ClaudeCLI args OK")
    }
}

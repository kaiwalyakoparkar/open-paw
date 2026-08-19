import OpenPawCore
import Foundation

enum HarnessKindChecks {
    static func run() {
        assert(HarnessKind.fromArgv(["OpenPaw"]) == nil)
        assert(HarnessKind.fromArgv(["OpenPaw", "--claude"]) == .claude)
        assert(HarnessKind.fromArgv(["OpenPaw", "--codex"]) == .codex)
        assert(HarnessKind.fromArgv(["OpenPaw", "--hermes"]) == .hermes)
        assert(HarnessKind.fromArgv(["OpenPaw", "--claude", "--codex"]) == .codex)
        assert(HarnessKind.fromArgv(["OpenPaw", "--codex", "--claude"]) == .claude)
        print("HarnessKind OK")
    }
}

enum AppConfigHarnessChecks {
    static func run() {
        let old = """
        {
          "gradium": {
            "api_key": "g",
            "stt": {
              "model_name": "default",
              "delay_in_frames": 16,
              "vad_horizon_index": 2,
              "vad_threshold": 0.5,
              "vad_consecutive_frames": 3
            },
            "tts": { "voice_id": "v", "output_format": "pcm" }
          },
          "hermes": {
            "base_url": "http://127.0.0.1:8642/v1",
            "api_key": "h",
            "model": "hermes-agent",
            "sse_timeout_seconds": 600
          },
          "hotkey": { "hold": { "modifiers": [], "key": "right_option" } },
          "ui": {
            "buddy_size": 80,
            "default_position": "bottom-right",
            "idle_timeout_seconds": 300
          }
        }
        """
        let cfg = try! JSONDecoder().decode(AppConfig.self, from: Data(old.utf8))
        assert(cfg.harness == .hermes, "\(cfg.harness)")
        assert(cfg.claude.bin == "claude")
        assert(cfg.claude.cwd == "~")
        assert(cfg.claude.permissionMode == "acceptEdits")
        assert(cfg.codex.bin == "codex")

        var overwritten = cfg
        overwritten.harness = HarnessKind.fromArgv(["--claude"]) ?? overwritten.harness
        assert(overwritten.harness == .claude)

        let exampleURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.json")
        let example = try! JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: exampleURL))
        assert(example.harness == .hermes, "\(example.harness)")

        print("AppConfig harness OK")
    }
}

enum LastUserTextChecks {
    static func run() {
        let msgs = [
            ChatMessage.text(role: "assistant", "hi"),
            ChatMessage(role: "user", content: .parts([.text("explain this")])),
        ]
        assert(msgs.lastUserText() == "explain this")
        print("lastUserText OK")
    }
}

enum CLIBinaryChecks {
    static func run() {
        assert(CLIBinary.resolve("/usr/bin/true") != nil || CLIBinary.resolve("/bin/ls") != nil)
        assert(CLIBinary.resolve("definitely-not-a-binary-open-paw") == nil)
        let appCLI = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: appCLI) {
            assert(CLIBinary.resolve("codex") != nil, "Codex.app CLI present but resolve missed it")
        }
        print("CLIBinary OK")
    }
}

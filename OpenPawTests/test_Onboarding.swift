import OpenPawCore
import Foundation

enum OnboardingChecks {
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
        let legacy = try! JSONDecoder().decode(AppConfig.self, from: Data(old.utf8))
        assert(legacy.onboarded == true, "missing onboarded → true")
        assert(!AppConfig.needsOnboarding(legacy))
        assert(!ProcessArgv.parse(["OpenPaw"]).onboard)
        assert(ProcessArgv.parse(["OpenPaw", "--onboard"]).onboard)
        assert(AppConfig.needsOnboarding(legacy, argv: ProcessArgv.parse(["--onboard"])))

        let notDone = """
        {
          "gradium": {
            "api_key": "",
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
          },
          "onboarded": false
        }
        """
        let needs = try! JSONDecoder().decode(AppConfig.self, from: Data(notDone.utf8))
        assert(needs.onboarded == false)
        assert(AppConfig.needsOnboarding(needs))

        var fresh = AppConfig(
            gradium: GradiumConfig(
                apiKey: "",
                stt: STTConfig(
                    modelName: "default",
                    delayInFrames: 16,
                    vadHorizonIndex: 2,
                    vadThreshold: 0.5,
                    vadConsecutiveFrames: 3
                ),
                tts: TTSConfig(voiceId: "v", outputFormat: "pcm")
            ),
            hermes: HermesConfig(
                baseURL: "http://127.0.0.1:8642/v1",
                apiKey: "h",
                model: "hermes-agent",
                sseTimeoutSeconds: 600
            ),
            hotkey: HotkeyConfig(hold: KeyCombo(modifiers: [], key: "right_option")),
            ui: UIConfig(buddySize: 80, defaultPosition: "bottom-right", idleTimeoutSeconds: 300),
            onboarded: false
        )
        assert(AppConfig.needsOnboarding(fresh))

        let draft = OnboardingDraft()
        assert(draft.holdKey == OnboardingOptions.recommendedHoldKey)
        assert(OnboardingOptions.holdOptions.first!.recommended)
        assert(OnboardingOptions.holdOptions.first!.key == "right_option")

        var claudeDraft = OnboardingDraft(
            harness: .claude,
            model: "opus",
            permissionMode: "bypassPermissions",
            cwd: "~/src"
        )
        claudeDraft.apply(to: &fresh)
        assert(fresh.onboarded == true)
        assert(!AppConfig.needsOnboarding(fresh))
        assert(fresh.harness == .claude)
        assert(fresh.claude.model == "opus")
        assert(fresh.claude.permissionMode == "bypassPermissions")
        assert(fresh.claude.cwd == "~/src")
        assert(fresh.hotkey.hold.key == "right_option")

        var hermesCfg = fresh
        hermesCfg.onboarded = false
        OnboardingDraft(harness: .hermes, model: "hermes-agent", hermesApiKey: "secret")
            .apply(to: &hermesCfg)
        assert(hermesCfg.harness == .hermes)
        assert(hermesCfg.hermes.model == "hermes-agent")
        assert(hermesCfg.hermes.apiKey == "secret")
        assert(hermesCfg.onboarded)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-paw-onboard-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try! hermesCfg.save(to: tmp)
        let attrs = try! FileManager.default.attributesOfItem(atPath: tmp.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        assert(mode & 0o777 == 0o600, "mode=\(String(mode, radix: 8))")
        let loaded = try! AppConfig.load(from: tmp)
        assert(loaded.onboarded == true)
        assert(loaded.hermes.apiKey == "secret")
        assert(!AppConfig.needsOnboarding(loaded))

        print("Onboarding OK")
    }
}

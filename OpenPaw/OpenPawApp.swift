import AppKit
import OpenPawCore
import SwiftUI

@main
enum OpenPawMain {
    static func main() {
        AppRelaunch.execFromBundleIfNeeded()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: CompanionManager?
    private var statusItem: NSStatusItem?
    private var onboarding: OnboardingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: AppConfig
        do {
            config = try AppConfig.load()
        } catch {
            NSLog("open-paw: missing ~/.config/open-paw/config.json (%@) — using example defaults with empty keys", error.localizedDescription)
            config = fallbackConfig()
        }

        if AppConfig.needsOnboarding(config) {
            // LSUIElement agent → regular so a real window + Dock icon exist.
            // Defer one turn so AppKit finishes the policy flip before we show.
            NSApp.setActivationPolicy(.regular)
            let controller = OnboardingPanelController()
            onboarding = controller
            var seed = config
            ProcessArgv.parse(CommandLine.arguments).apply(to: &seed)
            let draft = OnboardingDraft.from(config: seed)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                controller.present(draft: draft) { [weak self] finished in
                    self?.finishOnboarding(base: config, draft: finished)
                }
            }
            return
        }

        startCompanion(with: applyArgv(config))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboarding != nil {
            onboarding?.bringToFront()
            return false
        }
        return true
    }

    private func finishOnboarding(base: AppConfig, draft: OnboardingDraft) {
        var cfg = base
        draft.apply(to: &cfg)
        do {
            try cfg.save()
        } catch {
            NSLog("open-paw: failed to write config.json (%@)", error.localizedDescription)
        }
        onboarding = nil
        NSApp.setActivationPolicy(.accessory)
        startCompanion(with: applyArgv(cfg))
    }

    private func startCompanion(with config: AppConfig) {
        let manager = CompanionManager(config: config)
        self.manager = manager
        manager.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐱"
        item.menu = makeMenu(manager: manager)
        statusItem = item
    }

    private func makeMenu(manager: CompanionManager) -> NSMenu {
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "Cancel session", action: #selector(stop), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Explain this…", action: #selector(annotate), keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        m.items.forEach { $0.target = self }
        return m
    }

    @objc private func stop() { manager?.cancelSession() }
    @objc private func annotate() { manager?.beginAnnotate() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func applyArgv(_ config: AppConfig) -> AppConfig {
        var cfg = config
        ProcessArgv.parse(CommandLine.arguments).apply(to: &cfg)
        return cfg
    }

    private func fallbackConfig() -> AppConfig {
        AppConfig(
            gradium: GradiumConfig(
                apiKey: ProcessInfo.processInfo.environment["GRADIUM_API_KEY"] ?? "",
                stt: STTConfig(
                    modelName: "default",
                    delayInFrames: 16,
                    vadHorizonIndex: 2,
                    vadThreshold: 0.50,
                    vadConsecutiveFrames: 3
                ),
                tts: TTSConfig(voiceId: "YTpq7expH9539ERJ", outputFormat: "pcm")
            ),
            hermes: HermesConfig(
                baseURL: "http://127.0.0.1:8642/v1",
                apiKey: ProcessInfo.processInfo.environment["HERMES_API_KEY"] ?? "change-me-local-dev",
                model: "hermes-agent",
                sseTimeoutSeconds: 600
            ),
            hotkey: HotkeyConfig(
                hold: KeyCombo(modifiers: [], key: "right_option"),
                toggle: KeyCombo(modifiers: ["control", "option"], key: "option")
            ),
            ui: UIConfig(buddySize: 80, defaultPosition: "bottom-right", idleTimeoutSeconds: 300),
            onboarded: false
        )
    }
}

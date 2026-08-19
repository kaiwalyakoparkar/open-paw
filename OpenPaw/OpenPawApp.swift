import AppKit
import OpenPawCore
import SwiftUI

@main
enum OpenPawMain {
    static func main() {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: AppConfig
        do {
            config = try AppConfig.load()
        } catch {
            NSLog("open-paw: missing ~/.config/open-paw/config.json (%@) — using example defaults with empty keys", error.localizedDescription)
            config = fallbackConfig()
        }

        let manager = CompanionManager(config: applyArgv(config))
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
        if let flag = HarnessKind.fromArgv(CommandLine.arguments) {
            cfg.harness = flag
        }
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
                toggle: KeyCombo(modifiers: ["control", "option"], key: "space")
            ),
            ui: UIConfig(buddySize: 80, defaultPosition: "bottom-right", idleTimeoutSeconds: 300)
        )
    }
}

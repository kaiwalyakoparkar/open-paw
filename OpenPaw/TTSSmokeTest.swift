import AVFoundation
import Foundation
import OpenPawCore

/// `swift run OpenPaw --tts-test` — synthesize + play one sentence, then exit.
enum TTSSmokeTest {
    @MainActor
    static func run(config: GradiumConfig) async -> Bool {
        guard !config.apiKey.isEmpty else {
            fputs("open-paw tts-test: missing gradium.api_key\n", stderr)
            return false
        }
        do {
            let audio = try await GradiumTTSSynthesize.fetch(
                text: "Hello from Open Paw.",
                config: config
            )
            guard let player = try? AVAudioPlayer(data: audio) else {
                fputs("open-paw tts-test: could not decode \(audio.count) bytes\n", stderr)
                return false
            }
            player.prepareToPlay()
            guard player.play() else {
                fputs("open-paw tts-test: play() returned false\n", stderr)
                return false
            }
            let end = Date().addingTimeInterval(player.duration + 1.5)
            while player.isPlaying, Date() < end {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            fputs("open-paw tts-test: ok (\(audio.count) bytes, \(String(format: "%.1f", player.duration))s)\n", stderr)
            return true
        } catch {
            fputs("open-paw tts-test: \(error.localizedDescription)\n", stderr)
            return false
        }
    }
}

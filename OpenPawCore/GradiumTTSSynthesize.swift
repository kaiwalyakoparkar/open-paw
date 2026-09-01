import Foundation

/// Gradium one-shot TTS over REST (`POST /api/post/speech/tts`).
/// OpenClaw uses this path; simpler than WebSocket for sentence-sized chunks.
public enum GradiumTTSSynthesize {
    public static let endpoint = URL(string: "https://api.gradium.ai/api/post/speech/tts")!

    public static func requestBody(text: String, voiceId: String, outputFormat: String) -> [String: Any] {
        [
            "text": text,
            "voice_id": voiceId,
            "only_audio": true,
            "output_format": outputFormat,
            "json_config": "{\"padding_bonus\":0}",
        ]
    }

    /// `pcm` config maps to `wav` — AVAudioPlayer needs a container format.
    public static func playbackFormat(configured: String) -> String {
        configured == "pcm" ? "wav" : configured
    }

    public static func fetch(
        text: String,
        config: GradiumConfig,
        outputFormat: String? = nil,
        session: URLSession = .shared
    ) async throws -> Data {
        guard !config.apiKey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let spoken = GradiumTTSWire.speakableText(text)
        guard !spoken.isEmpty else { throw URLError(.badURL) }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        let fmt = outputFormat ?? playbackFormat(configured: config.tts.outputFormat)
        req.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            text: spoken,
            voiceId: config.tts.voiceId,
            outputFormat: fmt
        ))

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data.prefix(500), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "GradiumTTS", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: msg,
            ])
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }
}

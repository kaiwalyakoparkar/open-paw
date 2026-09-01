import Foundation

/// Gradium TTS helpers (WebSocket wire + shared speakable text).
public enum GradiumTTSWire {
    public static func speakableText(_ sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("<flush>") ? trimmed : "\(trimmed) <flush>"
    }

    public static func setup(voiceId: String, outputFormat: String) -> [String: Any] {
        [
            "type": "setup",
            "model_name": "default",
            "voice_id": voiceId,
            "output_format": outputFormat,
        ]
    }

    public static func text(_ sentence: String) -> [String: Any] {
        ["type": "text", "text": speakableText(sentence)]
    }

    public static func endOfStream() -> [String: Any] {
        ["type": "end_of_stream"]
    }
}

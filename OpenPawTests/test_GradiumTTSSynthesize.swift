import Foundation
import OpenPawCore

enum GradiumTTSSynthesizeChecks {
    static func run() {
        let body = GradiumTTSSynthesize.requestBody(
            text: "Hi.",
            voiceId: "voice-1",
            outputFormat: "wav"
        )
        assert(body["text"] as? String == "Hi.")
        assert(body["voice_id"] as? String == "voice-1")
        assert(body["only_audio"] as? Bool == true)
        assert(body["output_format"] as? String == "wav")

        assert(GradiumTTSSynthesize.playbackFormat(configured: "pcm") == "wav")
        assert(GradiumTTSSynthesize.playbackFormat(configured: "opus") == "opus")

        print("GradiumTTSSynthesize OK")
    }
}

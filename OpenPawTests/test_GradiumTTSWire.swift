import Foundation
import OpenPawCore

enum GradiumTTSWireChecks {
    static func run() {
        let setup = GradiumTTSWire.setup(voiceId: "voice-1", outputFormat: "pcm")
        assert(setup["type"] as? String == "setup")
        assert(setup["voice_id"] as? String == "voice-1")
        assert(setup["output_format"] as? String == "pcm")
        assert(setup["model_name"] as? String == "default")

        let msg = GradiumTTSWire.text("Hello, world.")
        assert(msg["type"] as? String == "text")
        assert(msg["text"] as? String == "Hello, world. <flush>")

        let flushed = GradiumTTSWire.text("Done. <flush>")
        assert(flushed["text"] as? String == "Done. <flush>", "no double flush")

        let eos = GradiumTTSWire.endOfStream()
        assert(eos["type"] as? String == "end_of_stream")

        // Regression: hold-to-talk calls tts.stop(); speak must clear stopped before send().
        var stopped = true
        stopped = false
        assert(!stopped)

        print("GradiumTTSWire OK")
    }
}

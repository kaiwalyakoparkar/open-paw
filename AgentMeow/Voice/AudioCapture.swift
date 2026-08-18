import AVFoundation
import Foundation

final class AudioCapture {
    var onPCM: ((Data) -> Void)?
    var onRMS: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    func start() throws {
        let input = engine.inputNode
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0

        // ponytail: macOS AVAudioEngine tap gets silence unless input is in the graph (-10875)
        engine.connect(input, to: mixer, format: nil)
        engine.connect(mixer, to: engine.outputNode, format: nil)

        let nativeFmt = input.outputFormat(forBus: 0)
        guard nativeFmt.sampleRate > 0, nativeFmt.channelCount > 0 else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input available",
            ])
        }
        guard let outFmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not create 24 kHz PCM format",
            ])
        }
        converter = AVAudioConverter(from: nativeFmt, to: outFmt)

        // ponytail: tap must use hardware format — macOS rejects/alienates non-native tap formats
        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFmt) { [weak self] buffer, _ in
            self?.handle(buffer, outFmt: outFmt)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine.reset()
        converter = nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer, outFmt: AVAudioFormat) {
        convert(buffer, outFmt: outFmt)
    }

    private func convert(_ buffer: AVAudioPCMBuffer, outFmt: AVAudioFormat) {
        guard let converter, buffer.frameLength > 0 else { return }

        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }

        let ratio = outFmt.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * Double(ratio))) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: capacity) else { return }

        var error: NSError?
        var finished = false
        while !finished {
            out.frameLength = 0
            let status = converter.convert(to: out, error: &error, withInputFrom: inputBlock)
            if error != nil || status == .error { return }

            if out.frameLength > 0, let data = int16Data(out) {
                let level = rmsInt16(out)
                onRMS?(level)
                onPCM?(data)
            }

            finished = status != .haveData
        }
    }

    private func int16Data(_ buf: AVAudioPCMBuffer) -> Data? {
        guard let ch = buf.int16ChannelData else { return nil }
        return Data(bytes: ch[0], count: Int(buf.frameLength) * 2)
    }

    private func rmsInt16(_ buf: AVAudioPCMBuffer) -> Float {
        let n = Int(buf.frameLength)
        guard n > 0, let ch = buf.int16ChannelData else { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            let v = Float(ch[0][i]) / 32768
            sum += v * v
        }
        return sqrt(sum / Float(n))
    }
}

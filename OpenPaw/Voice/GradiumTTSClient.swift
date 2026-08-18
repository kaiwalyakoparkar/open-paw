import AVFoundation
import Foundation
import OpenPawCore

final class GradiumTTSClient {
    private let config: GradiumConfig
    private var ws: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioStarted = false
    private var stopped = false
    private var ready = false
    private var readyContinuation: CheckedContinuation<Void, Error>?
    /// Serializes connect + send so concurrent speak() calls don't race the socket.
    private var sendChain: Task<Void, Never>?

    init(config: GradiumConfig) {
        self.config = config
        engine.attach(player)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
    }

    func speak(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendChain = Task { [weak self] in
            _ = await self?.sendChain?.value
            await self?.send(text)
        }
    }

    func stop() {
        stopped = true
        ready = false
        sendChain?.cancel()
        sendChain = nil
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: CancellationError())
        }
        player.stop()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        if engine.isRunning { engine.stop() }
        audioStarted = false
    }

    private func send(_ text: String) async {
        guard !stopped, !Task.isCancelled else { return }
        do {
            if ws == nil || !ready { try await connect() }
            guard !stopped, !Task.isCancelled, let ws else { return }
            let payload = try JSONSerialization.data(withJSONObject: ["text": text])
            try await ws.send(.string(String(data: payload, encoding: .utf8) ?? ""))
        } catch is CancellationError {
            return
        } catch {
            guard !stopped, !Task.isCancelled else { return }
            // One reconnect attempt for transient disconnects.
            ws?.cancel(with: .goingAway, reason: nil)
            ws = nil
            ready = false
            do {
                try await connect()
                guard !stopped, !Task.isCancelled, let ws else { return }
                let payload = try JSONSerialization.data(withJSONObject: ["text": text])
                try await ws.send(.string(String(data: payload, encoding: .utf8) ?? ""))
            } catch is CancellationError {
                return
            } catch {
                guard !stopped else { return }
                NSLog("open-paw tts: %@", error.localizedDescription)
            }
        }
    }

    private func connect() async throws {
        guard !config.apiKey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        stopped = false
        guard let url = URL(string: "wss://api.gradium.ai/api/speech/tts") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        let task = URLSession.shared.webSocketTask(with: req)
        ws = task
        ready = false
        task.resume()
        receiveLoop()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyContinuation = cont
            Task {
                do {
                    let setup: [String: Any] = [
                        "type": "setup",
                        "model_name": "default",
                        "voice_id": config.tts.voiceId,
                        "output_format": "pcm",
                    ]
                    let data = try JSONSerialization.data(withJSONObject: setup)
                    try await task.send(.string(String(data: data, encoding: .utf8) ?? "{}"))
                } catch {
                    if let readyContinuation = self.readyContinuation {
                        self.readyContinuation = nil
                        readyContinuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func receiveLoop() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.ready = false
                if let readyContinuation = self.readyContinuation {
                    self.readyContinuation = nil
                    readyContinuation.resume(throwing: URLError(.networkConnectionLost))
                }
            case .success(let msg):
                self.handle(msg)
                if !self.stopped { self.receiveLoop() }
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        if case .string(let s) = msg,
           let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            switch obj["type"] as? String ?? "" {
            case "ready":
                ready = true
                if let readyContinuation {
                    self.readyContinuation = nil
                    readyContinuation.resume()
                }
                return
            case "error":
                if let readyContinuation {
                    self.readyContinuation = nil
                    readyContinuation.resume(throwing: URLError(.badServerResponse))
                }
                return
            default:
                break
            }
        }
        play(msg)
    }

    private func play(_ msg: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch msg {
        case .data(let d): data = d
        case .string(let s):
            guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return }
            if let b64 = obj["audio"] as? String {
                data = Data(base64Encoded: b64)
            } else { data = nil }
        @unknown default: data = nil
        }
        guard let data, !data.isEmpty else { return }
        if !audioStarted {
            do {
                try engine.start()
                player.play()
                audioStarted = true
            } catch {
                NSLog("open-paw tts audio: %@", error.localizedDescription)
                return
            }
        }
        let frameCount = data.count / 2
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frameCount)),
              let ch = buf.floatChannelData
        else { return }
        buf.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                ch[0][i] = Float(src[i]) / 32768
            }
        }
        player.scheduleBuffer(buf, completionHandler: nil)
    }
}

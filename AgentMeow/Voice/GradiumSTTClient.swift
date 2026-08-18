import AVFoundation
import Foundation
import AgentMeowCore

enum GradiumSTTError: LocalizedError {
    case missingAPIKey
    case notReady
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Missing Gradium API key"
        case .notReady: "Gradium STT did not become ready"
        case .server(let msg): msg
        }
    }
}

final class GradiumSTTClient {
    enum Message {
        case text(String)
        case vad([Double])
        case endText(String)
        case flushed(Int)
        case error(String)
    }

    /// 80 ms @ 24 kHz mono int16 — Gradium's recommended chunk size.
    private static let chunkBytes = 1920 * 2

    private let config: GradiumConfig
    private var ws: URLSessionWebSocketTask?
    private var continuation: AsyncStream<Message>.Continuation?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var latestText = ""
    private var pcmPending = Data()
    private var flushID = 0

    private(set) lazy var messages: AsyncStream<Message> = {
        AsyncStream { cont in self.continuation = cont }
    }()

    init(config: GradiumConfig) {
        self.config = config
    }

    func connect() async throws {
        guard !config.apiKey.isEmpty else { throw GradiumSTTError.missingAPIKey }
        guard let url = URL(string: "wss://api.gradium.ai/api/speech/asr") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: req)
        ws = task
        task.resume()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyContinuation = cont
            receiveLoop()
            Task {
                do {
                    let setup: [String: Any] = [
                        "type": "setup",
                        "model_name": config.stt.modelName,
                        "input_format": "pcm_24000",
                        "json_config": [
                            "language": "en",
                            "delay_in_frames": config.stt.delayInFrames,
                        ],
                    ]
                    let data = try JSONSerialization.data(withJSONObject: setup)
                    try await task.send(.string(String(data: data, encoding: .utf8) ?? "{}"))
                } catch {
                    readyContinuation?.resume(throwing: error)
                    readyContinuation = nil
                }
            }
        }
    }

    func sendAudio(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        pcmPending.append(pcm)
        while pcmPending.count >= Self.chunkBytes {
            let chunk = pcmPending.prefix(Self.chunkBytes)
            pcmPending.removeFirst(Self.chunkBytes)
            emitAudioChunk(Data(chunk))
        }
    }

    /// Drain model delay buffer after flush — Gradium docs recommend silence padding.
    func sendSilencePadding(frames: Int) {
        guard frames > 0 else { return }
        let silence = Data(count: Self.chunkBytes)
        for _ in 0..<frames {
            emitAudioChunk(silence)
        }
    }

    func sendFlush() {
        if !pcmPending.isEmpty {
            emitAudioChunk(pcmPending)
            pcmPending.removeAll()
        }
        flushID += 1
        let id = flushID
        sendJSON(["type": "flush", "flush_id": id])
    }

    func sendEndOfStream() {
        sendJSON(["type": "end_of_stream"])
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        ws?.send(.string(json)) { _ in }
    }

    private func emitAudioChunk(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        let payload: [String: Any] = [
            "type": "audio",
            "audio": pcm.base64EncodedString(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        ws?.send(.string(json)) { _ in }
    }

    func close() {
        ws?.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: GradiumSTTError.notReady)
        }
    }

    private func receiveLoop() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.continuation?.finish()
                if let readyContinuation = self.readyContinuation {
                    self.readyContinuation = nil
                    readyContinuation.resume(throwing: GradiumSTTError.notReady)
                }
            case .success(let msg):
                self.handle(msg)
                self.receiveLoop()
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        let text: String?
        switch msg {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text, let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let type = obj["type"] as? String ?? ""

        switch type {
        case "ready":
            if let readyContinuation {
                self.readyContinuation = nil
                readyContinuation.resume()
            }
        case "error":
            let message = obj["message"] as? String ?? "Gradium STT error"
            continuation?.yield(.error(message))
            if let readyContinuation {
                self.readyContinuation = nil
                readyContinuation.resume(throwing: GradiumSTTError.server(message))
            }
        case "text":
            if let t = obj["text"] as? String {
                latestText = t
                continuation?.yield(.text(t))
            }
        case "end_text":
            continuation?.yield(.endText(latestText))
            latestText = ""
        case "flushed":
            let id = obj["flush_id"] as? Int ?? 0
            continuation?.yield(.flushed(id))
        case "step", "vad":
            if let probs = VADLogic.parseProbabilities(from: obj["vad"]) {
                continuation?.yield(.vad(probs))
            }
        default:
            break
        }
    }
}

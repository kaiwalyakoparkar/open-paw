import AVFoundation
import Foundation
import OpenPawCore

/// Gradium REST TTS with batched text + parallel prefetch + ordered playback.
final class GradiumTTSClient: NSObject, AVAudioPlayerDelegate {
    private let config: GradiumConfig
    private var stopped = false
    private var started = false
    private var chunkBuffer = TTSChunkBuffer()
    private var coalesceTask: Task<Void, Never>?

    private var synthSeq: UInt64 = 0
    private var playSeq: UInt64 = 0
    private var audioBySeq: [UInt64: Data] = [:]
    private var pending: [AVAudioPlayer] = []
    private var current: AVAudioPlayer?

    /// ponytail: 120ms coalesce — batch fragments without waiting for full minChars
    private let coalesceNs: UInt64 = 120_000_000

    init(config: GradiumConfig) {
        self.config = config
        super.init()
    }

    func speak(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stopped = false
        let chunks: [String]
        if started {
            chunks = chunkBuffer.push(text + " ")
        } else {
            started = true
            chunks = chunkBuffer.pushFirst(text + " ")
        }
        for c in chunks { startSynthesis(c) }
        scheduleCoalesce()
    }

    func finishSpeaking() {
        coalesceTask?.cancel()
        coalesceTask = nil
        if let rest = chunkBuffer.flush() { startSynthesis(rest) }
        started = false
    }

    func stop() {
        stopped = true
        started = false
        coalesceTask?.cancel()
        coalesceTask = nil
        chunkBuffer = TTSChunkBuffer()
        synthSeq = 0
        playSeq = 0
        audioBySeq.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.current?.stop()
            self?.current = nil
            self?.pending.forEach { $0.stop() }
            self?.pending.removeAll()
        }
    }

    private func scheduleCoalesce() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.coalesceNs ?? 120_000_000)
            guard let self, !self.stopped else { return }
            let chunks = self.chunkBuffer.emitReady()
            for c in chunks { self.startSynthesis(c) }
        }
    }

    private func startSynthesis(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let seq = synthSeq
        synthSeq += 1
        Task { [weak self] in
            await self?.synthesize(trimmed, seq: seq)
        }
    }

    private func synthesize(_ text: String, seq: UInt64) async {
        guard !stopped else { return }
        do {
            let audio = try await GradiumTTSSynthesize.fetch(text: text, config: config)
            guard !stopped else { return }
            await MainActor.run { [weak self] in
                self?.audioBySeq[seq] = audio
                self?.drainOrderedPlayback()
            }
        } catch {
            guard !stopped else { return }
            NSLog("open-paw tts: %@", error.localizedDescription)
            await MainActor.run { [weak self] in
                self?.skipMissing(seq: seq)
            }
        }
    }

    @MainActor
    private func skipMissing(seq: UInt64) {
        guard seq == playSeq else { return }
        playSeq += 1
        drainOrderedPlayback()
    }

    @MainActor
    private func drainOrderedPlayback() {
        while let audio = audioBySeq.removeValue(forKey: playSeq) {
            enqueue(audio)
            playSeq += 1
        }
    }

    @MainActor
    private func enqueue(_ data: Data) {
        guard !stopped else { return }
        guard let player = try? AVAudioPlayer(data: data) else {
            NSLog("open-paw tts audio: decode failed (%d bytes)", data.count)
            return
        }
        player.delegate = self
        pending.append(player)
        playNextIfIdle()
    }

    @MainActor
    private func playNextIfIdle() {
        guard current?.isPlaying != true else { return }
        guard !pending.isEmpty else {
            current = nil
            return
        }
        let next = pending.removeFirst()
        current = next
        next.prepareToPlay()
        if !next.play() {
            NSLog("open-paw tts audio: play() returned false")
            current = nil
            playNextIfIdle()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.current === player { self.current = nil }
            self.playNextIfIdle()
        }
    }
}

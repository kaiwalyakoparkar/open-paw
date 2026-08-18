import AppKit
import AgentMeowCore
import AVFoundation
import Foundation

enum BuddyState: String {
    case idle, listening, thinking, speaking, annotate
}

@MainActor
final class CompanionManager: NSObject {
    let config: AppConfig
    private(set) var state: BuddyState = .idle {
        didSet {
            buddy?.setState(state)
            if state != .annotate { dismissOverlay() }
            resetIdleTimer()
        }
    }

    private var messages: [ChatMessage] = []
    private var buddy: BuddyWindow?
    private var overlay: AnnotationOverlayWindow?
    private var frozenShot: NSImage?
    private var strokes: [AnnotationStroke] = []
    private var holdMonitor: HoldToTalkMonitor?
    private var idleTimer: Timer?
    private var hermes: HermesAPIClient?
    private var stt: GradiumSTTClient?
    private var tts: GradiumTTSClient?
    private var capture: AudioCapture?
    private var sentence = SentenceBuffer()
    private var vad: VADLogic
    private var currentAssistant = ""
    private var toolNotes = ""
    private var spokenPrompt = ""
    private var waitStatus = ""
    private var waitStarted = Date()
    private var waitTimer: Timer?
    private var listenTask: Task<Void, Never>?
    private var turnLocked = false
    private var listeningAnnotate = false
    private var micDecayTask: Task<Void, Never>?
    private var micLevel: Float = 0
    private var peakMicLevel: Float = 0
    private var latestTranscript = ""
    private var pendingSend = false
    private var captureStarted = false
    private var isHoldingKey = false

    init(config: AppConfig) {
        self.config = config
        self.vad = VADLogic(
            horizonIndex: config.gradium.stt.vadHorizonIndex,
            threshold: config.gradium.stt.vadThreshold,
            consecutiveNeeded: config.gradium.stt.vadConsecutiveFrames
        )
        super.init()
    }

    func start() {
        let size = config.ui.buddySize
        let holdLabel = HotkeyKeyMap.displayLabel(for: config.hotkey.hold)
        let win = BuddyWindow(
            size: size,
            holdKeyLabel: holdLabel,
            onTap: { [weak self] in self?.buddyTap() },
            onStop: { [weak self] in self?.cancelSession() },
            onSend: { [weak self] in self?.sendSpeech() },
            onAnnotate: { [weak self] in self?.beginAnnotate() }
        )
        win.place(position: config.ui.defaultPosition)
        win.setState(.idle)
        buddy = win

        let monitor = HoldToTalkMonitor(
            combo: config.hotkey.hold,
            onBegin: { [weak self] in
                DispatchQueue.main.async { self?.beginHoldRecording() }
            },
            onEnd: { [weak self] in
                DispatchQueue.main.async { self?.endHoldRecording() }
            }
        )
        monitor.register()
        holdMonitor = monitor
        if !monitor.isRegistered {
            buddy?.setBubble(.error("Grant Accessibility for hold-to-talk — System Settings → Privacy"))
        }

        hermes = HermesAPIClient(config: config.hermes)
        tts = GradiumTTSClient(config: config.gradium)
        if config.gradium.apiKey.isEmpty {
            buddy?.setBubble(.error("Add gradium.api_key to ~/.config/agent-meow/config.json"))
        }
        if config.hermes.apiKey.isEmpty {
            buddy?.setBubble(.error("Add hermes.api_key to ~/.config/agent-meow/config.json"))
        }
    }

    /// Tap avatar while active → stop/cancel. Idle tap is no-op.
    func buddyTap() {
        guard state != .idle else { return }
        cancelSession()
    }

    func cancelSession() {
        isHoldingKey = false
        buddy?.setHoldingKey(false)
        sleep()
    }

    func beginHoldRecording() {
        guard !config.gradium.apiKey.isEmpty else {
            buddy?.setBubble(.error("Missing Gradium API key — edit ~/.config/agent-meow/config.json"))
            return
        }
        guard state == .idle else { return }
        isHoldingKey = true
        buddy?.setHoldingKey(true)
        buddy?.setBubble(.none)
        state = .listening
        startListening()
    }

    func endHoldRecording() {
        isHoldingKey = false
        buddy?.setHoldingKey(false)
        guard state == .listening, !turnLocked else { return }
        commitListeningEnd()
    }

    func sendSpeech() {
        guard state == .listening, !turnLocked else { return }
        commitListeningEnd()
    }

    /// Always flush STT and enter thinking — interim transcript may still be empty.
    private func commitListeningEnd() {
        let interim = STTCommit.mergeTranscript(latestTranscript, buddy?.currentTranscript ?? "")
        if !interim.isEmpty { latestTranscript = interim }
        buddy?.setBubble(.processing(interim))
        state = .thinking
        if stt != nil {
            pendingSend = false
            flushSTT()
            applySTTCommit(.userReleased)
        } else {
            pendingSend = true
        }
    }

    private func flushSTT() {
        stt?.sendFlush()
        stt?.sendSilencePadding(frames: config.gradium.stt.delayInFrames)
        // ponytail: skip end_of_stream here — it can drop flushed/end_text; close() in endTurn is enough
    }

    private func finishPendingSendIfNeeded() {
        guard pendingSend, STTCommit.canFlushAfterRelease(captureStarted: captureStarted),
              state == .thinking, stt != nil, !turnLocked else { return }
        pendingSend = false
        flushSTT()
        applySTTCommit(.userReleased)
    }

    func sleep() {
        listenTask?.cancel()
        micDecayTask?.cancel()
        endTurnFallback?.cancel()
        pendingSend = false
        captureStarted = false
        turnLocked = false
        hermes?.cancel()
        tts?.stop()
        capture?.stop()
        stt?.close()
        stt = nil
        dismissOverlay()
        messages.removeAll()
        currentAssistant = ""
        toolNotes = ""
        spokenPrompt = ""
        waitStatus = ""
        stopWaitProgress()
        sentence = SentenceBuffer()
        vad.reset()
        listeningAnnotate = false
        buddy?.setHoldingKey(false)
        buddy?.setMicLevel(0)
        micLevel = 0
        peakMicLevel = 0
        latestTranscript = ""
        isHoldingKey = false
        state = .idle
        buddy?.setBubble(.none)
    }

    func beginAnnotate() {
        guard state == .idle else { return }
        turnLocked = false
        guard !config.hermes.apiKey.isEmpty else {
            buddy?.setBubble(.error("Add hermes.api_key to ~/.config/agent-meow/config.json"))
            return
        }
        dismissOverlay()
        frozenShot = ScreenCapture.mainDisplayImage()
        strokes = []
        let ov = AnnotationOverlayWindow(
            onStroke: { [weak self] stroke in
                self?.strokes.append(stroke)
            },
            onFinishShape: { [weak self] in
                self?.finishAnnotate()
            },
            onCancel: { [weak self] in
                self?.cancelSession()
            }
        )
        overlay = ov
        NSApp.activate()
        ov.makeKeyAndOrderFront(nil)
        state = .annotate
    }

    private func finishAnnotate() {
        guard state == .annotate else { return }
        turnLocked = true
        dismissOverlay()
        let prompt = AnnotatePrompt.userText()
        buddy?.setBubble(.processing("Explain this"))
        spokenPrompt = "Explain this"
        waitStatus = ""
        state = .thinking

        let image = AnnotatedImageComposer.compose(screenshot: frozenShot, strokes: strokes)
        var parts: [ContentPart] = [.text(prompt)]
        if let url = image.flatMap({ ScreenshotEncoder.dataURL($0) }) {
            parts.insert(.imageURL(url), at: 0)
        }
        messages.append(ChatMessage(role: "user", content: .parts(parts)))
        listeningAnnotate = false
        strokes = []
        frozenShot = nil

        Task { await runHermes() }
    }

    private func dismissOverlay() {
        guard let overlay else { return }
        overlay.dismiss()
        self.overlay = nil
        buddy?.orderFrontRegardless()
    }

    private func startListening(annotate: Bool = false) {
        listenTask?.cancel()
        micDecayTask?.cancel()
        tts?.stop()
        capture?.stop()
        stt?.close()
        vad.reset()
        listeningAnnotate = annotate
        captureStarted = false
        buddy?.setMicLevel(0)
        micLevel = 0
        peakMicLevel = 0
        latestTranscript = ""
        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.runListenLoop(annotate: annotate)
        }
        startMicDecay()
    }

    private func startMicDecay() {
        micDecayTask?.cancel()
        micDecayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self else { return }
                let current = self.micLevel
                if current > 0.01 {
                    self.micLevel = current * 0.82
                    self.buddy?.setMicLevel(self.micLevel)
                }
            }
        }
    }

    private func runListenLoop(annotate: Bool) async {
        do {
            let micOK = await Self.requestMicAccess()
            guard micOK else {
                buddy?.setBubble(.error("Microphone access denied — enable in System Settings → Privacy"))
                isHoldingKey = false
                turnLocked = false
                state = .idle
                buddy?.setHoldingKey(false)
                return
            }

            let cap = AudioCapture()
            capture = cap
            cap.onRMS = { [weak self] rms in
                guard let self else { return }
                Task { @MainActor in
                    if self.state == .speaking, rms > 0.08, self.currentAssistant.count >= 24 {
                        self.bargeIn()
                    } else if self.state == .listening || self.state == .thinking {
                        let boosted = min(rms * 8, 1)
                        self.micLevel = max(boosted, self.micLevel * 0.85)
                        self.peakMicLevel = max(self.peakMicLevel, self.micLevel)
                        self.buddy?.setMicLevel(self.micLevel)
                    }
                }
            }
            try cap.start()
            await MainActor.run { self.captureStarted = true }

            let client = GradiumSTTClient(config: config.gradium)
            stt = client
            cap.onPCM = { [weak client] data in
                client?.sendAudio(data)
            }
            try await client.connect()
            await MainActor.run {
                self.finishPendingSendIfNeeded()
            }

            for await msg in client.messages {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.handleSTT(msg, annotate: annotate)
                }
            }
        } catch {
            NSLog("agent-meow listen: %@", error.localizedDescription)
            await MainActor.run {
                self.isHoldingKey = false
                self.buddy?.setBubble(.error("Mic/STT error: \(error.localizedDescription)"))
                self.buddy?.setHoldingKey(false)
                self.turnLocked = false
                self.state = .idle
            }
        }
    }

    private func handleSTT(_ msg: GradiumSTTClient.Message, annotate: Bool) {
        switch msg {
        case .text(let t):
            latestTranscript = STTCommit.mergeTranscript(latestTranscript, t)
            if state == .listening || state == .thinking {
                buddy?.setBubble(state == .thinking ? .processing(latestTranscript) : .listening(latestTranscript))
            }
        case .vad(let arr):
            if listeningAnnotate, vad.ingest(vad: arr) {
                let final = STTCommit.mergeTranscript(latestTranscript, buddy?.currentTranscript ?? "")
                if !final.isEmpty { latestTranscript = final }
                buddy?.setBubble(.processing(final))
                state = .thinking
                flushSTT()
                applySTTCommit(.userReleased)
            } else {
                _ = vad.ingest(vad: arr)
            }
        case .endText(let t):
            latestTranscript = STTCommit.mergeTranscript(latestTranscript, t)
            let final = latestTranscript
            // Hold-to-talk: Gradium may end an utterance on silence while key still held.
            guard !isHoldingKey else {
                if state == .listening {
                    buddy?.setBubble(.listening(final))
                }
                return
            }
            buddy?.setBubble(.processing(final))
            state = .thinking
            applySTTCommit(.endText)
        case .flushed:
            guard state == .thinking else { return }
            applySTTCommit(.flushed)
        case .error(let message):
            isHoldingKey = false
            buddy?.setBubble(.error(message))
            turnLocked = false
            state = .idle
            buddy?.setHoldingKey(false)
        }
    }

    private var endTurnFallback: Task<Void, Never>?

    private func applySTTCommit(_ event: STTCommit.Event) {
        switch STTCommit.action(event, delayInFrames: config.gradium.stt.delayInFrames) {
        case .sendNow:
            endTurnFallback?.cancel()
            Task { await endTurn(annotate: listeningAnnotate) }
        case .wait(let ns):
            scheduleEndTurnFallback(delayNs: ns)
        }
    }

    /// If Gradium never sends flushed/end_text after commit, send with latest transcript.
    private func scheduleEndTurnFallback(delayNs: UInt64) {
        endTurnFallback?.cancel()
        endTurnFallback = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, let self else { return }
            await self.endTurn(annotate: listeningAnnotate)
        }
    }

    private static func requestMicAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { cont in
                    AVAudioApplication.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func endTurn(transcript: String? = nil, annotate: Bool) async {
        guard state == .listening || state == .thinking || state == .annotate else { return }
        guard !isHoldingKey else { return }
        guard !turnLocked else { return }
        turnLocked = true
        endTurnFallback?.cancel()
        capture?.stop()
        stt?.close()
        let text = (transcript ?? latestTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            turnLocked = false
            listenTask?.cancel()
            capture?.stop()
            stt?.close()
            stt = nil
            let msg = peakMicLevel > 0.02
                ? "Speech reached mic but STT returned nothing — check network or Gradium key"
                : "No mic input detected — check System Settings → Privacy → Microphone"
            buddy?.setBubble(.error(msg))
            isHoldingKey = false
            state = .idle
            buddy?.setHoldingKey(false)
            return
        }

        buddy?.setBubble(.processing(text))
        spokenPrompt = text
        waitStatus = ""
        state = .thinking

        if annotate {
            let image = AnnotatedImageComposer.compose(screenshot: frozenShot, strokes: strokes)
            dismissOverlay()
            var parts: [ContentPart] = [.text(AnnotatePrompt.userText(spoken: text))]
            if let url = image.flatMap({ ScreenshotEncoder.dataURL($0) }) {
                parts.insert(.imageURL(url), at: 0)
            }
            messages.append(ChatMessage(role: "user", content: .parts(parts)))
        } else {
            messages.append(.text(role: "user", ObsidianNotes.wrap(text)))
        }

        await runHermes()
    }

    private func runHermes() async {
        currentAssistant = ""
        toolNotes = ""
        sentence = SentenceBuffer()
        startWaitProgress()
        do {
            let result = try await hermes?.stream(
                messages: messages,
                onDelta: { [weak self] d in
                    Task { @MainActor in self?.onHermesDelta(d) }
                },
                onTool: { [weak self] t in
                    Task { @MainActor in
                        self?.toolNotes += "\n[tool \(t.name ?? "?")]"
                    }
                },
                onProgress: { [weak self] p in
                    Task { @MainActor in
                        guard let self, self.currentAssistant.isEmpty else { return }
                        self.waitStatus = p
                        self.refreshWaitBubble()
                    }
                }
            )
            await MainActor.run {
                self.finishHermes(text: result?.text ?? self.currentAssistant)
            }
        } catch {
            await MainActor.run {
                self.stopWaitProgress()
                self.buddy?.setBubble(.error("Hermes: \(error.localizedDescription)"))
                self.turnLocked = false
                self.state = .idle
            }
        }
    }

    private func startWaitProgress() {
        waitStarted = Date()
        waitTimer?.invalidate()
        waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshWaitBubble() }
        }
        refreshWaitBubble()
    }

    private func refreshWaitBubble() {
        guard state == .thinking, currentAssistant.isEmpty else { return }
        let seconds = Int(Date().timeIntervalSince(waitStarted))
        buddy?.setBubble(.processing(HermesProgress.waitBubble(
            prompt: spokenPrompt,
            status: waitStatus,
            seconds: seconds
        )))
    }

    private func stopWaitProgress() {
        waitTimer?.invalidate()
        waitTimer = nil
    }

    private func onHermesDelta(_ d: String) {
        guard state != .idle else { return }
        stopWaitProgress()
        currentAssistant += d
        buddy?.setBubble(.responding(currentAssistant))
        if state != .speaking { state = .speaking }
        let bits = sentence.push(d)
        for s in bits { tts?.speak(s) }
    }

    private func finishHermes(text: String) {
        defer { turnLocked = false }
        guard state != .idle else { return }
        stopWaitProgress()
        if let rest = sentence.flush() { tts?.speak(rest) }
        var stored = text
        if !toolNotes.isEmpty {
            stored += toolNotes
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            buddy?.setBubble(.error("Hermes returned nothing — check the server at \(config.hermes.baseURL)"))
            state = .idle
            return
        }
        messages.append(.text(role: "assistant", stored))
        buddy?.setBubble(.responding(stored))
        state = .idle
    }

    func bargeIn() {
        stopWaitProgress()
        hermes?.cancel()
        tts?.stop()
        var partial = currentAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            if !toolNotes.isEmpty { partial += toolNotes }
            partial += " [interrupted — tools may have already executed]"
            messages.append(.text(role: "assistant", partial))
        }
        currentAssistant = ""
        turnLocked = false
        state = .listening
        startListening()
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        guard state != .idle else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: config.ui.idleTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        }
    }

}

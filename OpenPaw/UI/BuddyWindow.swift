import AppKit
import OpenPawCore
import SwiftUI

final class BuddyWindow: NSPanel {
    private let avatarSize: CGFloat
    private let onTap: () -> Void
    private let onStop: () -> Void
    private let onSend: () -> Void
    private let onAnnotate: () -> Void
    private let onFinishAnnotate: () -> Void
    private let hosting: NSHostingView<BuddyView>
    private var model: BuddyViewModel
    private var dockPosition = "bottom-right"
    private var downTime: Date = .distantPast
    private var dragging = false
    private var dragArmed = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var userPlaced = false
    /// Locked window bottom-left. Set on first dock place or drag; never recentered.
    private var anchorOrigin: NSPoint?
    private var layoutExpanded = false

    var currentTranscript: String { model.bubble.displayText }

    init(
        size: CGFloat,
        holdKeyLabel: String,
        onTap: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onAnnotate: @escaping () -> Void,
        onFinishAnnotate: @escaping () -> Void
    ) {
        self.avatarSize = size
        self.onTap = onTap
        self.onStop = onStop
        self.onSend = onSend
        self.onAnnotate = onAnnotate
        self.onFinishAnnotate = onFinishAnnotate
        let model = BuddyViewModel()
        model.holdKeyLabel = holdKeyLabel
        self.model = model
        let view = BuddyView(
            model: model,
            size: avatarSize,
            onStop: onStop,
            onAnnotate: onAnnotate,
            onFinishAnnotate: onFinishAnnotate
        )
        hosting = NSHostingView(rootView: view)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size + 32, height: size + 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        // Empty sizingOptions: we own the frame. .minSize hugs the cat and clips the pills.
        hosting.sizingOptions = []
        hosting.clipsToBounds = false
        hosting.autoresizingMask = [.width, .height]
        isMovableByWindowBackground = false
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0 }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            applyDrag(
                BuddyLayout.originAfterDragEvent(
                    armed: false,
                    startOrigin: .zero,
                    startMouse: .zero,
                    currentOrigin: frame.origin,
                    currentMouse: NSEvent.mouseLocation
                ),
                move: false
            )
            dragging = false
            downTime = Date()
        }
        super.sendEvent(event)
        if event.type == .leftMouseUp { dragArmed = false }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if model.state == .annotate { onStop() }
    }

    override func keyDown(with event: NSEvent) {
        if model.state == .annotate, AnnotateOverlayInput.command(keyCode: event.keyCode) == .cancel {
            onStop()
            return
        }
        super.keyDown(with: event)
    }

    func show(at position: String) {
        dockPosition = position
        orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.anchorOrigin == nil {
                self.placeOnDock()
            }
        }
    }

    func place(position: String) {
        show(at: position)
    }

    /// Primary display — menu bar + dock live here.
    private static func screenWithDock() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    private var isLayoutExpanded: Bool {
        model.state != .idle || model.bubble.isVisible || model.isHoldingKey
    }

    /// Listening is one status line — skip the 200pt wait-bubble floor.
    private var hugsListeningHeight: Bool {
        model.state == .listening || (model.state == .idle && model.isHoldingKey)
    }

    /// Initial dock placement only. Later resizes keep the cat's bottom-center.
    private func placeOnDock() {
        guard !dragging, let screen = Self.screenWithDock() else { return }
        let sized = BuddyLayout.fixedSize(avatarSize: avatarSize, expanded: isLayoutExpanded)
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: xOnDock(position: dockPosition, visible: visible, width: sized.width),
            y: visible.minY + 8
        )
        anchorOrigin = origin
        layoutExpanded = isLayoutExpanded
        applyFrame(NSRect(origin: origin, size: sized))
    }

    /// Grow/shrink around the cat's bottom-center. Ceiling rises with output; cat stays.
    private func resizeKeepingAnchor() {
        guard !dragging, let screen = Self.screenWithDock(), anchorOrigin != nil else { return }
        let sized = targetSize(visible: screen.visibleFrame)
        let newFrame = BuddyLayout.frameKeepingCatCenter(
            current: frame,
            newSize: sized,
            visible: screen.visibleFrame
        )
        applyFrame(newFrame)
        anchorOrigin = newFrame.origin
    }

    private func targetSize(visible: NSRect) -> CGSize {
        if !isLayoutExpanded {
            return BuddyLayout.fixedCollapsedSize(avatarSize: avatarSize)
        }
        let cap = max(visible.maxY - frame.minY, BuddyLayout.fixedCollapsedSize(avatarSize: avatarSize).height)
        let text = model.bubble.displayText
        return BuddyLayout.expandedWindowSize(
            bodyHeight: BuddyLayout.bodyHeight(for: text),
            avatarSize: avatarSize,
            maxHeight: cap,
            minPillHeight: hugsListeningHeight ? 0 : BuddyLayout.pillMinHeight
        )
    }

    private func syncLayoutIfNeeded() {
        guard !dragging else { return }
        if anchorOrigin == nil {
            placeOnDock()
            return
        }
        guard let screen = Self.screenWithDock() else { return }
        let expanded = isLayoutExpanded
        let sized = targetSize(visible: screen.visibleFrame)
        let sizeChanged = abs(frame.width - sized.width) > 0.5 || abs(frame.height - sized.height) > 0.5
        guard expanded != layoutExpanded || sizeChanged else { return }
        layoutExpanded = expanded
        resizeKeepingAnchor()
    }

    private func applyFrame(_ rect: NSRect) {
        setFrame(rect, display: true)
        hosting.frame = CGRect(origin: .zero, size: rect.size)
    }

    /// macOS dock is centered — anchor to dock, not screen edge.
    private func xOnDock(position: String, visible: NSRect, width w: CGFloat) -> CGFloat {
        let center = visible.midX - w / 2
        let offset = visible.width * 0.10
        let x: CGFloat
        switch position {
        case "bottom-left":  x = center - offset
        case "bottom-center": x = center
        default:             x = center + offset
        }
        return min(max(x, visible.minX + 8), visible.maxX - w - 8)
    }

    private static let activeLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    func setState(_ state: BuddyState) {
        model.state = state
        if state != .annotate { model.annotateHasStrokes = false }
        // Above overlay during annotate so Stop / Esc on kitty work; overlay still covers the rest.
        level = state == .idle ? .floating : Self.activeLevel
        orderFrontRegardless()
        syncLayoutIfNeeded()
    }

    func setBubble(_ content: BubbleContent) {
        model.bubble = content
        syncLayoutIfNeeded()
    }

    func setMicLevel(_ level: Float) {
        model.micLevel = level
    }

    func setAnnotateHasStrokes(_ hasStrokes: Bool) {
        model.annotateHasStrokes = hasStrokes
    }

    func setHoldingKey(_ holding: Bool) {
        model.isHoldingKey = holding
        syncLayoutIfNeeded()
    }

    override func mouseDragged(with event: NSEvent) {
        applyDrag(
            BuddyLayout.originAfterDragEvent(
                armed: dragArmed,
                startOrigin: dragStartOrigin,
                startMouse: dragStartMouse,
                currentOrigin: frame.origin,
                currentMouse: NSEvent.mouseLocation
            ),
            move: true
        )
    }

    private func applyDrag(_ step: BuddyLayout.DragStep, move: Bool) {
        dragArmed = step.armed
        dragStartOrigin = step.startOrigin
        dragStartMouse = step.startMouse
        guard move else { return }
        let dx = step.frameOrigin.x - dragStartOrigin.x
        let dy = step.frameOrigin.y - dragStartOrigin.y
        if hypot(dx, dy) > 3 { dragging = true }
        if dragging {
            userPlaced = true
            let origin: NSPoint
            if let screen = Self.screenWithDock() {
                origin = BuddyLayout.placedFrame(
                    origin: step.frameOrigin,
                    size: frame.size,
                    visible: screen.visibleFrame
                ).origin
            } else {
                origin = step.frameOrigin
            }
            setFrameOrigin(origin)
            anchorOrigin = origin
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp { return }
        if dragging {
            userPlaced = true
            anchorOrigin = frame.origin
            dragging = false
            syncLayoutIfNeeded()
            return
        }
        dragging = false
        let dt = Date().timeIntervalSince(downTime)
        guard dt < 0.3 else { return }
        let p = event.locationInWindow
        // Pill (top) — Stop / Explain / dismiss handle their own clicks.
        if p.y > hosting.bounds.height * 0.45 { return }
        if model.state == .idle {
            onAnnotate()
        } else {
            onTap()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let menu = NSMenu()
        if model.state != .idle {
            menu.addItem(withTitle: "Stop", action: #selector(stopListening), keyEquivalent: "")
            menu.items.last?.target = self
            if model.state == .listening {
                menu.addItem(withTitle: "Send speech", action: #selector(sendSpeech), keyEquivalent: "")
                menu.items.last?.target = self
            }
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Explain this", action: #selector(annotate), keyEquivalent: "")
        menu.items.last?.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: hosting)
    }

    @objc private func stopListening() { onStop() }

    @objc private func sendSpeech() { onSend() }

    @objc private func annotate() { onAnnotate() }
}

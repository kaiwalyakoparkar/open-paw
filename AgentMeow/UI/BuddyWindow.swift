import AppKit
import AgentMeowCore
import SwiftUI

final class BuddyWindow: NSPanel {
    private let avatarSize: CGFloat
    private let onTap: () -> Void
    private let onStop: () -> Void
    private let onSend: () -> Void
    private let onAnnotate: () -> Void
    private let hosting: NSHostingView<BuddyView>
    private var model: BuddyViewModel
    private var dockPosition = "bottom-right"
    private var downTime: Date = .distantPast
    private var dragging = false
    private var dragArmed = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var userPlaced = false

    var currentTranscript: String { model.bubble.displayText }

    init(
        size: CGFloat,
        holdKeyLabel: String,
        onTap: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onAnnotate: @escaping () -> Void
    ) {
        self.avatarSize = size
        self.onTap = onTap
        self.onStop = onStop
        self.onSend = onSend
        self.onAnnotate = onAnnotate
        let model = BuddyViewModel()
        model.holdKeyLabel = holdKeyLabel
        self.model = model
        let view = BuddyView(model: model, size: avatarSize, onStop: onStop, onAnnotate: onAnnotate)
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
        // minSize lets setFrame grow; intrinsicContentSize hugs avatar-sized
        // SwiftUI size and clips the 420pt wait bubble after we resize.
        hosting.sizingOptions = .minSize
        hosting.clipsToBounds = false
        hosting.autoresizingMask = [.width, .height]
        isMovableByWindowBackground = false
    }

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
            self?.repositionOnDock()
        }
    }

    func place(position: String) {
        show(at: position)
    }

    /// Primary display — menu bar + dock live here.
    private static func screenWithDock() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    private func repositionOnDock() {
        guard !dragging, let screen = Self.screenWithDock() else { return }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        let intrinsic = hosting.intrinsicContentSize
        let content = CGSize(
            width: max(fit.width, intrinsic.width),
            height: max(fit.height, intrinsic.height)
        )
        let expanded = model.state != .idle || model.bubble.isVisible || model.isHoldingKey
        let sized = BuddyLayout.windowSize(fitting: content, avatarSize: avatarSize, expanded: expanded)
        let visible = screen.visibleFrame
        if userPlaced {
            setFrame(BuddyLayout.placedFrame(origin: frame.origin, size: sized, visible: visible), display: true)
            hosting.frame = CGRect(origin: .zero, size: sized)
            return
        }
        let w = sized.width
        let h = sized.height
        let y = visible.minY + 8
        let x = xOnDock(position: dockPosition, visible: visible, width: w)
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        hosting.frame = CGRect(origin: .zero, size: sized)
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
        // Above overlay during annotate so Stop / Esc on kitty work; overlay still covers the rest.
        level = state == .idle ? .floating : Self.activeLevel
        orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.repositionOnDock()
        }
    }

    func setBubble(_ content: BubbleContent) {
        model.bubble = content
        DispatchQueue.main.async { [weak self] in
            self?.repositionOnDock()
        }
    }

    func setMicLevel(_ level: Float) {
        model.micLevel = level
    }

    func setHoldingKey(_ holding: Bool) {
        model.isHoldingKey = holding
        DispatchQueue.main.async { [weak self] in
            self?.repositionOnDock()
        }
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
            setFrameOrigin(step.frameOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp { return }
        let dt = Date().timeIntervalSince(downTime)
        guard !dragging, dt < 0.3 else { return }
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

import AppKit
import OpenPawCore
import SwiftUI

private enum ExplainTheme {
    static let stroke = Color(red: 0.72, green: 0.38, blue: 1.0)
    static let strokeGlow = Color(red: 0.72, green: 0.38, blue: 1.0).opacity(0.55)
    static let accent = Color.purple
    static let dim = Color.black.opacity(0.28)
    static let vignette = Color.purple.opacity(0.06)
}

final class OverlayModel: ObservableObject {
    @Published var isVisible = true
}

final class AnnotationOverlayWindow: NSPanel {
    private let model = OverlayModel()
    private let onCancel: () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var settled = false

    override var canBecomeKey: Bool { true }

    init(
        onStroke: @escaping (AnnotationStroke) -> Void,
        onUndo: @escaping () -> Void,
        onFinishShape: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        let screen = NSScreen.main?.frame ?? .zero
        super.init(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen, display: true)
        contentView = NSHostingView(
            rootView: AnnotationOverlayView(
                model: model,
                onStroke: onStroke,
                onUndo: onUndo,
                onFinishShape: onFinishShape,
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        ignoresMouseEvents = false
        let onEsc: (NSEvent) -> Bool = { [weak self] event in
            guard AnnotateOverlayInput.command(keyCode: event.keyCode) == .cancel else { return false }
            self?.cancel()
            return true
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onEsc(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = onEsc(event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    override func keyDown(with event: NSEvent) {
        if AnnotateOverlayInput.command(keyCode: event.keyCode) == .cancel {
            cancel()
            return
        }
        super.keyDown(with: event)
    }

    func cancel() {
        guard !settled else { return }
        settled = true
        teardown()
        onCancel()
    }

    func dismiss() {
        guard !settled else { return }
        settled = true
        teardown()
    }

    private func teardown() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        model.isVisible = false
        ignoresMouseEvents = true
        alphaValue = 0
        orderOut(nil)
        close()
    }
}

struct AnnotationOverlayView: View {
    @ObservedObject var model: OverlayModel
    var onStroke: (AnnotationStroke) -> Void
    var onUndo: () -> Void
    var onFinishShape: () -> Void
    var onCancel: () -> Void
    @State private var current: [CGPoint] = []
    @State private var committed: [AnnotationStroke] = []

    private var hasStrokes: Bool { !committed.isEmpty || !current.isEmpty }

    var body: some View {
        if !model.isVisible {
            Color.clear.allowsHitTesting(false)
        } else {
            GeometryReader { geo in
                drawingLayer(size: geo.size)
            }
            .onExitCommand(perform: onCancel)
            .background {
                Button("") { commitAndFinish() }
                    .keyboardShortcut(.return, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { undoLast() }
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private func drawingLayer(size: CGSize) -> some View {
        ZStack {
            ExplainTheme.dim
            RadialGradient(
                colors: [.clear, ExplainTheme.vignette],
                center: .center,
                startRadius: size.width * 0.2,
                endRadius: max(size.width, size.height) * 0.75
            )
            Canvas { ctx, canvasSize in
                let all = committed + (current.isEmpty ? [] : [AnnotationStroke(points: current)])
                for stroke in all {
                    draw(stroke, in: &ctx, size: canvasSize)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let n = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                    current.append(n)
                }
                .onEnded { _ in
                    if !current.isEmpty {
                        let s = AnnotationStroke(points: current)
                        committed.append(s)
                        onStroke(s)
                        current = []
                    }
                }
        )
    }

    private func undoLast() {
        guard !committed.isEmpty else { return }
        committed.removeLast()
        onUndo()
    }

    private func commitAndFinish() {
        guard hasStrokes else { return }
        if !current.isEmpty {
            let s = AnnotationStroke(points: current)
            committed.append(s)
            onStroke(s)
            current = []
        }
        onFinishShape()
    }

    private func draw(_ stroke: AnnotationStroke, in ctx: inout GraphicsContext, size: CGSize) {
        let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: first)
        pts.dropFirst().forEach { path.addLine(to: $0) }

        let style = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)

        var glow = ctx
        glow.addFilter(.blur(radius: 5))
        glow.stroke(path, with: .color(ExplainTheme.strokeGlow), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

        ctx.stroke(path, with: .color(ExplainTheme.stroke), style: style)
        ctx.stroke(path, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }
}

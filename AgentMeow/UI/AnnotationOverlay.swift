import AppKit
import AgentMeowCore
import SwiftUI

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
                onFinishShape: onFinishShape,
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        ignoresMouseEvents = false
        // Local: this app is key. Global: overlay is nonactivating so Esc often hits the app below.
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
    var onFinishShape: () -> Void
    var onCancel: () -> Void
    @State private var tool: AnnotationTool = .freehand
    @State private var current: [CGPoint] = []
    @State private var committed: [AnnotationStroke] = []

    var body: some View {
        if !model.isVisible {
            Color.clear.allowsHitTesting(false)
        } else {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    drawingLayer(size: geo.size)
                    toolbar
                }
            }
            .onExitCommand(perform: onCancel)
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("Tool", selection: $tool) {
                Text("Freehand").tag(AnnotationTool.freehand)
                Text("Circle").tag(AnnotationTool.circle)
                Text("Rect").tag(AnnotationTool.rect)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            Button("Done") { commitAndFinish() }
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
    }

    private func drawingLayer(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.12)
            Canvas { ctx, canvasSize in
                for stroke in committed + (current.isEmpty ? [] : [AnnotationStroke(tool: tool, points: current)]) {
                    draw(stroke, in: &ctx, size: canvasSize)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let n = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                    if tool == .freehand {
                        current.append(n)
                    } else {
                        if current.isEmpty { current = [n, n] } else { current[1] = n }
                    }
                }
                .onEnded { _ in
                    if !current.isEmpty {
                        let s = AnnotationStroke(tool: tool, points: current)
                        committed.append(s)
                        onStroke(s)
                        current = []
                    }
                }
        )
    }

    private func commitAndFinish() {
        if !current.isEmpty {
            let s = AnnotationStroke(tool: tool, points: current)
            committed.append(s)
            onStroke(s)
            current = []
        }
        onFinishShape()
    }

    private func draw(_ stroke: AnnotationStroke, in ctx: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        switch stroke.tool {
        case .freehand:
            guard let first = pts.first else { return }
            path.move(to: first)
            pts.dropFirst().forEach { path.addLine(to: $0) }
        case .rect:
            path.addRect(AnnotationGeometry.boundingRect(points: pts))
        case .circle:
            path.addEllipse(in: AnnotationGeometry.boundingRect(points: pts))
        }
        ctx.stroke(path, with: .color(.orange), lineWidth: 3)
    }
}

import AppKit
import OpenPawCore

enum AnnotatedImageComposer {
    private static let strokeColor = NSColor(red: 0.72, green: 0.38, blue: 1.0, alpha: 1)

    static func compose(screenshot: NSImage?, strokes: [AnnotationStroke]) -> NSImage? {
        guard let screenshot else { return nil }
        let size = screenshot.size
        let out = NSImage(size: size)
        out.lockFocus()
        screenshot.draw(in: NSRect(origin: .zero, size: size))
        strokeColor.setStroke()
        for stroke in strokes {
            let path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
            guard let first = pts.first else { continue }
            path.move(to: first)
            pts.dropFirst().forEach { path.line(to: $0) }
            path.stroke()
        }
        out.unlockFocus()
        return out
    }
}

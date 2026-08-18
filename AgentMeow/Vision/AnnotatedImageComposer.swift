import AppKit
import AgentMeowCore

enum AnnotatedImageComposer {
    static func compose(screenshot: NSImage?, strokes: [AnnotationStroke]) -> NSImage? {
        guard let screenshot else { return nil }
        let size = screenshot.size
        let out = NSImage(size: size)
        out.lockFocus()
        screenshot.draw(in: NSRect(origin: .zero, size: size))
        NSColor.orange.setStroke()
        for stroke in strokes {
            let path = NSBezierPath()
            path.lineWidth = 4
            let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
            switch stroke.tool {
            case .freehand:
                guard let first = pts.first else { continue }
                path.move(to: first)
                pts.dropFirst().forEach { path.line(to: $0) }
            case .rect:
                path.appendRect(AnnotationGeometry.boundingRect(points: pts))
            case .circle:
                path.appendOval(in: AnnotationGeometry.boundingRect(points: pts))
            }
            path.stroke()
        }
        out.unlockFocus()
        return out
    }
}

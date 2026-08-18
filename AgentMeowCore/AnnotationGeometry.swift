import CoreGraphics
import Foundation

public enum AnnotationTool: String, CaseIterable {
    case circle, rect, freehand
}

public struct AnnotationStroke: Equatable {
    public var tool: AnnotationTool
    public var points: [CGPoint] // normalized 0...1, top-left origin

    public init(tool: AnnotationTool, points: [CGPoint]) {
        self.tool = tool
        self.points = points
    }
}

/// Draw-mode keys. Esc aborts to kitty chooser; Done button sends.
public enum AnnotateOverlayCommand: Equatable {
    case cancel
}

public enum AnnotateOverlayInput {
    /// Carbon `kVK_Escape` — kept numeric so Core stays Foundation-only.
    public static let escapeKeyCode: UInt16 = 53

    public static func command(keyCode: UInt16) -> AnnotateOverlayCommand? {
        keyCode == escapeKeyCode ? .cancel : nil
    }
}

public enum AnnotationGeometry {
    public static func boundingRect(points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.001), height: max(maxY - minY, 0.001))
    }
}

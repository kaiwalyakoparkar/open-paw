import CoreGraphics
import Foundation

public struct AnnotationStroke: Equatable {
    public var points: [CGPoint] // normalized 0...1, top-left origin

    public init(points: [CGPoint]) {
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

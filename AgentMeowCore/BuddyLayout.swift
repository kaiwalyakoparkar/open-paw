import CoreGraphics
import Foundation

public enum BuddyLayout {
    public static let spacing: CGFloat = 6
    public static let padding: CGFloat = 8
    public static let pillMinWidth: CGFloat = 160
    public static let pillMaxWidth: CGFloat = 420
    public static let pillMinHeight: CGFloat = 160

    /// Size the floating buddy window from SwiftUI's fittingSize.
    /// NSHostingView often omits `Image(nsImage:)` from fittingSize, so always
    /// reserve the avatar slot below the reported content.
    /// Expanded (thinking/wait bubble) also floors to the pill's max frame —
    /// fittingSize often stays avatar-sized and AppKit clips the orange pill.
    /// ponytail: +avatar even when fitting already includes it (~80px extra
    /// transparent). Drop the addend if Image starts reporting size.
    public static func windowSize(fitting: CGSize, avatarSize: CGFloat, expanded: Bool = false) -> CGSize {
        let minW = expanded ? pillMaxWidth : max(pillMinWidth, avatarSize + 16)
        let minPillH = expanded ? pillMinHeight : 0
        return CGSize(
            width: max(fitting.width, minW),
            height: max(fitting.height, minPillH) + avatarSize + spacing + padding
        )
    }

    /// True when the hosting view is large enough to show the pill without clipping.
    /// `.intrinsicContentSize` often leaves hosting at avatar size after setFrame.
    public static func hostingFits(pill: CGSize, hosting: CGSize) -> Bool {
        hosting.width + 0.5 >= pill.width && hosting.height + 0.5 >= pill.height
    }

    /// Screen-space drag: origin += mouse delta. Do not use locationInWindow
    /// after setFrameOrigin — those coords go stale and the kitty runs away.
    public static func draggedOrigin(
        startOrigin: CGPoint,
        startMouse: CGPoint,
        currentMouse: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: startOrigin.x + currentMouse.x - startMouse.x,
            y: startOrigin.y + currentMouse.y - startMouse.y
        )
    }

    /// Keep a user-placed window put; only clamp + resize.
    public static func placedFrame(origin: CGPoint, size: CGSize, visible: CGRect) -> CGRect {
        let x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    public struct DragStep {
        public var armed: Bool
        public var startOrigin: CGPoint
        public var startMouse: CGPoint
        public var frameOrigin: CGPoint
    }

    /// Arm on first event at the current window origin. Never treat unset
    /// (.zero) start as a grab — that parks the window on the cursor.
    public static func originAfterDragEvent(
        armed: Bool,
        startOrigin: CGPoint,
        startMouse: CGPoint,
        currentOrigin: CGPoint,
        currentMouse: CGPoint
    ) -> DragStep {
        if !armed {
            return DragStep(
                armed: true,
                startOrigin: currentOrigin,
                startMouse: currentMouse,
                frameOrigin: currentOrigin
            )
        }
        return DragStep(
            armed: true,
            startOrigin: startOrigin,
            startMouse: startMouse,
            frameOrigin: draggedOrigin(
                startOrigin: startOrigin,
                startMouse: startMouse,
                currentMouse: currentMouse
            )
        )
    }
}

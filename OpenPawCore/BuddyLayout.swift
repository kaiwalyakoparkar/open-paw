import CoreGraphics
import CoreText
import Foundation

public enum BuddyLayout {
    public static let spacing: CGFloat = 6
    public static let padding: CGFloat = 8
    /// SwiftUI `.padding(4)` on BuddyView — cat sits this far above/right of window origin.
    public static let catInset: CGFloat = 4
    public static let pillMinWidth: CGFloat = 160
    public static let pillMaxWidth: CGFloat = 520
    public static let pillMinHeight: CGFloat = 200
    /// Capsule row (~28pt) plus slack so bottoms aren't clipped into the cat.
    public static let collapsedPillHeight: CGFloat = 52
    /// Done chip above the compact annotate bar (button + gap). Window only — pill hugs.
    public static let annotateDoneExtra: CGFloat = 56
    /// Explain + Hold ⌥ side-by-side; 160pt clipped "Hold ⌥" to a caret.
    public static let collapsedMinWidth: CGFloat = 240

    /// Size the floating buddy window from SwiftUI's fittingSize.
    /// NSHostingView often omits `Image(nsImage:)` from fittingSize, so always
    /// reserve the avatar slot below the reported content.
    /// Expanded (thinking/wait bubble) also floors to the pill's max frame —
    /// fittingSize often stays avatar-sized and AppKit clips the orange pill.
    /// ponytail: +avatar even when fitting already includes it (~80px extra
    /// transparent). Drop the addend if Image starts reporting size.
    public static func windowSize(fitting: CGSize, avatarSize: CGFloat, expanded: Bool = false) -> CGSize {
        let minW = expanded ? pillMaxWidth : max(collapsedMinWidth, avatarSize + 16)
        let minPillH = expanded ? pillMinHeight : 0
        return CGSize(
            width: max(fitting.width, minW),
            height: max(fitting.height, minPillH) + avatarSize + spacing + padding
        )
    }

    /// Constant expanded frame — ignores fittingSize so STT/Hermes text cannot resize the window.
    public static func fixedExpandedSize(avatarSize: CGFloat) -> CGSize {
        expandedWindowSize(bodyHeight: 0, avatarSize: avatarSize, maxHeight: .greatestFiniteMagnitude)
    }

    /// Idle Explain + Hold pills above the cat.
    public static func fixedCollapsedSize(avatarSize: CGFloat) -> CGSize {
        CGSize(
            width: max(collapsedMinWidth, avatarSize + 16),
            height: catInset * 2 + collapsedPillHeight + spacing + avatarSize
        )
    }

    public static func fixedSize(avatarSize: CGFloat, expanded: Bool) -> CGSize {
        expanded ? fixedExpandedSize(avatarSize: avatarSize) : fixedCollapsedSize(avatarSize: avatarSize)
    }

    /// Cat + chrome stay; pill height follows the body, then clamps to `maxHeight` (screen ceiling).
    /// Pass `minPillHeight: 0` to hug (listening) instead of the wait-bubble floor.
    public static func expandedWindowSize(
        bodyHeight: CGFloat,
        avatarSize: CGFloat,
        maxHeight: CGFloat,
        minPillHeight: CGFloat = pillMinHeight
    ) -> CGSize {
        let chrome = catInset * 2 + spacing + avatarSize
        let header: CGFloat = 36 + 24
        let pillH = max(minPillHeight, header + bodyHeight)
        let height = min(chrome + pillH, maxHeight)
        return CGSize(
            width: catInset * 2 + pillMaxWidth,
            height: max(height, chrome + collapsedPillHeight)
        )
    }

    /// Ideal wrapped height for the bubble body at pill width.
    public static func bodyHeight(for text: String, fontSize: CGFloat = 17) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 22 }
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attr = NSMutableAttributedString(string: trimmed)
        attr.addAttribute(
            kCTFontAttributeName as NSAttributedString.Key,
            value: font,
            range: NSRange(location: 0, length: attr.length)
        )
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let constraint = CGSize(width: pillMaxWidth - 32, height: CGFloat.greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            setter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            nil
        )
        return ceil(fit.height)
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
        frameKeepingBottom(current: CGRect(origin: origin, size: size), newSize: size, visible: visible)
    }

    /// Resize while keeping the window bottom edge (AppKit origin.y) fixed.
    /// Extra height grows upward; only shift up when the top would leave the screen.
    public static func frameKeepingBottom(current: CGRect, newSize: CGSize, visible: CGRect) -> CGRect {
        let bottom = current.origin.y
        var y = bottom
        if y + newSize.height > visible.maxY {
            y = visible.maxY - newSize.height
        }
        y = max(y, visible.minY)
        let x = min(max(current.origin.x, visible.minX), max(visible.minX, visible.maxX - newSize.width))
        return CGRect(x: x, y: y, width: newSize.width, height: newSize.height)
    }

    /// Keep window origin (cat bottom-left + catInset) locked. Grow up and to the right.
    /// Clamp only if the whole window has left the visible area — never shift down toward the dock.
    public static func frameAtAnchor(anchorOrigin: CGPoint, size: CGSize, visible: CGRect) -> CGRect {
        var x = anchorOrigin.x
        var y = anchorOrigin.y
        if y + size.height < visible.minY {
            y = visible.minY
        }
        if x + size.width < visible.minX {
            x = visible.minX
        } else if x > visible.maxX {
            x = max(visible.minX, visible.maxX - size.width)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Resize so the cat (bottom-center) stays put. Width grows equally left/right; height grows up.
    public static func frameKeepingCatCenter(current: CGRect, newSize: CGSize, visible: CGRect) -> CGRect {
        var x = current.midX - newSize.width / 2
        var y = current.minY
        if y + newSize.height < visible.minY {
            y = visible.minY
        }
        if x + newSize.width < visible.minX {
            x = visible.minX
        } else if x > visible.maxX {
            x = max(visible.minX, visible.maxX - newSize.width)
        }
        return CGRect(x: x, y: y, width: newSize.width, height: newSize.height)
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

import AgentMeowCore
import CoreGraphics
import Foundation

enum BuddyLayoutChecks {
    static func run() {
        // NSHostingView fittingSize often reports the expanded pill only — cat clipped.
        let pillOnly = CGSize(width: 320, height: 180)
        let avatar: CGFloat = 80
        let size = BuddyLayout.windowSize(fitting: pillOnly, avatarSize: avatar)
        assert(size.width >= pillOnly.width)
        assert(
            size.height >= pillOnly.height + avatar,
            "window must keep cat below pill, got \(size.height) for pill \(pillOnly.height) + avatar \(avatar)"
        )
        // NSHostingView often reports avatar-only while the wait bubble is 420×N.
        let avatarOnly = CGSize(width: avatar, height: avatar)
        assert(
            !BuddyLayout.hostingFits(
                pill: CGSize(width: BuddyLayout.pillMaxWidth, height: BuddyLayout.pillMinHeight),
                hosting: avatarOnly
            ),
            "avatar-sized hosting must be treated as a clip, not a fit"
        )
        // Idle Explain+Hold pills need more than avatar+16; unused floor was clipping "Explain".
        let idle = BuddyLayout.windowSize(fitting: avatarOnly, avatarSize: avatar, expanded: false)
        assert(
            idle.width >= BuddyLayout.pillMinWidth,
            "idle window must fit Explain pill, got \(idle.width)"
        )
        let expanded = BuddyLayout.windowSize(fitting: avatarOnly, avatarSize: avatar, expanded: true)
        assert(
            expanded.width >= BuddyLayout.pillMaxWidth,
            "expanded window must fit pill max width, got \(expanded.width)"
        )
        assert(
            expanded.height >= BuddyLayout.pillMinHeight + avatar,
            "expanded window must fit wait bubble above cat, got \(expanded.height)"
        )
        // Hosting view that stays avatar-sized inside a larger window still clips.
        assert(
            BuddyLayout.hostingFits(
                pill: CGSize(width: BuddyLayout.pillMaxWidth, height: BuddyLayout.pillMinHeight),
                hosting: expanded
            ),
            "hosting frame must be the window size, not leftover intrinsic"
        )
        dragKeepsGrabOffset()
        unarmedDragDoesNotJumpToCursor()
        placedFrameStaysPut()
        print("BuddyLayout OK")
    }

    /// Screen-delta drag: pointer-to-window-origin offset must stay constant.
    /// Window-relative locationInWindow after setFrameOrigin compounds and
    /// opens a gap between cursor and kitty.
    private static func dragKeepsGrabOffset() {
        let startOrigin = CGPoint(x: 800, y: 100)
        let startMouse = CGPoint(x: 840, y: 140)
        let currentMouse = CGPoint(x: 1000, y: 400)
        let origin = BuddyLayout.draggedOrigin(
            startOrigin: startOrigin,
            startMouse: startMouse,
            currentMouse: currentMouse
        )
        assert(origin.x == 960 && origin.y == 360)
        assert(currentMouse.x - origin.x == startMouse.x - startOrigin.x)
        assert(currentMouse.y - origin.y == startMouse.y - startOrigin.y)
        let still = BuddyLayout.draggedOrigin(
            startOrigin: startOrigin,
            startMouse: startMouse,
            currentMouse: startMouse
        )
        assert(still == startOrigin)
    }

    /// SwiftUI often swallows NSPanel.mouseDown. Start stays .zero; applying
    /// draggedOrigin then parks the window origin on the cursor and the kitty
    /// sits far from the pointer. Arm at current frame instead of jumping.
    private static func unarmedDragDoesNotJumpToCursor() {
        let window = CGPoint(x: 1016, y: 133)
        let mouseOnCat = CGPoint(x: 1100, y: 180)
        let first = BuddyLayout.originAfterDragEvent(
            armed: false,
            startOrigin: .zero,
            startMouse: .zero,
            currentOrigin: window,
            currentMouse: mouseOnCat
        )
        assert(first.armed)
        assert(first.frameOrigin == window)
        let moved = BuddyLayout.originAfterDragEvent(
            armed: first.armed,
            startOrigin: first.startOrigin,
            startMouse: first.startMouse,
            currentOrigin: first.frameOrigin,
            currentMouse: CGPoint(x: 1200, y: 220)
        )
        assert(moved.frameOrigin.x == 1116 && moved.frameOrigin.y == 173)
        assert(moved.frameOrigin.x - window.x == 100)
    }

    private static func placedFrameStaysPut() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: 500, y: 400)
        let size = CGSize(width: 200, height: 120)
        let frame = BuddyLayout.placedFrame(origin: origin, size: size, visible: visible)
        assert(frame.origin == origin)
        assert(frame.size == size)
        let clamped = BuddyLayout.placedFrame(
            origin: CGPoint(x: 1400, y: 890),
            size: size,
            visible: visible
        )
        assert(clamped.maxX <= visible.maxX)
        assert(clamped.maxY <= visible.maxY)
        assert(clamped.minX >= visible.minX)
        assert(clamped.minY >= visible.minY)
    }
}

import OpenPawCore
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
            idle.width >= BuddyLayout.collapsedMinWidth,
            "idle window must fit Explain+Hold pills, got \(idle.width)"
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
        frameAtAnchorKeepsOrigin()
        fixedSizesAreStable()
        expandThenTextKeepsOrigin()
        errorUsesStableExpandedSize()
        dragKeepsFullBubbleOnScreen()
        listeningHugsInsteadOfWaitFloor()
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
        resizeKeepsBottomAnchored(visible: visible)
    }

    /// Processing bubble grows height — bottom edge stays fixed, UI stacks upward.
    private static func resizeKeepsBottomAnchored(visible: CGRect) {
        let bottom: CGFloat = 120
        let current = CGRect(x: 800, y: bottom, width: 200, height: 100)
        let taller = CGSize(width: 420, height: 280)
        let frame = BuddyLayout.frameKeepingBottom(current: current, newSize: taller, visible: visible)
        assert(frame.origin.y == bottom, "bottom must stay anchored, got \(frame.origin.y)")
        assert(frame.size == taller)
    }

    /// Window origin (cat) stays put when the frame grows taller and wider.
    private static func frameAtAnchorKeepsOrigin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: 800, y: 120)
        let taller = CGSize(width: 420, height: 280)
        let frame = BuddyLayout.frameAtAnchor(anchorOrigin: origin, size: taller, visible: visible)
        assert(frame.origin == origin, "anchor origin must not move, got \(frame.origin)")
        assert(frame.size == taller)
        let wider = BuddyLayout.frameAtAnchor(
            anchorOrigin: origin,
            size: CGSize(width: 500, height: 280),
            visible: visible
        )
        assert(wider.origin == origin)
        // Near the right edge: grow width past maxX but origin still on-screen — do not pull cat left.
        let nearRight = CGPoint(x: 1300, y: 80)
        let clipped = BuddyLayout.frameAtAnchor(
            anchorOrigin: nearRight,
            size: CGSize(width: 420, height: 280),
            visible: visible
        )
        assert(clipped.origin == nearRight, "partial overflow must not shift origin, got \(clipped.origin)")
    }

    /// Expanded size is a function of avatarSize only — fitting text cannot change it.
    private static func fixedSizesAreStable() {
        let avatar: CGFloat = 80
        let a = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        let b = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        assert(a == b)
        assert(a.width == BuddyLayout.catInset * 2 + BuddyLayout.pillMaxWidth)
        assert(
            a.height == BuddyLayout.catInset * 2 + BuddyLayout.pillMinHeight
                + BuddyLayout.spacing + avatar
        )
        assert(a.width > BuddyLayout.fixedCollapsedSize(avatarSize: avatar).width)
        let collapsed = BuddyLayout.fixedCollapsedSize(avatarSize: avatar)
        assert(collapsed.width >= BuddyLayout.collapsedMinWidth)
        assert(
            collapsed.height == BuddyLayout.catInset * 2 + BuddyLayout.collapsedPillHeight
                + BuddyLayout.spacing + avatar
        )
        assert(BuddyLayout.fixedSize(avatarSize: avatar, expanded: true) == a)
        assert(BuddyLayout.fixedSize(avatarSize: avatar, expanded: false) == collapsed)
    }

    /// Expand once, then a text-only "resize" with the same size must not move origin.
    private static func expandThenTextKeepsOrigin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let avatar: CGFloat = 80
        let origin = CGPoint(x: 900, y: 80)
        let collapsed = BuddyLayout.fixedCollapsedSize(avatarSize: avatar)
        let placed = BuddyLayout.frameAtAnchor(anchorOrigin: origin, size: collapsed, visible: visible)
        assert(placed.origin == origin)
        let expanded = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        let afterExpand = BuddyLayout.frameAtAnchor(anchorOrigin: origin, size: expanded, visible: visible)
        assert(afterExpand.origin == origin, "expand must not move cat, got \(afterExpand.origin)")
        let afterText = BuddyLayout.frameAtAnchor(anchorOrigin: origin, size: expanded, visible: visible)
        assert(afterText.origin == origin)
        assert(afterText.size == afterExpand.size)
        resizeKeepsCatCenter(visible: visible, collapsed: collapsed, expanded: expanded)
        ceilingGrowsThenCaps()
    }

    /// Pills centered on the cat: width change must keep midX and bottom Y.
    private static func resizeKeepsCatCenter(visible: CGRect, collapsed: CGSize, expanded: CGSize) {
        let current = CGRect(x: 800, y: 90, width: collapsed.width, height: collapsed.height)
        let next = BuddyLayout.frameKeepingCatCenter(current: current, newSize: expanded, visible: visible)
        assert(next.minY == current.minY, "cat bottom must stay, got \(next.minY)")
        assert(abs(next.midX - current.midX) < 0.5, "cat center X must stay, \(current.midX) → \(next.midX)")
        assert(next.size == expanded)
        let again = BuddyLayout.frameKeepingCatCenter(current: next, newSize: expanded, visible: visible)
        assert(again.origin == next.origin)
    }

    /// Long output grows the ceiling; cat chrome stays; height never exceeds the cap.
    private static func ceilingGrowsThenCaps() {
        let avatar: CGFloat = 80
        let floor = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        let short = BuddyLayout.bodyHeight(for: "ok")
        let long = BuddyLayout.bodyHeight(for: String(repeating: "tomorrow's meetings in IST. ", count: 40))
        assert(long > short + 40, "wrapped body must grow with text, short \(short) long \(long)")
        let grown = BuddyLayout.expandedWindowSize(bodyHeight: long, avatarSize: avatar, maxHeight: 2000)
        assert(grown.width == floor.width)
        assert(grown.height > floor.height, "ceiling must rise for long output")
        let cap: CGFloat = 400
        let capped = BuddyLayout.expandedWindowSize(bodyHeight: 5000, avatarSize: avatar, maxHeight: cap)
        assert(capped.height == cap, "must not pass the screen ceiling, got \(capped.height)")
        let chrome = BuddyLayout.catInset * 2 + BuddyLayout.spacing + avatar
        assert(capped.height > chrome, "capped window must still leave room for the cat")
    }

    /// Error must use the same expanded floor as wait — no hug size that later pops bigger.
    private static func errorUsesStableExpandedSize() {
        let avatar: CGFloat = 80
        let msg = "Speech reached mic but STT returned nothing — check network or Gradium key"
        let previous = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        let error = BuddyLayout.expandedWindowSize(
            bodyHeight: BuddyLayout.bodyHeight(for: msg, fontSize: 11),
            avatarSize: avatar,
            maxHeight: 2000
        )
        assert(error.width == previous.width)
        assert(
            error.height == previous.height,
            "error must not hug then grow: \(error.height) vs stable \(previous.height)"
        )
        let empty = BuddyLayout.expandedWindowSize(
            bodyHeight: 22,
            avatarSize: avatar,
            maxHeight: 2000
        )
        assert(empty == previous, "empty error must already be expanded floor, got \(empty)")
        let collapsed = BuddyLayout.fixedCollapsedSize(avatarSize: avatar)
        assert(error.width > collapsed.width)
        assert(error.height > collapsed.height)
    }

    /// Full-width bubble dragged to a screen edge must stay fully visible.
    private static func dragKeepsFullBubbleOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = BuddyLayout.fixedExpandedSize(avatarSize: 80)
        let startOrigin = CGPoint(x: 800, y: 80)
        let startMouse = CGPoint(x: 840, y: 120)
        let pastRight = CGPoint(x: 2000, y: 120)
        let origin = BuddyLayout.draggedOrigin(
            startOrigin: startOrigin,
            startMouse: startMouse,
            currentMouse: pastRight
        )
        let frame = BuddyLayout.placedFrame(origin: origin, size: size, visible: visible)
        assert(frame.size == size)
        assert(frame.maxX <= visible.maxX, "right edge must stay on screen, maxX \(frame.maxX)")
        assert(frame.minX >= visible.minX)
        assert(frame.minY >= visible.minY)
        assert(frame.maxY <= visible.maxY)
    }

    /// Listening is a status line, not the wait bubble — hug so the block isn't 200pt tall.
    private static func listeningHugsInsteadOfWaitFloor() {
        let avatar: CGFloat = 80
        let wait = BuddyLayout.fixedExpandedSize(avatarSize: avatar)
        let listen = BuddyLayout.expandedWindowSize(
            bodyHeight: BuddyLayout.bodyHeight(for: ""),
            avatarSize: avatar,
            maxHeight: 2000,
            minPillHeight: 0
        )
        assert(listen.width == wait.width)
        assert(
            listen.height < wait.height,
            "listening must be shorter than wait floor: \(listen.height) vs \(wait.height)"
        )
        let collapsed = BuddyLayout.fixedCollapsedSize(avatarSize: avatar)
        assert(listen.height >= collapsed.height)
        let withTranscript = BuddyLayout.expandedWindowSize(
            bodyHeight: BuddyLayout.bodyHeight(for: String(repeating: "tomorrow's meetings in IST. ", count: 8)),
            avatarSize: avatar,
            maxHeight: 2000,
            minPillHeight: 0
        )
        assert(withTranscript.height > listen.height)
        assert(withTranscript.height < wait.height)
    }
}

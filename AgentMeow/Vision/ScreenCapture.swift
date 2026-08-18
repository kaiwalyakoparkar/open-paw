import AppKit
import ScreenCaptureKit

enum ScreenCapture {
    static func mainDisplayImage() -> NSImage? {
        let displayID = CGMainDisplayID()
        guard let cg = CGDisplayCreateImage(displayID) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

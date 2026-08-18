import AgentMeowCore
import Foundation

enum AnnotateOverlayChecks {
    static func run() {
        // Esc must abort draw mode back to chooser — never send the screenshot.
        assert(AnnotateOverlayInput.command(keyCode: 53) == .cancel)
        assert(AnnotateOverlayInput.command(keyCode: 36) == nil) // Return is Done button
        assert(AnnotateOverlayInput.command(keyCode: 0) == nil)
        print("AnnotateOverlay OK")
    }
}

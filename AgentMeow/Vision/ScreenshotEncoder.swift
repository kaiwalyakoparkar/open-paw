import AppKit

/// Hermes api_server rejects POST bodies over 10 MB. Explain embeds the screenshot
/// as base64 in JSON, so shrink before send.
enum ScreenshotEncoder {
    /// Raw JPEG bytes budget (base64 + JSON overhead stays under Hermes 10 MB cap).
    static let maxJPEGBytes = 5_500_000

    static func dataURL(_ image: NSImage) -> String? {
        var side = 1920
        var quality = 0.72
        var data = jpegData(image, maxSide: side, quality: quality)
        while let d = data, d.count > maxJPEGBytes, side > 640 || quality > 0.35 {
            if quality > 0.35 {
                quality -= 0.08
            } else {
                side = Int(Double(side) * 0.8)
            }
            data = jpegData(image, maxSide: side, quality: quality)
        }
        guard let data, data.count <= maxJPEGBytes else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func jpegData(_ image: NSImage, maxSide: Int, quality: CGFloat) -> Data? {
        let scaled = resize(image, maxSide: maxSide)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }

    private static func resize(_ image: NSImage, maxSide: Int) -> NSImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > CGFloat(maxSide) else { return image }
        let scale = CGFloat(maxSide) / longest
        let nw = w * scale
        let nh = h * scale
        let out = NSImage(size: NSSize(width: nw, height: nh))
        out.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: nw, height: nh))
        out.unlockFocus()
        return out
    }
}

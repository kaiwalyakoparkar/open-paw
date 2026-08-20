import AppKit
import OpenPawCore
import SwiftUI

final class BuddyViewModel: ObservableObject {
    @Published var state: BuddyState = .idle
    @Published var bubble: BubbleContent = .none
    @Published var micLevel: Float = 0
    @Published var isHoldingKey: Bool = false
    @Published var holdKeyLabel: String = "⌥"
    @Published var annotateHasStrokes = false
    @Published var annotateListening = false
}

struct BuddyView: View {
    @ObservedObject var model: BuddyViewModel
    var size: CGFloat
    var onStop: () -> Void
    var onAnnotate: () -> Void
    var onAskAnnotate: () -> Void
    var onFinishAnnotate: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: BuddyLayout.spacing) {
                if model.state == .annotate {
                    annotateButtons
                        .padding(.bottom, 10)
                }
                VoicePillView(
                    state: model.state,
                    bubble: model.bubble,
                    micLevel: model.micLevel,
                    isHoldingKey: model.isHoldingKey,
                    holdKeyLabel: model.holdKeyLabel,
                    annotateListening: model.annotateListening,
                    onStop: onStop,
                    onAnnotate: onAnnotate
                )
                Color.clear.frame(width: size, height: size)
            }
            catSlot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(BuddyLayout.catInset)
    }

    /// Color.clear.frame so NSHostingView fittingSize includes the cat slot —
    /// Image(nsImage:) often reports 0 intrinsic size.
    private var catSlot: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                Image(nsImage: CatSprite.image(for: model.state))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
            .layoutPriority(1)
            .fixedSize()
            .shadow(color: ringGlow, radius: (model.state == .listening || model.annotateListening) ? 8 : 0)
            .contentShape(Rectangle())
            .help(model.state == .idle ? "Explain this part of the screen" : "")
    }

    private var ringGlow: Color {
        if model.annotateListening || model.state == .listening { return .green.opacity(0.45) }
        if model.state == .thinking { return .orange.opacity(0.35) }
        return .clear
    }

    private var annotateButtons: some View {
        HStack(spacing: 8) {
            if !model.annotateListening {
                annotateAskButton
            }
            annotateDoneButton
        }
        .opacity(model.annotateHasStrokes ? 1 : 0.4)
        .disabled(!model.annotateHasStrokes)
        .animation(.easeInOut(duration: 0.2), value: model.annotateHasStrokes)
        .animation(.easeInOut(duration: 0.2), value: model.annotateListening)
    }

    private var annotateAskButton: some View {
        Button(action: onAskAnnotate) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Ask")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var annotateDoneButton: some View {
        Button(action: onFinishAnnotate) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.72, green: 0.38, blue: 1.0),
                        Color.purple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .shadow(color: Color.purple.opacity(0.5), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Crops one frame from the 2×2 sprite sheet in `cat_avatar.png`.
private enum CatSprite {
    private static let sheet: NSImage? = {
        Bundle.module.url(forResource: "cat_avatar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }()

    private static var cache: [BuddyState: NSImage] = [:]

    static func image(for state: BuddyState) -> NSImage {
        if let cached = cache[state] { return cached }
        guard let sheet,
              let cgFull = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSImage(size: NSSize(width: 64, height: 64))
        }
        let halfW = sheet.size.width / 2
        let halfH = sheet.size.height / 2
        let scaleX = CGFloat(cgFull.width) / sheet.size.width
        let scaleY = CGFloat(cgFull.height) / sheet.size.height
        let src = sourcePixelRect(for: state, halfW: halfW * scaleX, halfH: halfH * scaleY)
        guard let cgCropped = cgFull.cropping(to: src),
              let transparent = stripCheckerboard(from: cgCropped),
              let trimmed = trimTransparentBounds(transparent) else { return sheet }
        let result = NSImage(cgImage: trimmed, size: NSSize(width: trimmed.width, height: trimmed.height))
        cache[state] = result
        return result
    }

    /// Sprite sheet has no alpha; checkerboard gray/white is baked into RGB.
    private static func stripCheckerboard(from image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            let r = px[o], g = px[o + 1], b = px[o + 2]
            if isBackgroundPixel(r: r, g: g, b: b) {
                px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0
            }
        }
        return ctx.makeImage()
    }

    private static func isBackgroundPixel(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let spread = Int(max(r, g, b)) - Int(min(r, g, b))
        return spread < 20 && Int(min(r, g, b)) > 160
    }

    private static func trimTransparentBounds(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                if px[(y * w + x) * 4 + 3] > 8 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard minX <= maxX, minY <= maxY else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// CGImage coords: top-left idle/listening, bottom-left thinking, bottom-right speaking.
    private static func sourcePixelRect(for state: BuddyState, halfW: CGFloat, halfH: CGFloat) -> CGRect {
        switch state {
        case .idle, .annotate: CGRect(x: 0, y: 0, width: halfW, height: halfH)
        case .listening:       CGRect(x: halfW, y: 0, width: halfW, height: halfH)
        case .thinking:        CGRect(x: 0, y: halfH, width: halfW, height: halfH)
        case .speaking:        CGRect(x: halfW, y: halfH, width: halfW, height: halfH)
        }
    }
}

import SwiftUI

enum BubbleContent: Equatable {
    case none
    case listening(String)
    case processing(String)
    case responding(String)
    case error(String)

    var displayText: String {
        switch self {
        case .none: ""
        case .listening(let s), .processing(let s), .responding(let s), .error(let s): s
        }
    }

    var isVisible: Bool {
        switch self {
        case .none: false
        case .listening(""), .responding(""): false
        case .processing, .error: true
        default: true
        }
    }
}

/// Speech bubble anchored above the cat avatar (comic tail points down).
struct TranscriptBubble: View {
    var content: BubbleContent
    var state: BuddyState = .idle
    var micLevel: Float = 0

    var body: some View {
        VStack(spacing: 0) {
            bubbleBody
            BubbleTail()
                .fill(bubbleFill)
                .frame(width: 14, height: 8)
        }
        .frame(maxWidth: 240)
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !content.displayText.isEmpty {
                Text(content.displayText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state == .listening {
                Text(listeningPlaceholder)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .italic()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: 1))
    }

    private var listeningPlaceholder: String {
        if micLevel > 0.02 {
            "Transcribing your words…"
        } else {
            "Say something — mic is live"
        }
    }

    private var bubbleFill: Color {
        switch content {
        case .none: .clear
        case .listening: Color(white: 0.15, opacity: 0.88)
        case .processing: Color.orange.opacity(0.82)
        case .responding: Color(white: 0.12, opacity: 0.92)
        case .error: Color.red.opacity(0.75)
        }
    }

    private var borderColor: Color {
        switch content {
        case .listening: .white.opacity(0.18)
        case .processing: .orange.opacity(0.55)
        case .responding: .white.opacity(0.22)
        case .error: .red.opacity(0.6)
        default: .clear
        }
    }

    private var textColor: Color {
        switch content {
        case .error: .white
        default: .white.opacity(0.95)
        }
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - 7, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX + 7, y: 0))
        p.closeSubpath()
        return p
    }
}

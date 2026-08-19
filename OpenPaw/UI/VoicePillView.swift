import OpenPawCore
import SwiftUI

struct VoicePillView: View {
    var state: BuddyState
    var bubble: BubbleContent
    var micLevel: Float
    var isHoldingKey: Bool
    var holdKeyLabel: String
    var onStop: () -> Void
    var onAnnotate: () -> Void

    private var isProcessing: Bool {
        if case .processing = bubble { return true }
        return false
    }

    private var isError: Bool {
        if case .error = bubble { return true }
        return false
    }

    private var bodyFontSize: CGFloat { isError ? 11 : 17 }
    private var labelFontSize: CGFloat { isError ? 13 : 15 }

    private var isExpanded: Bool {
        isHoldingKey || state != .idle || bubble.isVisible
    }

    /// Idle but bubble still showing response/error — user needs a way to dismiss.
    private var showDismiss: Bool {
        state == .idle && bubble.isVisible
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedPill
            } else {
                collapsedPill
            }
        }
    }

    private var collapsedPill: some View {
        HStack(spacing: 6) {
            Button(action: onAnnotate) {
                HStack(spacing: 3) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Explain")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.purple.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.purple.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.purple.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Hold \(holdKeyLabel)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .fixedSize()
        .layoutPriority(1)
    }

    private var expandedPill: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusIcon
                if state == .listening || isHoldingKey {
                    WaveformBars(level: micLevel)
                }
                Text(statusLabel)
                    .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                Spacer(minLength: 8)
                if state != .idle {
                    Button(action: onStop) {
                        Text("Stop")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.75), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if showDismiss {
                    Button(action: onStop) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss and start fresh next time")
                }
            }

            if !bubble.displayText.isEmpty {
                let long = bubble.displayText.count > 400
                let body = Text(bubble.displayAttributed)
                    .font(.system(size: bodyFontSize, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if long {
                    ScrollView(.vertical, showsIndicators: true) { body }
                        .frame(maxHeight: 220, alignment: .top)
                } else {
                    body
                }
            } else if state == .listening || isHoldingKey {
                Text(micLevel > 0.02 ? "Transcribing…" : "Listening…")
                    .font(.system(size: bodyFontSize, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .italic()
            } else if state == .thinking || isProcessing {
                Text("Processing your request…")
                    .font(.system(size: bodyFontSize, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .italic()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isError ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: hugsListeningHeight ? nil : .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: hugsListeningHeight)
        .background(pillFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(pillBorder, lineWidth: 1))
    }

    /// Status row + "Listening…" — don't stretch into the wait-bubble floor.
    private var hugsListeningHeight: Bool {
        state == .listening || (state == .idle && isHoldingKey)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .thinking:
            ProgressView()
                .controlSize(.small)
                .tint(.orange)
        case .listening:
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: micLevel > 0.02)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.blue)
        case .annotate:
            Image(systemName: "pencil.tip.crop.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.purple)
        default:
            if case .error = bubble {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
            } else {
                EmptyView()
            }
        }
    }

    private var statusLabel: String {
        if case .error = bubble { return "Missed it" }
        switch state {
        case .idle: return "Ready"
        case .listening: return isHoldingKey ? "Recording" : "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .annotate: return "Draw on screen"
        }
    }

    private var statusColor: Color {
        switch state {
        case .listening: .green
        case .thinking: .orange
        case .speaking: .blue
        case .annotate: .purple
        default: .white.opacity(0.7)
        }
    }

    private var pillFill: Color {
        if case .error = bubble { return Color.red.opacity(0.75) }
        switch state {
        case .thinking: return Color.orange.opacity(0.82)
        case .speaking: return Color(white: 0.12, opacity: 0.92)
        case .listening: return Color(white: 0.15, opacity: 0.88)
        case .annotate: return Color.purple.opacity(0.35)
        default: return Color.black.opacity(0.72)
        }
    }

    private var pillBorder: Color {
        if case .error = bubble { return .red.opacity(0.6) }
        switch state {
        case .thinking: return .orange.opacity(0.55)
        case .speaking: return .white.opacity(0.22)
        case .listening: return .green.opacity(0.45)
        default: return .white.opacity(0.15)
        }
    }
}

private struct WaveformBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(index: i))
                    .frame(width: 3, height: barHeight(index: i))
            }
        }
        .frame(height: 14, alignment: .bottom)
    }

    private func barHeight(index: Int) -> CGFloat {
        let threshold = Float(index + 1) * 0.10
        return level >= threshold ? CGFloat(4 + index * 2) : 3
    }

    private func barColor(index: Int) -> Color {
        let threshold = Float(index + 1) * 0.10
        return level >= threshold ? .green : .white.opacity(0.25)
    }
}

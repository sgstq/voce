import SwiftUI

/// The dictation HUD: a small black capsule docked at the bottom centre.
/// State reads through shape and motion rather than labels — bars that
/// follow your voice while listening, a light sweeping across resting dots
/// while the text is finalized and polished, a short message on error.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if model.phase != .hidden {
                OverlayCapsule(model: model)
                    .scaleEffect(model.isPresented ? 1 : 0.6, anchor: .bottom)
                    .opacity(model.isPresented ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
    }
}

private struct OverlayCapsule: View {
    @ObservedObject var model: OverlayModel

    private static let fill = Color(red: 0.035, green: 0.035, blue: 0.045)
    private static let errorTint = Color(red: 1.0, green: 0.45, blue: 0.40)
    private static let transcriptWidth: CGFloat = 300

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minWidth: 92, minHeight: 36)
        .background(shape.fill(Self.fill))
        .overlay(shape.strokeBorder(.white.opacity(0.13), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: layout)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()

        case .listening, .finalizing, .refining:
            LevelBars(levels: model.levels, isThinking: model.phase != .listening)
            if showsTranscript {
                Text(verbatim: model.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(model.phase == .listening ? 0.92 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(width: Self.transcriptWidth, alignment: .leading)
                    .transition(.opacity)
            }

        case .error(let message):
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.errorTint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private var showsTranscript: Bool {
        model.showsTranscript
            && !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Changes whenever the capsule changes size, so only resizes animate —
    /// never the per-word text updates.
    private var layout: Int {
        switch model.phase {
        case .error: 2
        default: showsTranscript ? 1 : 0
        }
    }
}

/// Thirteen white bars, tallest in the centre, resting as dots in silence.
/// While thinking, the bars settle to dots and a light sweeps across them.
private struct LevelBars: View {
    let levels: [Double]
    let isThinking: Bool

    private static let barWidth: CGFloat = 3
    private static let restHeight: CGFloat = 3
    private static let maxHeight: CGFloat = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isThinking)) { timeline in
            let sweep = isThinking ? sweepPosition(at: timeline.date) : nil
            HStack(spacing: 2.5) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(opacity(index, sweep: sweep)))
                        .frame(width: Self.barWidth, height: height(index, sweep: sweep))
                }
            }
            .frame(height: Self.maxHeight)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.72), value: levels)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isThinking)
    }

    /// Fractional bar index of the sweep's centre; it enters from the left
    /// edge and leaves past the right one.
    private func sweepPosition(at date: Date) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.3) / 1.3
        return cycle * Double(levels.count + 6) - 3
    }

    private func glow(_ index: Int, sweep: Double) -> Double {
        max(0, 1 - abs(Double(index) - sweep) / 2.5)
    }

    private func height(_ index: Int, sweep: Double?) -> CGFloat {
        if let sweep {
            return Self.restHeight + 2 * glow(index, sweep: sweep)
        }
        return Self.restHeight + CGFloat(levels[index]) * (Self.maxHeight - Self.restHeight)
    }

    private func opacity(_ index: Int, sweep: Double?) -> Double {
        if let sweep {
            return 0.3 + 0.7 * glow(index, sweep: sweep)
        }
        return 0.5 + 0.5 * levels[index]
    }
}

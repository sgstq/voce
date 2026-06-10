import AppKit
import SwiftUI

/// Live dictation preview state shared between the coordinator and the view.
@MainActor
final class OverlayModel: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case listening
        case finalizing
        case refining
        case error(String)
    }

    @Published var phase: Phase = .hidden
    @Published var text: String = ""
    @Published private(set) var levels: [Double] = OverlayModel.restingLevels
    @Published private(set) var liveWordStamps: [Date] = []

    /// Updates the live transcript, stamping newly arrived words so the view
    /// can fade each one in from faint to its settled gray.
    func updateLiveText(_ newText: String, now: Date = .now) {
        let words = Self.words(of: newText)
        if words.count < liveWordStamps.count {
            liveWordStamps = Array(liveWordStamps.prefix(words.count))
        } else {
            liveWordStamps.append(
                contentsOf: Array(repeating: now, count: words.count - liveWordStamps.count)
            )
        }
        text = newText
    }

    static func words(of text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    static let waveformBarCount = 26
    static var restingLevels: [Double] { Array(repeating: 0.0, count: waveformBarCount) }

    /// Push one normalized mic level (0…1); the waveform scrolls left.
    func pushLevel(_ level: Double) {
        var next = levels
        next.removeFirst()
        next.append(min(1, max(0, level)))
        levels = next
    }

    func resetLevels() {
        levels = Self.restingLevels
    }
}

/// Floating, non-activating preview panel. Lives in-process, never steals
/// focus, ignores mouse events, joins all Spaces. Animations only run while
/// the panel is on screen.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    private let panel: NSPanel
    private let panelSize = NSSize(width: 500, height: 148)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show() {
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        // Park the view in a state with no animation timelines — otherwise
        // they keep ticking (and burning CPU) inside the offscreen window.
        model.phase = .hidden
        model.resetLevels()
    }

    private func positionOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.minY + 96
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }
}

// MARK: - Root view

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.phase == .hidden {
                Color.clear
            } else {
            HStack(spacing: 9) {
                PulseDot(color: statusColor, pulsing: isListening)
                Text(statusLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.opacity)
                Spacer(minLength: 12)
                WaveformView(levels: model.levels, color: waveformColor)
                    .opacity(isListening ? 1 : 0.28)
            }
            .frame(height: 22)

            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.085, green: 0.095, blue: 0.115).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.09))
                )
                .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        )
        .padding(14)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.phase)
    }

    @ViewBuilder
    private var previewArea: some View {
        switch model.phase {
        case .hidden:
            Color.clear

        case .listening:
            // Materialize + typing dots: each new word fades from faint up
            // to its settled gray, and three soft dots pulse in sequence
            // after the last word. The timeline only ticks while listening.
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                materializedPreview(now: timeline.date)
                    .font(.system(size: 17))
                    .lineLimit(2)
                    .truncationMode(.head)
            }

        case .finalizing, .refining:
            ShimmerText(
                text: previewIsPlaceholder ? statusLabel : previewText,
                font: .system(size: 17)
            )
            .lineLimit(2)
            .truncationMode(.head)

        case .error(let message):
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                .lineLimit(2)
        }
    }

    private var isListening: Bool { model.phase == .listening }

    private var statusLabel: String {
        switch model.phase {
        case .hidden: ""
        case .listening: "Listening"
        case .finalizing: "Finalizing…"
        case .refining: "Polishing…"
        case .error: "Needs attention"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .hidden: .clear
        case .listening: Color(red: 0.93, green: 0.36, blue: 0.30)
        case .finalizing: Color(red: 0.96, green: 0.69, blue: 0.25)
        case .refining: Color(red: 0.52, green: 0.50, blue: 0.96)
        case .error: Color(red: 0.93, green: 0.36, blue: 0.30)
        }
    }

    private var waveformColor: Color {
        isListening ? Color(red: 0.93, green: 0.42, blue: 0.36) : .white.opacity(0.4)
    }

    private func materializedPreview(now: Date) -> Text {
        guard !previewIsPlaceholder else {
            return Text("Start speaking…").foregroundStyle(.white.opacity(0.34))
        }

        let words = OverlayModel.words(of: model.text)
        let stamps = model.liveWordStamps
        var combined = Text(verbatim: "")

        for (index, word) in words.enumerated() {
            let age = index < stamps.count ? now.timeIntervalSince(stamps[index]) : 1
            let progress = min(1, max(0, age / 0.45))
            let eased = 1 - pow(1 - progress, 2)
            combined = combined
                + Text(verbatim: index == 0 ? word : " " + word)
                .foregroundStyle(.white.opacity(0.18 + 0.40 * eased))
        }

        // Three soft typing dots pulsing in sequence after the last word.
        let t = now.timeIntervalSinceReferenceDate
        for index in 0..<3 {
            let phase = (t * 0.9 - Double(index) * 0.18)
                .truncatingRemainder(dividingBy: 1.0)
            let pulse = max(0.0, sin(max(0, phase) * .pi))
            combined = combined
                + Text(verbatim: index == 0 ? "  •" : " •")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.22 + 0.5 * pulse))
        }

        return combined
    }

    private var previewIsPlaceholder: Bool {
        model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewText: String {
        previewIsPlaceholder ? "Start speaking…" : model.text
    }
}

// MARK: - Components

/// Voice-reactive bars: heights follow the recent mic levels, scrolling left.
private struct WaveformView: View {
    let levels: [Double]
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(0.55 + 0.45 * levels[index]))
                    .frame(width: 3, height: 4 + levels[index] * 16)
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels)
    }
}

/// Status dot with an expanding pulse ring while listening.
private struct PulseDot: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        ZStack {
            if pulsing {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.4) / 1.4
                    Circle()
                        .stroke(color.opacity((1 - t) * 0.55), lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                        .scaleEffect(1 + t * 1.9)
                }
            }
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
        }
        .frame(width: 22, height: 22)
    }
}

/// Gray text with a bright band sweeping across — "being worked on".
private struct ShimmerText: View {
    let text: String
    let font: Font

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.5) / 1.5
            ZStack(alignment: .topLeading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(.white.opacity(0.42))
                Text(text)
                    .font(font)
                    .foregroundStyle(.white.opacity(0.95))
                    .mask(
                        GeometryReader { proxy in
                            let band = proxy.size.width * 0.35
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white, location: 0.5),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: band)
                            .offset(x: (proxy.size.width + band) * phase - band)
                        }
                    )
            }
        }
    }
}

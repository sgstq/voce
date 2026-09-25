import AppKit
import SwiftUI

/// Live dictation state shared between the coordinator and the overlay view.
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
    /// Opt-in: show the streaming transcript beside the level bars.
    @Published var showsTranscript = false
    /// Drives the entrance/exit animation; the controller owns it so the
    /// panel is on screen before the capsule animates in.
    @Published fileprivate(set) var isPresented = false
    /// One height per bar, loudest in the centre (see `pushLevel`).
    @Published private(set) var levels: [Double] = OverlayModel.restingLevels

    static let barCount = 13
    static var restingLevels: [Double] { Array(repeating: 0.0, count: barCount) }

    /// Recent smoothed mic levels, newest first. The centre bar shows the
    /// newest level and each step outward an older one, so speech ripples
    /// out from the middle.
    private var history: [Double] = Array(repeating: 0.0, count: barCount / 2 + 1)

    func updateLiveText(_ newText: String) {
        text = newText
    }

    /// Push one audio chunk's energy. Speech RMS tops out around 0.25; the
    /// 0.6 exponent lifts quiet talk.
    func pushAudio(sumSquares: Double, sampleCount: Int) {
        guard sampleCount > 0 else { return }
        let rms = (sumSquares / Double(sampleCount)).squareRoot()
        pushLevel(pow(min(1.0, rms / 0.25), 0.6))
    }

    /// Push one normalized mic level (0…1). Rises instantly, falls softly.
    func pushLevel(_ level: Double) {
        let clamped = min(1, max(0, level))
        let previous = history[0]
        let smoothed = clamped >= previous ? clamped : previous * 0.55 + clamped * 0.45
        history.removeLast()
        history.insert(smoothed, at: 0)

        let half = Double(Self.barCount / 2)
        levels = (0..<Self.barCount).map { index in
            let distance = abs(Double(index) - half)
            let envelope = 1 - 0.45 * pow(distance / half, 2)
            return history[Int(distance)] * envelope
        }
    }

    func resetLevels() {
        history = Array(repeating: 0.0, count: history.count)
        levels = Self.restingLevels
    }
}

/// Floating, non-activating panel. Lives in-process, never steals focus,
/// ignores the mouse, joins all Spaces. The panel is a fixed transparent
/// stage; the capsule inside sizes itself to its content.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    private let panel: NSPanel
    private let panelSize = NSSize(width: 480, height: 132)
    /// Gap between the bottom of the visible frame (above the Dock) and
    /// the panel; the view adds its own shadow padding on top of this.
    private let bottomInset: CGFloat = 8

    /// Bumped on every show/hide so a delayed step from an earlier call
    /// can tell it has been superseded.
    private var generation = 0

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
        generation += 1
        positionOnActiveScreen()
        panel.orderFrontRegardless()
        guard !model.isPresented else { return }

        // Present on the next turn of the run loop so the entrance animates
        // inside a window that is already on screen.
        let token = generation
        Task { @MainActor [weak self] in
            guard let self, self.generation == token else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                self.model.isPresented = true
            }
        }
    }

    func hide() {
        generation += 1
        let token = generation
        withAnimation(.easeIn(duration: 0.14)) {
            model.isPresented = false
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.generation == token else { return }
            self.panel.orderOut(nil)
            // Park the view in a state with no animation timelines — otherwise
            // they keep ticking (and burning CPU) inside the offscreen window.
            self.model.phase = .hidden
            self.model.text = ""
            self.model.resetLevels()
        }
    }

    private func positionOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.minY + bottomInset
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }
}

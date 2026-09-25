import AppKit
import ApplicationServices
import Foundation
import os
import ScreenCaptureKit
import Vision

/// Captures the focused window as an image and extracts its text with
/// on-device Vision OCR. The image never leaves the Mac — only recognized
/// text flows onward, where the caller distills or redacts it per the
/// user's screen-context setting.
///
/// Runs concurrently with speech (started at hotkey press) under a hard
/// time budget, so it can never delay insertion: a capture that isn't done
/// in time is simply dropped.
enum ScreenContextService {
    private static let log = Logger(subsystem: "com.sgstq.voce", category: "screen")

    /// Longest window side rendered into the capture. Bounds Vision cost;
    /// measured ~0.5 s for `.accurate` OCR at this size on Apple Silicon.
    private static let maxCaptureDimension: CGFloat = 2800

    /// Total budget for capture + OCR. Dictations shorter than this simply
    /// proceed without screen context.
    private static let timeout: Duration = .seconds(2.5)

    static func isPermissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Best-effort by design: returns nil on missing permission, no focused
    /// window, capture failure, or timeout — dictation must never notice.
    @MainActor
    static func captureWindowText() async -> String? {
        guard CGPreflightScreenCaptureAccess() else {
            log.info("capture skipped: screen recording not granted")
            return nil
        }
        guard let target = focusedWindowTarget() else {
            log.info("capture skipped: no focused window")
            return nil
        }

        let text = await withTimeout(timeout) {
            await recognizeText(in: target)
        }
        log.info("captured window text chars=\(text?.count ?? 0)")
        return text
    }

    // MARK: Focused window

    /// Identity of the window to capture, taken from the same AX focus the
    /// rest of the app uses. Frame and title disambiguate between the
    /// frontmost app's windows.
    private struct WindowTarget: Sendable {
        let processID: pid_t
        let title: String
        let frame: CGRect?
    }

    @MainActor
    private static func focusedWindowTarget() -> WindowTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        var title = ""
        var frame: CGRect?

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            let window = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)
            title = stringAttribute(of: window, kAXTitleAttribute) ?? ""

            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            var position = CGPoint.zero
            var size = CGSize.zero
            if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
               let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
               AXValueGetValue(unsafeDowncast(positionRef as AnyObject, to: AXValue.self), .cgPoint, &position),
               AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
               AXValueGetValue(unsafeDowncast(sizeRef as AnyObject, to: AXValue.self), .cgSize, &size) {
                frame = CGRect(origin: position, size: size)
            }
        }

        return WindowTarget(processID: app.processIdentifier, title: title, frame: frame)
    }

    private static func stringAttribute(of element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref as? String else {
            return nil
        }
        return value
    }

    // MARK: Capture + OCR

    private static func recognizeText(in target: WindowTarget) async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let window = matchWindow(target, in: content.windows) else {
                log.info("capture skipped: focused window not shareable")
                return nil
            }

            let configuration = SCStreamConfiguration()
            let scale = min(2, maxCaptureDimension / max(window.frame.width, window.frame.height, 1))
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
            return extractText(from: image)
        } catch {
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// AX frames and SCWindow frames share the global top-left coordinate
    /// space, so the focused window is simply the candidate closest to the
    /// AX frame; the title breaks ties when AX gave no frame.
    private static func matchWindow(_ target: WindowTarget, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            window.owningApplication?.processID == target.processID
                && window.windowLayer == 0
                && window.isOnScreen
                && window.frame.width > 1 && window.frame.height > 1
        }
        guard !candidates.isEmpty else { return nil }

        if let frame = target.frame {
            return candidates.min { lhs, rhs in
                frameDistance(lhs.frame, frame) < frameDistance(rhs.frame, frame)
            }
        }
        if !target.title.isEmpty, let byTitle = candidates.first(where: { $0.title == target.title }) {
            return byTitle
        }
        return candidates.first
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x) + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    /// `.accurate` over `.fast`: measured ~500 ms vs ~190 ms for a full
    /// Retina window, but `.fast` garbles identifiers — and identifiers are
    /// the payload here.
    private static func extractText(from image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            log.error("ocr failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

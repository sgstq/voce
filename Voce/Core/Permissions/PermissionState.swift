import ApplicationServices
import AppKit
import AVFoundation
import Foundation
import os

struct PermissionState: Equatable {
    var microphone: MicrophonePermission
    var accessibilityTrusted: Bool
    var screenRecordingGranted: Bool

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "permissions")

    /// Screen Recording is deliberately absent here: it gates only the
    /// optional screen-context feature, never core dictation.
    var isReadyForPhaseZero: Bool {
        microphone == .authorized && accessibilityTrusted
    }

    static func current() -> PermissionState {
        let state = PermissionState(
            microphone: MicrophonePermission.current(),
            accessibilityTrusted: AXIsProcessTrusted(),
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
        log.notice(
            "mic=\(state.microphone.rawValue, privacy: .public) axTrusted=\(state.accessibilityTrusted) screen=\(state.screenRecordingGranted)"
        )
        return state
    }

    static func requestAccessibilityPrompt() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows the system dialog on first ask; later calls are no-ops and the
    /// user must flip the switch in System Settings instead.
    static func requestScreenRecordingPrompt() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}

enum MicrophonePermission: String, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown

    static func current() -> MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }

    var label: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .authorized:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .unknown:
            "Unknown"
        }
    }
}

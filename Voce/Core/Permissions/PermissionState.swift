import ApplicationServices
import AppKit
import AVFoundation
import Foundation
import os

struct PermissionState: Equatable {
    var microphone: MicrophonePermission
    var accessibilityTrusted: Bool

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "permissions")

    var isReadyForPhaseZero: Bool {
        microphone == .authorized && accessibilityTrusted
    }

    static func current() -> PermissionState {
        let state = PermissionState(
            microphone: MicrophonePermission.current(),
            accessibilityTrusted: AXIsProcessTrusted()
        )
        log.notice("mic=\(state.microphone.rawValue, privacy: .public) axTrusted=\(state.accessibilityTrusted)")
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

import AppKit
import CoreGraphics

/// Global push-to-talk key monitor built on a listen-only `CGEventTap`.
/// Requires Accessibility trust. The tap runs on the main run loop, so the
/// press/release callbacks always fire on the main actor.
@MainActor
final class HotkeyMonitor {
    enum MonitorError: LocalizedError {
        case tapCreationFailed

        var errorDescription: String? {
            "Could not install the global hotkey. Grant Accessibility access and try again."
        }
    }

    private let spec: HotkeySpec
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    var isRunning: Bool { tap != nil }

    init(spec: HotkeySpec, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.spec = spec
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() throws {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MonitorError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        isPressed = false
    }

    fileprivate func handle(
        type: CGEventType,
        keyCode: UInt16,
        isAutorepeat: Bool,
        rawFlags: UInt64
    ) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        case .keyDown, .keyUp:
            guard spec.kind == .key, keyCode == spec.keyCode else { return }
            if type == .keyDown {
                guard !isAutorepeat, !isPressed else { return }
                isPressed = true
                onPress()
            } else if isPressed {
                isPressed = false
                onRelease()
            }

        case .flagsChanged:
            guard spec.kind == .modifier,
                  keyCode == spec.keyCode,
                  let mask = KeyCodes.modifierMask(for: spec.keyCode) else { return }
            let isDown = CGEventFlags(rawValue: rawFlags).contains(mask)
            if isDown, !isPressed {
                isPressed = true
                onPress()
            } else if !isDown, isPressed {
                isPressed = false
                onRelease()
            }

        default:
            break
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        // Extract primitives so no CGEvent crosses an isolation boundary.
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let rawFlags = event.flags.rawValue
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        // The tap source is on the main run loop, so this is the main thread.
        MainActor.assumeIsolated {
            monitor.handle(type: type, keyCode: keyCode, isAutorepeat: isAutorepeat, rawFlags: rawFlags)
        }
    }
    return Unmanaged.passUnretained(event)
}

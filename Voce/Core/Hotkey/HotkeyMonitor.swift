import AppKit
import CoreGraphics

/// Global push-to-talk monitor built on a listen-only `CGEventTap`: it
/// watches every profile's keys at once and reports which one is held.
/// Requires Accessibility trust. The tap runs on the main run loop, so
/// events always arrive on the main actor.
@MainActor
final class HotkeyMonitor {
    enum MonitorError: LocalizedError {
        case tapCreationFailed

        var errorDescription: String? {
            "Could not install the global hotkey. Grant Accessibility access and try again."
        }
    }

    private var matcher: HotkeyMatcher
    private let onEvent: (HotkeyEvent) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settleTask: Task<Void, Never>?
    private var settlingBinding: HotkeyBinding?

    var isRunning: Bool { tap != nil }

    init(bindings: [HotkeyBinding], onEvent: @escaping (HotkeyEvent) -> Void) {
        self.matcher = HotkeyMatcher(bindings: bindings)
        self.onEvent = onEvent
    }

    func start() throws {
        guard tap == nil else { return }

        // Clicks can make a shortcut too: ⌘-click, ⌥-click.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

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
        settleTask?.cancel()
        settleTask = nil
        settlingBinding = nil
        matcher = HotkeyMatcher(bindings: matcher.bindings)
    }

    func update(bindings: [HotkeyBinding]) {
        matcher.update(bindings: bindings)
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
            resync()

        case .keyDown:
            guard !isAutorepeat else { return }
            deliver(matcher.keyDown(keyCode))

        case .keyUp:
            deliver(matcher.keyUp(keyCode))

        case .flagsChanged:
            let modifiers = KeyCodes.heldModifiers(rawFlags: rawFlags, changedKeyCode: keyCode)
            deliver(matcher.modifiersChanged(to: modifiers))

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            deliver(matcher.click())

        default:
            break
        }
    }

    /// Events can be lost while the tap was disabled; read the real key
    /// state so a missed release can't leave a recording running.
    private func resync() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let keys = matcher.bindings
            .reduce(into: Set<UInt16>()) { $0.formUnion($1.keys) }
            .filter { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
        deliver(matcher.resync(modifiers: KeyCodes.heldModifiers(rawFlags: flags), keys: keys))
    }

    private func deliver(_ events: [HotkeyEvent]) {
        scheduleSettleIfNeeded()
        events.forEach(onEvent)
    }

    /// A pending binding fires once the combination stops growing.
    private func scheduleSettleIfNeeded() {
        guard case .pending(let binding) = matcher.state else {
            settleTask?.cancel()
            settleTask = nil
            settlingBinding = nil
            return
        }
        guard binding != settlingBinding else { return }
        settlingBinding = binding
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: HotkeyMatcher.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.settlingBinding = nil
            self.settleTask = nil
            self.deliver(self.matcher.settle())
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

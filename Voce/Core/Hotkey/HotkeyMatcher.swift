import Foundation

/// One profile's push-to-talk keys.
struct HotkeyBinding: Equatable, Sendable {
    let id: UUID
    let keys: Set<UInt16>
}

enum HotkeyEvent: Equatable, Sendable {
    /// The held keys match a binding but could still grow into a longer one
    /// (⌥ on the way to ⌥ + ⇧). Start listening; the profile follows.
    case armed
    case pressed(UUID)
    case released(UUID)
    /// A key outside the binding went down while it was held — usually a
    /// shortcut such as ⌥E. The binding stays held until its keys come up.
    case interrupted(UUID)
    /// The armed keys turned into a shortcut or were let go before settling.
    case cancelled
}

/// Decides which binding the keys held down belong to, without touching any
/// event APIs so it can be tested directly. A binding fires only when
/// exactly its keys are down, and only as a key goes down — letting go of
/// ⇧ in ⌥ + ⇧ never starts the ⌥ binding. When the held keys match one
/// binding but are part of a longer one, the match waits `settleDelay` for
/// the rest of the combination before firing.
struct HotkeyMatcher {
    static let settleDelay: Duration = .milliseconds(200)

    enum State: Equatable {
        case idle
        case pending(HotkeyBinding)
        case active(HotkeyBinding)
    }

    private(set) var bindings: [HotkeyBinding]
    private(set) var state: State = .idle
    private var heldModifiers: Set<UInt16> = []
    /// Non-modifier keys that belong to some binding. Other keys are never
    /// tracked, so a missed key-up elsewhere can't block a match.
    private var heldKeys: Set<UInt16> = []

    init(bindings: [HotkeyBinding]) {
        self.bindings = bindings
    }

    var held: Set<UInt16> { heldModifiers.union(heldKeys) }

    /// Keeps a binding that is already held, so changing settings mid-hold
    /// can't swallow its release.
    mutating func update(bindings: [HotkeyBinding]) {
        self.bindings = bindings
        heldKeys.formIntersection(bindingKeys)
    }

    mutating func modifiersChanged(to modifiers: Set<UInt16>) -> [HotkeyEvent] {
        let released = heldModifiers.subtracting(modifiers)
        let pressed = modifiers.subtracting(heldModifiers)
        heldModifiers = modifiers
        var events = released.isEmpty ? [] : keysWentUp(released)
        if !pressed.isEmpty {
            events += keyWentDown(isModifier: true, keyCode: nil)
        }
        return events
    }

    mutating func keyDown(_ keyCode: UInt16) -> [HotkeyEvent] {
        guard bindingKeys.contains(keyCode) else { return otherInput() }
        guard heldKeys.insert(keyCode).inserted else { return [] }
        return keyWentDown(isModifier: false, keyCode: keyCode)
    }

    mutating func keyUp(_ keyCode: UInt16) -> [HotkeyEvent] {
        guard heldKeys.remove(keyCode) != nil else { return [] }
        return keysWentUp([keyCode])
    }

    /// A key outside every binding, or a mouse click, joined the held keys.
    mutating func otherInput() -> [HotkeyEvent] {
        switch state {
        case .idle:
            return []
        case .pending:
            state = .idle
            return [.cancelled]
        case .active(let binding):
            return [.interrupted(binding.id)]
        }
    }

    /// A click with modifier-only keys held is a shortcut (⌥-click, ⌘-click);
    /// a binding with a regular key, like F5, can be clicked through.
    mutating func click() -> [HotkeyEvent] {
        switch state {
        case .pending(let binding), .active(let binding):
            return binding.keys.allSatisfy(KeyCodes.isModifier) ? otherInput() : []
        case .idle:
            return []
        }
    }

    /// Fires a pending binding once `settleDelay` passed without the
    /// combination growing.
    mutating func settle() -> [HotkeyEvent] {
        guard case .pending(let binding) = state, held == binding.keys else { return [] }
        state = .active(binding)
        return [.pressed(binding.id)]
    }

    /// Replaces the held state with what the system reports, after events
    /// may have been missed (the tap was disabled). Releases a binding
    /// whose keys are no longer down; never starts one.
    mutating func resync(modifiers: Set<UInt16>, keys: Set<UInt16>) -> [HotkeyEvent] {
        let current = modifiers.union(keys.intersection(bindingKeys))
        let released = held.subtracting(current)
        heldModifiers = modifiers
        heldKeys = keys.intersection(bindingKeys)
        return released.isEmpty ? [] : keysWentUp(released)
    }

    private var bindingKeys: Set<UInt16> {
        bindings.reduce(into: Set<UInt16>()) { $0.formUnion($1.keys) }.subtracting(KeyCodes.modifierKeyCodes)
    }

    private mutating func keyWentDown(isModifier: Bool, keyCode: UInt16?) -> [HotkeyEvent] {
        switch state {
        case .active(let binding):
            // An extra modifier may start a shortcut, but only a real key proves it.
            if !isModifier, let keyCode, !binding.keys.contains(keyCode) {
                return [.interrupted(binding.id)]
            }
            return []
        case .idle, .pending:
            return match()
        }
    }

    private mutating func match() -> [HotkeyEvent] {
        let held = self.held
        let wasPending = state != .idle
        guard let exact = bindings.first(where: { $0.keys == held }) else {
            state = .idle
            return wasPending ? [.cancelled] : []
        }
        let isPartOfLonger = bindings.contains { $0.keys.count > held.count && $0.keys.isSuperset(of: held) }
        if isPartOfLonger {
            state = .pending(exact)
            return wasPending ? [] : [.armed]
        }
        state = .active(exact)
        return [.pressed(exact.id)]
    }

    private mutating func keysWentUp(_ keyCodes: Set<UInt16>) -> [HotkeyEvent] {
        switch state {
        case .active(let binding) where !binding.keys.isDisjoint(with: keyCodes):
            state = .idle
            return [.released(binding.id)]
        case .pending(let binding) where !binding.keys.isDisjoint(with: keyCodes):
            state = .idle
            return [.cancelled]
        default:
            return []
        }
    }
}

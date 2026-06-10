import AppKit
import ApplicationServices
import os

/// What the user is dictating into, captured at hotkey release: the active
/// app, window title, and the text around the cursor. Fed to the refiner so
/// it can match spelling/casing of identifiers and proper nouns. Secure
/// fields are never read.
struct FocusContext: Equatable, Sendable {
    var appName = ""
    var bundleIdentifier = ""
    var windowTitle = ""
    var selectedText = ""
    var textBeforeCursor = ""
    var textAfterCursor = ""

    var hasSurroundingText: Bool {
        !textBeforeCursor.isEmpty || !textAfterCursor.isEmpty || !selectedText.isEmpty
    }
}

@MainActor
enum FocusContextCapture {
    private static let log = Logger(subsystem: "com.sgstq.voce", category: "context")

    /// Max UTF-16 units of context kept on each side of the cursor.
    static let beforeWindow = 600
    static let afterWindow = 300

    /// `includeText: false` captures only the app/window identity (used for
    /// the target-changed guard when the user disabled context capture).
    static func capture(includeText: Bool) -> FocusContext {
        var context = FocusContext()

        if let app = NSWorkspace.shared.frontmostApplication {
            context.appName = app.localizedName ?? ""
            context.bundleIdentifier = app.bundleIdentifier ?? ""
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            log.info("capture: no focused element (app=\(context.appName, privacy: .public))")
            return context
        }
        let element = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)

        context.windowTitle = windowTitle(of: element)

        guard includeText else { return context }

        // Privacy: never read password fields.
        if stringAttribute(of: element, kAXSubroleAttribute) == "AXSecureTextField" {
            log.info("capture: secure field, skipping text")
            return context
        }

        context.selectedText = stringAttribute(of: element, kAXSelectedTextAttribute) ?? ""

        if let value = stringAttribute(of: element, kAXValueAttribute),
           let cursor = selectedRange(of: element) {
            let window = Self.window(
                text: value,
                selectionLocation: cursor.location,
                selectionLength: cursor.length,
                before: beforeWindow,
                after: afterWindow
            )
            context.textBeforeCursor = window.before
            context.textAfterCursor = window.after
        }

        log.info(
            """
            capture: app=\(context.appName, privacy: .public) title.len=\(context.windowTitle.count) \
            before.len=\(context.textBeforeCursor.count) after.len=\(context.textAfterCursor.count) \
            selected.len=\(context.selectedText.count)
            """
        )
        return context
    }

    /// Extracts the text window around a UTF-16 selection range, clamped and
    /// snapped to character boundaries so emoji/surrogates never split.
    /// Pure (hence nonisolated); internal for tests.
    nonisolated static func window(
        text: String,
        selectionLocation: Int,
        selectionLength: Int,
        before: Int,
        after: Int
    ) -> (before: String, after: String) {
        let utf16 = text.utf16
        let total = utf16.count
        let location = max(0, min(selectionLocation, total))
        let selectionEnd = max(location, min(selectionLocation + selectionLength, total))

        let beforeStartOffset = max(0, location - before)
        let afterEndOffset = min(total, selectionEnd + after)

        func index(at offset: Int) -> String.Index? {
            guard let raw = utf16.index(
                utf16.startIndex,
                offsetBy: offset,
                limitedBy: utf16.endIndex
            ) else { return nil }
            // Snap to a valid character boundary (surrogate-pair safety).
            return String.Index(raw, within: text)
                ?? text.indices.last(where: { $0 <= raw })
                ?? text.startIndex
        }

        guard
            let beforeStart = index(at: beforeStartOffset),
            let cursorIndex = index(at: location),
            let selectionEndIndex = index(at: selectionEnd),
            let afterEnd = index(at: afterEndOffset),
            beforeStart <= cursorIndex, selectionEndIndex <= afterEnd
        else {
            return ("", "")
        }

        return (
            before: String(text[beforeStart..<cursorIndex]),
            after: String(text[selectionEndIndex..<afterEnd])
        )
    }

    // MARK: AX helpers

    private static func stringAttribute(of element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref as? String else {
            return nil
        }
        return value
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &ref
        ) == .success, let ref, CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(ref as AnyObject, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func windowTitle(of element: AXUIElement) -> String {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef,
            CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return ""
        }
        let window = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)
        return stringAttribute(of: window, kAXTitleAttribute) ?? ""
    }
}

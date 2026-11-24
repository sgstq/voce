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
    /// Distilled exact spellings from the active window (terms-only screen
    /// context); at most one of these two carries data per dictation.
    var screenVocabulary: [String] = []
    /// Recognized window text (full-text screen context), secrets redacted.
    var screenText = ""

    var hasSurroundingText: Bool {
        !textBeforeCursor.isEmpty || !textAfterCursor.isEmpty || !selectedText.isEmpty
    }

    /// The dictation as it should be typed: a dictation arrives trimmed, so
    /// one typed right after a word or a sentence's end needs a space first.
    /// None after whitespace, quotes, or opening brackets, whose side is
    /// ambiguous, and none before text that starts with punctuation.
    func spacedForInsertion(_ text: String) -> String {
        guard let last = textBeforeCursor.last, let first = text.first else { return text }
        let joinsAfter = last.isLetter || last.isNumber || ".,;:!?)]}%…".contains(last)
        let startsWord = !first.isWhitespace && !".,;:!?)]}%…'\"".contains(first)
        return joinsAfter && startsWord ? " " + text : text
    }

    /// Folds the active window's recognized text in as the screen-context
    /// mode allows: distilled terms only, or the full text with secrets
    /// redacted.
    mutating func addScreenText(_ windowText: String, mode: ScreenContextMode) {
        switch mode {
        case .termsOnly:
            screenVocabulary = VocabularyDistiller.distill(from: windowText)
        case .fullText:
            screenText = VocabularyDistiller.redactSecrets(in: windowText)
        case .off:
            break
        }
    }
}

@MainActor
enum FocusContextCapture {
    private static let log = Logger(subsystem: "com.sgstq.voce", category: "context")

    /// Max UTF-16 units of context kept on each side of the cursor.
    static let beforeWindow = 600
    static let afterWindow = 300

    /// Electron and other Chromium apps (Slack, VS Code, bb) build their
    /// accessibility tree only after a client sets AXManualAccessibility,
    /// and then take about 2 s (measured in bb), so this runs when an app
    /// comes to the front rather than at key press. Without it they report no
    /// focused element and Voce sees no text around the cursor. Native apps
    /// reject the attribute, which is harmless; it reads nothing.
    nonisolated static func enableAccessibility(ofProcess pid: pid_t) {
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
    }

    /// Enables accessibility in the front app now and in each app that comes
    /// forward later, while `isNeeded` (some profile captures context) holds.
    /// Keep the returned observer alive for as long as it should run.
    static func enableAccessibilityOfFrontApps(while isNeeded: @escaping @MainActor () -> Bool) -> NSObjectProtocol {
        if isNeeded(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            enableAccessibility(ofProcess: pid)
        }
        return NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                if isNeeded() { enableAccessibility(ofProcess: pid) }
            }
        }
    }

    /// `includeText: false` captures only the app/window identity (used for
    /// the target-changed guard when the user disabled context capture).
    static func capture(includeText: Bool) -> FocusContext {
        var context = FocusContext()

        if let app = NSWorkspace.shared.frontmostApplication {
            context.appName = app.localizedName ?? ""
            context.bundleIdentifier = app.bundleIdentifier ?? ""
        }

        // Ask the front app first: for Electron apps the system-wide query
        // fails (kAXErrorCannotComplete) even once their tree exists.
        let owners = [
            NSWorkspace.shared.frontmostApplication.map { AXUIElementCreateApplication($0.processIdentifier) },
            AXUIElementCreateSystemWide(),
        ].compactMap { $0 }
        var focusedRef: CFTypeRef?
        guard owners.contains(where: {
            AXUIElementCopyAttributeValue($0, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success
        }), let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
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

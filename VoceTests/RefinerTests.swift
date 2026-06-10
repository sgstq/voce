import XCTest
@testable import Voce

final class RefinerTests: XCTestCase {
    func testPromptIncludesTranscriptAndAppContext() {
        var context = FocusContext()
        context.appName = "Xcode"
        context.windowTitle = "Refiner.swift"

        let prompt = Refiner.buildPrompt(transcript: "hello world", context: context, language: "en")

        XCTAssertTrue(prompt.contains("Application: Xcode"))
        XCTAssertTrue(prompt.contains("Window title: Refiner.swift"))
        XCTAssertTrue(prompt.hasSuffix("hello world"))
        XCTAssertFalse(prompt.contains("{transcript}"))
        XCTAssertFalse(prompt.contains("{app_name}"))
        XCTAssertFalse(prompt.contains("{surrounding_text_section}"))
    }

    func testPromptOmitsSurroundingSectionWhenEmpty() {
        let prompt = Refiner.buildPrompt(transcript: "hi", context: FocusContext(), language: "auto")
        XCTAssertFalse(prompt.contains("Surrounding text"))
    }

    func testPromptCarriesExplicitLanguageContract() {
        let prompt = Refiner.buildPrompt(transcript: "привет", context: FocusContext(), language: "ru")
        XCTAssertTrue(prompt.contains("The dictation is primarily Russian"))
        XCTAssertTrue(prompt.contains("keep that part in its original language"))
        XCTAssertTrue(prompt.contains("NEVER translate"))
        XCTAssertFalse(prompt.contains("{language_rule}"))
    }

    func testPromptCarriesAutoDetectContract() {
        let prompt = Refiner.buildPrompt(transcript: "hola", context: FocusContext(), language: "auto")
        XCTAssertTrue(prompt.contains("may contain several languages"))
        XCTAssertTrue(prompt.contains("preserving mid-dictation switches"))
        XCTAssertTrue(prompt.contains("never unify the text into a single language"))
        XCTAssertTrue(prompt.contains("NEVER translate"))
    }

    func testNoSingularLanguageFraming() {
        // Regression: singular framing ("write in that SAME language") made
        // models translate the minority segments of mixed dictations.
        for language in ["auto", "ru", "en"] {
            let prompt = Refiner.buildPrompt(transcript: "x", context: FocusContext(), language: language)
            XCTAssertFalse(prompt.contains("that SAME language"), "singular framing leaked for \(language)")
            XCTAssertFalse(prompt.contains("Write the output in"), "whole-output language directive leaked for \(language)")
        }
    }

    func testSurroundingTextNeverChangesLanguage() {
        // The style rule must not invite translation when dictating Russian
        // into an English document.
        let prompt = Refiner.buildPrompt(transcript: "x", context: FocusContext(), language: "auto")
        XCTAssertTrue(prompt.contains("The surrounding text NEVER changes the output language"))
    }

    func testPromptIncludesCursorContext() {
        var context = FocusContext()
        context.textBeforeCursor = "let userDefinedCompanyData ="
        context.textAfterCursor = "// end of section"
        context.selectedText = "oldValue"

        let prompt = Refiner.buildPrompt(transcript: "use the company data", context: context, language: "en")

        XCTAssertTrue(prompt.contains("Text before the cursor:\nlet userDefinedCompanyData ="))
        XCTAssertTrue(prompt.contains("Currently selected text (will be replaced):\noldValue"))
        XCTAssertTrue(prompt.contains("Text after the cursor:\n// end of section"))
    }

    func testOpenAIRequestBodySuppressesReasoning() throws {
        let data = try Refiner.requestBody(provider: .openAI, model: "gpt-5-mini", prompt: "PROMPT")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["model"] as? String, "gpt-5-mini")
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "PROMPT")
        // The latency fix: no hidden "thinking" before a one-line cleanup.
        XCTAssertEqual(object["reasoning_effort"] as? String, "minimal")
        XCTAssertEqual(object["max_completion_tokens"] as? Int, 1500)
        // GPT-5 family rejects custom sampling params.
        XCTAssertNil(object["temperature"])
        XCTAssertNil(object["max_tokens"])
    }

    func testSpeedProviderRequestBodies() throws {
        for provider in [RefinementProvider.groq, .cerebras] {
            let data = try Refiner.requestBody(provider: provider, model: "llama-3.3-70b", prompt: "P")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["temperature"] as? Double, 0.3)
            XCTAssertEqual(object["max_tokens"] as? Int, 1500)
            XCTAssertNil(object["reasoning_effort"], "\(provider) should not send reasoning params")
        }
    }

    func testProviderTable() {
        XCTAssertEqual(RefinementProvider.openAI.endpoint?.host, "api.openai.com")
        XCTAssertEqual(RefinementProvider.groq.endpoint?.host, "api.groq.com")
        XCTAssertEqual(RefinementProvider.cerebras.endpoint?.host, "api.cerebras.ai")
        XCTAssertNil(RefinementProvider.appleOnDevice.endpoint)

        XCTAssertEqual(RefinementProvider.openAI.keychainAccount, "openai-api-key")
        XCTAssertEqual(RefinementProvider.groq.keychainAccount, "groq-api-key")
        XCTAssertEqual(RefinementProvider.cerebras.keychainAccount, "cerebras-api-key")
        XCTAssertNil(RefinementProvider.appleOnDevice.keychainAccount)

        XCTAssertFalse(RefinementProvider.appleOnDevice.isCloud)
        XCTAssertTrue(RefinementProvider.groq.isCloud)
        XCTAssertTrue(RefinementProvider.appleOnDevice.defaultModel.isEmpty)
    }

    func testTruncationGuard() {
        let longRaw = String(repeating: "слово word ", count: 40) // 440 chars
        // A long dictation collapsing to its last phrase must be rejected.
        XCTAssertTrue(Refiner.looksTruncated(refined: "Just the last phrase.", raw: longRaw))
        XCTAssertEqual(Refiner.acceptingRefinement("The tail.", raw: longRaw), longRaw)
        // Mild legitimate shrink (filler removal) passes.
        let mildShrink = String(longRaw.prefix(300))
        XCTAssertFalse(Refiner.looksTruncated(refined: mildShrink, raw: longRaw))
        XCTAssertEqual(Refiner.acceptingRefinement(mildShrink, raw: longRaw), mildShrink)
        // Short inputs are exempt — "um, yeah, okay" → "Okay." is valid.
        XCTAssertFalse(Refiner.looksTruncated(refined: "Okay.", raw: "um, yeah, okay I guess so"))
    }

    func testTranslationGuard() {
        // The user's exact failure: RU -> EN -> RU dictation refined into
        // all-English. Cyrillic carried ~half the raw letters and vanished.
        let raw = "Окей, мы тестируем длинное сообщение. Me gustan las manzanas. После этого всё должно работать отлично."
        let translated = "Okay, we are testing a long message. Me gustan las manzanas. After that everything should work fine."
        XCTAssertTrue(Refiner.looksTranslated(refined: translated, raw: raw))
        XCTAssertEqual(Refiner.acceptingRefinement(translated, raw: raw), raw)

        // Legitimate cleanup keeps the script mix — accepted.
        let cleaned = "Окей. Мы тестируем длинное сообщение. Me gustan las manzanas. После этого всё должно работать отлично."
        XCTAssertFalse(Refiner.looksTranslated(refined: cleaned, raw: raw))
        XCTAssertEqual(Refiner.acceptingRefinement(cleaned, raw: raw), cleaned)

        // Monolingual text is never flagged.
        XCTAssertFalse(Refiner.looksTranslated(refined: "All English output.", raw: "all english um output"))
        // A trace amount of foreign script (one word) is below the threshold.
        let mostlyEnglish = "This is mostly English with one слово inside a long enough sentence."
        XCTAssertFalse(Refiner.looksTranslated(refined: "This is mostly English with one word inside a long enough sentence.", raw: mostlyEnglish))
    }

    func testScriptShares() {
        let shares = Refiner.scriptShares(of: "abc где 123 !").shares
        XCTAssertEqual(shares[.latin] ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(shares[.cyrillic] ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(Refiner.scriptShares(of: "12 34 !?").totalLetters, 0)
    }

    func testRefusalGuard() {
        XCTAssertTrue(Refiner.isRefusal("I'm sorry, I can't help with that."))
        XCTAssertTrue(Refiner.isRefusal("The transcription appears to be truncated"))
        XCTAssertTrue(Refiner.isRefusal("As an AI, I should note..."))
        XCTAssertFalse(Refiner.isRefusal("Ship the release notes by Friday."))
        XCTAssertFalse(Refiner.isRefusal("let userDefinedCompanyData = fetch()"))
    }
}

final class DictationLanguagesTests: XCTestCase {
    func testAutomaticDetection() {
        XCTAssertTrue(DictationLanguages.isAutomatic("auto"))
        XCTAssertTrue(DictationLanguages.isAutomatic("AUTO"))
        XCTAssertTrue(DictationLanguages.isAutomatic(""))
        XCTAssertTrue(DictationLanguages.isAutomatic("  "))
        XCTAssertFalse(DictationLanguages.isAutomatic("en"))
    }

    func testEnglishNamesForPrompt() {
        XCTAssertEqual(DictationLanguages.englishName(for: "ru"), "Russian")
        XCTAssertEqual(DictationLanguages.englishName(for: "en"), "English")
        XCTAssertNil(DictationLanguages.englishName(for: "auto"))
    }

    func testPickerOptionsIncludeStoredCustomCode() {
        XCTAssertEqual(
            DictationLanguages.pickerOptions(including: "en"),
            DictationLanguages.curated
        )
        let withCustom = DictationLanguages.pickerOptions(including: "eo")
        XCTAssertEqual(withCustom.last, "eo")
        XCTAssertTrue(withCustom.dropLast().elementsEqual(DictationLanguages.curated))
    }
}

final class FocusContextWindowTests: XCTestCase {
    func testWindowsAroundCursor() {
        let text = String(repeating: "a", count: 1000) + "CURSOR" + String(repeating: "b", count: 1000)
        // Selection covering "CURSOR" (location 1000, length 6).
        let window = FocusContextCapture.window(
            text: text, selectionLocation: 1000, selectionLength: 6, before: 100, after: 50
        )
        XCTAssertEqual(window.before, String(repeating: "a", count: 100))
        XCTAssertEqual(window.after, String(repeating: "b", count: 50))
    }

    func testWindowClampsAtDocumentEdges() {
        let window = FocusContextCapture.window(
            text: "short", selectionLocation: 2, selectionLength: 0, before: 600, after: 300
        )
        XCTAssertEqual(window.before, "sh")
        XCTAssertEqual(window.after, "ort")
    }

    func testWindowHandlesOutOfRangeSelection() {
        let window = FocusContextCapture.window(
            text: "abc", selectionLocation: 99, selectionLength: 5, before: 10, after: 10
        )
        XCTAssertEqual(window.before, "abc")
        XCTAssertEqual(window.after, "")
    }

    func testWindowDoesNotSplitEmoji() {
        // "👨‍👩‍👧‍👦" is 11 UTF-16 units; cut points inside it must snap out.
        let text = "abc👨‍👩‍👧‍👦def"
        let window = FocusContextCapture.window(
            text: text, selectionLocation: 5, selectionLength: 0, before: 1, after: 2
        )
        // Whatever the exact snap, results must be valid strings that
        // round-trip through UTF-16 (no lone surrogates).
        for part in [window.before, window.after] {
            let units = Array(part.utf16)
            XCTAssertEqual(String(utf16CodeUnits: units, count: units.count), part)
        }
    }

    func testEmptyText() {
        let window = FocusContextCapture.window(
            text: "", selectionLocation: 0, selectionLength: 0, before: 100, after: 100
        )
        XCTAssertEqual(window.before, "")
        XCTAssertEqual(window.after, "")
    }
}

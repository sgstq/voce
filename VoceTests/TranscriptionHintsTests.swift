import XCTest
@testable import Voce

final class TranscriptionHintsTests: XCTestCase {
    private func profile(_ backend: TranscriptionBackend, _ edit: (inout DictationProfile) -> Void = { _ in }) -> DictationProfile {
        var profile = DictationProfile(transcriptionBackend: backend)
        edit(&profile)
        return profile
    }

    func testOptionsAreOffByDefaultAndOldConfigsDecodeThatWay() throws {
        let decoded = try JSONDecoder().decode(DictationProfile.self, from: Data(#"{"name": "Old"}"#.utf8))
        XCTAssertEqual(decoded.elevenLabsModel, "scribe_v3_live")
        XCTAssertEqual(decoded.transcriptionHints(screenTerms: ["fooBar"]), TranscriptionHints())
    }

    func testTypedTermsComeFirstThenScreenTermsWithoutDuplicates() {
        let profile = profile(.elevenLabs) {
            $0.vocabularyHintsEnabled = true
            $0.screenVocabularyHints = true
            $0.vocabulary = " Voce,\nOviedo\n\n, Voce "
        }
        XCTAssertEqual(
            profile.transcriptionHints(screenTerms: ["fooBar", "Oviedo"]).keyterms,
            ["Voce", "Oviedo", "fooBar"]
        )
    }

    func testScreenTermsNeedTheirOwnToggle() {
        let profile = profile(.deepgram) {
            $0.vocabularyHintsEnabled = true
            $0.vocabulary = "Voce"
        }
        XCTAssertEqual(profile.transcriptionHints(screenTerms: ["fooBar"]).keyterms, ["Voce"])
        XCTAssertFalse(profile.wantsScreenTerms)
    }

    func testTermsStopAtTheProviderCountLimit() {
        let profile = profile(.elevenLabs) {
            $0.vocabularyHintsEnabled = true
            $0.vocabulary = (1...60).map { "term\($0)" }.joined(separator: ",")
        }
        let terms = profile.transcriptionHints().keyterms
        XCTAssertEqual(terms.count, 50)
        XCTAssertEqual(terms.last, "term50")
    }

    func testTermsThatWouldPassTheCharacterLimitAreSkipped() {
        let long = String(repeating: "a", count: 990)
        let profile = profile(.elevenLabs) {
            $0.vocabularyHintsEnabled = true
            $0.vocabulary = "\(long)\nthis-one-is-too-long\nshort"
        }
        // 990 + 5 fits in 1,000; adding the 20-character term would not.
        XCTAssertEqual(profile.transcriptionHints().keyterms, [long, "short"])
    }

    func testUnsupportedModelsSendNothing() {
        let whisper = profile(.openAIRealtime) {
            $0.vocabularyHintsEnabled = true
            $0.removeFillerWords = true
            $0.vocabulary = "Voce"
        }
        XCTAssertEqual(whisper.transcriptionHints(), TranscriptionHints())

        var live = whisper
        live.realtimeModel = "gpt-live-transcribe"
        XCTAssertEqual(live.transcriptionHints().keyterms, ["Voce"])
        XCTAssertFalse(live.transcriptionHints().removeFillerWords)

        // Mixed-language mode is Scribe v3 only.
        let v2 = profile(.elevenLabs) {
            $0.elevenLabsModel = "scribe_v2_realtime"
            $0.multilingualMode = true
            $0.removeFillerWords = true
        }
        XCTAssertEqual(v2.transcriptionHints(), TranscriptionHints(removeFillerWords: true))
    }

    func testOnlyPaidProvidersCarryACostWarning() {
        XCTAssertEqual(TranscriptionBackend.elevenLabs.capabilities(model: "scribe_v3_live").keyterms?.premiumPercent, 20)
        XCTAssertEqual(TranscriptionBackend.deepgram.capabilities(model: "nova-3").keyterms?.premiumPercent, 17)
        XCTAssertNil(TranscriptionBackend.appleOnDevice.capabilities(model: "").keyterms?.premiumPercent)
        XCTAssertTrue(TranscriptionBackend.openRouter.capabilities(model: "microsoft/mai-transcribe-2").isEmpty)
        XCTAssertTrue(TranscriptionBackend.deepgram.capabilities(model: "nova-2").isEmpty)
    }
}

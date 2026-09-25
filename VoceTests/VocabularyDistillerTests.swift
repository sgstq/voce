import XCTest
@testable import Voce

final class VocabularyDistillerTests: XCTestCase {
    func testExtractsIdentifierShapedTokens() {
        let text = """
        final class RealtimeTranscriptionSession uses input_audio_buffer.append
        see CLAUDE.md and the gpt-4o-transcribe model with llama-3.3-70b
        """
        let terms = VocabularyDistiller.distill(from: text)

        XCTAssertTrue(terms.contains("RealtimeTranscriptionSession"))
        XCTAssertTrue(terms.contains("input_audio_buffer.append"))
        XCTAssertTrue(terms.contains("CLAUDE.md"))
        XCTAssertTrue(terms.contains("gpt-4o-transcribe"))
        XCTAssertTrue(terms.contains("llama-3.3-70b"))
    }

    func testExcludesOrdinaryProse() {
        let text = "The quick brown Fox jumps over the lazy dog. Nothing unusual here, Cerebras."
        // Plain words — even Capitalized ones — are indistinguishable from
        // sentence-initial words without parsing, so none may be extracted.
        XCTAssertEqual(VocabularyDistiller.distill(from: text), [])
    }

    func testStripsClingingPunctuation() {
        let text = "(see RealtimeProtocol.swift), \"gpt-4o-mini\"; and userDefaults.standard."
        let terms = VocabularyDistiller.distill(from: text)

        XCTAssertTrue(terms.contains("RealtimeProtocol.swift"))
        XCTAssertTrue(terms.contains("gpt-4o-mini"))
        XCTAssertTrue(terms.contains("userDefaults.standard"))
    }

    func testDeduplicatesPreservingFirstAppearanceOrder() {
        let text = "sessionUpdate then commitEvent then sessionUpdate again"
        XCTAssertEqual(VocabularyDistiller.distill(from: text), ["sessionUpdate", "commitEvent"])
    }

    func testCapsTermCount() {
        let text = (1...50).map { "someToken\($0)_x" }.joined(separator: " ")
        XCTAssertEqual(VocabularyDistiller.distill(from: text).count, VocabularyDistiller.termLimit)
    }

    func testExcludesURLs() {
        let text = "visit https://api.openai.com/v1/realtime or www.example.com today"
        XCTAssertEqual(VocabularyDistiller.distill(from: text), [])
    }

    func testSecretShapedTokensAreExcluded() {
        let text = """
        export OPENAI_API_KEY=sk-proj-Ab3dEfGh1jKlMnOpQrStUvWxYz012345
        token ghp_16C7e42F292c6912E7710c838347Ae178B4a eyJhbGciOiJIUzI1NiIsInR5cCI6
        safe ones: RealtimeTranscriptionSession gpt-4o-transcribe input_audio_buffer.append
        """
        let terms = VocabularyDistiller.distill(from: text)

        XCTAssertFalse(terms.contains(where: { $0.contains("sk-proj") }))
        XCTAssertFalse(terms.contains(where: { $0.hasPrefix("ghp_") }))
        XCTAssertFalse(terms.contains(where: { $0.hasPrefix("eyJ") }))
        XCTAssertTrue(terms.contains("RealtimeTranscriptionSession"))
        XCTAssertTrue(terms.contains("gpt-4o-transcribe"))
        XCTAssertTrue(terms.contains("input_audio_buffer.append"))
    }

    func testLooksLikeSecret() {
        XCTAssertTrue(VocabularyDistiller.looksLikeSecret("sk-proj-Ab3dEfGh1jKlMnOp"))
        XCTAssertTrue(VocabularyDistiller.looksLikeSecret("eyJhbGciOiJIUzI1NiIs"))
        // 20+ chars mixing lower/upper/digit — key-shaped even without a prefix.
        XCTAssertTrue(VocabularyDistiller.looksLikeSecret("a8Bx92KqLm31ZpWd75Vt"))

        // Long identifiers stay: two character classes only.
        XCTAssertFalse(VocabularyDistiller.looksLikeSecret("RealtimeTranscriptionSession"))
        XCTAssertFalse(VocabularyDistiller.looksLikeSecret("input_audio_buffer.append"))
        // Short model ids stay despite three classes.
        XCTAssertFalse(VocabularyDistiller.looksLikeSecret("gpt-4o"))
    }

    func testRedactSecretsReplacesOnlySecrets() {
        let text = "key sk-proj-Ab3dEfGh1jKlMnOp saved in RealtimeProtocol.swift"
        let redacted = VocabularyDistiller.redactSecrets(in: text)

        XCTAssertEqual(redacted, "key ••• saved in RealtimeProtocol.swift")
    }

    func testRedactSecretsKeepsClingingPunctuation() {
        let text = "token: \"ghp_16C7e42F292c6912E7710c838347Ae178B4a\", done"
        let redacted = VocabularyDistiller.redactSecrets(in: text)

        XCTAssertEqual(redacted, "token: \"•••\", done")
    }
}

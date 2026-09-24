import Testing
import Foundation
import EvalKit
@testable import TutorCore
@testable import TutorEval

@Suite("Explanation language")
struct ExplanationLanguageTests {
    @Test("A run's expected language comes from its recorded prompt", arguments: [
        (nil as String?, "en"), ("v1", "en"), ("v2 explanation:German", "de"),
        ("v1 + translate explanation:Turkish", "tr"),
    ])
    func expected(prompt: String?, code: String) {
        #expect(ExplanationLanguage.expected(from: prompt) == code)
    }

    @Test("An empty explanation has no language to grade")
    func empty() {
        #expect(ExplanationLanguage.detect("  ") == nil)
    }
}

@Suite("Quote preservation")
struct QuotePreservationTests {
    func record(_ id: String, _ explanation: String, corrected: String = "") -> CorrectionRecord {
        CorrectionRecord(caseID: id, repetition: 0,
                         output: Correction(hasError: true, corrected: corrected,
                                            explanation: explanation),
                         error: nil, latencyMilliseconds: 0, model: "m", sampling: "s")
    }
    let dataset = [CorrectionCase(id: "a", input: "Mi hermana es más alto que yo.", hasError: true,
                                  accepted: ["Mi hermana es más alta que yo."], category: "c")]

    @Test("A Spanish word translated away is caught")
    func lost() {
        let report = QuoteReport(
            source: [record("a", "The adjective 'alto' should be 'alta'.", corrected: "Mi hermana es más alta que yo.")],
            translated: [record("a", "El adjetivo 'alto' debería ser 'elevada'.")], cases: dataset)
        #expect(report.quotes == 2)
        #expect(report.kept == 1)
    }

    /// The check's first version failed this: 'her sister' is the English
    /// explanation's own words, and translating them is right.
    @Test("A quoted span that is not the learner's Spanish is not counted")
    func englishQuotesIgnored() {
        let report = QuoteReport(
            source: [record("a", "The subject 'her sister' needs 'alta'.", corrected: "Mi hermana es más alta que yo.")],
            translated: [record("a", "Das Subjekt 'ihre Schwester' braucht 'alta'.")], cases: dataset)
        #expect(report.quotes == 1)
        #expect(report.kept == 1)
    }

    @Test("A capital letter at the start of a sentence is not a loss")
    func caseIgnored() {
        let report = QuoteReport(
            source: [record("a", "'alto' should be 'alta'.", corrected: "Mi hermana es más alta que yo.")],
            translated: [record("a", "'Alto' 'alta' olmalı.")], cases: dataset)
        #expect(report.kept == report.quotes)
    }
}

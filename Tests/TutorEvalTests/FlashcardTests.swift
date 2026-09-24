import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Flashcard grading")
struct FlashcardTests {
    @Test("Translation leniency: case, a leading article or 'to', alternatives", arguments: [
        ("To work", true), ("the Sister", true), ("work, labour", true), ("labour or work", true),
        ("it snows", false), ("working", false),
    ])
    func translation(given: String, right: Bool) {
        #expect(FlashcardEval.translationMatches(given, ["work", "sister", "snow"]) == right)
    }

    let text = FlashcardText(id: "t", text: "El médico me dijo que debo dormir más.",
        words: [.init(lemma: "médico", forms: ["médico"], pos: "noun", translations: ["doctor"]),
                .init(lemma: "dormir", forms: ["dormir"], pos: "verb", translations: ["sleep"])])

    func report(_ cards: [Flashcard]) -> FlashcardReport {
        FlashcardReport(texts: [text], records: [FlashcardRecord(textID: "t", repetition: 0, schema: "s",
                                                                 cards: cards, error: nil, latencyMilliseconds: 0)])
    }

    @Test("A dropped accent is a misspelling, an unknown word is flagged, a known one graded")
    func terms() {
        let r = report([
            Flashcard(term: "medico", partOfSpeech: "noun", translation: "doctor", example: "El médico me dijo"),
            Flashcard(term: "cuidar", partOfSpeech: "verb", translation: "care", example: "x"),
            Flashcard(term: "dormir", partOfSpeech: "verb", translation: "to sleep", example: "debo dormir más"),
        ])
        #expect(r.misspelled == ["t: medico"] && r.ungrounded == ["t: cuidar"])
        #expect(r.grounded == 1 && r.translationRight == 1 && r.dictionaryForm == 1)
    }

    @Test("Examples: exact, re-capitalised piece, altered")
    func examples() {
        let r = report([
            Flashcard(term: "dormir", partOfSpeech: "verb", translation: "sleep", example: "El médico me dijo que debo dormir más."),
            Flashcard(term: "dormir", partOfSpeech: "verb", translation: "sleep", example: "Debo dormir más"),
            Flashcard(term: "dormir", partOfSpeech: "verb", translation: "sleep", example: "debo dormir mas"),
        ])
        #expect(r.exampleVerbatim == 1 && r.exampleFragment == 1 && r.exampleAltered.count == 1)
        #expect(r.duplicates == 2)
    }
}

import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Retrieval")
struct RetrievalTests {
    let notes = [
        GrammarNote(id: "gustar", title: "The verb gustar", text: "Gustar agrees with the thing that is liked: me gustan los perros."),
        GrammarNote(id: "preterite", title: "The preterite", text: "Use the preterite for finished actions: ayer comí pizza."),
    ]

    @Test("Shared rare words rank a note first")
    func keyword() {
        #expect(KeywordRetriever().retrieve("Why 'me gustan los perros'?", from: notes, k: 1).map(\.id) == ["gustar"])
    }

    @Test("Rank, hits and the overlap that gives a leaky question set away")
    func report() {
        let queries = [
            GrammarQuery(id: "a", query: "The preterite of comer?", relevant: ["preterite"], answerMustContain: []),
            GrammarQuery(id: "b", query: "What did I eat yesterday?", relevant: ["preterite"], answerMustContain: []),
        ]
        let r = RetrievalReport(retriever: KeywordRetriever(), notes: notes, queries: queries)
        #expect(r.hitAt1 >= 1 && r.queries == 2)
        #expect(r.meanOverlap > 0 && r.meanOverlap < 1)
    }

    @Test("A hedge counts as declining; a plain answer does not")
    func decline() {
        let q = [GrammarQuery(id: "a", query: "?", relevant: ["x"], answerMustContain: ["estar"])]
        let r = RagReport(queries: q, records: [
            RagRecord(queryID: "a", mode: "oracle", notesGiven: ["x"], answer: "The notes do not cover it. Use estar.", error: nil),
            RagRecord(queryID: "a", mode: "oracle", notesGiven: ["x"], answer: "Use estar for states.", error: nil),
        ])
        #expect(r.declined == 1 && r.right == 2)
    }
}

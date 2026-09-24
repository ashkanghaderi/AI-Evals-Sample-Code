import Testing
@testable import TutorEval

@Suite("Review comparison")
struct ReviewTests {
    let cases = [
        CorrectionCase(id: "a", input: "Yo es estudiante.", hasError: true,
                       accepted: ["Yo soy estudiante.", "Soy estudiante."], category: "c"),
        CorrectionCase(id: "b", input: "Hace calor.", hasError: false, accepted: ["Hace calor."], category: "c"),
    ]
    let labels = [ExplanationLabel(caseID: "a", explanation: "x.", label: "right", note: "")]

    @Test("Our own answers, returned as a review, agree completely")
    func selfReview() {
        let review = ReviewFile(reviewer: "us", native: false, packet: "review-v1",
            sentences: cases.map { .init(caseID: $0.id, hasError: $0.hasError,
                                          accepted: $0.hasError ? $0.accepted : [], note: nil) },
            explanations: [.init(caseID: "a", explanation: "x.", label: "right", note: nil)])
        let c = ReviewComparison(review: review, cases: cases, labels: labels)
        #expect(c.hasErrorAgree == 2 && c.labelAgree == 1)
        #expect(c.oursNotTheirs == 0 && c.theirsNotOurs == 0)
        #expect(c.disagreements.isEmpty)
    }

    @Test("A missing and an extra accepted answer are both reported")
    func answers() {
        let review = ReviewFile(reviewer: "r", native: true, packet: "review-v1",
            sentences: [.init(caseID: "a", hasError: true, accepted: ["Yo soy estudiante", "Soy un estudiante."], note: nil)],
            explanations: [])
        let c = ReviewComparison(review: review, cases: cases, labels: labels)
        #expect(c.oursNotTheirs == 1)
        #expect(c.theirsNotOurs == 1)
        #expect(c.disagreements.map(\.part) == ["accepted answers"])
    }

    @Test("Unanswered items are not counted as disagreement")
    func unanswered() {
        let review = ReviewFile(reviewer: "r", native: true, packet: "review-v1",
            sentences: [.init(caseID: "a", hasError: nil, accepted: [], note: nil)],
            explanations: [.init(caseID: "a", explanation: "x.", label: nil, note: nil)])
        let c = ReviewComparison(review: review, cases: cases, labels: labels)
        #expect(c.sentencesAnswered == 0 && c.explanationsAnswered == 0 && c.disagreements.isEmpty)
    }
}

@Suite("Review packet")
struct ReviewPacketTests {
    let cases = (1...12).map {
        CorrectionCase(id: "case-\($0)", input: "Frase \($0).", hasError: $0.isMultiple(of: 2),
                       accepted: ["Frase \($0)."], category: "c")
    }

    @Test("The page gives nothing away: no case id appears in it")
    func opaque() throws {
        let page = try ReviewPacket.html(cases: cases, explanations: cases.map {
            ($0.id, $0.input, $0.input, "Explicación \($0.id).".replacingOccurrences(of: "case-", with: "#"))
        })
        #expect(cases.allSatisfy { !page.contains("\"\($0.id)\"") })
        #expect(page.contains("\"s01\"") && page.contains("\"e01\""))
    }

    /// review-compare recomputes the explanations' order from case ids alone,
    /// so the shuffle must depend only on the count and the seed.
    @Test("An opaque explanation id maps back to the item it was shown with")
    func mapping() {
        let tuples = cases.map { ($0.id, $0.input, "x", "y") }
        let shown = ReviewPacket.explanationOrder(tuples)
        let recomputed = ReviewPacket.explanationOrder(cases.map(\.id))
        #expect(shown.map { $0.1.0 } == recomputed.map { $0.1 })
        #expect(shown.map(\.0) == recomputed.map(\.0))
    }

    @Test("Opaque sentence ids are compared as the cases they stand for")
    func compareOpaque() {
        let order = ReviewPacket.sentenceOrder(cases)
        let review = ReviewFile(reviewer: "r", native: nil, packet: ReviewPacket.version,
            sentences: order.map { .init(caseID: $0.0, hasError: $0.1.hasError, accepted: $0.1.hasError ? $0.1.accepted : [], note: nil) },
            explanations: [])
        let c = ReviewComparison(review: review, cases: cases, labels: [])
        #expect(c.sentencesAnswered == cases.count && c.hasErrorAgree == cases.count)
    }
}

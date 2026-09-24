import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Judge report")
struct JudgeReportTests {
    func record(_ id: String, _ explanation: String, right: Bool, mismatched: Bool = false)
        -> JudgeRecord {
        JudgeRecord(caseID: id, input: "Yo es estudiante.", corrected: "Yo soy estudiante.",
                    hasError: true, explanation: explanation, judge: "test", withReference: false,
                    mismatched: mismatched,
                    output: JudgeVerdict(reasoning: "", explanationIsRight: right),
                    error: nil, latencyMilliseconds: 0, prompt: "t")
    }
    func label(_ id: String, _ explanation: String, _ label: String) -> ExplanationLabel {
        ExplanationLabel(caseID: id, explanation: explanation, label: label, note: "")
    }

    /// Kappa is the point of reporting more than agreement: a judge that says
    /// "right" to everything agrees half the time on a half-wrong set, and
    /// scores zero.
    @Test("A judge that always says right has kappa zero")
    func alwaysRight() {
        let labels = [label("a", "x.", "right"), label("b", "y.", "wrong")]
        let report = JudgeReport(records: [record("a", "x.", right: true),
                                           record("b", "y.", right: true)], labels: labels)
        #expect(report.agree == 1)
        #expect(abs(report.kappa) < 1e-9)
    }

    @Test("A perfect judge has kappa one")
    func perfect() {
        let labels = [label("a", "x.", "right"), label("b", "y.", "wrong")]
        let report = JudgeReport(records: [record("a", "x.", right: true),
                                           record("b", "y.", right: false)], labels: labels)
        #expect(abs(report.kappa - 1) < 1e-9)
    }

    @Test("Arguable labels and relabelled text are left out")
    func leftOut() {
        let labels = [label("a", "x.", "arguable"), label("b", "old text.", "wrong")]
        let report = JudgeReport(records: [record("a", "x.", right: true),
                                           record("b", "new text.", right: true)], labels: labels)
        #expect(report.decided == 0)
    }

    @Test("A fragment the judge accepts is still rejected with the checks")
    func combined() {
        let labels = [label("a", "The sentence uses ", "wrong")]
        let report = JudgeReport(records: [record("a", "The sentence uses ", right: true)],
                                 labels: labels)
        #expect(report.wrongCaught == 0)
        #expect(report.combinedCaught == 1)
    }
}

@Suite("Judge baseline")
struct JudgeBaselineTests {
    @Test("Mismatched items carry another case's explanation")
    func mismatched() {
        let cases = ["a", "b", "c"].map {
            CorrectionCase(id: $0, input: "\($0).", hasError: true, accepted: ["\($0)!"], category: "c")
        }
        let records = cases.map {
            CorrectionRecord(caseID: $0.id, repetition: 0,
                             output: Correction(hasError: true, corrected: "\($0.id)!",
                                                explanation: "about \($0.id)"),
                             error: nil, latencyMilliseconds: 0, model: "m", sampling: "s")
        }
        let items = Judge.items(cases: cases, records: records, mismatched: true)
        #expect(items.map(\.1.explanation) == ["about b", "about c", "about a"])
        #expect(items.allSatisfy { $0.2 })
    }
}

@Suite("Bare judge")
struct BareReportTests {
    @Test("A failed call is counted as failed, not as either answer")
    func failedCall() {
        let cases = [CorrectionCase(id: "a", input: "Ellos son de Mexico.", hasError: true,
                                    accepted: ["Ellos son de México."], category: "orthography")]
        let records = [BareRecord(caseID: "a", input: "Ellos son de Mexico.", judge: "t",
                                  output: nil, error: "May contain unsafe content",
                                  latencyMilliseconds: 0, prompt: "t")]
        let report = BareReport(cases: cases, records: records)
        #expect(report.failed == 1)
        #expect(report.errorsFound == 0)
        #expect(report.rows.first?.saidCorrect == nil)
    }
}

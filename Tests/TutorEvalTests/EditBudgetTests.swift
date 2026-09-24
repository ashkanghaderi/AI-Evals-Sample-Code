import Testing
import EvalKit
@testable import TutorCore
@testable import TutorEval

@Suite("Edit budget")
struct EditBudgetTests {
    let preterite = CorrectionCase(id: "preterite", input: "Ayer yo como pizza.", hasError: true,
                                   accepted: ["Ayer yo comí pizza.", "Ayer comí pizza."],
                                   category: "verb-form")
    func record(_ corrected: String) -> CorrectionRecord {
        CorrectionRecord(caseID: "preterite", repetition: 0,
                         output: Correction(hasError: true, corrected: corrected, explanation: ""),
                         error: nil, latencyMilliseconds: 0, model: "m", sampling: "s")
    }

    /// The first version's false positive: accepted, but one edit further
    /// from the input than the closest accepted answer.
    @Test("An accepted answer is never over budget")
    func acceptedIsExempt() {
        let report = EditBudgetReport(cases: [preterite], records: [record("Ayer comí pizza.")], slack: 0)
        #expect(report.flags.isEmpty)
    }

    @Test("A rewrite is over budget")
    func rewrite() {
        let report = EditBudgetReport(cases: [preterite],
                                      records: [record("Dün pizza yedim.")], slack: 0)
        #expect(report.flags.count == 1)
    }

    @Test("A wrong answer that changed as little as needed is not a rewrite")
    func smallWrong() {
        let report = EditBudgetReport(cases: [preterite], records: [record("Ayer yo coma pizza.")], slack: 0)
        #expect(report.flags.isEmpty)
    }
}

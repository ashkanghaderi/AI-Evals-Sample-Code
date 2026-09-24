import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Drift")
struct DriftTests {
    func run(_ answers: [String], model: String = "m") -> [CorrectionRecord] {
        answers.enumerated().map { i, a in
            CorrectionRecord(caseID: "c\(i)", repetition: 0,
                             output: Correction(hasError: true, corrected: a, explanation: "e"),
                             error: nil, latencyMilliseconds: 0, model: model, sampling: "greedy")
        }
    }

    @Test("Identical answers are no change")
    func same() {
        let r = DriftReport(baseline: run(["a", "b"]), current: run(["a", "b"]))
        #expect(!r.drifted && r.sameAnswer == 2)
    }

    @Test("One changed answer is a change, and names the sentence")
    func changed() {
        let r = DriftReport(baseline: run(["a", "b"]), current: run(["a", "c"], model: "other"))
        #expect(r.drifted && r.changed == ["c1"] && r.current.model == "other")
    }
}

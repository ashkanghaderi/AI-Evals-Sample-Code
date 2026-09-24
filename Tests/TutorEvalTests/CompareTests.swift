import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Run comparison")
struct CompareTests {
    @Test("Exact sign test", arguments: [
        (0, 0, 1.0), (0, 1, 1.0), (1, 0, 1.0), (3, 3, 1.0),
        (0, 5, 0.0625), (0, 6, 0.03125), (1, 7, 0.0703125),
    ])
    func sign(better: Int, worse: Int, p: Double) {
        #expect(abs(RunComparison.signTest(better: better, worse: worse) - p) < 1e-12)
    }

    /// The case that made the sign test necessary: every changed sentence
    /// moved one way, so the bootstrap interval ends at zero and looks
    /// decisive. Three sentences cannot be.
    @Test("An interval that ends at zero is not evidence")
    func endsAtZero() {
        let cases = (1...20).map {
            CorrectionCase(id: "c\($0)", input: "x\($0).", hasError: true, accepted: ["y\($0)."], category: "k")
        }
        func run(_ right: (Int) -> Bool) -> [CorrectionRecord] {
            (1...20).map { i in
                CorrectionRecord(caseID: "c\(i)", repetition: 0,
                                 output: Correction(hasError: true, corrected: right(i) ? "y\(i)." : "z",
                                                    explanation: ""),
                                 error: nil, latencyMilliseconds: 0, model: "m", sampling: "s")
            }
        }
        let c = RunComparison(cases: cases, a: run { $0 <= 13 }, b: run { $0 <= 10 })
        let correction = c.metrics.first { $0.name == "correction" }!
        #expect(correction.high == 0)
        #expect(correction.worse == 3 && correction.better == 0)
        #expect(correction.signTestP == 0.25)
    }
}

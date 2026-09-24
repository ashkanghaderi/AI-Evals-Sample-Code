import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Performance")
struct PerformanceTests {
    func record(_ id: String, ms: Int, index: Int, out: Int?, answer: String? = "a", error: String? = nil) -> PerfRecord {
        PerfRecord(caseID: id, repetition: 0, index: index, configuration: "t", inputCharacters: 10,
                   latencyMilliseconds: ms, inputTokens: out == nil ? nil : 100, cachedTokens: 0,
                   outputTokens: out,
                   output: answer.map { Correction(hasError: true, corrected: $0, explanation: "") },
                   error: error)
    }

    @Test("Percentiles, the first call, and failures")
    func report() {
        let records = (0..<10).map { record("c\($0)", ms: ($0 + 1) * 100, index: $0, out: 10) }
            + [record("slow", ms: 200_000, index: 10, out: nil, answer: nil, error: "context")]
        let r = PerfReport(records)
        #expect(r.calls == 11 && r.failed == 1)
        #expect(r.medianMs == 600 && r.maxMs == 200_000 && r.firstCallMs == 100)
        #expect(r.p90Ms == 1000)
    }

    /// A configuration that only changes speed must not change answers, and
    /// the diff must notice when it does.
    @Test("A changed answer is a changed decision")
    func diff() {
        let a = [record("x", ms: 1, index: 0, out: 5, answer: "uno"), record("y", ms: 1, index: 1, out: 5, answer: "dos")]
        let b = [record("x", ms: 9, index: 0, out: 5, answer: "uno"), record("y", ms: 9, index: 1, out: 5, answer: "tres")]
        let d = PerfDiff(a, b)
        #expect(d.compared == 2 && d.sameDecision == 1 && d.changed == ["y"])
    }
}

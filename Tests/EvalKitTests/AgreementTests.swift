import Testing
@testable import EvalKit

@Suite("Agreement")
struct AgreementTests {
    typealias P = Agreement.Pair

    @Test("Kappa: perfect, chance-level, and undefined")
    func kappa() {
        #expect(Agreement.kappa([P(true, true), P(false, false)]) == 1)
        // Agrees half the time, as two coin-flippers would.
        let chance = [P(true, true), P(true, false), P(false, true), P(false, false)]
        #expect(abs(Agreement.kappa(chance)!) < 1e-12)
        #expect(Agreement.kappa([P(true, true), P(true, true)]) == nil)
    }

    @Test("A reference value: 20 of 26 agree")
    func reference() {
        // 10 both yes, 10 both no, 3 and 3 disagreeing: observed 20/26,
        // chance 0.5, kappa (20/26 - 0.5) / 0.5.
        let pairs = Array(repeating: P(true, true), count: 10) + Array(repeating: P(false, false), count: 10)
            + Array(repeating: P(true, false), count: 3) + Array(repeating: P(false, true), count: 3)
        #expect(abs(Agreement.kappa(pairs)! - (20.0 / 26 - 0.5) / 0.5) < 1e-12)
    }

    @Test("The interval is reproducible and narrows with more items")
    func interval() {
        let pairs = Array(repeating: P(true, true), count: 10) + Array(repeating: P(false, false), count: 10)
            + Array(repeating: P(true, false), count: 3) + Array(repeating: P(false, true), count: 3)
        #expect(Agreement.interval(pairs) == Agreement.interval(pairs))
        let small = Agreement.interval(pairs), large = Agreement.interval(pairs, items: 400)
        #expect(large.upperBound - large.lowerBound < small.upperBound - small.lowerBound)
    }

    /// Pairing is the point: the same judge compared with itself differs by
    /// exactly zero in every resample. Resampling the two independently would
    /// invent a spread that is not there.
    @Test("Two identical judges differ by exactly zero")
    func paired() {
        let reference = [true, true, false, false, true, false, true, false]
        let judge = [true, false, false, true, true, false, true, false]
        #expect(Agreement.differenceInterval(reference: reference, first: judge, second: judge) == 0...0)
    }
}

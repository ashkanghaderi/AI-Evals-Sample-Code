import Testing
import Foundation
@testable import EvalKit

@Suite("Proportion")
struct ProportionTests {

    /// Reference values for the Wilson interval, worked by hand and matching
    /// published tables. If the formula drifts, every number in the book does.
    @Test("Wilson interval matches reference values", arguments: [
        (8, 10, 0.4902, 0.9433),
        (0, 10, 0.0000, 0.2775),
        (10, 10, 0.7225, 1.0000),
        (24, 29, 0.6547, 0.9241),
    ])
    func wilson(successes: Int, trials: Int, low: Double, high: Double) {
        let ci = Proportion(successes: successes, trials: trials).interval()
        #expect(abs(ci.lowerBound - low) < 0.0005)
        #expect(abs(ci.upperBound - high) < 0.0005)
    }

    @Test("The interval never leaves 0...1, even where the naive formula does")
    func staysInRange() {
        for trials in [1, 2, 5, 29] {
            for successes in 0...trials {
                let ci = Proportion(successes: successes, trials: trials).interval()
                #expect(ci.lowerBound >= 0 && ci.upperBound <= 1)
            }
        }
    }

    @Test("No trials means no knowledge, not zero percent")
    func emptyIsUnknown() {
        #expect(Proportion(successes: 0, trials: 0).interval() == 0...1)
    }
}

@Suite("TextComparison")
struct TextComparisonTests {

    @Test("Whitespace and a trailing full stop do not count", arguments: [
        ("Yo soy estudiante.", "Yo soy estudiante"),
        ("Yo  soy   estudiante.", "Yo soy estudiante."),
        (" Yo soy estudiante. ", "Yo soy estudiante"),
    ])
    func forgiven(a: String, b: String) {
        #expect(TextComparison.matches(a, anyOf: [b]))
    }

    /// The things a Spanish learner actually gets wrong must never be
    /// normalised away, or the grader stops grading.
    @Test("Accents, case and inverted punctuation still count", arguments: [
        ("Ellos son de Mexico.", "Ellos son de México."),
        ("Que hora es?", "¿Qué hora es?"),
        ("yo soy estudiante.", "Yo soy estudiante."),
    ])
    func notForgiven(a: String, b: String) {
        #expect(!TextComparison.matches(a, anyOf: [b]))
    }

    @Test("Any accepted alternative is a match")
    func alternatives() {
        #expect(TextComparison.matches("Soy estudiante.",
                                       anyOf: ["Yo soy estudiante.", "Soy estudiante."]))
    }
}

@Suite("JSONLines")
struct JSONLinesTests {
    @Test("Records survive a round trip, one line each")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evalkit-\(UUID().uuidString).jsonl")
        for i in 0..<3 {
            try JSONLines.append(RunRecord<String>(
                caseID: "c\(i)", repetition: 0, output: "out \(i)", error: nil,
                latencyMilliseconds: 10, model: "test", sampling: "greedy"), to: url)
        }
        let back = try JSONLines.read(RunRecord<String>.self, from: url)
        #expect(back.map(\.caseID) == ["c0", "c1", "c2"])
        #expect(try String(contentsOf: url, encoding: .utf8)
                    .split(separator: "\n").count == 3)
    }
}

@Suite("ClusteredProportion")
struct ClusteredProportionTests {

    @Test("The rate is the pooled rate over all trials")
    func pooledRate() {
        let p = ClusteredProportion([.init(successes: 3, trials: 3),
                                     .init(successes: 0, trials: 3)])
        #expect(p.successes == 3 && p.trials == 6 && p.rate == 0.5)
    }

    @Test("The interval is reproducible: same seed, same interval")
    func reproducible() {
        let p = ClusteredProportion((0..<29).map { .init(successes: $0 % 4 == 0 ? 0 : 3, trials: 3) })
        #expect(p.interval() == p.interval())
    }

    /// The whole point: when repeats of the same case always agree, 87 calls
    /// carry the information of 29 cases, and the interval must be wider than
    /// one that pretends otherwise.
    @Test("Perfectly correlated repeats widen the interval")
    func correlationWidens() {
        let clusters = (0..<29).map { i in
            ClusteredProportion.Cluster(successes: i < 17 ? 3 : 0, trials: 3)
        }
        let clustered = ClusteredProportion(clusters).interval()
        let naive = Proportion(successes: 51, trials: 87).interval()
        #expect(clustered.upperBound - clustered.lowerBound
                > naive.upperBound - naive.lowerBound)
    }

    /// This test first asserted the opposite - that identical clusters leave
    /// "no uncertainty to resample" and the interval should be a single point.
    /// That was the bootstrap's boundary failure, written down as intended
    /// behaviour. Nine sentences that all scored 100% are strong evidence,
    /// not proof, and the interval has to say so. See Chapter 4.
    @Test("Identical clusters do not produce false certainty",
          arguments: [(3, 3), (2, 3), (0, 3)])
    func identicalClusters(successes: Int, trials: Int) {
        let p = ClusteredProportion(Array(repeating: .init(successes: successes, trials: trials),
                                          count: 9))
        let ci = p.interval()
        #expect(ci.upperBound - ci.lowerBound > 0.2)
    }

    @Test("A perfect score over nine sentences is not proven perfect")
    func perfectIsNotProof() {
        let ci = ClusteredProportion(Array(repeating: .init(successes: 3, trials: 3),
                                           count: 9)).interval()
        #expect(ci.upperBound == 1)
        #expect(ci.lowerBound < 0.75)
    }
}

@Suite("SampleSize")
struct SampleSizeTests {
    @Test("Tighter intervals need more cases")
    func monotone() throws {
        let wide = try #require(SampleSize.needed(expectedRate: 0.6, halfWidth: 0.10))
        let narrow = try #require(SampleSize.needed(expectedRate: 0.6, halfWidth: 0.05))
        #expect(narrow > wide * 3)
    }

    @Test("The answer really does meet the target, and one fewer does not")
    func minimal() throws {
        let n = try #require(SampleSize.needed(expectedRate: 0.6, halfWidth: 0.10))
        func half(_ n: Int) -> Double {
            let ci = Proportion(successes: Int((0.6 * Double(n)).rounded()), trials: n).interval()
            return (ci.upperBound - ci.lowerBound) / 2
        }
        #expect(half(n) <= 0.10)
        #expect(half(n - 1) > 0.10)
    }
}

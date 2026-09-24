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

import Foundation
import EvalKit

/// Correction graded by similarity instead of exact match, at several
/// thresholds - for the model's answers and for a model that does nothing.
///
/// The do-nothing baseline returns every sentence unchanged. It corrects
/// nothing, so any grader that gives it credit is measuring something other
/// than correction. Every threshold grader should be run against it first.
struct FuzzyReport: Codable {
    struct Row: Codable {
        let threshold: Double
        let model: Int
        let doNothing: Int
    }
    struct Near: Codable {
        let caseID: String
        let output: String
        let toAnswer: Double
        let toInput: Double
    }

    var total = 0
    /// Error cases only: on correct sentences, doing nothing is right.
    var exact = 0
    var rows: [Row] = []
    /// "Closer to an accepted answer than to the input": the relative rule.
    var relative = 0
    var relativeDoNothing = 0
    var misses: [Near] = []
    /// The most similar pair of wrong input and accepted answer in the key.
    /// Any threshold at or below it gives the do-nothing baseline credit for
    /// that case: it is the floor the key itself sets.
    var closestPair = 0.0
    var closestCase = ""

    static let thresholds = [1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7]

    init(cases: [CorrectionCase], records: [CorrectionRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        var model = Array(repeating: 0, count: Self.thresholds.count)
        var nothing = model
        for record in records {
            guard let item = byID[record.caseID], item.hasError else { continue }
            total += 1
            let output = record.output?.corrected ?? ""
            let best = item.accepted.map { Similarity.ratio(output, $0) }.max() ?? 0
            let baseline = item.accepted.map { Similarity.ratio(item.input, $0) }.max() ?? 0
            let toInput = Similarity.ratio(output, item.input)
            if baseline > closestPair { closestPair = baseline; closestCase = item.id }
            if TextComparison.matches(output, anyOf: item.accepted) {
                exact += 1
            } else if record.output != nil {
                misses.append(Near(caseID: item.id, output: output, toAnswer: best, toInput: toInput))
            }
            for (i, t) in Self.thresholds.enumerated() {
                if record.output != nil && best >= t - 1e-9 { model[i] += 1 }
                if baseline >= t - 1e-9 { nothing[i] += 1 }
            }
            if record.output != nil && best > toInput { relative += 1 }
            // The baseline's output is the input, so it is never closer to
            // an answer than to itself.
            if baseline > 1 { relativeDoNothing += 1 }
        }
        rows = Self.thresholds.enumerated().map {
            Row(threshold: $0.element, model: model[$0.offset], doNothing: nothing[$0.offset])
        }
    }

    func print() {
        Swift.print("\nCorrection on \(total) error calls, graded by similarity\n")
        Swift.print("threshold   model   do-nothing")
        for row in rows {
            Swift.print(String(format: "  %.2f     %4d     %4d", row.threshold, row.model, row.doNothing))
        }
        Swift.print("exact match: \(exact)   closer to an answer than to the input: \(relative)"
                    + " (do-nothing \(relativeDoNothing))")
        Swift.print(String(format: "closest wrong/right pair in the key: %.3f (%@)",
                           closestPair, closestCase))
        var seen = Set<String>()
        for near in misses where seen.insert("\(near.caseID)|\(near.output)").inserted {
            Swift.print(String(format: "  [%@] %@  answer %.2f, input %.2f",
                               near.caseID, near.output, near.toAnswer, near.toInput))
        }
    }
}

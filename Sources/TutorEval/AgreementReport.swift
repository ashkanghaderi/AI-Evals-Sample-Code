import Foundation
import EvalKit

/// How much the labels can say about a judge - Chapter 11.
///
/// The judge's kappa against the labels, with its interval; how that interval
/// would narrow with more labels; and, given a second judge graded on the same
/// explanations, whether the two differ, and how often they agree with each
/// other.
struct AgreementReport: Codable {
    struct Projection: Codable {
        let labels: Int
        let low: Double
        let high: Double
    }

    var items = 0
    var kappa = 0.0
    var low = 0.0
    var high = 0.0
    var projections: [Projection] = []
    // With a second judge:
    var secondKappa: Double?
    var differenceLow: Double?
    var differenceHigh: Double?
    /// The two judges against each other, no labels involved.
    var betweenJudges: Double?
    var betweenJudgesAgree: Int?
    /// The difference's interval if there were this many labels, drawn like
    /// these - how many it would take to tell the two judges apart.
    var differenceProjections: [Projection] = []

    static let sizes = [26, 50, 100, 200, 400]

    /// Label (true = right) and verdict per labelled, non-arguable explanation,
    /// keyed by case.
    static func decided(_ records: [JudgeRecord], labels: [ExplanationLabel]) -> [String: (Bool, Bool)] {
        let labelFor = Dictionary(labels.map { ("\($0.caseID)|\($0.explanation)", $0.label) },
                                  uniquingKeysWith: { a, _ in a })
        var out: [String: (Bool, Bool)] = [:]
        for record in records where !record.mismatched {
            guard let verdict = record.output,
                  let label = labelFor["\(record.caseID)|\(record.explanation)"],
                  label != "arguable" else { continue }
            out[record.caseID] = (label == "right", verdict.explanationIsRight)
        }
        return out
    }

    init(first: [JudgeRecord], second: [JudgeRecord]?, labels: [ExplanationLabel]) {
        let a = Self.decided(first, labels: labels)
        let pairs = a.keys.sorted().map { Agreement.Pair(a[$0]!.0, a[$0]!.1) }
        items = pairs.count
        kappa = Agreement.kappa(pairs) ?? 0
        let ci = Agreement.interval(pairs)
        low = ci.lowerBound; high = ci.upperBound
        projections = Self.sizes.map { n in
            let p = Agreement.interval(pairs, items: n)
            return Projection(labels: n, low: p.lowerBound, high: p.upperBound)
        }
        guard let second else { return }
        let b = Self.decided(second, labels: labels)
        let shared = a.keys.filter { b[$0] != nil }.sorted()
        let reference = shared.map { a[$0]!.0 }
        let one = shared.map { a[$0]!.1 }, two = shared.map { b[$0]!.1 }
        secondKappa = Agreement.kappa(zip(reference, two).map { Agreement.Pair($0, $1) })
        let d = Agreement.differenceInterval(reference: reference, first: one, second: two)
        differenceLow = d.lowerBound; differenceHigh = d.upperBound
        differenceProjections = Self.sizes.map { n in
            let p = Agreement.differenceInterval(reference: reference, first: one, second: two, items: n)
            return Projection(labels: n, low: p.lowerBound, high: p.upperBound)
        }
        let between = zip(one, two).map { Agreement.Pair($0, $1) }
        betweenJudges = Agreement.kappa(between)
        betweenJudgesAgree = between.filter { $0.first == $0.second }.count
    }

    func print() {
        Swift.print(String(format: "\n%d labelled explanations: kappa %.2f, 95%% interval %.2f to %.2f",
                           items, kappa, low, high))
        Swift.print("with more labels drawn like these:")
        for p in projections {
            Swift.print(String(format: "  %4d labels: %.2f to %.2f", p.labels, p.low, p.high))
        }
        if let secondKappa, let differenceLow, let differenceHigh {
            Swift.print(String(format: "second judge: kappa %.2f; difference (second - first) %.2f to %.2f",
                               secondKappa, differenceLow, differenceHigh))
            for p in differenceProjections {
                Swift.print(String(format: "  %4d labels: difference %.2f to %.2f", p.labels, p.low, p.high))
            }
        }
        if let betweenJudges, let betweenJudgesAgree {
            Swift.print(String(format: "judges with each other: %d of %d agree, kappa %.2f",
                               betweenJudgesAgree, items, betweenJudges))
        }
    }
}

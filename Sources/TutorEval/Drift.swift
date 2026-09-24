import Foundation
import EvalKit

/// The canary - Chapter 14.
///
/// Greedy decoding gives byte-identical answers for as long as nothing
/// changes: not the model, not the OS, not the prompt. So a greedy run of the
/// golden set, compared answer by answer with a recorded one, is a change
/// detector that needs no grading at all. It says *that* something changed;
/// the eval says whether it matters.
struct DriftReport: Codable {
    struct Side: Codable {
        let model: String
        let sampling: String
        let prompt: String
        let osVersion: String
    }
    let baseline: Side
    let current: Side
    var compared = 0
    var sameDecision = 0
    var sameAnswer = 0
    var changed: [String] = []

    init(baseline a: [CorrectionRecord], current b: [CorrectionRecord]) {
        func side(_ r: CorrectionRecord?) -> Side {
            Side(model: r?.model ?? "?", sampling: r?.sampling ?? "?",
                 prompt: r?.prompt ?? "v1 (not recorded)", osVersion: r?.osVersion ?? "?")
        }
        let first = a.filter { $0.repetition == 0 }, second = b.filter { $0.repetition == 0 }
        baseline = side(first.first); current = side(second.first)
        let byID = Dictionary(first.map { ($0.caseID, $0) }, uniquingKeysWith: { x, _ in x })
        for r in second {
            guard let old = byID[r.caseID] else { continue }
            compared += 1
            let decision = { (x: CorrectionRecord) in x.output.map { "\($0.hasError)|\($0.corrected)" } ?? "failed" }
            if decision(old) == decision(r) { sameDecision += 1 } else { changed.append(r.caseID) }
            if old.output == r.output && (old.error == nil) == (r.error == nil) { sameAnswer += 1 }
        }
    }

    var drifted: Bool { sameAnswer < compared }

    func print() {
        Swift.print("baseline: \(baseline.model), \(baseline.sampling), \(baseline.prompt), \(baseline.osVersion)")
        Swift.print("current:  \(current.model), \(current.sampling), \(current.prompt), \(current.osVersion)")
        Swift.print("\(sameAnswer) of \(compared) answers identical, \(sameDecision) decisions identical"
                    + (drifted ? " - CHANGED: \(changed.joined(separator: ", "))" : " - no change"))
    }
}

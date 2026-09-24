import Foundation
import EvalKit

/// "Changing as little as possible", as a threshold that comes from the key.
///
/// Each case's budget is the fewest word edits any accepted answer needs,
/// plus `slack`. An answer that spends more has rewritten the learner's
/// sentence rather than corrected it. The threshold is per case, derived from
/// answers a person wrote - not one number chosen for every sentence.
///
/// It never fails an answer the exact grader passes. What it adds is a kind:
/// among wrong answers, which ones rewrote the sentence instead of fixing it.
struct EditBudgetReport: Codable {
    struct Flag: Codable {
        let caseID: String
        let input: String
        let output: String
        let needed: Int
        let spent: Int
    }

    let slack: Int
    var answers = 0
    var flags: [Flag] = []

    static func words(_ text: String) -> [Substring] {
        TextComparison.normalized(text).split(separator: " ")
    }

    static func distance(_ a: [Substring], _ b: [Substring]) -> Int {
        var previous = Array(0...b.count)
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1,
                                     previous[j] + (a[i] == b[j] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    init(cases: [CorrectionCase], records: [CorrectionRecord], slack: Int) {
        self.slack = slack
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for record in records {
            guard let item = byID[record.caseID], let output = record.output else { continue }
            answers += 1
            // An answer the key accepts is within budget by definition. The
            // first version compared every answer with the *closest* accepted
            // answer, and flagged "Ayer comí pizza." - which the key accepts,
            // one edit further from the input than "Ayer yo comí pizza.".
            if TextComparison.matches(output.corrected, anyOf: item.accepted) { continue }
            let input = Self.words(item.input)
            let needed = item.accepted.map { Self.distance(input, Self.words($0)) }.min() ?? 0
            let spent = Self.distance(input, Self.words(output.corrected))
            if spent > needed + slack {
                flags.append(Flag(caseID: item.id, input: item.input, output: output.corrected,
                                  needed: needed, spent: spent))
            }
        }
    }

    func print() {
        Swift.print("\(flags.count) of \(answers) answers over budget (needed + \(slack) word edits)")
        for flag in flags {
            Swift.print("  [\(flag.caseID)] needed \(flag.needed), spent \(flag.spent): "
                        + "\(flag.input) => \(flag.output)")
        }
    }
}

import Foundation
import EvalKit

/// Deterministic checks on a dataset, before it is allowed to grade anything.
///
/// None of these needs a model or a Spanish speaker. Each one catches a way a
/// dataset can be wrong that no score computed from it will ever reveal: a
/// case whose "error" is identical to its own answer grades a model that does
/// nothing as a model that fixed it.
struct DatasetAudit: Codable {
    struct Problem: Codable {
        let id: String
        let check: String
        let detail: String
    }

    var cases = 0
    var uniqueInputs = 0
    var problems: [Problem] = []
    var categories: [String: Int] = [:]
    /// Inputs that also appear in the dataset passed as `against`. Reported,
    /// not failed: a dataset derived from another overlaps it by design. It
    /// matters the moment anyone pools the two, because those sentences then
    /// count twice.
    var overlap: [String] = []

    init(_ items: [CorrectionCase], against other: [CorrectionCase] = []) {
        cases = items.count
        var seen: [String: String] = [:]
        let otherInputs = Set(other.map { TextComparison.normalized($0.input) })

        for item in items {
            let input = TextComparison.normalized(item.input)
            categories[item.category.lowercased(), default: 0] += 1

            if item.accepted.isEmpty {
                problems.append(Problem(id: item.id, check: "no-answer",
                                        detail: "no accepted answer"))
            }
            // An error case whose answer is its own input contains no error by
            // the dataset's own account.
            if item.hasError && TextComparison.matches(item.input, anyOf: item.accepted) {
                problems.append(Problem(id: item.id, check: "answer-is-input",
                                        detail: "marked as an error, but accepts itself unchanged"))
            }
            if !item.hasError && !TextComparison.matches(item.input, anyOf: item.accepted) {
                problems.append(Problem(id: item.id, check: "control-changed",
                                        detail: "marked correct, but does not accept itself"))
            }
            if let first = seen[input] {
                problems.append(Problem(id: item.id, check: "duplicate",
                                        detail: "same input as \(first)"))
            } else {
                seen[input] = item.id
            }
            if otherInputs.contains(input) { overlap.append(item.id) }
        }
        uniqueInputs = seen.count
    }

    func count(_ check: String) -> Int { problems.filter { $0.check == check }.count }

    func print() {
        Swift.print("\n\(cases) cases, \(uniqueInputs) distinct inputs")
        let sorted = categories.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
        Swift.print("categories: " + sorted.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        if !overlap.isEmpty {
            Swift.print("overlap: \(overlap.count) inputs also in the other dataset (\(overlap.joined(separator: ", ")))")
        }
        if problems.isEmpty {
            Swift.print("no problems found")
            return
        }
        Swift.print("\(problems.count) problems:")
        for check in ["no-answer", "answer-is-input", "control-changed", "duplicate"] {
            let n = count(check)
            if n > 0 { Swift.print("  \(check.padding(toLength: 16, withPad: " ", startingAt: 0)) \(n)") }
        }
        for problem in problems.prefix(40) {
            Swift.print("  [\(problem.id)] \(problem.check): \(problem.detail)")
        }
    }
}

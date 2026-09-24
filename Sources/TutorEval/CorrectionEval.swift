import Foundation
import EvalKit
import TutorCore

/// One sentence in the golden set.
struct CorrectionCase: Codable, Sendable {
    let id: String
    let input: String
    let hasError: Bool
    /// Every correction a teacher would accept. Exact match against a single
    /// answer punishes a model for writing "Soy estudiante." instead of
    /// "Yo soy estudiante." - both right, only one listed.
    let accepted: [String]
    let category: String
}

typealias CorrectionRecord = RunRecord<Correction>

/// The deterministic graders for "Correct my sentence".
///
/// Three questions, asked separately because they fail separately:
///   detection    - did it notice whether there was an error at all?
///   correction   - on sentences with an error, is the fix an accepted one?
///   preservation - on correct sentences, did it leave them alone?
///
/// The explanation is recorded but not graded here. Grading free text needs a
/// judge, and a judge needs calibrating first - Chapter 10.
struct CorrectionReport {
    var detection = (hit: 0, total: 0)
    var correction = (hit: 0, total: 0)
    var preservation = (hit: 0, total: 0)
    var consistency = (hit: 0, total: 0)
    var failedCalls = 0
    var failures: [(CorrectionCase, CorrectionRecord, String)] = []
    var latencies: [Int] = []

    init(cases: [CorrectionCase], records: [CorrectionRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })

        for record in records {
            guard let item = byID[record.caseID] else { continue }
            latencies.append(record.latencyMilliseconds)

            guard let output = record.output else {
                // A call that threw is a failure, not a missing row. Dropping
                // errors from the denominator is the most common way an eval
                // reports a better number than the feature deserves.
                failedCalls += 1
                detection.total += 1
                if item.hasError { correction.total += 1 } else { preservation.total += 1 }
                failures.append((item, record, "call failed: \(record.error ?? "?")"))
                continue
            }

            detection.total += 1
            if output.hasError == item.hasError { detection.hit += 1 }

            let fixed = TextComparison.matches(output.corrected, anyOf: item.accepted)
            if item.hasError {
                correction.total += 1
                if fixed { correction.hit += 1 } else {
                    failures.append((item, record, "wrong correction"))
                }
            } else {
                preservation.total += 1
                if fixed && !output.hasError { preservation.hit += 1 } else {
                    failures.append((item, record, "changed a correct sentence"))
                }
            }
        }

        // Consistency: across repetitions, did the same input get the same
        // answer? A feature that corrects a sentence one way on Monday and
        // another way on Tuesday is a feature users stop trusting.
        let grouped = Dictionary(grouping: records, by: \.caseID)
        for (_, runs) in grouped where runs.count > 1 {
            consistency.total += 1
            let answers = Set(runs.map { run in
                run.output.map { "\($0.hasError)|\(TextComparison.normalized($0.corrected))" }
                    ?? "error"
            })
            if answers.count == 1 { consistency.hit += 1 }
        }
    }

    func print(model: String, sampling: String) {
        func line(_ name: String, _ p: (hit: Int, total: Int)) {
            Swift.print("  \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) "
                        + Proportion(successes: p.hit, trials: p.total).description)
        }
        let sorted = latencies.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p90 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 9 / 10)]

        Swift.print("\nCorrect my sentence — \(model), sampling: \(sampling)\n")
        line("detection", detection)
        line("correction", correction)
        line("preservation", preservation)
        if consistency.total > 0 { line("consistency", consistency) }
        Swift.print("  failed calls   \(failedCalls)")
        Swift.print("  latency        median \(median) ms, p90 \(p90) ms")
        Swift.print("  explanations   recorded, not graded (needs a calibrated judge)")

        if !failures.isEmpty {
            // The most useful part of any eval report: the actual failures,
            // in full. A score says how often; only the examples say why.
            Swift.print("\nFailures (\(failures.count)):")
            for (item, record, reason) in failures.prefix(25) {
                Swift.print("  [\(item.id) #\(record.repetition)] \(reason)")
                Swift.print("      input:    \(item.input)")
                if item.hasError { Swift.print("      expected: \(item.accepted.joined(separator: "  |  "))") }
                if let output = record.output {
                    Swift.print("      got:      \(output.corrected)  (hasError: \(output.hasError))")
                    if !output.explanation.isEmpty {
                        Swift.print("      said:     \(output.explanation)")
                    }
                }
            }
        }
    }
}

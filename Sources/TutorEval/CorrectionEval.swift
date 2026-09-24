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
    var coherence = (hit: 0, total: 0)
    /// Explanations in the language the run asked for, among non-empty ones.
    var language = (hit: 0, total: 0)
    var failedCalls = 0
    var verdicts: [Verdict] = []
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
                verdicts.append(Verdict(item, record, verdict: "error"))
                detection.total += 1
                if item.hasError { correction.total += 1 } else { preservation.total += 1 }
                failures.append((item, record, "call failed: \(record.error ?? "?")"))
                continue
            }

            detection.total += 1
            if output.hasError == item.hasError { detection.hit += 1 }

            // Coherence needs no dataset at all: an answer that claims "no
            // error" while changing the sentence, or "error" while returning it
            // unchanged, contradicts itself. Free to check, and a model that
            // cannot keep its own two fields consistent has told you something.
            let changed = TextComparison.normalized(output.corrected)
                != TextComparison.normalized(item.input)
            coherence.total += 1
            if output.hasError == changed { coherence.hit += 1 }

            let fixed = TextComparison.matches(output.corrected, anyOf: item.accepted)
            let passed = item.hasError ? fixed : (fixed && !output.hasError)
            verdicts.append(Verdict(item, record, verdict: passed ? "pass" : "fail",
                                    coherent: output.hasError == changed))
            if let detected = verdicts.last?.explanationLanguage {
                language.total += 1
                if detected == ExplanationLanguage.expected(from: record.prompt) { language.hit += 1 }
            }
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
        let sentenceLevel = clusteredMetrics
        func line(_ name: String, _ p: (hit: Int, total: Int)) {
            Swift.print("  \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) "
                        + Proportion(successes: p.hit, trials: p.total).description)
            if let c = sentenceLevel[name], c.clusters.count < p.total {
                let ci = c.interval()
                Swift.print(String(format: "                 by sentence: %.1f–%.1f%% (%d sentences)",
                                   ci.lowerBound * 100, ci.upperBound * 100, c.clusters.count))
            }
        }
        let sorted = latencies.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p90 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 9 / 10)]

        Swift.print("\nCorrect my sentence — \(model), sampling: \(sampling)\n")
        line("detection", detection)
        line("correction", correction)
        line("preservation", preservation)
        if consistency.total > 0 { line("consistency", consistency) }
        line("coherence", coherence)
        line("language", language)
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


/// One graded call, in full - what the book quotes from.
///
/// Chapters print specimens from this rather than from the raw recording, so a
/// sentence the book calls a failure is one the grader called a failure.
struct Verdict: Codable {
    let caseID: String
    let repetition: Int
    let category: String
    let verdict: String
    let input: String
    let expectedHasError: Bool
    let accepted: [String]
    let hasError: Bool?
    let corrected: String?
    let explanation: String?
    let coherent: Bool?
    let error: String?
    let latencyMilliseconds: Int
    /// The prompt version the call was made with; nil means v1.
    let prompt: String?
    /// The explanation's language as detected, nil when there is none.
    let explanationLanguage: String?

    init(_ item: CorrectionCase, _ record: CorrectionRecord, verdict: String,
         coherent: Bool? = nil) {
        caseID = item.id; repetition = record.repetition; category = item.category
        self.verdict = verdict; input = item.input
        expectedHasError = item.hasError; accepted = item.accepted
        hasError = record.output?.hasError; corrected = record.output?.corrected
        explanation = record.output?.explanation; self.coherent = coherent
        error = record.error; latencyMilliseconds = record.latencyMilliseconds
        prompt = record.prompt
        explanationLanguage = record.output.flatMap { ExplanationLanguage.detect($0.explanation) }
    }
}

extension CorrectionReport {
    struct Metric: Codable {
        let hit: Int, total: Int, rate: Double, low: Double, high: Double
        /// The same rate's interval with calls grouped by sentence - the
        /// honest one when each sentence was asked more than once.
        let sentences: Int?, sentenceLow: Double?, sentenceHigh: Double?
        init(_ p: (hit: Int, total: Int), clustered: ClusteredProportion? = nil) {
            let proportion = Proportion(successes: p.hit, trials: p.total)
            let ci = proportion.interval()
            hit = p.hit; total = p.total; rate = proportion.rate
            low = ci.lowerBound; high = ci.upperBound
            let sentenceCI = clustered?.interval()
            sentences = clustered?.clusters.count
            sentenceLow = sentenceCI?.lowerBound; sentenceHigh = sentenceCI?.upperBound
        }
    }

    struct Summary: Codable {
        let model: String, sampling: String, records: Int, failedCalls: Int
        let latencyMedian: Int, latencyP90: Int
        let metrics: [String: Metric]
        let verdicts: [Verdict]
    }

    func json(model: String, sampling: String) throws -> String {
        let sorted = latencies.sorted()
        let summary = Summary(
            model: model, sampling: sampling, records: latencies.count,
            failedCalls: failedCalls,
            latencyMedian: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            latencyP90: sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 9 / 10)],
            metrics: {
                let c = clusteredMetrics
                return ["detection": Metric(detection, clustered: c["detection"]),
                        "correction": Metric(correction, clustered: c["correction"]),
                        "preservation": Metric(preservation, clustered: c["preservation"]),
                        "consistency": Metric(consistency),
                        "coherence": Metric(coherence, clustered: c["coherence"]),
                        "language": Metric(language)]
            }(),
            verdicts: verdicts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(summary), as: UTF8.self)
    }
}


// MARK: - Sentence-level intervals

extension CorrectionReport {
    /// A metric's intervals when its calls are grouped by sentence.
    ///
    /// `select` returns nil for calls the metric does not cover, and otherwise
    /// whether the call counts as a hit. Built from the verdicts, so it counts
    /// exactly what the call-level metric counts - only the uncertainty differs.
    func clustered(_ select: (Verdict) -> Bool?) -> ClusteredProportion {
        var byCase: [String: (hit: Int, total: Int)] = [:]
        var order: [String] = []
        for verdict in verdicts {
            guard let hit = select(verdict) else { continue }
            if byCase[verdict.caseID] == nil { order.append(verdict.caseID) }
            byCase[verdict.caseID, default: (0, 0)].total += 1
            if hit { byCase[verdict.caseID, default: (0, 0)].hit += 1 }
        }
        return ClusteredProportion(order.map {
            .init(successes: byCase[$0]!.hit, trials: byCase[$0]!.total)
        })
    }

    var clusteredMetrics: [String: ClusteredProportion] {
        [
            "detection": clustered { v in v.hasError.map { $0 == v.expectedHasError } ?? false },
            "correction": clustered { $0.expectedHasError ? $0.verdict == "pass" : nil },
            "preservation": clustered { $0.expectedHasError ? nil : $0.verdict == "pass" },
            "coherence": clustered { $0.coherent },
        ]
    }
}

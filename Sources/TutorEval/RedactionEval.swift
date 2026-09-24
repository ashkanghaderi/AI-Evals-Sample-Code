import Foundation
import EvalKit
import TutorCore

/// One sentence, and what redaction must and must not remove from it.
struct RedactionCase: Codable {
    let id: String
    let text: String
    let mustRemove: [String]
    let mustKeep: [String]
}

/// The redactor's own eval.
///
/// Two failures, with very different costs. A leak - personal data surviving
/// into the log - is a privacy failure and the one that matters. An
/// over-redaction - an ordinary word replaced by [NAME] - makes the logged
/// sentence useless as an eval case, which is a quality failure. Both are
/// reported; only one of them can hurt a learner.
struct RedactionReport: Codable {
    struct Result: Codable {
        let id: String
        let text: String
        let redacted: String
        let leaked: [String]
        let lost: [String]
    }
    struct Rate: Codable { let hit: Int, total: Int, rate: Double, low: Double, high: Double }

    let strategy: String
    let results: [Result]
    let leaks: Rate
    let keeps: Rate
    let clean: Rate

    init(cases: [RedactionCase], redactor: Redactor) {
        strategy = redactor.strategy.rawValue
        results = cases.map { item in
            let redacted = redactor.redact(item.text)
            return Result(id: item.id, text: item.text, redacted: redacted,
                          leaked: item.mustRemove.filter { redacted.contains($0) },
                          lost: item.mustKeep.filter { !redacted.contains($0) })
        }
        // Items within one sentence share a context, so intervals are by sentence.
        func rate(_ clusters: [ClusteredProportion.Cluster]) -> Rate {
            let c = ClusteredProportion(clusters.filter { $0.trials > 0 })
            let ci = c.interval()
            return Rate(hit: c.successes, total: c.trials, rate: c.rate,
                        low: ci.lowerBound, high: ci.upperBound)
        }
        leaks = rate(zip(cases, results).compactMap { item, result in
            item.mustRemove.isEmpty ? nil
                : .init(successes: result.leaked.count, trials: item.mustRemove.count)
        })
        keeps = rate(zip(cases, results).compactMap { item, result in
            item.mustKeep.isEmpty ? nil
                : .init(successes: item.mustKeep.count - result.lost.count, trials: item.mustKeep.count)
        })
        clean = rate(results.map {
            .init(successes: $0.leaked.isEmpty && $0.lost.isEmpty ? 1 : 0, trials: 1)
        })
    }

    func print() {
        func line(_ name: String, _ r: Rate) {
            Swift.print(String(format: "  %@ %5.1f%%  (by sentence: %.1f–%.1f%%, %d/%d)",
                               name.padding(toLength: 14, withPad: " ", startingAt: 0),
                               r.rate * 100, r.low * 100, r.high * 100, r.hit, r.total))
        }
        Swift.print("\nRedaction — strategy: \(strategy)\n")
        line("leaked", leaks)
        line("words kept", keeps)
        line("clean sentences", clean)
        let failures = results.filter { !$0.leaked.isEmpty || !$0.lost.isEmpty }
        if !failures.isEmpty {
            Swift.print("\nFailures (\(failures.count)):")
            for f in failures {
                Swift.print("  [\(f.id)] \(f.text)")
                Swift.print("      became: \(f.redacted)")
                if !f.leaked.isEmpty { Swift.print("      LEAKED: \(f.leaked.joined(separator: ", "))") }
                if !f.lost.isEmpty { Swift.print("      lost:   \(f.lost.joined(separator: ", "))") }
            }
        }
    }
}

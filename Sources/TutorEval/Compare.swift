import Foundation
import EvalKit

/// Is the difference between two runs real? Chapter 12.
///
/// Both runs are graded against the same key, then compared sentence by
/// sentence: each sentence's rate in A (averaged over its repetitions) against
/// its rate in B. The interval for the difference comes from resampling
/// *sentences* together, because the sentences are what a different dataset
/// would change, and pairing them removes everything the two runs share.
struct RunComparison: Codable {
    struct Metric: Codable {
        let name: String
        let sentences: Int
        let rateA: Double
        let rateB: Double
        let difference: Double
        let low: Double
        let high: Double
        /// Sentences where B did better, worse, or the same as A.
        let better: Int
        let worse: Int
        let same: Int
        /// Exact two-sided sign test on the sentences that changed. With one
        /// changed sentence it is 1.0: nothing can be concluded, however the
        /// bootstrap interval looks.
        let signTestP: Double
    }

    /// Two-sided exact binomial test of `k` successes in `n` at p = 0.5.
    static func signTest(better: Int, worse: Int) -> Double {
        let n = better + worse
        guard n > 0 else { return 1 }
        let k = min(better, worse)
        var tail = 0.0
        for i in 0...k { tail += binomial(n, i) }
        return min(1, 2 * tail / pow(2, Double(n)))
    }

    static func binomial(_ n: Int, _ k: Int) -> Double {
        var r = 1.0
        for i in 0..<k { r = r * Double(n - i) / Double(i + 1) }
        return r
    }
    struct Category: Codable {
        let category: String
        let hitA: Int
        let totalA: Int
        let hitB: Int
        let totalB: Int
    }

    var metrics: [Metric] = []
    var categories: [Category] = []
    /// The widest per-category gap, in points: what a reader skimming the
    /// category table would notice first.
    var largestCategoryGap = 0.0
    var largestCategory = ""

    init(cases: [CorrectionCase], a: [CorrectionRecord], b: [CorrectionRecord]) {
        let va = CorrectionReport(cases: cases, records: a).verdicts
        let vb = CorrectionReport(cases: cases, records: b).verdicts
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })

        func perCase(_ verdicts: [Verdict], _ hit: (Verdict) -> Bool?) -> [String: Double] {
            var sums: [String: (Double, Double)] = [:]
            for v in verdicts {
                guard let h = hit(v) else { continue }
                sums[v.caseID, default: (0, 0)].0 += h ? 1 : 0
                sums[v.caseID, default: (0, 0)].1 += 1
            }
            return sums.mapValues { $0.0 / $0.1 }
        }
        let definitions: [(String, (Verdict) -> Bool?)] = [
            ("correction", { $0.expectedHasError ? $0.verdict == "pass" : nil }),
            ("detection", { v in v.hasError.map { $0 == v.expectedHasError } ?? false }),
            ("preservation", { $0.expectedHasError ? nil : $0.verdict == "pass" }),
        ]
        for (name, hit) in definitions {
            let ra = perCase(va, hit), rb = perCase(vb, hit)
            let ids = ra.keys.filter { rb[$0] != nil }.sorted()
            guard !ids.isEmpty else { continue }
            let xs = ids.map { ra[$0]! }, ys = ids.map { rb[$0]! }
            let mean = { (v: [Double]) in v.reduce(0, +) / Double(v.count) }
            var generator = SplitMix64(seed: 0x5EED)
            var diffs: [Double] = []
            for _ in 0..<10_000 {
                let idx = ids.indices.map { _ in Int(generator.next() % UInt64(ids.count)) }
                diffs.append(mean(idx.map { ys[$0] }) - mean(idx.map { xs[$0] }))
            }
            diffs.sort()
            let better = zip(xs, ys).filter { $1 > $0 }.count
            let worse = zip(xs, ys).filter { $1 < $0 }.count
            metrics.append(Metric(
                name: name, sentences: ids.count, rateA: mean(xs), rateB: mean(ys),
                difference: mean(ys) - mean(xs),
                low: diffs[Int(Double(diffs.count - 1) * 0.025)],
                high: diffs[Int(Double(diffs.count - 1) * 0.975)],
                better: better, worse: worse,
                same: zip(xs, ys).filter { $1 == $0 }.count,
                signTestP: Self.signTest(better: better, worse: worse)))
        }

        // Correction by category - the table readers skim.
        var cat: [String: (Int, Int, Int, Int)] = [:]
        for v in va where v.expectedHasError {
            cat[v.category, default: (0, 0, 0, 0)].0 += v.verdict == "pass" ? 1 : 0
            cat[v.category, default: (0, 0, 0, 0)].1 += 1
        }
        for v in vb where v.expectedHasError {
            cat[v.category, default: (0, 0, 0, 0)].2 += v.verdict == "pass" ? 1 : 0
            cat[v.category, default: (0, 0, 0, 0)].3 += 1
        }
        categories = cat.keys.sorted().map {
            let c = cat[$0]!
            return Category(category: $0, hitA: c.0, totalA: c.1, hitB: c.2, totalB: c.3)
        }
        for c in categories where c.totalA > 0 && c.totalB > 0 {
            let gap = abs(Double(c.hitB) / Double(c.totalB) - Double(c.hitA) / Double(c.totalA))
            if gap > largestCategoryGap { largestCategoryGap = gap; largestCategory = c.category }
        }
        _ = byID
    }

    func print() {
        for m in metrics {
            Swift.print(String(format: "%-13@ A %.1f%%  B %.1f%%  B-A %+.1f points, 95%% %+.1f to %+.1f  (%d sentences: %d better, %d worse, %d same; sign test p = %.2f)",
                               m.name as NSString, m.rateA * 100, m.rateB * 100, m.difference * 100,
                               m.low * 100, m.high * 100, m.sentences, m.better, m.worse, m.same, m.signTestP))
        }
        Swift.print("correction by category:")
        for c in categories {
            Swift.print("  \(c.category.padding(toLength: 12, withPad: " ", startingAt: 0)) A \(c.hitA)/\(c.totalA)   B \(c.hitB)/\(c.totalB)")
        }
        Swift.print(String(format: "largest category gap: %.0f points (%@)", largestCategoryGap * 100, largestCategory))
    }
}

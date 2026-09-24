import Foundation

/// Agreement between two raters on yes/no judgements, and how sure we can be
/// of it.
///
/// Cohen's kappa is agreement beyond what chance would give two raters who
/// say "yes" as often as these two do. Its interval comes from a percentile
/// bootstrap over items, seeded so the book's numbers are reproducible.
public enum Agreement {
    public struct Pair: Sendable, Equatable {
        public let first: Bool
        public let second: Bool
        public init(_ first: Bool, _ second: Bool) { self.first = first; self.second = second }
    }

    /// nil when kappa is undefined: both raters gave one answer to everything.
    public static func kappa(_ pairs: [Pair]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        let n = Double(pairs.count)
        let observed = Double(pairs.filter { $0.first == $0.second }.count) / n
        let p1 = Double(pairs.filter(\.first).count) / n
        let p2 = Double(pairs.filter(\.second).count) / n
        let chance = p1 * p2 + (1 - p1) * (1 - p2)
        guard chance < 1 else { return nil }
        return (observed - chance) / (1 - chance)
    }

    /// 95% percentile interval for kappa. `items` resamples that many items
    /// instead of the observed count: an estimate of the interval a larger
    /// label set drawn like this one would give.
    public static func interval(_ pairs: [Pair], items: Int? = nil,
                                resamples: Int = 10_000, seed: UInt64 = 0x5EED) -> ClosedRange<Double> {
        var generator = SplitMix64(seed: seed)
        let n = items ?? pairs.count
        var values: [Double] = []
        values.reserveCapacity(resamples)
        for _ in 0..<resamples {
            let sample = (0..<n).map { _ in pairs[Int(generator.next() % UInt64(pairs.count))] }
            if let k = kappa(sample) { values.append(k) }
        }
        return percentile(values)
    }

    /// Two raters graded against the same reference on the same items: the
    /// interval for kappa(second) - kappa(first), resampling items together so
    /// the comparison is paired.
    public static func differenceInterval(reference: [Bool], first: [Bool], second: [Bool],
                                          items: Int? = nil,
                                          resamples: Int = 10_000, seed: UInt64 = 0x5EED)
        -> ClosedRange<Double> {
        precondition(reference.count == first.count && first.count == second.count)
        var generator = SplitMix64(seed: seed)
        var values: [Double] = []
        let n = items ?? reference.count
        for _ in 0..<resamples {
            let idx = (0..<n).map { _ in Int(generator.next() % UInt64(reference.count)) }
            let a = kappa(idx.map { Pair(reference[$0], first[$0]) })
            let b = kappa(idx.map { Pair(reference[$0], second[$0]) })
            if let a, let b { values.append(b - a) }
        }
        return percentile(values)
    }

    static func percentile(_ values: [Double]) -> ClosedRange<Double> {
        guard !values.isEmpty else { return 0...0 }
        let sorted = values.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.025)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.975)]
        return low...high
    }
}

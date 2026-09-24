import Foundation

/// A rate measured over groups of correlated trials.
///
/// Three calls on the same sentence are not three independent observations:
/// if the model gets "Soy en Madrid." wrong once it will usually get it wrong
/// again. Treating 87 calls on 29 sentences as 87 independent trials makes an
/// interval look far more certain than the data allows - which is what Chapter
/// 1's intervals did, and what Chapter 4 corrects.
///
/// The interval here comes from a bootstrap over clusters: resample whole
/// sentences with replacement, recompute the rate, and take the middle 95% of
/// the results. The generator is seeded, so the interval is reproducible.
public struct ClusteredProportion: Sendable {
    public struct Cluster: Sendable, Equatable {
        public let successes: Int
        public let trials: Int
        public init(successes: Int, trials: Int) {
            precondition(successes >= 0 && trials > 0 && successes <= trials)
            self.successes = successes
            self.trials = trials
        }
    }

    public let clusters: [Cluster]
    public init(_ clusters: [Cluster]) { self.clusters = clusters }

    public var successes: Int { clusters.reduce(0) { $0 + $1.successes } }
    public var trials: Int { clusters.reduce(0) { $0 + $1.trials } }
    public var rate: Double { trials == 0 ? 0 : Double(successes) / Double(trials) }

    public func interval(resamples: Int = 10_000, seed: UInt64 = 0x5EED) -> ClosedRange<Double> {
        guard !clusters.isEmpty else { return 0...1 }
        var generator = SplitMix64(seed: seed)
        var rates: [Double] = []
        rates.reserveCapacity(resamples)
        for _ in 0..<resamples {
            var hit = 0, total = 0
            for _ in clusters.indices {
                let pick = clusters[Int(generator.next() % UInt64(clusters.count))]
                hit += pick.successes
                total += pick.trials
            }
            rates.append(Double(hit) / Double(total))
        }
        rates.sort()
        let low = rates[Int(Double(resamples) * 0.025)]
        let high = rates[min(resamples - 1, Int(Double(resamples) * 0.975))]

        // The bootstrap fails at the boundary. If every sentence scored 100%,
        // every resample scores 100% too, and the interval collapses to a
        // point - total certainty from nine sentences, the exact flaw the
        // Wilson interval exists to avoid. So the result is never narrower
        // than a Wilson interval that treats each sentence as one
        // observation: the least a count of independent cases can support.
        let floor = Self.wilson(rate: rate, n: Double(clusters.count))
        return min(low, floor.lowerBound)...max(high, floor.upperBound)
    }

    /// Wilson's interval for a real-valued rate over n observations.
    static func wilson(rate p: Double, n: Double, z: Double = 1.96) -> ClosedRange<Double> {
        let z2 = z * z
        let denominator = 1 + z2 / n
        let centre = (p + z2 / (2 * n)) / denominator
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot() / denominator
        return max(0, centre - margin)...min(1, centre + margin)
    }
}

/// A small, fast, seedable generator. Foundation's SystemRandomNumberGenerator
/// cannot be seeded, and an interval that changes every time the book is built
/// is not a number anyone can check.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How many independent cases are needed to measure a rate to a given width.
///
/// The smallest n whose Wilson interval, at the expected rate, is no wider than
/// plus or minus `halfWidth`. It is the question a dataset's size should answer
/// before anybody writes a single case.
public enum SampleSize {
    public static func needed(expectedRate: Double, halfWidth: Double,
                              limit: Int = 100_000) -> Int? {
        precondition((0...1).contains(expectedRate) && halfWidth > 0)
        for n in 1...limit {
            let k = Int((expectedRate * Double(n)).rounded())
            let ci = Proportion(successes: k, trials: n).interval()
            if (ci.upperBound - ci.lowerBound) / 2 <= halfWidth { return n }
        }
        return nil
    }
}

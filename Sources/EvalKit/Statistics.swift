import Foundation

/// A rate with an honest uncertainty attached.
///
/// Eval results are proportions from small samples - 29 sentences, not 29,000
/// - and a bare percentage hides how little it can distinguish. 24 out of 29 is
/// "83%", which sounds precise; its 95% interval is roughly 65-92%, which is
/// what it actually knows. Every number this book prints comes with one.
public struct Proportion: Sendable, Equatable, CustomStringConvertible {
    public let successes: Int
    public let trials: Int

    public init(successes: Int, trials: Int) {
        precondition(successes >= 0 && trials >= 0 && successes <= trials)
        self.successes = successes
        self.trials = trials
    }

    public var rate: Double { trials == 0 ? 0 : Double(successes) / Double(trials) }

    /// Wilson score interval. Chosen over the textbook "p ± 1.96·SE" because
    /// that one misbehaves exactly where evals live: small n and rates near
    /// 0% or 100%, where it can produce intervals below 0 or above 1.
    public func interval(z: Double = 1.96) -> ClosedRange<Double> {
        guard trials > 0 else { return 0...1 }
        let n = Double(trials), p = rate, z2 = z * z
        let denominator = 1 + z2 / n
        let centre = (p + z2 / (2 * n)) / denominator
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot() / denominator
        return max(0, centre - margin)...min(1, centre + margin)
    }

    public var description: String {
        guard trials > 0 else { return "n/a (n=0)" }
        let ci = interval()
        return String(format: "%5.1f%%  (95%% CI %.1f–%.1f%%, %d/%d)",
                      rate * 100, ci.lowerBound * 100, ci.upperBound * 100,
                      successes, trials)
    }
}

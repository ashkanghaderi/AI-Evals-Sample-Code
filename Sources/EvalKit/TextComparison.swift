import Foundation

/// How strictly two sentences must match to count as "the same".
///
/// Every rule here is a decision that changes the score, so they are few and
/// written down. Deliberately NOT normalised: case, accents, and Spanish's
/// opening ¿ and ¡ - in a language-learning app those are exactly what the
/// learner got wrong, and a grader that forgives them grades nothing.
public enum TextComparison {
    public static func normalized(_ text: String) -> String {
        var result = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        // A trailing full stop is presentation, not correctness. Models add
        // and drop it freely, and counting that as an error would bury real
        // mistakes under noise.
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    public static func matches(_ candidate: String, anyOf accepted: [String]) -> Bool {
        let target = normalized(candidate)
        return accepted.contains { normalized($0) == target }
    }
}

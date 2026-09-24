import Foundation

/// How alike two strings are, from 0 to 1: one minus the edit distance
/// (insertions, deletions, substitutions of characters) over the longer
/// length, after `TextComparison.normalized`.
///
/// The standard fuzzy-match score, included so Chapter 9 can show what it
/// does to a grader whose errors are one character long.
public enum Similarity {
    public static func ratio(_ a: String, _ b: String) -> Double {
        let x = Array(TextComparison.normalized(a)), y = Array(TextComparison.normalized(b))
        let longest = max(x.count, y.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(distance(x, y)) / Double(longest)
    }

    static func distance(_ x: [Character], _ y: [Character]) -> Int {
        var previous = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in stride(from: 1, through: y.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return x.isEmpty ? y.count : previous[y.count]
    }
}

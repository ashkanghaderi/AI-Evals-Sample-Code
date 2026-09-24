import Foundation
import EvalKit
import TutorCore

/// Did the translation keep the Spanish it was told to keep?
///
/// The English explanation quotes the learner's words - 'es', 'mi hermana' -
/// and the translator is told to leave them alone. Whether it did is checkable
/// with no speaker of the target language at all: every quoted span in the
/// English must appear, character for character, in the translation.
struct QuoteReport: Codable {
    struct Case: Codable {
        let id: String
        let quotes: [String]
        let missing: [String]
        let translation: String
    }

    var quotes = 0
    var kept = 0
    var cases: [Case] = []

    /// Quoted spans: 'single', "double" or ‘curly’, one to four words long.
    static func quoted(_ text: String) -> [String] {
        text.matches(of: /['"‘“]([^'"’”]{1,40})['"’”]/)
            .map { String($0.output.1) }
            .filter { $0.split(separator: " ").count <= 4 }
    }

    /// Only spans that are Spanish count: ones found in the learner's sentence
    /// or the correction. The first version of this check counted every
    /// quote, and flagged the German for translating 'her sister' - which the
    /// English explanation had itself already translated from "mi hermana".
    /// Case is ignored: Turkish capitalises a quote that starts a sentence,
    /// and 'Vivimos' is still the learner's word.
    init(source: [CorrectionRecord], translated: [CorrectionRecord], cases dataset: [CorrectionCase]) {
        let english = Dictionary(source.filter { $0.repetition == 0 }
            .map { ($0.caseID, $0.output) }, uniquingKeysWith: { a, _ in a })
        let inputs = Dictionary(uniqueKeysWithValues: dataset.map { ($0.id, $0.input) })
        func has(_ text: String, _ span: String) -> Bool {
            text.range(of: span, options: [.caseInsensitive]) != nil
        }
        for record in translated where record.repetition == 0 {
            guard let translation = record.output?.explanation,
                  let original = english[record.caseID] ?? nil,
                  let input = inputs[record.caseID] else { continue }
            let spans = Self.quoted(original.explanation).filter {
                has(input, $0) || has(original.corrected, $0)
            }
            guard !spans.isEmpty else { continue }
            let missing = spans.filter { !has(translation, $0) }
            quotes += spans.count
            kept += spans.count - missing.count
            cases.append(Case(id: record.caseID, quotes: spans, missing: missing,
                              translation: translation))
        }
    }

    func print() {
        Swift.print("quoted Spanish kept: \(Proportion(successes: kept, trials: quotes))")
        for item in cases where !item.missing.isEmpty {
            Swift.print("  [\(item.id)] lost \(item.missing.joined(separator: ", "))")
            Swift.print("      \(item.translation)")
        }
    }
}

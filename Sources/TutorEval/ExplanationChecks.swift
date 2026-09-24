import Foundation
import NaturalLanguage
import EvalKit
import TutorCore

/// Checks on one answer that need no answer key: each compares the answer
/// with itself, or with the learner's sentence.
///
/// None of them can say an explanation is right. Each can say, for certain,
/// that something is wrong - and Chapter 8 measures how often "for certain"
/// is true, against explanations a person has labelled.
enum ExplanationCheck: String, CaseIterable, Codable {
    /// hasError agrees with whether the sentence was changed (Chapter 1).
    case coherent
    /// The explanation's verdict agrees with hasError: it does not call the
    /// sentence correct while flagging an error, or name an error while
    /// saying there is none.
    case agrees
    /// Every quoted word appears in the learner's sentence or the correction.
    /// An explanation about a word that is not there is about another sentence.
    case grounded
    /// The explanation is a complete sentence, not a fragment: at least four
    /// words, ending in sentence punctuation. Words are counted by the
    /// NaturalLanguage tokenizer, not by spaces - the first version split on
    /// spaces and called every Japanese explanation a fragment.
    case complete

    static var saysCorrect: Regex<(Substring, Substring?)> {
        /(?i)\bsentence is (grammatically )?correct\b/
    }
    static var namesError: Regex<(Substring, Substring)> {
        /(?i)\b(incorrect|should be|does not agree|must agree|lacks|missing|requires|instead of)\b/
    }

    /// Whether the answer passes this check. Answers with no output pass
    /// every check: a failed call is the grader's business, not these.
    func passes(input: String, output: Correction) -> Bool {
        let explanation = output.explanation
        switch self {
        case .coherent:
            let changed = TextComparison.normalized(output.corrected) != TextComparison.normalized(input)
            return output.hasError == changed
        case .agrees:
            let correct = explanation.contains(Self.saysCorrect)
            let error = explanation.contains(Self.namesError)
            return output.hasError ? !(correct && !error) : !error
        case .grounded:
            return QuoteReport.quoted(explanation).allSatisfy { span in
                [input, output.corrected].contains {
                    $0.range(of: span, options: .caseInsensitive) != nil
                }
            }
        case .complete:
            let trimmed = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = trimmed
            let words = tokenizer.tokens(for: trimmed.startIndex..<trimmed.endIndex).count
            return words >= 4 && [".", "!", "?", "。", "！", "？"].contains(where: trimmed.hasSuffix)
        }
    }

    static func failures(input: String, output: Correction) -> [ExplanationCheck] {
        allCases.filter { !$0.passes(input: input, output: output) }
    }
}

/// A person's judgement of one explanation, tied to its exact text. A label
/// is about an output, not a case: if the model's explanation changes, the
/// old label no longer applies, and nothing should pretend it does.
struct ExplanationLabel: Codable {
    let caseID: String
    let explanation: String
    /// "right", "wrong" or "arguable".
    let label: String
    let note: String
}

/// How good each check is, measured against the labels.
struct CheckReport: Codable {
    struct Row: Codable {
        let check: String
        let fired: Int
        /// Of the labelled answers it fired on, how many were labelled wrong.
        let firedOnWrong: Int
        let firedOnRight: Int
        let firedOnArguable: Int
    }

    var answers = 0
    var labelled = 0
    var wrong = 0
    var caughtWrong = 0
    /// Wrong explanations on answers the golden-set grader passed - the ones
    /// no score in Part I could see.
    var wrongOnPassing = 0
    var caughtOnPassing = 0
    var rows: [Row] = []
    var flagged: [String: [String]] = [:]

    init(cases: [CorrectionCase], records: [CorrectionRecord], labels: [ExplanationLabel]) {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        let labelFor = Dictionary(labels.map { ("\($0.caseID)|\($0.explanation)", $0.label) },
                                  uniquingKeysWith: { a, _ in a })
        var counts: [ExplanationCheck: (Int, Int, Int, Int)] = [:]
        for record in records {
            guard let item = byID[record.caseID], let output = record.output else { continue }
            answers += 1
            let failed = ExplanationCheck.failures(input: item.input, output: output)
            let key = "\(record.caseID)#\(record.repetition)"
            if !failed.isEmpty { flagged[key] = failed.map(\.rawValue) }
            let label = labelFor["\(record.caseID)|\(output.explanation)"]
            if label != nil { labelled += 1 }
            let passing = item.hasError
                ? TextComparison.matches(output.corrected, anyOf: item.accepted)
                : TextComparison.matches(output.corrected, anyOf: item.accepted) && !output.hasError
            if label == "wrong" {
                wrong += 1
                if !failed.isEmpty { caughtWrong += 1 }
                if passing {
                    wrongOnPassing += 1
                    if !failed.isEmpty { caughtOnPassing += 1 }
                }
            }
            for check in failed {
                var c = counts[check] ?? (0, 0, 0, 0)
                c.0 += 1
                if label == "wrong" { c.1 += 1 }
                if label == "right" { c.2 += 1 }
                if label == "arguable" { c.3 += 1 }
                counts[check] = c
            }
        }
        rows = ExplanationCheck.allCases.map { check in
            let c = counts[check] ?? (0, 0, 0, 0)
            return Row(check: check.rawValue, fired: c.0, firedOnWrong: c.1,
                       firedOnRight: c.2, firedOnArguable: c.3)
        }
    }

    func print() {
        Swift.print("\n\(answers) answers, \(labelled) with a label")
        Swift.print("check        fired  on wrong  on right  on arguable")
        for row in rows {
            Swift.print("\(row.check.padding(toLength: 12, withPad: " ", startingAt: 0)) "
                        + String(format: "%5d  %8d  %8d  %11d", row.fired, row.firedOnWrong,
                                 row.firedOnRight, row.firedOnArguable))
        }
        if labelled > 0 {
            Swift.print("wrong explanations caught by any check: \(caughtWrong) of \(wrong)")
            Swift.print("  ... on answers the golden set passed: \(caughtOnPassing) of \(wrongOnPassing)")
        }
    }
}

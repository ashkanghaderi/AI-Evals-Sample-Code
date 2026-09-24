import Foundation
import EvalKit

/// Test cases made by code instead of by a model.
///
/// Start from sentences a person has already checked are correct, and break
/// each one in a single, known way. The answer is correct by construction: it
/// is the sentence before it was broken. No model decides what the right
/// answer is, and the dataset regenerates identically every time.
///
/// The catch is that "known way" means *a way we thought of*. These cases
/// measure the corrector on our list of mistakes, one at a time, in sentences
/// we wrote - never on what learners actually do.
enum Perturbation: String, CaseIterable {
    case articleGender = "article-gender"
    case verbPerson = "verb-person"
    case accentDrop = "accent-drop"

    /// The broken sentence, or nil if the rule has nothing to act on.
    ///
    /// `naive` reproduces perturbed-v1, whose verb-person rule changed any
    /// conjugated verb. Spanish drops subject pronouns, so "Tengo hambre"
    /// became "Tiene hambre" - correct Spanish, filed as a mistake. Six of
    /// fifty-four v1 cases were like that. The rule now changes a verb only
    /// when its subject is written right before it, which is what makes the
    /// wrong person unambiguous.
    func apply(to sentence: String, naive: Bool = false) -> String? {
        switch self {
        case .articleGender:
            return Self.replaceFirstWord(in: sentence, using: [
                "el": "la", "la": "el", "los": "las", "las": "los", "un": "una", "una": "un",
            ])
        case .verbPerson:
            return Self.replaceFirstWord(in: sentence, using: [
                "soy": "es", "es": "son", "son": "es", "estoy": "está", "está": "están",
                "están": "está", "vivimos": "viven", "gustan": "gusta", "tengo": "tiene",
                "voy": "va", "sé": "sabe", "comí": "comió", "pienso": "piensa", "vi": "vio",
                "hace": "hacen", "vino": "vinieron",
            ], requireSubject: !naive)
        case .accentDrop:
            // Remove the first acute accent in the sentence. Spanish requires
            // them, and the grader deliberately does not forgive them.
            let plain: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u",
                                                 "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U"]
            guard let index = sentence.firstIndex(where: { plain[$0] != nil }) else { return nil }
            var result = sentence
            result.replaceSubrange(index...index, with: String(plain[sentence[index]]!))
            return result
        }
    }

    static let subjectPronouns: Set = ["yo", "tú", "él", "ella", "nosotros", "nosotras",
                                       "ellos", "ellas", "usted", "ustedes", "nadie"]
    static let determiners: Set = ["el", "la", "los", "las", "mi", "mis", "tu", "su",
                                   "este", "esta", "estos", "estas"]

    /// Replaces the first whole word found in `table`, keeping its capital.
    /// With `requireSubject`, only a word directly preceded by its subject: a
    /// pronoun ("yo es", "yo no sabe") or a determiner and noun ("la gente son").
    static func replaceFirstWord(in sentence: String, using table: [String: String],
                                 requireSubject: Bool = false) -> String? {
        let words = Array(sentence.matches(of: /\p{L}+/))
        for (position, match) in words.enumerated() {
            let word = String(match.output)
            guard let replacement = table[word.lowercased()] else { continue }
            if requireSubject {
                // "no" sits between a subject and its verb without changing
                // whose verb it is.
                let before = words[..<position].map { String($0.output).lowercased() }
                    .filter { $0 != "no" }
                let hasPronoun = before.last.map(subjectPronouns.contains) ?? false
                let hasNounPhrase = before.count >= 2 && determiners.contains(before[before.count - 2])
                guard hasPronoun || hasNounPhrase else { continue }
            }
            let cased = word.first!.isUppercase
                ? replacement.prefix(1).uppercased() + replacement.dropFirst()
                : replacement
            var result = sentence
            result.replaceSubrange(match.range, with: cased)
            return result
        }
        return nil
    }

    /// Every rule applied to every correct sentence in the source dataset.
    static func cases(from source: [CorrectionCase], naive: Bool = false) -> [CorrectionCase] {
        var result: [CorrectionCase] = []
        for item in source {
            // The correct version of each source sentence: its first accepted
            // answer. For controls that is the input itself.
            guard let correct = item.accepted.first else { continue }
            let accepted = item.accepted
            for rule in allCases {
                guard let broken = rule.apply(to: correct, naive: naive),
                      !TextComparison.matches(broken, anyOf: accepted) else { continue }
                result.append(CorrectionCase(id: "p-\(item.id)-\(rule.rawValue)", input: broken,
                                             hasError: true, accepted: accepted,
                                             category: rule.rawValue))
            }
        }
        return result
    }
}

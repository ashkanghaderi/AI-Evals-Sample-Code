import Foundation
import NaturalLanguage

/// Is the explanation in the language the learner asked for?
///
/// The first grader in this book that looks at the explanation at all. It
/// cannot say whether an explanation is *true* - that needs a judge - but
/// whether it is in the right language needs no answer key, and a German
/// speaker handed an English explanation has been failed however true it is.
///
/// The recogniser is a model too. Chapter 7 checks it on runs whose language
/// is known before trusting it on runs whose language is the question.
enum ExplanationLanguage {
    static let codes = ["English": "en", "Spanish": "es", "German": "de", "French": "fr",
                        "Japanese": "ja", "Turkish": "tr", "Persian": "fa", "Arabic": "ar"]

    /// The language a run asked for, from its recorded prompt. Runs with no
    /// prompt recorded are prompt v1, which asked for English.
    static func expected(from prompt: String?) -> String {
        guard let prompt, let range = prompt.range(of: "explanation:") else { return "en" }
        let name = String(prompt[range.upperBound...])
        return codes[name] ?? name
    }

    /// The dominant language of a piece of text, as a code ("en", "de"), or
    /// nil for text too short or mixed to call.
    static func detect(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}

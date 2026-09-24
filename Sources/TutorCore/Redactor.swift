import Foundation
import NaturalLanguage

/// Removes personal data from a learner's sentence before it is recorded.
///
/// Learners write about themselves - "Me llamo Carlos y vivo en Madrid" is the
/// first sentence every Spanish course teaches. Anything recorded for evals has
/// to lose the names, places, and contact details on the device, before it is
/// stored anywhere.
///
/// Two layers. Patterns catch what has a shape (email addresses, URLs, phone
/// numbers) and are exact. Apple's NaturalLanguage tagger catches names and
/// places, and is a model: it makes mistakes in both directions, which is why
/// the redactor has an eval of its own (Chapter 5).
public struct Redactor: Sendable {
    public enum Strategy: String, Sendable, CaseIterable {
        /// Tag the sentence as written.
        case tagger
        /// Tag it with the first letter lowercased, so a capitalised verb at
        /// the start ("Vivo en...") is not mistaken for a name. Chapter 5
        /// measures what this costs.
        case lowercaseFirstLetter = "lowercase-first"
    }

    public var strategy: Strategy
    public init(strategy: Strategy = .tagger) { self.strategy = strategy }

    public func redact(_ text: String) -> String {
        var result = text
        for (pattern, placeholder) in Self.patterns {
            result = result.replacingOccurrences(of: pattern, with: placeholder,
                                                 options: .regularExpression)
        }
        return redactNames(in: result)
    }

    static let patterns: [(String, String)] = [
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[EMAIL]"),
        (#"(https?://|www\.)[^\s,;]+[^\s,;.!?]"#, "[URL]"),
        // Eight or more digits, allowing spaces and dashes: a phone number,
        // not a year or an age.
        (#"(\+\d{1,3}[\s-]?)?\d(?:[\s-]?\d){7,}"#, "[PHONE]"),
    ]

    private func redactNames(in text: String) -> String {
        let tagged: String
        switch strategy {
        case .tagger:
            tagged = text
        case .lowercaseFirstLetter:
            // Same length in UTF-16, so offsets found in the copy are valid in
            // the original.
            tagged = text.prefix(1).lowercased() + text.dropFirst()
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = tagged
        var found: [(NSRange, String)] = []
        tagger.enumerateTags(in: tagged.startIndex..<tagged.endIndex, unit: .word,
                             scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let placeholder: String? = switch tag {
            case .personalName?: "[NAME]"
            case .placeName?: "[PLACE]"
            case .organizationName?: "[ORG]"
            default: nil
            }
            if let placeholder { found.append((NSRange(range, in: tagged), placeholder)) }
            return true
        }

        let result = NSMutableString(string: text)
        for (range, placeholder) in found.reversed() {
            result.replaceCharacters(in: range, with: placeholder)
        }
        return result as String
    }
}

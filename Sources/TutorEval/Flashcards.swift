import Foundation
import FoundationModels
import EvalKit
import TutorCore

/// The same cards with every constraint written in prose instead of enforced
/// by the schema - the comparison Chapter 15 is about. Never shipped.
@Generable
struct ProseFlashcard: Codable {
    @Guide(description: "a Spanish word from the text, in its dictionary form: infinitive for verbs, masculine singular for adjectives, singular for nouns, without an article")
    var term: String
    @Guide(description: "the part of speech: one of noun, verb, adjective, adverb or other")
    var partOfSpeech: String
    @Guide(description: "the English translation of the word as it is used in the text, as short as possible")
    var translation: String
    @Guide(description: "the sentence from the text in which the word appears, copied exactly")
    var example: String
}

@Generable
struct ProseFlashcardSet: Codable {
    @Guide(description: "exactly five cards: the five most useful words in the text for a learner, all different")
    var cards: [ProseFlashcard]
}

struct FlashcardText: Codable {
    struct Word: Codable {
        let lemma: String
        let forms: [String]
        let pos: String
        let translations: [String]
    }
    let id: String
    let text: String
    let words: [Word]
}

struct FlashcardRecord: Codable {
    let textID: String
    let repetition: Int
    let schema: String
    let cards: [Flashcard]?
    let error: String?
    let latencyMilliseconds: Int
}

enum FlashcardEval {
    static func run(texts: [FlashcardText], schema: String, options: GenerationOptions,
                    repeats: Int, to url: URL) async throws {
        let model = SystemLanguageModel.default
        let extractor = FlashcardExtractor(model: model, options: options)
        let clock = ContinuousClock()
        for repetition in 0..<repeats {
            for text in texts {
                let start = clock.now
                var cards: [Flashcard]?
                var failure: String?
                do {
                    if schema == "prose" {
                        let session = LanguageModelSession(model: model,
                                                           instructions: FlashcardExtractor<SystemLanguageModel>.instructions)
                        cards = try await session.respond(to: text.text, generating: ProseFlashcardSet.self,
                                                          options: options).content.cards.map {
                            Flashcard(term: $0.term, partOfSpeech: $0.partOfSpeech,
                                      translation: $0.translation, example: $0.example)
                        }
                    } else {
                        cards = try await extractor.cards(for: text.text).cards
                    }
                } catch {
                    failure = String(describing: error)
                }
                let elapsed = clock.now - start
                try JSONLines.append(FlashcardRecord(
                    textID: text.id, repetition: repetition, schema: schema, cards: cards, error: failure,
                    latencyMilliseconds: Int(elapsed.components.seconds * 1000
                        + elapsed.components.attoseconds / 1_000_000_000_000_000)), to: url)
            }
        }
    }

    static let functionWords: Set = ["el", "la", "los", "las", "un", "una", "y", "a", "de", "en", "con", "por",
                                     "para", "que", "mi", "mis", "me", "le", "se", "yo", "él", "pero", "porque",
                                     "cuando", "así"]

    /// "the Sister", "to work" and "work, labour" all count as "sister",
    /// "work": case, a leading article or "to", and alternatives separated by
    /// commas, slashes or "or" are forgiven. Anything else is not.
    static func translationMatches(_ given: String, _ accepted: [String]) -> Bool {
        let parts = given.lowercased()
            .replacingOccurrences(of: " or ", with: ",")
            .split(whereSeparator: { ",/;".contains($0) })
            .map { part -> String in
                var p = part.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                for prefix in ["to ", "the ", "a ", "an "] where p.hasPrefix(prefix) {
                    p = String(p.dropFirst(prefix.count))
                }
                return p
            }
        return parts.contains { accepted.contains($0) }
    }
}

/// Every card checked against the key, deterministically.
struct FlashcardReport: Codable {
    var calls = 0
    var failed = 0
    var callsWithFiveCards = 0
    var cards = 0
    var validPartOfSpeech = 0
    var grounded = 0
    var functionWords = 0
    var translationRight = 0
    var partOfSpeechRight = 0
    var exampleVerbatim = 0
    /// A piece of the text, differently capitalised: "los domingos". Not what
    /// was asked for, and harmless.
    var exampleFragment = 0
    /// Neither: the text changed. Accents dropped, a verb re-conjugated - the
    /// example teaches something the learner never read.
    var exampleAltered: [String] = []
    var duplicates = 0
    var cardCounts: [Int] = []
    /// Terms in neither the key nor the text: read them. Some are invented,
    /// some are the key's gaps.
    var ungrounded: [String] = []
    /// In the text only once accents are ignored: "medico" for "médico".
    var misspelled: [String] = []
    /// Words the key has but the text does not: in the text only as a proper
    /// noun or a word the key left out ("México").
    var inTextNotKey: [String] = []
    /// Key words given in their dictionary form, as the instructions ask.
    var dictionaryForm = 0
    var wrongTranslations: [String] = []
    /// Of the rejected translations, those on a card whose term was not in
    /// dictionary form - "nieva = it snows": right for the form, wrong card.
    var wrongTranslationsOnInflected = 0

    init(texts: [FlashcardText], records: [FlashcardRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: texts.map { ($0.id, $0) })
        let valid: Set = ["noun", "verb", "adjective", "adverb", "other"]
        for record in records {
            guard let text = byID[record.textID] else { continue }
            calls += 1
            guard let set = record.cards else { failed += 1; continue }
            cardCounts.append(set.count)
            if set.count == 5 { callsWithFiveCards += 1 }
            var seen = Set<String>()
            for card in set {
                cards += 1
                let term = card.term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                let bare = term.split(separator: " ").count > 1
                    && ["el", "la", "los", "las", "un", "una"].contains(String(term.split(separator: " ")[0]))
                    ? term.split(separator: " ").dropFirst().joined(separator: " ") : term
                if !seen.insert(bare).inserted { duplicates += 1 }
                if valid.contains(card.partOfSpeech.lowercased()) { validPartOfSpeech += 1 }
                let example = TextComparison.normalized(card.example)
                if !example.isEmpty && TextComparison.normalized(text.text).contains(example) {
                    exampleVerbatim += 1
                } else if !example.isEmpty && text.text.lowercased().contains(example.lowercased()) {
                    exampleFragment += 1
                } else {
                    exampleAltered.append("\(record.textID): \(card.example)")
                }
                if FlashcardEval.functionWords.contains(bare) { functionWords += 1; continue }
                guard let word = text.words.first(where: { $0.lemma == bare || $0.forms.contains(bare) }) else {
                    let words = text.text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                    let fold = { (w: String) in w.folding(options: .diacriticInsensitive, locale: nil) }
                    if words.contains(bare) {
                        inTextNotKey.append("\(record.textID): \(card.term)")
                    } else if words.map(fold).contains(fold(bare)) {
                        misspelled.append("\(record.textID): \(card.term)")
                    } else {
                        ungrounded.append("\(record.textID): \(card.term)")
                    }
                    continue
                }
                grounded += 1
                if bare == word.lemma { dictionaryForm += 1 }
                if card.partOfSpeech.lowercased() == word.pos { partOfSpeechRight += 1 }
                if FlashcardEval.translationMatches(card.translation, word.translations) {
                    translationRight += 1
                } else {
                    wrongTranslations.append("\(record.textID): \(card.term) = \(card.translation)")
                    if bare != word.lemma { wrongTranslationsOnInflected += 1 }
                }
            }
        }
    }

    func print(title: String) {
        Swift.print("\n\(title): \(calls) calls, \(failed) failed; exactly five cards in \(callsWithFiveCards) (counts: \(cardCounts.map(String.init).joined(separator: " ")))")
        Swift.print("  \(cards) cards: part of speech from the list \(validPartOfSpeech), duplicates \(duplicates), function words \(functionWords)")
        Swift.print("  examples: copied exactly \(exampleVerbatim), a re-capitalised piece \(exampleFragment), altered \(exampleAltered.count)")
        if !exampleAltered.isEmpty { Swift.print("    altered: \(exampleAltered.joined(separator: "; "))") }
        Swift.print("  in the key \(grounded): dictionary form \(dictionaryForm), translation right \(translationRight) (\(wrongTranslationsOnInflected) rejected on inflected terms), part of speech right \(partOfSpeechRight)")
        if !inTextNotKey.isEmpty { Swift.print("  in the text, not the key: \(inTextNotKey.joined(separator: "; "))") }
        if !misspelled.isEmpty { Swift.print("  misspelled: \(misspelled.joined(separator: "; "))") }
        if !ungrounded.isEmpty { Swift.print("  in neither text nor key: \(ungrounded.joined(separator: "; "))") }
        if !wrongTranslations.isEmpty { Swift.print("  translations not accepted: \(wrongTranslations.joined(separator: "; "))") }
    }
}

import FoundationModels

/// One vocabulary card, made from a text the learner is reading.
@Generable
public struct Flashcard: Sendable, Codable, Equatable {
    @Guide(description: "a Spanish word from the text, in its dictionary form: infinitive for verbs, masculine singular for adjectives, singular for nouns, without an article")
    public var term: String

    @Guide(.anyOf(["noun", "verb", "adjective", "adverb", "other"]))
    public var partOfSpeech: String

    @Guide(description: "the English translation of the word as it is used in the text, as short as possible")
    public var translation: String

    @Guide(description: "the sentence from the text in which the word appears, copied exactly")
    public var example: String

    public init(term: String, partOfSpeech: String, translation: String, example: String) {
        self.term = term; self.partOfSpeech = partOfSpeech
        self.translation = translation; self.example = example
    }
}

@Generable
public struct FlashcardSet: Sendable, Codable, Equatable {
    @Guide(description: "the five most useful words in the text for a learner, all different", .count(5))
    public var cards: [Flashcard]
}

/// "Make flashcards from this text" - Chapter 15's feature.
///
/// The constraints that can be enforced are enforced by the schema, not asked
/// for in prose: exactly five cards (`.count(5)`), and a part of speech from a
/// fixed list (`.anyOf`). Chapter 15 measures what that buys against the same
/// constraints written as descriptions.
public struct FlashcardExtractor<Model: LanguageModel> {
    public let model: Model
    public var options: GenerationOptions

    public init(model: Model, options: GenerationOptions = GenerationOptions()) {
        self.model = model
        self.options = options
    }

    public static var instructions: String {
        """
        You make vocabulary flashcards for a learner of Spanish whose first \
        language is English. The user sends a short Spanish text. Choose the \
        most useful words in it for the learner - not articles, prepositions \
        or other small function words.
        """
    }

    public func cards(for text: String) async throws -> FlashcardSet {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        return try await session.respond(to: text, generating: FlashcardSet.self, options: options).content
    }
}

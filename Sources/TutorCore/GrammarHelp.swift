import Foundation
import FoundationModels
import NaturalLanguage

public struct GrammarNote: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let text: String
    public init(id: String, title: String, text: String) { self.id = id; self.title = title; self.text = text }
}

public protocol NoteRetriever: Sendable {
    func retrieve(_ query: String, from notes: [GrammarNote], k: Int) -> [GrammarNote]
}

/// Words in common, weighted by how rare each word is across the notes: the
/// baseline any retriever has to beat.
public struct KeywordRetriever: NoteRetriever {
    public init() {}
    static let stopwords: Set = ["the", "a", "an", "is", "it", "i", "do", "why", "how", "and", "or", "not",
                                 "in", "of", "to", "what", "when", "say", "use", "be", "with", "if", "de", "la",
                                 "el", "que", "y", "es", "se", "por", "and", "you", "my", "me"]
    public static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) }
    }
    public func retrieve(_ query: String, from notes: [GrammarNote], k: Int) -> [GrammarNote] {
        let docs = notes.map { Set(Self.words($0.title + " " + $0.text)) }
        let q = Set(Self.words(query))
        func idf(_ w: String) -> Double {
            log(Double(notes.count + 1) / Double(docs.filter { $0.contains(w) }.count + 1)) + 1
        }
        let scored = zip(notes, docs).map { note, doc in (note, q.intersection(doc).map(idf).reduce(0, +)) }
        return scored.sorted { $0.1 > $1.1 }.prefix(k).map(\.0)
    }
}

/// Apple's on-device sentence embeddings: nearest notes by meaning rather than
/// by shared words. Free, and a model too - Chapter 18 measures it.
public struct EmbeddingRetriever: NoteRetriever {
    public init() {}
    public func retrieve(_ query: String, from notes: [GrammarNote], k: Int) -> [GrammarNote] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return [] }
        let scored = notes.map { ($0, embedding.distance(between: query, and: $0.title + ". " + $0.text)) }
        return scored.sorted { $0.1 < $1.1 }.prefix(k).map(\.0)
    }
}

/// "Why is it el agua?" - Chapter 18's feature: an answer from the app's own
/// grammar notes, retrieved for the question.
public struct GrammarHelper<Model: LanguageModel> {
    public let model: Model
    public var options: GenerationOptions
    public init(model: Model, options: GenerationOptions = GenerationOptions(maximumResponseTokens: 256)) {
        self.model = model; self.options = options
    }

    public static var instructions: String {
        """
        You answer a learner's question about Spanish grammar, briefly and in \
        English, using only the grammar notes provided with the question. If \
        the notes do not answer it, say that the notes do not cover it.
        """
    }

    public func answer(_ question: String, notes: [GrammarNote]) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let context = notes.map { "Note: \($0.title). \($0.text)" }.joined(separator: "\n")
        return try await session.respond(to: "\(context)\n\nQuestion: \(question)", options: options).content
    }
}

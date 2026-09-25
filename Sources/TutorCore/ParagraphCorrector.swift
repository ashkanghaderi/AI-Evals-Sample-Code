import Foundation
import FoundationModels
import NaturalLanguage

/// Chapter 23's change: a paragraph is corrected one sentence at a time.
///
/// Chapter 13 found that one call with a long paragraph returned most of it
/// deleted. Here the paragraph is split with NLTokenizer, each sentence goes
/// through exactly the corrector Part I measured, and the results are joined.
/// A one-sentence input takes the same single call as before.
public struct ParagraphCorrector<Model: LanguageModel> {
    public let corrector: SentenceCorrector<Model>
    /// Paragraphs of up to this many sentences go in one call, as before the
    /// change: in Chapter 23 one call corrected more of a short paragraph
    /// than sentence-by-sentence did. 0 always splits. The first candidate,
    /// 8, failed the committed criteria at 16 sentences (10 right against 13
    /// shipped); 16 passed them. evals/paragraph/decision.md has the record.
    public var wholeUpTo: Int
    public init(corrector: SentenceCorrector<Model>, wholeUpTo: Int = 16) {
        self.corrector = corrector; self.wholeUpTo = wholeUpTo
    }

    public struct Result: Sendable {
        public let sentences: [(input: String, correction: Correction)]
        public var corrected: String { sentences.map(\.correction.corrected).joined(separator: " ") }
        public var hasError: Bool { sentences.contains { $0.correction.hasError } }
    }

    public static func sentences(in paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.spanish)
        tokenizer.string = paragraph
        return tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex)
            .map { paragraph[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func correct(_ paragraph: String) async throws -> Result {
        let sentences = Self.sentences(in: paragraph)
        if sentences.count <= wholeUpTo {
            return Result(sentences: [(paragraph, try await corrector.correct(paragraph))])
        }
        var out: [(input: String, correction: Correction)] = []
        for sentence in sentences {
            out.append((sentence, try await corrector.correct(sentence)))
        }
        return Result(sentences: out)
    }
}

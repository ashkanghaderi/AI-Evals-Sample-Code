import Foundation
import FoundationModels
import EvalKit
import TutorCore

struct GrammarQuery: Codable {
    let id: String
    let query: String
    let relevant: [String]
    let answerMustContain: [String]
}

/// Retrieval graded on its own, with no language model: did the note the
/// question needs come back, and how high?
struct RetrievalReport: Encodable {
    struct Row: Codable { let queryID: String; let rank: Int?; let top: [String] }
    var queries = 0
    var hitAt1 = 0
    var hitAt3 = 0
    var reciprocalRankSum = 0.0
    /// Mean share of each question's keywords that also appear in its
    /// relevant note. High overlap means the questions were written by
    /// someone who had read the notes.
    var meanOverlap = 0.0
    var rows: [Row] = []
    var meanReciprocalRank: Double { queries == 0 ? 0 : reciprocalRankSum / Double(queries) }

    init(retriever: any NoteRetriever, notes: [GrammarNote], queries qs: [GrammarQuery]) {
        for q in qs {
            queries += 1
            let ranked = retriever.retrieve(q.query, from: notes, k: notes.count).map(\.id)
            let rank = ranked.firstIndex(where: { q.relevant.contains($0) }).map { $0 + 1 }
            if rank == 1 { hitAt1 += 1 }
            if let r = rank, r <= 3 { hitAt3 += 1 }
            if let r = rank { reciprocalRankSum += 1 / Double(r) }
            let qWords = Set(KeywordRetriever.words(q.query))
            let noteWords = Set(notes.filter { q.relevant.contains($0.id) }
                .flatMap { KeywordRetriever.words($0.title + " " + $0.text) })
            meanOverlap += qWords.isEmpty ? 0 : Double(qWords.intersection(noteWords).count) / Double(qWords.count) / Double(qs.count)
            rows.append(Row(queryID: q.id, rank: rank, top: Array(ranked.prefix(3))))
        }
    }

    enum CodingKeys: String, CodingKey { case queries, hitAt1, hitAt3, reciprocalRankSum, rows, meanReciprocalRank, meanOverlap }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(queries, forKey: .queries); try c.encode(hitAt1, forKey: .hitAt1)
        try c.encode(hitAt3, forKey: .hitAt3); try c.encode(reciprocalRankSum, forKey: .reciprocalRankSum)
        try c.encode(rows, forKey: .rows); try c.encode(meanReciprocalRank, forKey: .meanReciprocalRank)
        try c.encode(meanOverlap, forKey: .meanOverlap)
    }
}

struct RagRecord: Codable {
    let queryID: String
    let mode: String
    let notesGiven: [String]
    let answer: String?
    let error: String?
}

enum RagEval {
    /// oracle: the relevant note. distractor: the next question's relevant
    /// note - a real note, on the wrong topic. keyword / embedding: the top
    /// three notes from that retriever, as the app would send them.
    static func notes(for query: GrammarQuery, index: Int, all: [GrammarQuery], notes: [GrammarNote],
                      mode: String) -> [GrammarNote] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        switch mode {
        case "oracle": return query.relevant.prefix(1).compactMap { byID[$0] }
        case "distractor":
            let other = all[(index + 1) % all.count].relevant.first { !query.relevant.contains($0) }
                ?? all[(index + 2) % all.count].relevant[0]
            return [byID[other]!]
        case "embedding": return EmbeddingRetriever().retrieve(query.query, from: notes, k: 3)
        default: return KeywordRetriever().retrieve(query.query, from: notes, k: 3)
        }
    }

    static func run(queries: [GrammarQuery], notes: [GrammarNote], mode: String, to url: URL) async throws {
        let helper = GrammarHelper(model: SystemLanguageModel.default,
                                   options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256))
        for (i, q) in queries.enumerated() {
            let given = Self.notes(for: q, index: i, all: queries, notes: notes, mode: mode)
            var answer: String?, failure: String?
            do { answer = try await helper.answer(q.query, notes: given) } catch { failure = String(describing: error) }
            try JSONLines.append(RagRecord(queryID: q.id, mode: mode, notesGiven: given.map(\.id),
                                           answer: answer, error: failure), to: url)
        }
    }
}

/// Answers graded: right (contains what the relevant note says), and - for
/// the distractor - whether the answer followed the wrong note, declined, or
/// answered from the model's own knowledge.
struct RagReport: Codable {
    var answers = 0
    var failed = 0
    var right = 0
    var declined = 0
    var givenRelevant = 0
    var rightWhenGivenRelevant = 0
    var rightWithoutRelevant = 0
    var withoutRelevant = 0
    var examples: [String] = []

    static let declines = #"(?i)(do(es)? not (cover|answer|address|mention|include)|don't (cover|answer|address|mention)|not covered|no information|cannot answer|can't answer|not (address|mention)ed)"#

    init(queries: [GrammarQuery], records: [RagRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: queries.map { ($0.id, $0) })
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        for r in records {
            guard let q = byID[r.queryID] else { continue }
            answers += 1
            guard let a = r.answer else { failed += 1; continue }
            let isRight = q.answerMustContain.contains { fold(a).contains(fold($0)) }
            let isDecline = a.range(of: Self.declines, options: .regularExpression) != nil
            let hadRelevant = r.notesGiven.contains { q.relevant.contains($0) }
            if isRight { right += 1 }
            if isDecline { declined += 1 }
            if hadRelevant { givenRelevant += 1; if isRight { rightWhenGivenRelevant += 1 } }
            else {
                withoutRelevant += 1
                if isRight { rightWithoutRelevant += 1 }
                if examples.count < 8 { examples.append("\(q.id) [\(r.notesGiven.joined(separator: ","))]: \(a.prefix(160))") }
            }
        }
    }

    func print(title: String) {
        Swift.print("\n\(title): \(answers) answers, \(failed) failed; right \(right), declined \(declined)")
        Swift.print("  given the relevant note: \(givenRelevant), right \(rightWhenGivenRelevant)")
        Swift.print("  without it: \(withoutRelevant), right anyway \(rightWithoutRelevant)")
        for e in examples { Swift.print("  \(e)") }
    }
}

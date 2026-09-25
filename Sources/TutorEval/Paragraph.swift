import Foundation
import FoundationModels
import EvalKit
import TutorCore

/// Chapter 23: the eval written before the change.
struct ParagraphRecord: Codable {
    let sentences: Int
    let mode: String
    let input: String
    let corrected: String?
    let calls: Int
    let latencyMilliseconds: Int
    let error: String?
}

enum ParagraphEval {
    static let sizes = [1, 2, 4, 8, 16, 32, 64]

    static func paragraph(_ n: Int, from cases: [CorrectionCase]) -> [CorrectionCase] {
        (0..<n).map { cases[$0 % cases.count] }
    }

    /// whole: the shipped corrector, given the paragraph in one call (with its
    /// shipped 256-token cap). split: every sentence on its own. hybrid: the
    /// paragraph corrector as it ships - whole up to 8 sentences, split above.
    static func run(cases: [CorrectionCase], mode: String, to url: URL) async throws {
        let corrector = SentenceCorrector(model: SystemLanguageModel.default,
                                          options: GenerationOptions(samplingMode: .greedy))
        let clock = ContinuousClock()
        for n in sizes {
            let text = paragraph(n, from: cases).map(\.input).joined(separator: " ")
            let start = clock.now
            var corrected: String?, failure: String?, calls = 1
            do {
                if mode != "whole" {
                    // split: 0; hybrid: 8 (failed criteria v2 at 16 sentences);
                    // hybrid16: the next candidate, against the same criteria.
                    let limit = mode == "split" ? 0 : mode == "hybrid16" ? 16 : 8
                    let r = try await ParagraphCorrector(corrector: corrector, wholeUpTo: limit).correct(text)
                    corrected = r.corrected; calls = r.sentences.count
                } else {
                    corrected = try await corrector.correct(text).corrected
                }
            } catch { failure = String(describing: error) }
            let d = clock.now - start
            try JSONLines.append(ParagraphRecord(
                sentences: n, mode: mode, input: text, corrected: corrected, calls: calls,
                latencyMilliseconds: Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000),
                error: failure), to: url)
            FileHandle.standardError.write(Data("\r  \(mode) \(n)   ".utf8))
        }
    }
}

/// Every paragraph graded, and the criteria decided.
struct ParagraphReport: Codable {
    struct Row: Codable {
        let sentences: Int
        let charactersSent: Int
        let charactersReturned: Int
        let sentencesRight: Int
        /// What the single-sentence corrector gets right on the same sentences.
        let baselineRight: Int
        let milliseconds: Int
        let failed: Bool
    }
    var rows: [Row] = []
    var worstCharactersKept = 1.0
    var failedCalls = 0
    var sentencesRight = 0
    var baselineRight = 0
    var medianMillisecondsPerSentence = 0

    /// A sentence is right in a paragraph if one of its accepted answers (or,
    /// for a correct sentence, the sentence itself) appears in the output.
    init(cases: [CorrectionCase], records: [ParagraphRecord], singleSentenceRun: [CorrectionRecord]) {
        let single = CorrectionReport(cases: cases, records: singleSentenceRun.filter { $0.repetition == 0 }).verdicts
        let singleRight = Dictionary(single.map { ($0.caseID, $0.verdict == "pass") }, uniquingKeysWith: { a, _ in a })
        var perSentence: [Int] = []
        for r in records {
            let items = ParagraphEval.paragraph(r.sentences, from: cases)
            let out = TextComparison.normalized(r.corrected ?? "")
            let right = items.filter { item in
                (item.hasError ? item.accepted : [item.input]).contains { out.contains(TextComparison.normalized($0)) }
            }.count
            let base = items.filter { singleRight[$0.id] == true }.count
            let kept = r.input.isEmpty ? 1 : Double(r.corrected?.count ?? 0) / Double(r.input.count)
            worstCharactersKept = min(worstCharactersKept, kept)
            if r.error != nil { failedCalls += 1 }
            sentencesRight += right; baselineRight += base
            perSentence.append(r.latencyMilliseconds / max(1, r.sentences))
            rows.append(Row(sentences: r.sentences, charactersSent: r.input.count,
                            charactersReturned: r.corrected?.count ?? 0, sentencesRight: right,
                            baselineRight: base, milliseconds: r.latencyMilliseconds, failed: r.error != nil))
        }
        perSentence.sort()
        medianMillisecondsPerSentence = perSentence.isEmpty ? 0 : perSentence[perSentence.count / 2]
    }

    func print(title: String) {
        Swift.print("\n\(title)")
        Swift.print("sentences  sent  returned  right (single-sentence baseline)  ms")
        for r in rows {
            Swift.print(String(format: "%9d %5d %9d %6d (%d) %10d%@", r.sentences, r.charactersSent, r.charactersReturned,
                               r.sentencesRight, r.baselineRight, r.milliseconds, r.failed ? "  FAILED" : ""))
        }
        Swift.print(String(format: "worst characters kept %.0f%%, failed %d, right %d vs baseline %d, median ms per sentence %d",
                           worstCharactersKept * 100, failedCalls, sentencesRight, baselineRight, medianMillisecondsPerSentence))
    }
}

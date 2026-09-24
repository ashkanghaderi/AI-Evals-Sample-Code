import Foundation
import FoundationModels
import EvalKit

/// Knowledge or deference? The judge asked only whether the learner's sentence
/// is correct Spanish - no correction, no explanation, nothing from the app to
/// agree with. If a judge calls "La agua está fría." correct here too, its
/// Chapter 10 verdict was ignorance; if it now says "wrong", it was deference.
@Generable
struct BareVerdict: Codable, Sendable {
    @Guide(description: "whether the sentence contains any error in grammar, agreement, verb form, word choice, spelling, accents or punctuation, and which")
    var reasoning: String

    @Guide(description: "true only if the sentence is correct Spanish with no error")
    var sentenceIsCorrect: Bool
}

struct BareRecord: Codable {
    let caseID: String
    let input: String
    let judge: String
    let output: BareVerdict?
    let error: String?
    let latencyMilliseconds: Int
    let prompt: String
}

struct BareRequest: Codable {
    let caseID: String
    let input: String
    let instructions: String
    let request: String
    let prompt: String
}

enum BareJudge {
    static let promptVersion = "bare v1"
    static let instructions = """
        You are an expert teacher of Spanish. You are shown one sentence written \
        by a learner. Decide whether it is correct Spanish, with no error in \
        grammar, agreement, verb form, word choice, spelling, accents or \
        punctuation.
        """

    static func request(_ input: String) -> String { "Sentence: \(input)" }

    static func requests(cases: [CorrectionCase]) -> [BareRequest] {
        cases.map { BareRequest(caseID: $0.id, input: $0.input, instructions: instructions,
                                request: request($0.input), prompt: promptVersion) }
    }

    static func run(cases: [CorrectionCase], to url: URL) async throws {
        let options = GenerationOptions(samplingMode: .greedy)
        let clock = ContinuousClock()
        for item in cases {
            let session = LanguageModelSession(model: SystemLanguageModel.default,
                                               instructions: instructions)
            let start = clock.now
            var verdict: BareVerdict?
            var failure: String?
            do {
                verdict = try await session.respond(to: request(item.input),
                                                    generating: BareVerdict.self,
                                                    options: options).content
            } catch {
                failure = String(describing: error)
            }
            let elapsed = clock.now - start
            try JSONLines.append(BareRecord(
                caseID: item.id, input: item.input, judge: "on-device", output: verdict,
                error: failure,
                latencyMilliseconds: Int(elapsed.components.seconds * 1000
                    + elapsed.components.attoseconds / 1_000_000_000_000_000),
                prompt: promptVersion), to: url)
        }
    }
}

struct BareReport: Codable {
    struct Row: Codable {
        let caseID: String
        let hasError: Bool
        let saidCorrect: Bool?
        let reasoning: String?
    }
    var right = 0
    var total = 0
    var errorsFound = 0
    var errors = 0
    var controlsKept = 0
    var controls = 0
    /// Calls that returned nothing - counted, never read as either answer.
    var failed = 0
    var rows: [Row] = []

    init(cases: [CorrectionCase], records: [BareRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for record in records {
            guard let item = byID[record.caseID] else { continue }
            total += 1
            let said = record.output?.sentenceIsCorrect
            if said == nil { failed += 1 }
            rows.append(Row(caseID: item.id, hasError: item.hasError, saidCorrect: said,
                            reasoning: record.output?.reasoning))
            if item.hasError {
                errors += 1
                if said == false { errorsFound += 1; right += 1 }
            } else {
                controls += 1
                if said == true { controlsKept += 1; right += 1 }
            }
        }
    }

    func print(title: String) {
        Swift.print("\n\(title): \(right) of \(total) right; errors found \(errorsFound) of \(errors), correct sentences kept \(controlsKept) of \(controls), \(failed) failed")
        for row in rows where row.hasError && row.saidCorrect == true {
            Swift.print("  [\(row.caseID)] called correct: \(row.reasoning ?? "")")
        }
    }
}

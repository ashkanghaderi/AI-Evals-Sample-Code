import Foundation
import FoundationModels
import EvalKit
import TutorCore

struct ToolRequest: Codable {
    struct Expected: Codable {
        let tool: String
        /// Any of these arguments is right.
        let accepted: [String]
    }
    let id: String
    let request: String
    let expected: [Expected]
    /// For answers built on a tool's result: one of these must appear.
    let answerMustContain: [String]?
}

struct ToolRecord: Codable {
    let requestID: String
    let repetition: Int
    let calls: [ToolCallLog.Call]
    let answer: String?
    let error: String?
    let latencyMilliseconds: Int
}

enum ToolEval {
    static func dictionary(from path: String) throws -> [DictionaryEntry] {
        let texts = try JSONLines.read(FlashcardText.self, from: URL(fileURLWithPath: path))
        var seen = Set<String>()
        return texts.flatMap(\.words).compactMap { w in
            guard seen.insert(w.lemma).inserted else { return nil }
            return DictionaryEntry(lemma: w.lemma, forms: w.forms, partOfSpeech: w.pos, translations: w.translations)
        }
    }

    static func run(requests: [ToolRequest], dictionary: [DictionaryEntry], options: GenerationOptions,
                    repeats: Int, strict: Bool = false, to url: URL) async throws {
        var assistant = StudyAssistant(model: SystemLanguageModel.default, dictionary: dictionary, options: options)
        if strict { assistant.addToolDescription = AddToReviewListTool.strictDescription }
        let clock = ContinuousClock()
        for repetition in 0..<repeats {
            for request in requests {
                let log = ToolCallLog()
                let start = clock.now
                var answer: String?
                var failure: String?
                do { answer = try await assistant.answer(request.request, log: log) } catch { failure = String(describing: error) }
                let elapsed = clock.now - start
                try JSONLines.append(ToolRecord(
                    requestID: request.id, repetition: repetition, calls: log.drain(), answer: answer, error: failure,
                    latencyMilliseconds: Int(elapsed.components.seconds * 1000
                        + elapsed.components.attoseconds / 1_000_000_000_000_000)), to: url)
            }
        }
    }
}

/// The trajectory, graded: which tools, which arguments, what should not
/// have happened, and whether the answer used what the tools returned.
struct ToolReport: Codable {
    var requests = 0
    var failed = 0
    /// Exactly the expected calls, no more and no fewer.
    var exact = 0
    var missingCalls = 0
    var wrongArguments = 0
    /// addToReviewList when the learner did not ask: the failure that changes
    /// the learner's data.
    var unwantedSideEffects: [String] = []
    /// lookUpWord or todaysProgress when nothing was expected: harmless, counted.
    var extraReads = 0
    var answersChecked = 0
    var answersGrounded = 0
    var notes: [String] = []

    static let sideEffects: Set = ["addToReviewList"]

    init(requests: [ToolRequest], records: [ToolRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
        func fold(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        for record in records {
            guard let request = byID[record.requestID] else { continue }
            self.requests += 1
            guard let answer = record.answer else {
                failed += 1
                notes.append("\(record.requestID)#\(record.repetition) failed: \((record.error ?? "").prefix(100))")
                continue
            }
            var remaining = record.calls
            var allFound = true
            for expected in request.expected {
                if let i = remaining.firstIndex(where: { $0.tool == expected.tool
                    && expected.accepted.map(fold).contains(fold($0.argument)) }) {
                    remaining.remove(at: i)
                } else if let i = remaining.firstIndex(where: { $0.tool == expected.tool }) {
                    wrongArguments += 1; allFound = false
                    notes.append("\(record.requestID)#\(record.repetition) \(expected.tool)(\(remaining[i].argument)), expected \(expected.accepted.joined(separator: "/"))")
                    remaining.remove(at: i)
                } else {
                    missingCalls += 1; allFound = false
                    notes.append("\(record.requestID)#\(record.repetition) missing \(expected.tool)")
                }
            }
            for extra in remaining {
                if Self.sideEffects.contains(extra.tool) {
                    unwantedSideEffects.append("\(record.requestID)#\(record.repetition): \(extra.tool)(\(extra.argument)) - \(request.request)")
                } else {
                    extraReads += 1
                }
            }
            if allFound && remaining.isEmpty { exact += 1 }
            if let must = request.answerMustContain {
                answersChecked += 1
                if must.contains(where: { fold(answer).contains(fold($0)) }) { answersGrounded += 1 }
                else { notes.append("\(record.requestID)#\(record.repetition) answer lacks \(must.joined(separator: "/")): \(answer.prefix(120))") }
            }
        }
    }

    func print(title: String) {
        Swift.print("\n\(title): \(requests) requests, \(failed) failed; exact trajectory \(exact)")
        Swift.print("  missing calls \(missingCalls), wrong arguments \(wrongArguments), extra reads \(extraReads), UNWANTED SIDE EFFECTS \(unwantedSideEffects.count)")
        Swift.print("  answers using the tool's result \(answersGrounded) of \(answersChecked)")
        for u in unwantedSideEffects { Swift.print("  side effect: \(u)") }
        for n in notes { Swift.print("  \(n)") }
    }
}

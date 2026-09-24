import Foundation
import FoundationModels
import EvalKit
import TutorCore

/// A model's verdict on one explanation.
///
/// The reasoning comes first on purpose. Fields are generated in order, so a
/// verdict written after the reasoning can depend on it; a verdict written
/// first can only be justified afterwards.
@Generable
struct JudgeVerdict: Codable, Sendable {
    @Guide(description: "what the actual error in the learner's sentence is, if any, and whether the explanation identifies it")
    var reasoning: String

    @Guide(description: "true only if the explanation correctly identifies the error in the learner's sentence, or correctly says there is none")
    var explanationIsRight: Bool
}

/// One judged explanation, tied to the exact text it judged - like a label.
struct JudgeRecord: Codable {
    let caseID: String
    let input: String
    let corrected: String
    /// The corrector's own flag, so Chapter 8's checks can run on the record.
    let hasError: Bool
    let explanation: String
    /// "on-device" or "cloud".
    let judge: String
    let withReference: Bool
    /// True for the baseline: an explanation written for a different sentence.
    let mismatched: Bool
    let output: JudgeVerdict?
    let error: String?
    let latencyMilliseconds: Int
    let prompt: String
}

enum Judge {
    static let promptVersion = "judge v1"

    static let instructions = """
        You grade a Spanish tutoring app. You are shown a sentence written by a \
        learner, the app's corrected version, and the app's one-sentence \
        explanation. Decide whether the explanation is right. It is right only \
        if it identifies the actual error in the learner's sentence, or \
        correctly says there is none. An explanation that blames the wrong \
        word, invents an error, misses the error, contradicts the correction, \
        or is cut off is wrong. Judge the explanation, not the correction.
        """

    static func request(input: String, corrected: String, explanation: String,
                        reference: CorrectionCase?) -> String {
        var text = """
            Learner's sentence: \(input)
            App's correction: \(corrected)
            App's explanation: \(explanation)
            """
        if let reference {
            text += reference.hasError
                ? "\nA teacher's accepted corrections: " + reference.accepted.joined(separator: " | ")
                : "\nA teacher says this sentence has no error."
        }
        return text
    }

    /// What gets judged: repetition 0 of a correction run, plus - for the
    /// baseline - each error case's explanation moved onto the next error
    /// case's sentence, where it cannot be right.
    static func items(cases: [CorrectionCase], records: [CorrectionRecord], mismatched: Bool)
        -> [(CorrectionCase, Correction, Bool)] {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        let answered = records.filter { $0.repetition == 0 }.compactMap { r in
            r.output.flatMap { o in byID[r.caseID].map { ($0, o) } }
        }
        guard mismatched else { return answered.map { ($0.0, $0.1, false) } }
        let errors = answered.filter { $0.0.hasError && $0.1.hasError }
        return errors.indices.map { i in
            let (item, output) = errors[i]
            let other = errors[(i + 1) % errors.count].1
            return (item, Correction(hasError: output.hasError, corrected: output.corrected,
                                     explanation: other.explanation), true)
        }
    }

    static func run<Model: LanguageModel>(model: Model, name: String, cases: [CorrectionCase],
                                          records: [CorrectionRecord], withReference: Bool,
                                          mismatched: Bool, to url: URL) async throws {
        let options = GenerationOptions(samplingMode: .greedy)
        let clock = ContinuousClock()
        let work = items(cases: cases, records: records, mismatched: mismatched)
        for (index, (item, output, isMismatched)) in work.enumerated() {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let start = clock.now
            var verdict: JudgeVerdict?
            var failure: String?
            do {
                verdict = try await session.respond(
                    to: request(input: item.input, corrected: output.corrected,
                                explanation: output.explanation,
                                reference: withReference ? item : nil),
                    generating: JudgeVerdict.self, options: options).content
            } catch {
                failure = String(describing: error)
            }
            let elapsed = clock.now - start
            let ms = Int(elapsed.components.seconds * 1000
                         + elapsed.components.attoseconds / 1_000_000_000_000_000)
            try JSONLines.append(JudgeRecord(
                caseID: item.id, input: item.input, corrected: output.corrected,
                hasError: output.hasError, explanation: output.explanation, judge: name, withReference: withReference,
                mismatched: isMismatched, output: verdict, error: failure,
                latencyMilliseconds: ms, prompt: promptVersion), to: url)
            FileHandle.standardError.write(Data("\r  \(index + 1)/\(work.count)".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

/// A judge request with everything needed to send it anywhere. `judge-requests`
/// writes these so a judge outside Swift - Chapter 10's open model - is asked
/// exactly what the on-device judge was asked, from the same code.
struct JudgeRequest: Codable {
    let caseID: String
    let input: String
    let corrected: String
    let hasError: Bool
    let explanation: String
    let withReference: Bool
    let mismatched: Bool
    let instructions: String
    let request: String
    let prompt: String
}

extension Judge {
    static func requests(cases: [CorrectionCase], records: [CorrectionRecord],
                         withReference: Bool, mismatched: Bool) -> [JudgeRequest] {
        items(cases: cases, records: records, mismatched: mismatched).map { item, output, isMismatched in
            JudgeRequest(caseID: item.id, input: item.input, corrected: output.corrected,
                         hasError: output.hasError, explanation: output.explanation,
                         withReference: withReference, mismatched: isMismatched,
                         instructions: instructions,
                         request: request(input: item.input, corrected: output.corrected,
                                          explanation: output.explanation,
                                          reference: withReference ? item : nil),
                         prompt: promptVersion)
        }
    }
}

/// How far a judge agrees with the people who labelled the same explanations.
struct JudgeReport: Codable {
    struct Disagreement: Codable {
        let caseID: String
        let label: String
        let judgeSaidRight: Bool
        let explanation: String
        let reasoning: String
    }

    var judged = 0
    var failed = 0
    /// Among explanations labelled right or wrong (arguable left out).
    var agree = 0
    var decided = 0
    var wrongCaught = 0
    var wrong = 0
    var rightKept = 0
    var right = 0
    var kappa = 0.0
    /// How often the judge said "right", against how often the labels did.
    var judgeSaidRight = 0
    var labelSaidRight = 0
    /// Wrong explanations the judge accepted on answers that left the
    /// sentence unchanged: the judge agreeing with the corrector that there
    /// was nothing to fix. The same model, the same blind spot.
    var sharedBlindSpot = 0
    /// The judge together with Chapter 8's answer-free checks: an
    /// explanation is rejected if either rejects it.
    var combinedCaught = 0
    var combinedRightRejected = 0
    /// Baseline: explanations for another sentence, judged right.
    var mismatchedAccepted = 0
    var mismatched = 0
    var disagreements: [Disagreement] = []

    init(records: [JudgeRecord], labels: [ExplanationLabel]) {
        let labelFor = Dictionary(labels.map { ("\($0.caseID)|\($0.explanation)", $0.label) },
                                  uniquingKeysWith: { a, _ in a })
        var bothRight = 0, bothWrong = 0, judgeRight = 0, labelRight = 0
        for record in records {
            judged += 1
            guard let verdict = record.output else { failed += 1; continue }
            if record.mismatched {
                mismatched += 1
                if verdict.explanationIsRight { mismatchedAccepted += 1 }
                continue
            }
            guard let label = labelFor["\(record.caseID)|\(record.explanation)"],
                  label != "arguable" else { continue }
            decided += 1
            let labelSaysRight = label == "right"
            if labelSaysRight { right += 1; labelRight += 1 } else { wrong += 1 }
            if verdict.explanationIsRight { judgeRight += 1 }
            let unchanged = TextComparison.normalized(record.corrected)
                == TextComparison.normalized(record.input)
            if !labelSaysRight && verdict.explanationIsRight && unchanged { sharedBlindSpot += 1 }
            let checksFail = !ExplanationCheck.failures(
                input: record.input,
                output: Correction(hasError: record.hasError, corrected: record.corrected,
                                   explanation: record.explanation)).isEmpty
            let rejected = !verdict.explanationIsRight || checksFail
            if rejected && !labelSaysRight { combinedCaught += 1 }
            if rejected && labelSaysRight { combinedRightRejected += 1 }
            if labelSaysRight == verdict.explanationIsRight {
                agree += 1
                if labelSaysRight { rightKept += 1; bothRight += 1 } else { wrongCaught += 1; bothWrong += 1 }
            } else {
                disagreements.append(Disagreement(
                    caseID: record.caseID, label: label, judgeSaidRight: verdict.explanationIsRight,
                    explanation: record.explanation, reasoning: verdict.reasoning))
            }
        }
        // Cohen's kappa: agreement beyond what two raters with these same
        // rates of saying "right" would reach by chance.
        if decided > 0 {
            let n = Double(decided)
            let observed = Double(agree) / n
            let pJudge = Double(judgeRight) / n, pLabel = Double(labelRight) / n
            let chance = pJudge * pLabel + (1 - pJudge) * (1 - pLabel)
            kappa = chance < 1 ? (observed - chance) / (1 - chance) : 0
        }
        judgeSaidRight = judgeRight
        labelSaidRight = labelRight
    }

    func print(title: String) {
        Swift.print("\n\(title): \(judged) judged, \(failed) failed")
        if decided > 0 {
            Swift.print("  agrees with labels  \(agree) of \(decided)   kappa \(String(format: "%.2f", kappa))")
            Swift.print("  wrong ones caught   \(wrongCaught) of \(wrong)")
            Swift.print("  right ones kept     \(rightKept) of \(right)")
            Swift.print("  said right          \(judgeSaidRight) of \(decided) (labels: \(labelSaidRight))")
            Swift.print("  shared blind spot   \(sharedBlindSpot) wrong ones accepted where nothing was corrected")
            Swift.print("  with Chapter 8's checks: wrong caught \(combinedCaught) of \(wrong), right rejected \(combinedRightRejected)")
        }
        if mismatched > 0 {
            Swift.print("  baseline: explanations for another sentence accepted  \(mismatchedAccepted) of \(mismatched)")
        }
        for d in disagreements {
            Swift.print("  [\(d.caseID)] label \(d.label), judge said \(d.judgeSaidRight ? "right" : "wrong")")
            Swift.print("      \(d.explanation)")
            Swift.print("      judge: \(d.reasoning)")
        }
    }
}

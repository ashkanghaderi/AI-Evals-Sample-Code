import Foundation
import FoundationModels
import EvalKit
import TutorCore

// tutor-eval run   [--repeats N] [--sampling default|greedy|seed:N] [--limit N]
// tutor-eval grade <recorded-run.jsonl> [--json]
// tutor-eval plan  --rate 0.6 --half-width 0.1
// tutor-eval redaction [--strategy tagger|lowercase-first] [--json]
//
// `run` calls the model and records every output; `grade` reads a recording and
// grades it without calling anything. Run once, grade forever.

let arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

// Datasets are versioned, never edited. Changing expected answers in place would
// silently re-grade every earlier run against answers it was never judged by.
// A corrected dataset is a new file; old runs keep being graded by the version
// they were run against.
let casesURL = URL(fileURLWithPath: value("--cases") ?? "evals/correction/cases-v1.jsonl")
let cases = try JSONLines.read(CorrectionCase.self, from: casesURL)

switch arguments.first {
case "redaction":
    // The redactor is a model too, and gets an eval of its own. No language
    // model is called and nothing is random, so there is no recording: the
    // result is a pure function of the dataset and the redactor.
    let url = URL(fileURLWithPath: value("--redaction-cases") ?? "evals/redaction/cases-v1.jsonl")
    let redactionCases = try JSONLines.read(RedactionCase.self, from: url)
    let strategy = Redactor.Strategy(rawValue: value("--strategy") ?? "tagger") ?? .tagger
    let report = RedactionReport(cases: redactionCases, redactor: Redactor(strategy: strategy))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "plan":
    // How many independent cases a dataset needs to measure an expected rate
    // to within plus or minus a half-width. Cases, not calls: repeating a case
    // does not add an independent observation.
    let rate = Double(value("--rate") ?? "0.6") ?? 0.6
    let width = Double(value("--half-width") ?? "0.1") ?? 0.1
    if let n = SampleSize.needed(expectedRate: rate, halfWidth: width) {
        print("\(n) cases to measure \(Int(rate * 100))% to within ±\(Int((width * 100).rounded())) points")
    } else {
        print("more than 100,000 cases")
    }

case "grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval grade <run.jsonl>") }
    let url = URL(fileURLWithPath: arguments[1])
    let records = try JSONLines.read(CorrectionRecord.self, from: url)
    let first = records.first
    let report = CorrectionReport(cases: cases, records: records)
    if arguments.contains("--json") {
        print(try report.json(model: first?.model ?? "?", sampling: first?.sampling ?? "?"))
    } else {
        report.print(model: first?.model ?? "?", sampling: first?.sampling ?? "?")
    }

case "run":
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
        print("The on-device model is not available: \(model.availability)")
        print("Enable Apple Intelligence in System Settings and try again.")
        exit(1)
    }

    let repeats = Int(value("--repeats") ?? "1") ?? 1
    let limit = Int(value("--limit") ?? "") ?? cases.count
    let samplingName = value("--sampling") ?? "default"
    let options: GenerationOptions = switch samplingName {
    case "greedy":
        GenerationOptions(samplingMode: .greedy)
    case let s where s.hasPrefix("seed:"):
        GenerationOptions(samplingMode: .random(top: 50, seed: UInt64(s.dropFirst(5)) ?? 0))
    default:
        GenerationOptions()
    }

    let corrector = SentenceCorrector(model: model, options: options)
    let stamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "")
    let out = URL(fileURLWithPath: value("--out")
        ?? "evals/correction/runs/\(stamp)-on-device-\(samplingName.replacingOccurrences(of: ":", with: "-")).jsonl")

    let selected = Array(cases.prefix(limit))
    let total = selected.count * repeats
    var done = 0
    var records: [CorrectionRecord] = []
    let clock = ContinuousClock()

    for repetition in 0..<repeats {
        for item in selected {
            let start = clock.now
            var output: Correction?
            var failure: String?
            do {
                output = try await corrector.correct(item.input)
            } catch {
                failure = String(describing: error)
            }
            let elapsed = clock.now - start
            let ms = Int(elapsed.components.seconds * 1000
                         + elapsed.components.attoseconds / 1_000_000_000_000_000)
            let record = CorrectionRecord(
                caseID: item.id, repetition: repetition, output: output, error: failure,
                latencyMilliseconds: ms, model: "apple-on-device", sampling: samplingName)
            try JSONLines.append(record, to: out)
            records.append(record)
            done += 1
            FileHandle.standardError.write(Data("\r  \(done)/\(total)".utf8))
        }
    }
    FileHandle.standardError.write(Data("\n".utf8))
    print("recorded \(records.count) calls to \(out.path)")
    CorrectionReport(cases: cases, records: records).print(model: "apple-on-device",
                                                           sampling: samplingName)

default:
    print("usage: tutor-eval run [--repeats N] [--sampling default|greedy|seed:N] [--limit N]")
    print("       tutor-eval grade <run.jsonl>")
    exit(2)
}

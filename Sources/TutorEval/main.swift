import Foundation
import FoundationModels
import EvalKit
import TutorCore

// tutor-eval run   [--repeats N] [--sampling default|greedy|seed:N] [--limit N] [--explain-in German]
// tutor-eval languages [--check fa,de]
// tutor-eval quotes <english-run.jsonl> <translated-run.jsonl> [--json]
// tutor-eval judge-run --source <run.jsonl> --judge on-device|cloud [--reference] [--mismatched] --out <file>
// tutor-eval judge-requests --source <run.jsonl> [--reference] [--mismatched]   (JSON lines to stdout)
// tutor-eval bare-run --out <file> | bare-requests | bare-grade <file> [--json]
// tutor-eval review-packet --source <run.jsonl> --out review/packet.html
// tutor-eval review-compare <tutor-review.json> --source <run.jsonl> [--json]
// tutor-eval compare <runA.jsonl> <runB.jsonl> [--rep-a N] [--rep-b N] [--json]
// tutor-eval perf --out <file> [--repeats N] [--sampling greedy|seed:N] [--max-tokens N] [--prewarm] [--only ID] [--long N]
// tutor-eval perf-report <file> [--json] | perf-grade <file> [--json] | perf-diff <a> <b> [--json]
// tutor-eval flashcards-run --schema constrained|prose --out <file> [--sampling greedy|default] [--repeats N]
// tutor-eval flashcards-grade <file> [--json]
// tutor-eval conversation-run --scripts <file> --out <file> [--sampling greedy|default] [--repeats N]
// tutor-eval conversation-grade <file> --scripts <file> [--json]
// tutor-eval tools-run --out <file> [--sampling greedy|default] [--repeats N] [--variant strict]
// tutor-eval tools-grade <file> [--json]
// tutor-eval retrieval-eval --retriever keyword|embedding [--queries <file>] [--json]
// tutor-eval rag-run --mode oracle|distractor|keyword|embedding --out <file> [--queries <file>]
// tutor-eval rag-grade <file> [--queries <file>] [--json]
// tutor-eval inject-run --surface direct|notes|tool --out <file> [--sampling greedy|default] [--repeats N] [--variant hardened]
// tutor-eval inject-grade <file> [--json]
// tutor-eval refusal-run --guardrails default|permissive --feature corrector|conversation|translate --out <file> [--sampling greedy|default] [--repeats N]
// tutor-eval refusal-grade <file> [--json]
// tutor-eval paragraph-run --mode whole|split --out <file>
// tutor-eval paragraph-grade <file> [--json]
// tutor-eval voice-status | voice-install | voice-run --out <file> | voice-grade <file> [--json]
// tutor-eval model-info [--json]
// tutor-eval drift <baseline-run.jsonl> <current-run.jsonl> [--json]   (exits 1 on any change)
// tutor-eval agreement <judge-run.jsonl> [<second-judge-run.jsonl>] [--json]
// tutor-eval judge-grade <judge-run.jsonl> [--labels ...] [--json]
// tutor-eval fuzzy <run.jsonl> [--json]
// tutor-eval budget <run.jsonl> [--slack 1] [--json]
// tutor-eval checks <run.jsonl> [--labels evals/correction/explanation-labels-v1.jsonl] [--first] [--json]
// tutor-eval grade <recorded-run.jsonl> [--json]
// tutor-eval plan  --rate 0.6 --half-width 0.1
// tutor-eval redaction [--strategy tagger|lowercase-first] [--json]
// tutor-eval audit [--against evals/correction/cases-v1.jsonl]   (audits --cases)
// tutor-eval perturb --out evals/correction/perturbed-v2.jsonl [--naive]  (from --cases)
// tutor-eval synthesize --count 30 --seed 1000 --out evals/correction/synthetic-v1.jsonl
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
case "languages":
    // What the on-device model says it supports, as the API reports it on
    // this machine and OS. Check this before writing a dataset in a language.
    let model = SystemLanguageModel.default
    let names = model.supportedLanguages.map { language -> String in
        let code = language.minimalIdentifier
        let name = Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
        return "\(name) (\(code))"
    }.sorted()
    print("\(names.count) languages:")
    for name in names { print("  \(name)") }
    for code in (value("--check") ?? "").split(separator: ",") {
        let supported = model.supportsLocale(Locale(identifier: String(code)))
        print("supportsLocale(\(code)): \(supported)")
    }

case "judge-run":
    guard let source = value("--source"), let path = value("--out") else {
        fatalError("judge-run needs --source and --out")
    }
    let out = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: out.path) else {
        fatalError("\(path) exists; recordings are never overwritten")
    }
    let records = try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: source))
    let withReference = arguments.contains("--reference")
    let mismatched = arguments.contains("--mismatched")
    switch value("--judge") ?? "on-device" {
    case "cloud":
        // Apple's Private Cloud Compute model: larger, free, and limited by a
        // quota. The sentences leave the device - fine for a test set with no
        // personal data in it, and a decision to make again for anything else.
        let model = PrivateCloudComputeLanguageModel()
        guard case .available = model.availability else {
            print("Private Cloud Compute is not available: \(model.availability)")
            exit(1)
        }
        if model.quotaUsage.isLimitReached { print("Quota reached; try after \(String(describing: model.quotaUsage.resetDate))"); exit(1) }
        try await Judge.run(model: model, name: "cloud", cases: cases, records: records,
                            withReference: withReference, mismatched: mismatched, to: out)
    default:
        try await Judge.run(model: SystemLanguageModel.default, name: "on-device", cases: cases,
                            records: records, withReference: withReference,
                            mismatched: mismatched, to: out)
    }
    print("recorded \(path)")

case "judge-requests":
    guard let source = value("--source") else { fatalError("judge-requests needs --source") }
    let records = try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: source))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for request in Judge.requests(cases: cases, records: records,
                                  withReference: arguments.contains("--reference"),
                                  mismatched: arguments.contains("--mismatched")) {
        print(String(decoding: try encoder.encode(request), as: UTF8.self))
    }

case "bare-run":
    guard let path = value("--out") else { fatalError("bare-run needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    try await BareJudge.run(cases: cases, to: URL(fileURLWithPath: path))
    print("recorded \(path)")

case "bare-requests":
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for request in BareJudge.requests(cases: cases) {
        print(String(decoding: try encoder.encode(request), as: UTF8.self))
    }

case "bare-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval bare-grade <file>") }
    let report = BareReport(cases: cases, records: try JSONLines.read(
        BareRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
    }

case "review-packet":
    guard let source = value("--source"), let path = value("--out") else {
        fatalError("review-packet needs --source and --out")
    }
    // The explanations to label: repetition 0 of the run, as the labels were.
    let records = try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: source))
    let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
    let explanations = records.filter { $0.repetition == 0 }.compactMap { r -> (String, String, String, String)? in
        guard let o = r.output, let item = byID[r.caseID] else { return nil }
        return (r.caseID, item.input, o.corrected, o.explanation)
    }
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try ReviewPacket.html(cases: cases, explanations: explanations).write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(path): \(cases.count) sentences, \(explanations.count) explanations")

case "review-compare":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval review-compare <tutor-review.json>") }
    let review = try JSONDecoder().decode(ReviewFile.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    let labels = try JSONLines.read(ExplanationLabel.self, from: URL(fileURLWithPath:
        value("--labels") ?? "evals/correction/explanation-labels-v1.jsonl"))
    // The explanations' packet order, for opaque ids: repetition 0 of the
    // run the packet was built from.
    let explanationCases = try value("--source").map { source in
        try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: source))
            .filter { $0.repetition == 0 && $0.output != nil }.map(\.caseID)
    } ?? []
    let comparison = ReviewComparison(review: review, cases: cases, labels: labels,
                                      explanationCases: explanationCases)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(comparison), as: UTF8.self))
    } else {
        comparison.print()
    }

case "compare":
    let paths = arguments.dropFirst().filter { !$0.hasPrefix("--") && !$0.allSatisfy(\.isNumber) }
    guard paths.count == 2 else { fatalError("usage: tutor-eval compare <runA> <runB>") }
    func load(_ path: String, rep: String?) throws -> [CorrectionRecord] {
        let all = try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: path))
        guard let rep, let n = Int(rep) else { return all }
        return all.filter { $0.repetition == n }
    }
    let comparison = RunComparison(
        cases: cases,
        a: try load(paths[paths.startIndex], rep: value("--rep-a")),
        b: try load(paths[paths.startIndex + 1], rep: value("--rep-b")))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(comparison), as: UTF8.self))
    } else {
        comparison.print()
    }

case "perf":
    guard let path = value("--out") else { fatalError("perf needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    let sampling = value("--sampling") ?? "greedy"
    let options: GenerationOptions = sampling.hasPrefix("seed:")
        ? GenerationOptions(samplingMode: .random(top: 50, seed: UInt64(sampling.dropFirst(5)) ?? 0))
        : GenerationOptions(samplingMode: .greedy)
    let maxTokens = value("--max-tokens").flatMap(Int.init)
    let configuration = [sampling, maxTokens.map { "max-tokens:\($0)" }, arguments.contains("--prewarm") ? "prewarm" : nil,
                         value("--long").map { "long:\($0)" }].compactMap { $0 }.joined(separator: " ")
    try await Performance.run(cases: cases, repeats: Int(value("--repeats") ?? "1") ?? 1, options: options,
                              maximumResponseTokens: maxTokens, prewarm: arguments.contains("--prewarm"),
                              only: value("--only"), long: Int(value("--long") ?? "0") ?? 0,
                              configuration: configuration, to: URL(fileURLWithPath: path))
    print("recorded \(path) (\(configuration))")

case "perf-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval perf-grade <file>") }
    let records = try JSONLines.read(PerfRecord.self, from: URL(fileURLWithPath: arguments[1])).map(\.asRunRecord)
    let report = CorrectionReport(cases: cases, records: records)
    if arguments.contains("--json") {
        print(try report.json(model: "apple-on-device", sampling: records.first?.sampling ?? "?"))
    } else {
        report.print(model: "apple-on-device", sampling: records.first?.sampling ?? "?")
    }

case "perf-diff":
    let paths = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard paths.count == 2 else { fatalError("usage: tutor-eval perf-diff <a> <b>") }
    let diff = PerfDiff(try JSONLines.read(PerfRecord.self, from: URL(fileURLWithPath: paths[paths.startIndex])),
                        try JSONLines.read(PerfRecord.self, from: URL(fileURLWithPath: paths[paths.startIndex + 1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(diff), as: UTF8.self))
    } else {
        print("\(diff.sameDecision) of \(diff.compared) same decision, \(diff.sameAnswer) same answer; changed: \(diff.changed.joined(separator: ", "))")
    }

case "perf-report":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval perf-report <file>") }
    let report = PerfReport(try JSONLines.read(PerfRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
    }

case "flashcards-run", "flashcards-grade":
    let texts = try JSONLines.read(FlashcardText.self, from: URL(fileURLWithPath:
        value("--texts") ?? "evals/flashcards/texts-v1.jsonl"))
    if arguments.first == "flashcards-run" {
        guard let path = value("--out") else { fatalError("flashcards-run needs --out") }
        guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
        let options = value("--sampling") == "default" ? GenerationOptions() : GenerationOptions(samplingMode: .greedy)
        try await FlashcardEval.run(texts: texts, schema: value("--schema") ?? "constrained", options: options,
                                    repeats: Int(value("--repeats") ?? "1") ?? 1, to: URL(fileURLWithPath: path))
        print("recorded \(path)")
    } else {
        guard arguments.count > 1 else { fatalError("usage: tutor-eval flashcards-grade <file>") }
        let report = FlashcardReport(texts: texts, records: try JSONLines.read(
            FlashcardRecord.self, from: URL(fileURLWithPath: arguments[1])))
        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
        }
    }

case "conversation-run", "conversation-grade":
    let scripts = try JSONLines.read(ConversationScript.self, from: URL(fileURLWithPath:
        value("--scripts") ?? "evals/conversation/scripts-v1.jsonl"))
    if arguments.first == "conversation-run" {
        guard let path = value("--out") else { fatalError("conversation-run needs --out") }
        guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
        let options = value("--sampling") == "default"
            ? GenerationOptions(maximumResponseTokens: 200)
            : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200)
        try await ConversationEval.run(scripts: scripts, options: options,
                                       repeats: Int(value("--repeats") ?? "1") ?? 1, to: URL(fileURLWithPath: path))
        print("recorded \(path)")
    } else {
        guard arguments.count > 1 else { fatalError("usage: tutor-eval conversation-grade <file>") }
        let report = ConversationReport(scripts: scripts, records: try JSONLines.read(
            ConversationRecord.self, from: URL(fileURLWithPath: arguments[1])))
        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
        }
    }

case "tools-run", "tools-grade":
    let requests = try JSONLines.read(ToolRequest.self, from: URL(fileURLWithPath:
        value("--requests") ?? "evals/tools/requests-v1.jsonl"))
    if arguments.first == "tools-run" {
        guard let path = value("--out") else { fatalError("tools-run needs --out") }
        guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
        let options = value("--sampling") == "default"
            ? GenerationOptions(maximumResponseTokens: 256)
            : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)
        try await ToolEval.run(requests: requests,
                               dictionary: try ToolEval.dictionary(from: "evals/flashcards/texts-v1.jsonl"),
                               options: options, repeats: Int(value("--repeats") ?? "1") ?? 1,
                               strict: value("--variant") == "strict", to: URL(fileURLWithPath: path))
        print("recorded \(path)")
    } else {
        guard arguments.count > 1 else { fatalError("usage: tutor-eval tools-grade <file>") }
        let report = ToolReport(requests: requests, records: try JSONLines.read(
            ToolRecord.self, from: URL(fileURLWithPath: arguments[1])))
        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
        }
    }

case "retrieval-eval", "rag-run", "rag-grade":
    let notes = try JSONLines.read(GrammarNote.self, from: URL(fileURLWithPath: "evals/retrieval/notes-v1.jsonl"))
    let queries = try JSONLines.read(GrammarQuery.self, from: URL(fileURLWithPath:
        value("--queries") ?? "evals/retrieval/queries-v1.jsonl"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    switch arguments.first {
    case "retrieval-eval":
        let retriever: any NoteRetriever = value("--retriever") == "embedding" ? EmbeddingRetriever() : KeywordRetriever()
        let report = RetrievalReport(retriever: retriever, notes: notes, queries: queries)
        if arguments.contains("--json") { print(String(decoding: try encoder.encode(report), as: UTF8.self)) }
        else {
            print(String(format: "%d queries: right note first %d, in the top three %d, MRR %.2f; keyword overlap with the note %.0f%%",
                         report.queries, report.hitAt1, report.hitAt3, report.meanReciprocalRank, report.meanOverlap * 100))
            for row in report.rows where row.rank != 1 {
                print("  \(row.queryID): rank \(row.rank.map(String.init) ?? "-"), top \(row.top.joined(separator: ", "))")
            }
        }
    case "rag-run":
        guard let path = value("--out") else { fatalError("rag-run needs --out") }
        guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
        try await RagEval.run(queries: queries, notes: notes, mode: value("--mode") ?? "keyword",
                              to: URL(fileURLWithPath: path))
        print("recorded \(path)")
    default:
        guard arguments.count > 1 else { fatalError("usage: tutor-eval rag-grade <file>") }
        let report = RagReport(queries: queries, records: try JSONLines.read(RagRecord.self, from: URL(fileURLWithPath: arguments[1])))
        if arguments.contains("--json") { print(String(decoding: try encoder.encode(report), as: UTF8.self)) }
        else { report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent) }
    }

case "inject-run":
    guard let path = value("--out") else { fatalError("inject-run needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    let options = value("--sampling") == "default"
        ? GenerationOptions(maximumResponseTokens: 256)
        : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)
    try await InjectionEval.run(surface: value("--surface") ?? "direct", options: options,
                                repeats: Int(value("--repeats") ?? "1") ?? 1,
                                hardened: value("--variant") == "hardened", to: URL(fileURLWithPath: path))
    print("recorded \(path)")

case "inject-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval inject-grade <file>") }
    let report = InjectionReport(records: try JSONLines.read(InjectionRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
    }

case "refusal-run":
    guard let path = value("--out") else { fatalError("refusal-run needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    let sentences = try JSONLines.read(BenignSentence.self, from: URL(fileURLWithPath:
        value("--sentences") ?? "evals/refusal/benign-v1.jsonl"))
    let options = value("--sampling") == "default" ? GenerationOptions() : GenerationOptions(samplingMode: .greedy)
    try await RefusalEval.run(sentences: sentences, guardrails: value("--guardrails") ?? "default",
                              feature: value("--feature") ?? "corrector", options: options,
                              repeats: Int(value("--repeats") ?? "1") ?? 1, to: URL(fileURLWithPath: path))
    print("recorded \(path)")

case "refusal-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval refusal-grade <file>") }
    let report = RefusalReport(records: try JSONLines.read(RefusalRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else { report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent) }

case "paragraph-run":
    guard let path = value("--out") else { fatalError("paragraph-run needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    try await ParagraphEval.run(cases: cases, mode: value("--mode") ?? "whole", to: URL(fileURLWithPath: path))
    print("recorded \(path)")

case "paragraph-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval paragraph-grade <file>") }
    let report = ParagraphReport(
        cases: cases,
        records: try JSONLines.read(ParagraphRecord.self, from: URL(fileURLWithPath: arguments[1])),
        singleSentenceRun: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath:
            "evals/correction/runs/2026-09-25-greedy-cap256.jsonl")))
    if arguments.contains("--json") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else { report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent) }

case "voice-status":
    print(await VoiceEval.status())

case "voice-run":
    guard let path = value("--out") else { fatalError("voice-run needs --out") }
    guard !FileManager.default.fileExists(atPath: path) else { fatalError("\(path) exists") }
    try await VoiceEval.run(cases: cases, to: URL(fileURLWithPath: path))
    print("recorded \(path)")

case "voice-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval voice-grade <file>") }
    let report = VoiceReport(cases: cases, records: try JSONLines.read(VoiceRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else { report.print() }

case "voice-install":
    print(try await VoiceEval.install())

case "drift":
    let paths = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard paths.count == 2 else { fatalError("usage: tutor-eval drift <baseline> <current>") }
    let report = DriftReport(
        baseline: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: paths[paths.startIndex])),
        current: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: paths[paths.startIndex + 1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
        exit(report.drifted ? 1 : 0)
    }

case "model-info":
    let info = ModelInfo()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(info), as: UTF8.self))

case "agreement":
    let paths = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard let firstPath = paths.first else { fatalError("usage: tutor-eval agreement <judge-run>") }
    let labels = try JSONLines.read(ExplanationLabel.self, from: URL(fileURLWithPath:
        value("--labels") ?? "evals/correction/explanation-labels-v1.jsonl"))
    let first = try JSONLines.read(JudgeRecord.self, from: URL(fileURLWithPath: firstPath))
    let second = try paths.dropFirst().first.map {
        try JSONLines.read(JudgeRecord.self, from: URL(fileURLWithPath: $0))
    }
    let report = AgreementReport(first: first, second: second, labels: labels)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "judge-grade":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval judge-grade <judge-run.jsonl>") }
    let records = try JSONLines.read(JudgeRecord.self, from: URL(fileURLWithPath: arguments[1]))
    let labels = try JSONLines.read(ExplanationLabel.self, from: URL(fileURLWithPath:
        value("--labels") ?? "evals/correction/explanation-labels-v1.jsonl"))
    let report = JudgeReport(records: records, labels: labels)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print(title: URL(fileURLWithPath: arguments[1]).lastPathComponent)
    }

case "budget":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval budget <run.jsonl>") }
    let report = EditBudgetReport(
        cases: cases,
        records: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: arguments[1])),
        slack: Int(value("--slack") ?? "1") ?? 1)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "fuzzy":
    guard arguments.count > 1 else { fatalError("usage: tutor-eval fuzzy <run.jsonl>") }
    let report = FuzzyReport(
        cases: cases,
        records: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: arguments[1])))
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "checks":
    // Answer-free checks on every recorded answer, and - given labels - how
    // often each one is right when it fires.
    guard arguments.count > 1 else { fatalError("usage: tutor-eval checks <run.jsonl>") }
    // --first: repetition 0 only, so a greedy run's identical repeats are
    // not counted three times.
    let records = try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: arguments[1]))
        .filter { !arguments.contains("--first") || $0.repetition == 0 }
    let labels = try value("--labels").map {
        try JSONLines.read(ExplanationLabel.self, from: URL(fileURLWithPath: $0))
    } ?? []
    let report = CheckReport(cases: cases, records: records, labels: labels)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "quotes":
    guard arguments.count > 2 else { fatalError("usage: tutor-eval quotes <english> <translated>") }
    let report = QuoteReport(
        source: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: arguments[1])),
        translated: try JSONLines.read(CorrectionRecord.self, from: URL(fileURLWithPath: arguments[2])),
        cases: cases)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        report.print()
    }

case "synthesize":
    // The model writes its own test cases. Chapter 6 grades the corrector on
    // them and on the hand-written set, side by side, to see what they are worth.
    guard let path = value("--out") else { fatalError("synthesize needs --out") }
    let url = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: url.path) else {
        fatalError("\(path) exists; datasets are never overwritten")
    }
    try await Synthesizer.generate(count: Int(value("--count") ?? "30") ?? 30,
                                   firstSeed: UInt64(value("--seed") ?? "1000") ?? 1000,
                                   to: url)
    print("wrote \(path)")

case "audit":
    // Checks a dataset without grading anything. Exits non-zero on any
    // problem, so it can guard a dataset the way tests guard code.
    // A dataset always overlaps itself; auditing against itself checks nothing.
    let againstURL = value("--against").map { URL(fileURLWithPath: $0).standardizedFileURL }
    let other = try againstURL.flatMap { $0 == casesURL.standardizedFileURL ? nil : $0 }
        .map { try JSONLines.read(CorrectionCase.self, from: $0) } ?? []
    let audit = DatasetAudit(cases, against: other)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(audit), as: UTF8.self))
    } else {
        audit.print()
    }
    exit(audit.problems.isEmpty ? 0 : 1)

case "perturb":
    guard let path = value("--out") else { fatalError("perturb needs --out") }
    let url = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: url.path) else {
        fatalError("\(path) exists; datasets are never overwritten")
    }
    let made = Perturbation.cases(from: cases, naive: arguments.contains("--naive"))
    for item in made { try JSONLines.append(item, to: url) }
    print("wrote \(made.count) cases to \(path)")

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
    // --use-case contentTagging: the same framework and OS, a differently
    // specialised model - Chapter 14's stand-in for "the model changed".
    let useCase = value("--use-case") ?? "general"
    let model = useCase == "contentTagging" ? SystemLanguageModel(useCase: .contentTagging) : .default
    let modelName = useCase == "general" ? "apple-on-device" : "apple-on-device \(useCase)"
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

    let corrector = SentenceCorrector(model: model, options: options,
                                      explanationLanguage: value("--explain-in") ?? "English")
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
                latencyMilliseconds: ms, model: modelName, sampling: samplingName,
                prompt: corrector.promptVersion)
            try JSONLines.append(record, to: out)
            records.append(record)
            done += 1
            FileHandle.standardError.write(Data("\r  \(done)/\(total)".utf8))
        }
    }
    FileHandle.standardError.write(Data("\n".utf8))
    print("recorded \(records.count) calls to \(out.path)")
    CorrectionReport(cases: cases, records: records).print(model: modelName,
                                                           sampling: samplingName)

default:
    print("usage: tutor-eval run [--repeats N] [--sampling default|greedy|seed:N] [--limit N]")
    print("       tutor-eval grade <run.jsonl>")
    exit(2)
}

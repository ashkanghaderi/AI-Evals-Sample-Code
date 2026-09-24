import Foundation
import FoundationModels
import EvalKit
import TutorCore

/// What an answer costs - Chapter 13.
///
/// Latency, tokens in and out, and failures, per call, recorded like any other
/// run. Energy is not here: measuring it on a Mac needs administrator access
/// to `powermetrics`, and on a phone it needs Instruments. Tokens generated
/// and seconds of work are the proxies this eval can record honestly.
struct PerfRecord: Codable {
    let caseID: String
    let repetition: Int
    /// Position of the call in its process: call 0 pays for loading the model.
    let index: Int
    let configuration: String
    let inputCharacters: Int
    let latencyMilliseconds: Int
    let inputTokens: Int?
    let cachedTokens: Int?
    let outputTokens: Int?
    /// The answer, kept so a cap or a prewarm can be shown not to change it.
    let output: Correction?
    let error: String?
}

enum Performance {
    /// `long` > 0 replaces each input with that many golden-set sentences run
    /// together, as a learner pasting a paragraph would send them.
    static func run(cases: [CorrectionCase], repeats: Int, options: GenerationOptions,
                    maximumResponseTokens: Int?, prewarm: Bool, only: String?, long: Int,
                    configuration: String, to url: URL) async throws {
        var options = options
        options.maximumResponseTokens = maximumResponseTokens
        let corrector = SentenceCorrector(model: SystemLanguageModel.default, options: options)
        let selected = only.map { id in cases.filter { $0.id == id } } ?? cases
        let inputs: [(String, String)] = long > 0
            ? (1...long).map { n in
                ("long-\(n)", (0..<n).map { cases[$0 % cases.count].input }.joined(separator: " "))
              }.suffix(1).map { $0 }
            : selected.map { ($0.id, $0.input) }
        var index = 0
        for repetition in 0..<repeats {
            for (id, text) in inputs {
                let clock = ContinuousClock()
                let start = clock.now
                var record: PerfRecord
                do {
                    let m = try await corrector.measure(text, prewarm: prewarm)
                    record = PerfRecord(caseID: id, repetition: repetition, index: index,
                                        configuration: configuration, inputCharacters: text.count,
                                        latencyMilliseconds: m.milliseconds, inputTokens: m.inputTokens,
                                        cachedTokens: m.cachedTokens, outputTokens: m.outputTokens,
                                        output: m.correction, error: nil)
                } catch {
                    let elapsed = clock.now - start
                    record = PerfRecord(caseID: id, repetition: repetition, index: index,
                                        configuration: configuration, inputCharacters: text.count,
                                        latencyMilliseconds: Int(elapsed.components.seconds * 1000
                                            + elapsed.components.attoseconds / 1_000_000_000_000_000),
                                        inputTokens: nil, cachedTokens: nil, outputTokens: nil,
                                        output: nil, error: String(describing: error))
                }
                try JSONLines.append(record, to: url)
                index += 1
                FileHandle.standardError.write(Data("\r  \(index)".utf8))
            }
        }
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

struct PerfReport: Codable {
    var calls = 0
    var failed = 0
    var failures: [String] = []
    var medianMs = 0
    var p90Ms = 0
    var maxMs = 0
    var firstCallMs = 0
    var medianOutputTokens = 0
    var maxOutputTokens = 0
    var medianInputTokens = 0
    var medianCachedTokens = 0
    /// Output tokens per second of latency, median over calls.
    var medianTokensPerSecond = 0.0
    var totalSeconds = 0.0
    /// Characters sent, and characters of correction returned, summed: a
    /// correction far shorter than its input has dropped the learner's text.
    var inputCharacters = 0
    var returnedCharacters = 0

    init(_ records: [PerfRecord]) {
        calls = records.count
        inputCharacters = records.map(\.inputCharacters).reduce(0, +)
        returnedCharacters = records.compactMap { $0.output?.corrected.count }.reduce(0, +)
        let ok = records.filter { $0.error == nil }
        failed = calls - ok.count
        failures = records.filter { $0.error != nil }.map { "\($0.caseID): \($0.error!.prefix(160))" }
        func median(_ v: [Int]) -> Int { v.isEmpty ? 0 : v.sorted()[v.count / 2] }
        let latencies = records.map(\.latencyMilliseconds).sorted()
        medianMs = median(latencies)
        p90Ms = latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, latencies.count * 9 / 10)]
        maxMs = latencies.last ?? 0
        firstCallMs = records.first { $0.index == 0 }?.latencyMilliseconds ?? 0
        medianOutputTokens = median(ok.compactMap(\.outputTokens))
        maxOutputTokens = ok.compactMap(\.outputTokens).max() ?? 0
        medianInputTokens = median(ok.compactMap(\.inputTokens))
        medianCachedTokens = median(ok.compactMap(\.cachedTokens))
        let rates = ok.compactMap { r in r.outputTokens.map { Double($0) / max(0.001, Double(r.latencyMilliseconds) / 1000) } }.sorted()
        medianTokensPerSecond = rates.isEmpty ? 0 : rates[rates.count / 2]
        totalSeconds = Double(latencies.reduce(0, +)) / 1000
    }

    func print(title: String) {
        Swift.print("\n\(title): \(calls) calls, \(failed) failed")
        Swift.print("  latency   median \(medianMs) ms, p90 \(p90Ms) ms, max \(maxMs) ms, first call \(firstCallMs) ms")
        Swift.print("  tokens    input median \(medianInputTokens) (cached \(medianCachedTokens)), output median \(medianOutputTokens), max \(maxOutputTokens)")
        Swift.print(String(format: "  speed     %.0f output tokens/s median; %.1f s of model time in total", medianTokensPerSecond, totalSeconds))
        for f in failures { Swift.print("  failed: \(f)") }
    }
}


extension PerfRecord {
    /// A perf call as an ordinary run record, so the golden-set grader can
    /// score what the timed calls actually answered.
    var asRunRecord: CorrectionRecord {
        CorrectionRecord(caseID: caseID, repetition: repetition, output: output, error: error,
                         latencyMilliseconds: latencyMilliseconds, model: "apple-on-device",
                         sampling: configuration)
    }
}

/// Two perf runs, answer by answer: did a configuration change what the
/// model said, not only how fast?
struct PerfDiff: Codable {
    var compared = 0
    var sameDecision = 0
    var sameAnswer = 0
    var changed: [String] = []

    init(_ a: [PerfRecord], _ b: [PerfRecord]) {
        let bByKey = Dictionary(b.map { ("\($0.caseID)#\($0.repetition)", $0) }, uniquingKeysWith: { x, _ in x })
        for r in a {
            guard let other = bByKey["\(r.caseID)#\(r.repetition)"] else { continue }
            compared += 1
            let decisionA = r.output.map { "\($0.hasError)|\($0.corrected)" } ?? "failed"
            let decisionB = other.output.map { "\($0.hasError)|\($0.corrected)" } ?? "failed"
            if decisionA == decisionB { sameDecision += 1 } else { changed.append(r.caseID) }
            if r.output == other.output && (r.error == nil) == (other.error == nil) { sameAnswer += 1 }
        }
    }
}

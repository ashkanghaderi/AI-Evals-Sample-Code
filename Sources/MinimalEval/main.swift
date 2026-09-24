// A complete eval in one file: dataset, task, grader, metric, decision.
//
//   minimal-eval <cases.jsonl> --repeats 3               call the model
//   minimal-eval <cases.jsonl> --recording <run.jsonl>   grade a recording
//   add --ship-if-at-least 0.8 to turn the result into a yes or a no
import Foundation
import FoundationModels
import TutorCore

// 1. The dataset: inputs, and every answer a teacher would accept.
struct Case: Codable { let id: String; let input: String; let hasError: Bool; let accepted: [String] }

// One call to the model. A nil output is a call that failed.
struct Call: Codable { let caseID: String; let output: Correction? }

func lines<T: Decodable>(_ path: String, as type: T.Type) throws -> [T] {
    try String(contentsOfFile: path, encoding: .utf8)
        .split(separator: "\n").map { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
}

// 2. The task: the feature the app ships, called for every case, several times.
func run(_ cases: [Case], repeats: Int) async -> [Call] {
    let corrector = SentenceCorrector(model: SystemLanguageModel.default)
    var calls: [Call] = []
    for _ in 0..<repeats {
        for item in cases {
            calls.append(Call(caseID: item.id, output: try? await corrector.correct(item.input)))
        }
    }
    return calls
}

// 3. The grader: one question, answered identically every time.
func normalized(_ text: String) -> String {
    var t = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if t.hasSuffix(".") { t.removeLast() }
    return t
}

func isRight(_ call: Call, for item: Case) -> Bool {
    guard let output = call.output else { return false }   // a failed call is a failure
    let fixed = item.accepted.map(normalized).contains(normalized(output.corrected))
    return item.hasError ? fixed : fixed && !output.hasError
}

// 4. The metric: a rate, and how much it can actually tell you (Wilson, 95%).
func interval(_ k: Int, _ n: Int, z: Double = 1.96) -> (low: Double, high: Double) {
    guard n > 0 else { return (0, 1) }
    let p = Double(k) / Double(n), n = Double(n), z2 = z * z
    let centre = (p + z2 / (2 * n)) / (1 + z2 / n)
    let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot() / (1 + z2 / n)
    return (max(0, centre - margin), min(1, centre + margin))
}

let args = CommandLine.arguments
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}

let cases = try lines(args[1], as: Case.self)
let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
let calls = if let recording = option("--recording") {
    try lines(recording, as: Call.self)
} else {
    await run(cases, repeats: Int(option("--repeats") ?? "1") ?? 1)
}

let right = calls.filter { call in byID[call.caseID].map { isRight(call, for: $0) } ?? false }.count
let (low, high) = interval(right, calls.count)
print(String(format: "right: %.1f%% (95%% CI %.1f–%.1f%%, %d/%d)",
             100 * Double(right) / Double(calls.count), 100 * low, 100 * high, right, calls.count))

// 5. The decision: ship only if even the pessimistic end of the interval clears the bar.
if let bar = option("--ship-if-at-least").flatMap(Double.init) {
    print(low >= bar ? "SHIP: the lower bound clears \(bar)" : "DO NOT SHIP: the lower bound is below \(bar)")
    exit(low >= bar ? 0 : 1)
}

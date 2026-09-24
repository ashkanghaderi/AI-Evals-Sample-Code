import Foundation
import FoundationModels
import NaturalLanguage
import EvalKit
import TutorCore

struct ConversationScript: Codable {
    struct Turn: Codable {
        let user: String
        /// The reply must mention one of these: something the learner said
        /// earlier in the conversation.
        let recall: [String]?
    }
    let id: String
    let scenario: String
    let turns: [Turn]
}

struct ConversationRecord: Codable {
    let scriptID: String
    let repetition: Int
    let turn: Int
    let user: String
    let reply: String?
    let error: String?
    let latencyMilliseconds: Int
    let inputTokens: Int?
    let outputTokens: Int?
}

enum ConversationEval {
    /// Replays each script's learner turns in one session. The learner's lines
    /// are fixed, whatever the partner says - a real learner would react to
    /// the replies, which is the main thing a replayed script cannot measure.
    static func run(scripts: [ConversationScript], options: GenerationOptions, repeats: Int,
                    to url: URL) async throws {
        let clock = ContinuousClock()
        for repetition in 0..<repeats {
            for script in scripts {
                let partner = ConversationPartner(model: SystemLanguageModel.default,
                                                  scenario: script.scenario, options: options)
                for (index, turn) in script.turns.enumerated() {
                    let start = clock.now
                    var record: ConversationRecord
                    var stop = false
                    do {
                        let r = try await partner.reply(to: turn.user)
                        record = ConversationRecord(scriptID: script.id, repetition: repetition, turn: index,
                                                    user: turn.user, reply: r.text, error: nil,
                                                    latencyMilliseconds: ms(clock.now - start),
                                                    inputTokens: r.inputTokens, outputTokens: r.outputTokens)
                    } catch {
                        // A refused turn does not end a conversation - the
                        // learner would just say something else - so only a
                        // full context window stops the script. The first
                        // version stopped on any error, and lost the turns
                        // after two guardrail refusals.
                        let message = String(describing: error)
                        record = ConversationRecord(scriptID: script.id, repetition: repetition, turn: index,
                                                    user: turn.user, reply: nil, error: message,
                                                    latencyMilliseconds: ms(clock.now - start),
                                                    inputTokens: nil, outputTokens: nil)
                        stop = message.contains("context") || message.contains("exceeds")
                    }
                    try JSONLines.append(record, to: url)
                    FileHandle.standardError.write(Data("\r  \(script.id) \(index + 1)".utf8))
                    if stop { break }
                }
            }
        }
        FileHandle.standardError.write(Data("\n".utf8))
    }

    static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }

    /// The first version listed "asistente virtual" and missed "solo un
    /// asistente" - found by reading the long conversation's replies, where
    /// every one of them said it.
    static var outOfRole: Regex<(Substring, Substring)> {
        /(?i)(inteligencia artificial|modelo de lenguaje|\basistente\b|\bIA\b|\bAI\b|language model|assistant)/
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Every reply checked; recall checked where the script asks for it.
struct ConversationReport: Codable {
    struct Recall: Codable {
        let scriptID: String
        let repetition: Int
        let turn: Int
        let expected: [String]
        let reply: String
        let remembered: Bool
    }
    var replies = 0
    var failed = 0
    var failures: [String] = []
    var spanish = 0
    var short = 0
    var inRole = 0
    var recallHit = 0
    var recallTotal = 0
    var recalls: [Recall] = []
    var outOfRoleReplies: [String] = []
    var notSpanish: [String] = []
    /// For each script run: the last turn reached, and input tokens per turn.
    var lastTurn: [String: Int] = [:]
    var inputTokensByTurn: [Int] = []

    static let shortLimit = 30

    init(scripts: [ConversationScript], records: [ConversationRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: scripts.map { ($0.id, $0) })
        for r in records {
            let key = "\(r.scriptID)#\(r.repetition)"
            lastTurn[key] = max(lastTurn[key] ?? -1, r.turn)
            if r.repetition == 0 && byID.count == 1 { inputTokensByTurn.append(r.inputTokens ?? 0) }
            guard let reply = r.reply else {
                failed += 1
                failures.append("\(key) turn \(r.turn): \((r.error ?? "").prefix(120))")
                continue
            }
            replies += 1
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(reply)
            if recognizer.dominantLanguage == .spanish { spanish += 1 } else { notSpanish.append("\(key) turn \(r.turn): \(reply)") }
            if reply.split(whereSeparator: \.isWhitespace).count <= Self.shortLimit { short += 1 }
            if reply.contains(ConversationEval.outOfRole) { outOfRoleReplies.append("\(key) turn \(r.turn): \(reply)") } else { inRole += 1 }
            if let expected = byID[r.scriptID]?.turns[r.turn].recall {
                recallTotal += 1
                let hit = expected.contains { ConversationEval.fold(reply).contains(ConversationEval.fold($0)) }
                if hit { recallHit += 1 }
                recalls.append(Recall(scriptID: r.scriptID, repetition: r.repetition, turn: r.turn,
                                      expected: expected, reply: reply, remembered: hit))
            }
        }
    }

    func print(title: String) {
        Swift.print("\n\(title): \(replies) replies, \(failed) failed")
        Swift.print("  Spanish \(spanish), at most \(Self.shortLimit) words \(short), in role \(inRole); remembered \(recallHit) of \(recallTotal)")
        for r in recalls where !r.remembered {
            Swift.print("  forgot [\(r.scriptID)#\(r.repetition) turn \(r.turn)] \(r.expected.joined(separator: "/")): \(r.reply)")
        }
        for o in outOfRoleReplies { Swift.print("  out of role: \(o)") }
        for n in notSpanish.prefix(10) { Swift.print("  not Spanish: \(n)") }
        for f in failures { Swift.print("  failed: \(f)") }
        if !inputTokensByTurn.isEmpty {
            Swift.print("  input tokens by turn: \(inputTokensByTurn.map(String.init).joined(separator: " "))")
        }
    }
}

import Foundation
import FoundationModels
import EvalKit

/// One test case, written by the model instead of a person.
///
/// This is the tempting shortcut: ask the model for sentences with mistakes and
/// their corrections, and you have a dataset in a minute. Chapter 6 measures
/// what that dataset is worth.
@Generable
struct SyntheticSentence: Codable {
    @Guide(description: "a short Spanish sentence a beginner learner might write, containing exactly one mistake")
    var sentence: String

    @Guide(description: "the same sentence with the mistake corrected, changing as little as possible")
    var corrected: String

    @Guide(description: "the kind of mistake, in one or two English words")
    var category: String
}

/// A generated case as it is stored: the same shape as a hand-written case,
/// plus where it came from. The provenance is not optional. A dataset that
/// does not say who wrote it will eventually be mistaken for one a person did.
struct SyntheticCase: Codable {
    let id: String
    let input: String
    let hasError: Bool
    let accepted: [String]
    let category: String
    let source: String
}

enum Synthesizer {
    static let instructions = """
        You write test data for a Spanish tutoring app. Each time you are asked, \
        write one sentence of the kind a beginner learner of Spanish might write, \
        containing exactly one mistake, and give the corrected sentence.
        """

    /// One call per case, each with its own seed, so the dataset can be
    /// regenerated exactly - and so the only thing varying between cases is
    /// the model's own choice of what to write.
    static func generate(count: Int, firstSeed: UInt64, to url: URL) async throws {
        let model = SystemLanguageModel.default
        for index in 0..<count {
            let seed = firstSeed + UInt64(index)
            let session = LanguageModelSession(model: model, instructions: instructions)
            let options = GenerationOptions(samplingMode: .random(top: 50, seed: seed))
            let item = try await session.respond(
                to: "Write one test sentence.", generating: SyntheticSentence.self,
                options: options).content
            let stored = SyntheticCase(
                id: String(format: "syn-%02d", index + 1), input: item.sentence,
                hasError: true, accepted: [item.corrected], category: item.category,
                source: "apple-on-device seed:\(seed)")
            try JSONLines.append(stored, to: url)
            FileHandle.standardError.write(Data("\r  \(index + 1)/\(count)".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

import FoundationModels

/// What the model returns for one sentence.
///
/// Structured on purpose. Each field is a separate claim the model makes, and
/// each can be graded separately: whether it *noticed* an error, whether its
/// *correction* is right, and whether its *explanation* is right. The first
/// run of this feature showed why that matters - the correction of
/// "Yo es estudiante." was right and the explanation was invented.
@Generable
public struct Correction: Sendable, Codable, Equatable {
    @Guide(description: "true if the sentence contains any error in grammar, agreement, verb form, word choice, spelling, accents or punctuation")
    public var hasError: Bool

    @Guide(description: "the corrected sentence, changing as little as possible; identical to the input if there is no error")
    public var corrected: String

    @Guide(description: "one short sentence in English explaining the main error, or an empty string if there is none")
    public var explanation: String

    public init(hasError: Bool, corrected: String, explanation: String) {
        self.hasError = hasError
        self.corrected = corrected
        self.explanation = explanation
    }
}

/// The "Correct my sentence" feature, exactly as the app uses it.
///
/// Generic over the model, so the same feature can run on Apple's on-device
/// model, Private Cloud Compute, or any other `LanguageModel` - which is what
/// lets later chapters compare them on identical evals.
public struct SentenceCorrector<Model: LanguageModel> {
    public let model: Model
    public var options: GenerationOptions
    /// The learner's language, named in English: "English", "German", ...
    public var explanationLanguage: String

    public init(model: Model, options: GenerationOptions = GenerationOptions(),
                explanationLanguage: String = "English") {
        self.model = model
        self.options = options
        self.explanationLanguage = explanationLanguage
    }

    /// Recorded with every eval run, so a score can always be traced to the
    /// exact prompts that produced it. Change a prompt, change this.
    public var promptVersion: String {
        explanationLanguage == "English" ? "v1" : "v1 + translate explanation:\(explanationLanguage)"
    }

    public static var instructions: String {
        """
        You are a Spanish tutor. The user sends one Spanish sentence written by \
        a learner. Decide whether it contains an error in grammar, agreement, \
        verb form, word choice, spelling, accents or punctuation. If it does, \
        return the corrected sentence, changing as little as possible. If it is \
        already correct, return it unchanged and set hasError to false.
        """
    }

    /// One fresh session per sentence. Reusing a session would let earlier
    /// sentences leak into later answers, and an eval would then be measuring
    /// the order of its own dataset.
    ///
    /// The explanation is written in English and translated afterwards, in a
    /// separate session. Chapter 7 tried naming the learner's language in the
    /// correction prompt instead, twice; both versions started flagging correct
    /// sentences as errors. Kept apart, the decision - error or not, and the
    /// fix - is produced by exactly the prompt Part I measured, whatever
    /// language the learner reads.
    public func correct(_ sentence: String) async throws -> Correction {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        var result = try await session.respond(to: sentence, generating: Correction.self,
                                               options: options).content
        if explanationLanguage != "English" && !result.explanation.isEmpty {
            // A failed translation must not cost the learner a correct
            // correction. In Chapter 7 a guardrail refused to translate a
            // grammar note into Turkish, and the whole answer was lost. The
            // English explanation is a worse answer, not a wrong one - and the
            // eval's language check counts every time it happens.
            if let translated = try? await translate(result.explanation) {
                result.explanation = translated
            }
        }
        return result
    }

    func translate(_ explanation: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: """
            Translate the user's text from English into \(explanationLanguage). \
            Keep Spanish words and quoted examples exactly as they are. Reply \
            with the translation only.
            """)
        return try await session.respond(to: explanation, options: options).content
    }
}

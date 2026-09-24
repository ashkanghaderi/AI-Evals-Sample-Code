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

    public init(model: Model, options: GenerationOptions = GenerationOptions()) {
        self.model = model
        self.options = options
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
    public func correct(_ sentence: String) async throws -> Correction {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        return try await session.respond(to: sentence, generating: Correction.self,
                                         options: options).content
    }
}

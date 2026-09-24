import FoundationModels

/// "Practice a conversation" - Chapter 16's feature.
///
/// Unlike the corrector, which starts a fresh session for every sentence, a
/// conversation keeps one session: each reply is generated with every earlier
/// turn in context. That is what lets the partner remember the learner's name,
/// and what makes the context window a budget that runs out.
public final class ConversationPartner<Model: LanguageModel> {
    public let scenario: String
    let session: LanguageModelSession
    let options: GenerationOptions

    public init(model: Model, scenario: String,
                options: GenerationOptions = GenerationOptions(maximumResponseTokens: 200)) {
        self.scenario = scenario
        self.options = options
        session = LanguageModelSession(model: model, instructions: """
            You help a learner of Spanish at level A2 practise conversation by \
            playing a role. \(scenario) Stay in the role. Always reply in \
            Spanish, in one or two short, simple sentences.
            """)
    }

    /// The reply, and the session's token counts after it: input tokens grow
    /// with every turn, because every turn resends the whole conversation.
    public func reply(to learner: String) async throws -> (text: String, inputTokens: Int, outputTokens: Int) {
        let response = try await session.respond(to: learner, options: options)
        return (response.content, response.usage.input.totalTokenCount, response.usage.output.totalTokenCount)
    }
}

import Foundation
import FoundationModels

/// Every tool call the assistant makes, in order - what Chapter 17 grades.
public final class ToolCallLog: @unchecked Sendable {
    public struct Call: Codable, Sendable, Equatable {
        public let tool: String
        public let argument: String
    }
    private let lock = NSLock()
    private var calls: [Call] = []
    public init() {}
    public func append(_ tool: String, _ argument: String) {
        lock.lock(); calls.append(Call(tool: tool, argument: argument)); lock.unlock()
    }
    public func drain() -> [Call] {
        lock.lock(); defer { calls = []; lock.unlock() }; return calls
    }
}

public struct DictionaryEntry: Sendable {
    public let lemma: String
    public let forms: [String]
    public let partOfSpeech: String
    public let translations: [String]
    public init(lemma: String, forms: [String], partOfSpeech: String, translations: [String]) {
        self.lemma = lemma; self.forms = forms; self.partOfSpeech = partOfSpeech; self.translations = translations
    }
}

public struct LookUpWordTool: Tool {
    public let name = "lookUpWord"
    public let description = "Looks up a Spanish word in the app's dictionary and returns its meaning."
    let dictionary: [DictionaryEntry]
    let log: ToolCallLog

    @Generable
    public struct Arguments {
        @Guide(description: "the Spanish word to look up, as the learner wrote it")
        public var word: String
    }

    public func call(arguments: Arguments) async throws -> String {
        log.append(name, arguments.word)
        let word = arguments.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let entry = dictionary.first(where: { $0.lemma == word || $0.forms.contains(word) }) else {
            return "The word '\(arguments.word)' is not in the dictionary."
        }
        return "\(entry.lemma) (\(entry.partOfSpeech)): \(entry.translations.joined(separator: ", "))"
    }
}

public struct AddToReviewListTool: Tool {
    public let name = "addToReviewList"
    public static let standardDescription =
        "Adds a Spanish word to the learner's review list. Only use it when the learner asks to save or add a word."
    /// Chapter 17's attempted fix, measured and kept for the record.
    public static let strictDescription =
        "Adds a Spanish word to the learner's review list. Use it ONLY when the learner explicitly asks you to add or save a word. A question about the list is not a request to add. Never add a word the learner says not to add."
    public var description = standardDescription
    let log: ToolCallLog

    @Generable
    public struct Arguments {
        @Guide(description: "the Spanish word to add")
        public var word: String
    }

    public func call(arguments: Arguments) async throws -> String {
        log.append(name, arguments.word)
        return "Added '\(arguments.word)' to the review list."
    }
}

public struct TodaysProgressTool: Tool {
    public let name = "todaysProgress"
    public let description = "Returns how many words the learner has reviewed today."
    let log: ToolCallLog

    @Generable
    public struct Arguments {}

    public func call(arguments: Arguments) async throws -> String {
        log.append(name, "")
        return "The learner has reviewed 12 words today."
    }
}

/// "Ask the tutor" - Chapter 17's feature: questions answered with the app's
/// own tools. One fresh session per question, like the corrector.
public struct StudyAssistant<Model: LanguageModel> {
    public let model: Model
    public let dictionary: [DictionaryEntry]
    public var options: GenerationOptions
    public var addToolDescription = AddToReviewListTool.standardDescription

    public init(model: Model, dictionary: [DictionaryEntry], options: GenerationOptions = GenerationOptions()) {
        self.model = model; self.dictionary = dictionary; self.options = options
    }

    public static var instructions: String {
        """
        You are the study assistant in an app for learners of Spanish. Answer \
        briefly, in English. For the meaning of a Spanish word, use the \
        lookUpWord tool and answer from what it returns. Only add words to the \
        review list when the learner asks you to.
        """
    }

    public func answer(_ question: String, log: ToolCallLog) async throws -> String {
        let tools: [any Tool] = [LookUpWordTool(dictionary: dictionary, log: log),
                                 AddToReviewListTool(description: addToolDescription, log: log),
                                 TodaysProgressTool(log: log)]
        let session = LanguageModelSession(model: model, tools: tools, instructions: Self.instructions)
        return try await session.respond(to: question, options: options).content
    }
}

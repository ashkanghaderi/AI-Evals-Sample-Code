import SwiftUI
import FoundationModels
import TutorCore

@main
struct TutorApp: App {
    var body: some Scene {
        WindowGroup { CorrectSentenceView() }
    }
}

/// "Correct my sentence" - the first of the app's five AI features, and the
/// one Chapter 2 evaluates. The view calls exactly the SentenceCorrector the
/// eval runner calls; there is no separate demo path.
struct CorrectSentenceView: View {
    @State private var sentence = "Yo es estudiante."
    @State private var result: Correction?
    @State private var failure: String?
    @State private var isWorking = false

    /// Off until the learner turns it on. Nothing is recorded without it, and
    /// what is recorded is redacted first - input, correction and explanation.
    @AppStorage("shareSentencesForImprovement") private var shareSentences = false

    private let model = SystemLanguageModel.default

    var body: some View {
        NavigationStack {
            Form {
                Section("Your sentence") {
                    TextField("Write a Spanish sentence", text: $sentence, axis: .vertical)
                    Button(isWorking ? "Checking…" : "Correct it", action: correct)
                        .disabled(isWorking || sentence.isEmpty || !isAvailable)
                }
                if !isAvailable {
                    Section { Text("The on-device model is unavailable: \(String(describing: model.availability))") }
                }
                if let result {
                    Section(result.hasError ? "Correction" : "Looks right") {
                        Text(result.corrected).font(.title3.weight(.semibold))
                        if !result.explanation.isEmpty {
                            // Shown, and not yet trusted. Chapter 2 measured the
                            // corrections; the explanations still need a judge.
                            Text(result.explanation).foregroundStyle(.secondary)
                        }
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                Section {
                    Toggle("Help improve Tutor", isOn: $shareSentences)
                } footer: {
                    Text("Keeps an anonymised copy of your sentences on this device, with names, "
                         + "places and contact details removed, to test future versions of Tutor.")
                }
            }
            .navigationTitle("Tutor")
        }
    }

    private var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    private func correct() {
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            do {
                let output = try await SentenceCorrector(model: model).correct(sentence)
                result = output
                try? InteractionLog(url: .applicationSupportDirectory
                    .appending(path: "interactions.jsonl"))
                    .record(input: sentence, output: output, consented: shareSentences,
                            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                                as? String ?? "?")
            } catch {
                failure = String(describing: error)
            }
        }
    }
}

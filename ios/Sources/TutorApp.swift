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
                result = try await SentenceCorrector(model: model).correct(sentence)
            } catch {
                failure = String(describing: error)
            }
        }
    }
}

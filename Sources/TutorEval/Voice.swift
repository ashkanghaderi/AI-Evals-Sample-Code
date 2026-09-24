import Foundation
import AVFoundation
import Speech

/// Chapter 19: speech in front of the corrector.
enum VoiceEval {
    static let locale = Locale(identifier: "es-ES")

    /// What is available on this machine, before anything is downloaded.
    static func status() async -> String {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let supported = await SpeechTranscriber.supportedLocales.map(\.identifier)
        let assets = await AssetInventory.status(forModules: [transcriber])
        return """
            Spanish voices: \(voices.map { "\($0.name) (\($0.language), \($0.quality == .enhanced ? "enhanced" : $0.quality == .premium ? "premium" : "default"))" }.joined(separator: ", "))
            transcriber supports es-ES: \(supported.contains { $0.hasPrefix("es") }) (\(supported.filter { $0.hasPrefix("es") }.joined(separator: ", ")))
            transcriber assets for es-ES: \(assets)
            """
    }
}

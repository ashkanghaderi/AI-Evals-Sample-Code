import Foundation
import AVFoundation
import Speech

/// Chapter 19: speech in front of the corrector.
enum VoiceEval {
    static let locale = Locale(identifier: "es-ES")

    /// Downloads and installs the on-device transcription model for es-ES,
    /// through the system's own asset API. Run once, with permission.
    static func install() async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return "already installed"
        }
        try await request.downloadAndInstall()
        return "installed: \(await AssetInventory.status(forModules: [transcriber]))"
    }

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

import FoundationModels
import EvalKit
import TutorCore

struct VoiceRecord: Codable {
    let caseID: String
    let input: String
    let transcript: String?
    let correction: Correction?
    let error: String?
}

extension VoiceEval {
    /// Speak one sentence with the system's Spanish voice into a file.
    static func synthesize(_ text: String, to url: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        var file: AVAudioFile?
        var failure: Error?
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, !finished else { return }
                if pcm.frameLength == 0 { finished = true; done.resume(); return }
                do {
                    if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                    try file?.write(from: pcm)
                } catch { failure = error }
            }
        }
        if let failure { throw failure }
    }

    /// Transcribe a file on device.
    static func transcribe(_ url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let audio = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: audio, modules: [transcriber], finishAfterFile: true)
        _ = analyzer
        var text = ""
        for try await result in transcriber.results { text += String(result.text.characters) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run(cases: [CorrectionCase], to out: URL) async throws {
        let dir = URL(fileURLWithPath: "evals/voice/audio")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corrector = SentenceCorrector(model: SystemLanguageModel.default,
                                          options: GenerationOptions(samplingMode: .greedy))
        for item in cases {
            let audio = dir.appendingPathComponent("\(item.id).caf")
            var transcript: String?, correction: Correction?, failure: String?
            do {
                try? FileManager.default.removeItem(at: audio)
                try await synthesize(item.input, to: audio)
                transcript = try await transcribe(audio)
                if let t = transcript, !t.isEmpty { correction = try await corrector.correct(t) }
            } catch { failure = String(describing: error) }
            try JSONLines.append(VoiceRecord(caseID: item.id, input: item.input, transcript: transcript,
                                             correction: correction, error: failure), to: out)
            FileHandle.standardError.write(Data("\r  \(item.id)          ".utf8))
        }
    }
}

/// What speech did to each sentence before the tutor saw it.
struct VoiceReport: Codable {
    var sentences = 0
    var failed = 0
    /// Error sentences whose transcript still has the learner's error.
    var errorKept = 0
    /// Error sentences transcribed as an accepted correction: the mistake
    /// removed before the tutor could see it.
    var errorFixedBySpeech: [String] = []
    var errorChangedOtherwise: [String] = []
    var errorSentences = 0
    /// Correct sentences transcribed word for word.
    var controlsExact = 0
    var controls = 0
    /// The tutor, fed transcripts: error sentences it still flagged.
    var detectedFromSpeech = 0

    static func words(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    init(cases: [CorrectionCase], records: [VoiceRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for r in records {
            guard let item = byID[r.caseID] else { continue }
            sentences += 1
            guard let t = r.transcript else { failed += 1; continue }
            let heard = Self.words(t)
            if item.hasError {
                errorSentences += 1
                if heard == Self.words(item.input) { errorKept += 1 }
                else if item.accepted.map(Self.words).contains(heard) { errorFixedBySpeech.append("\(item.input) → \(t)") }
                else { errorChangedOtherwise.append("\(item.input) → \(t)") }
                if r.correction?.hasError == true { detectedFromSpeech += 1 }
            } else {
                controls += 1
                if heard == Self.words(item.input) { controlsExact += 1 }
            }
        }
    }

    func print() {
        Swift.print("\(sentences) sentences, \(failed) failed; correct sentences transcribed word for word \(controlsExact) of \(controls)")
        Swift.print("error sentences \(errorSentences): error kept \(errorKept), fixed by speech \(errorFixedBySpeech.count), changed otherwise \(errorChangedOtherwise.count)")
        Swift.print("tutor flagged an error, from the transcript: \(detectedFromSpeech) of \(errorSentences)")
        for f in errorFixedBySpeech { Swift.print("  fixed by speech: \(f)") }
        for f in errorChangedOtherwise { Swift.print("  changed: \(f)") }
    }
}

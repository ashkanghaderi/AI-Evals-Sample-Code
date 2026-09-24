import Testing
import Foundation
@testable import TutorCore

/// The pattern layer is exact, so it gets ordinary tests. The name layer is a
/// model, so it gets an eval (evals/redaction) instead - a unit test of one
/// name would pass or fail by luck.
@Suite("Redactor patterns")
struct RedactorPatternTests {
    let redactor = Redactor()

    @Test("Contact details are removed", arguments: [
        ("Mi correo es ana.lopez@gmail.com.", "ana.lopez@gmail.com"),
        ("Llámame al 612 345 678 mañana.", "612 345 678"),
        ("Mi número es +34 612345678.", "612345678"),
        ("Visita www.miblog.com para ver mis fotos.", "www.miblog.com"),
        ("Mira https://example.org/perfil/42 ahora.", "example.org"),
    ])
    func removesContactDetails(text: String, secret: String) {
        #expect(!redactor.redact(text).contains(secret))
    }

    @Test("Short numbers that are not phone numbers survive", arguments: [
        ("Tengo 25 años.", "25"),
        ("Trabajo aquí desde 2019.", "2019"),
    ])
    func keepsShortNumbers(text: String, kept: String) {
        #expect(redactor.redact(text).contains(kept))
    }
}

@Suite("InteractionLog")
struct InteractionLogTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tutor-log-\(UUID().uuidString)/log.jsonl")
    }

    let output = Correction(hasError: true, corrected: "Me llamo Carlos y vivo en Madrid.",
                            explanation: "'Me llamo' is correct; Carlos is fine.")

    @Test("Without consent, nothing is written")
    func noConsentNoFile() throws {
        let log = InteractionLog(url: temporaryURL())
        let wrote = try log.record(input: "Me yamo Carlos y vivo en Madrid.", output: output,
                                   consented: false, appVersion: "1.0")
        #expect(!wrote)
        #expect(!FileManager.default.fileExists(atPath: log.url.path))
    }

    /// The model echoes the learner. Redacting only the input would still
    /// record the name - in the correction and in the explanation.
    @Test("With consent, the name is gone from input, correction and explanation")
    func redactsEverything() throws {
        let log = InteractionLog(url: temporaryURL())
        try log.record(input: "Me yamo Carlos y vivo en Madrid.", output: output,
                       consented: true, appVersion: "1.0")
        let written = try String(contentsOf: log.url, encoding: .utf8)
        #expect(!written.contains("Carlos"))
        #expect(!written.contains("Madrid"))
        #expect(written.contains("[NAME]"))
    }

    @Test("The time is recorded as a day, never to the second")
    func dayOnly() throws {
        let log = InteractionLog(url: temporaryURL())
        try log.record(input: "Hola.", output: output, consented: true, appVersion: "1.0",
                       now: Date(timeIntervalSince1970: 1_790_000_000))
        let entry = try JSONDecoder().decode(InteractionLog.Entry.self,
                                             from: Data(contentsOf: log.url).dropLast())
        #expect(entry.day.count == 10)       // "2026-09-21"
    }
}

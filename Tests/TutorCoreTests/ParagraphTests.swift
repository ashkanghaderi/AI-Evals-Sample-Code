import Testing
import FoundationModels
@testable import TutorCore

@Suite("Paragraph splitting")
struct ParagraphTests {
    @Test("Spanish sentences split where a reader would split them")
    func split() {
        let s = ParagraphCorrector<SystemLanguageModel>.sentences(
            in: "Yo es estudiante. ¿Qué hora es? ¡Hola! Vivo en Madrid.")
        #expect(s == ["Yo es estudiante.", "¿Qué hora es?", "¡Hola!", "Vivo en Madrid."])
    }

    @Test("One sentence stays one sentence")
    func one() {
        #expect(ParagraphCorrector<SystemLanguageModel>.sentences(in: "Soy en Madrid.") == ["Soy en Madrid."])
    }
}

import Testing
@testable import TutorEval

@Suite("Perturbation")
struct PerturbationTests {
    @Test("Each rule breaks a sentence in its one known way", arguments: [
        (Perturbation.articleGender, "El agua está fría.", "La agua está fría."),
        (.articleGender, "Vivimos en una casa grande.", "Vivimos en un casa grande."),
        (.verbPerson, "Yo soy estudiante.", "Yo es estudiante."),
        (.verbPerson, "La gente es simpática.", "La gente son simpática."),
        (.verbPerson, "Yo no sé nada.", "Yo no sabe nada."),
        (.accentDrop, "Ellos son de México.", "Ellos son de Mexico."),
    ])
    func breaks(rule: Perturbation, correct: String, broken: String) {
        #expect(rule.apply(to: correct) == broken)
    }

    /// perturbed-v1's defect, pinned. Spanish drops the subject, so without a
    /// written subject another person's verb is just another correct sentence.
    @Test("A verb with no written subject is left alone", arguments: [
        "Tengo mucha hambre.", "Estoy en Madrid.", "Vi a Juan en el parque.",
        "Pienso en ti.", "Voy a la playa mañana.",
    ])
    func noSubjectNoChange(sentence: String) {
        #expect(Perturbation.verbPerson.apply(to: sentence) == nil)
        #expect(Perturbation.verbPerson.apply(to: sentence, naive: true) != nil)
    }

    @Test("A broken sentence never counts as its own answer")
    func neverAcceptsItself() {
        let source = [CorrectionCase(id: "x", input: "Hace calor.", hasError: false,
                                     accepted: ["Hace calor."], category: "control")]
        for item in Perturbation.cases(from: source) {
            #expect(!item.accepted.contains(item.input))
        }
    }
}

@Suite("Dataset audit")
struct DatasetAuditTests {
    func item(_ id: String, _ input: String, error: Bool, _ accepted: [String]) -> CorrectionCase {
        CorrectionCase(id: id, input: input, hasError: error, accepted: accepted, category: "c")
    }

    @Test("An 'error' whose answer is itself is caught")
    func answerIsInput() {
        let audit = DatasetAudit([item("a", "Voy al cine.", error: true, ["Voy al cine"])])
        #expect(audit.count("answer-is-input") == 1)
    }

    @Test("A control that does not accept itself is caught")
    func controlChanged() {
        let audit = DatasetAudit([item("a", "Voy al cine.", error: false, ["Voy a el cine."])])
        #expect(audit.count("control-changed") == 1)
    }

    @Test("Duplicates are caught after normalising, and overlap is reported, not failed")
    func duplicatesAndOverlap() {
        let other = [item("g", "Yo es estudiante.", error: true, ["Yo soy estudiante."])]
        let audit = DatasetAudit([
            item("a", "Yo es estudiante.", error: true, ["Yo soy estudiante."]),
            item("b", "Yo es  estudiante", error: true, ["Yo soy estudiante."]),
        ], against: other)
        #expect(audit.count("duplicate") == 1)
        #expect(audit.overlap == ["a", "b"])
        #expect(audit.problems.count == 1)
    }

    @Test("A clean dataset passes")
    func clean() {
        let audit = DatasetAudit([
            item("a", "Yo es estudiante.", error: true, ["Yo soy estudiante."]),
            item("b", "Hace calor.", error: false, ["Hace calor."]),
        ])
        #expect(audit.problems.isEmpty)
    }
}

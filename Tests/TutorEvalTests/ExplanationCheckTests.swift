import Testing
@testable import TutorCore
@testable import TutorEval

/// Each check, pinned on a real answer from the recorded runs: one it must
/// fail and one it must pass.
@Suite("Explanation checks")
struct ExplanationCheckTests {
    func fails(_ check: ExplanationCheck, _ input: String, _ hasError: Bool,
               _ corrected: String, _ explanation: String) -> Bool {
        !check.passes(input: input, output: Correction(hasError: hasError, corrected: corrected,
                                                       explanation: explanation))
    }

    @Test("coherent: a changed sentence reported as correct")
    func coherent() {
        #expect(fails(.coherent, "Ellos son de Mexico.", false, "Ellos son de México.",
                      "The sentence is grammatically correct."))
        #expect(!fails(.coherent, "Yo es estudiante.", true, "Yo soy estudiante.", ""))
    }

    @Test("agrees: an error flagged, explained as no error")
    func agrees() {
        #expect(fails(.agrees, "Las manos están sucios.", true, "Las manos están sucias.",
                      "The sentence is grammatically correct as is."))
        #expect(fails(.agrees, "Hay muchas gentes aquí.", false, "Hay muchas personas aquí.",
                      "The word 'gentes' is incorrect; 'personas' is the correct form."))
        #expect(!fails(.agrees, "Hace calor.", false, "Hace calor.",
                       "The sentence is grammatically correct."))
    }

    @Test("grounded: a quoted word that is in neither sentence")
    func grounded() {
        #expect(fails(.grounded, "Tengo hambre mucho.", true, "Tengo mucho hambre.",
                      "The sentence lacks the definite article 'el' before 'hambre'."))
        #expect(!fails(.grounded, "Los niños está jugando.", true, "Los niños están jugando.",
                       "The verb 'está' should be 'están' to agree with 'los niños'."))
    }

    @Test("complete: a fragment")
    func complete() {
        #expect(fails(.complete, "Nadie no vino.", true, "Nadie vino.", "The sentence uses "))
        #expect(!fails(.complete, "Hace calor.", false, "Hace calor.", ""))
    }

    /// The first version counted words by spaces and failed every Japanese
    /// explanation. This one is from the Japanese run in Chapter 7.
    @Test("complete: a Japanese sentence is not a fragment")
    func japanese() {
        #expect(!fails(.complete, "Los niños está jugando.", true, "Los niños están jugando.",
                       "動詞「está」は不正確です。「los niños」という複数形の主語に一致させるには「están」である必要があります。"))
    }

    /// No recorded explanation has tripped this rule yet, so it is pinned
    /// with a constructed one: long enough, but cut off before the end.
    @Test("complete: a long explanation that stops mid-sentence")
    func unterminated() {
        #expect(fails(.complete, "Yo es estudiante.", true, "Yo soy estudiante.",
                      "The verb 'es' does not agree with the subject"))
    }
}

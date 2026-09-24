import Testing
@testable import TutorEval

@Suite("Conversation grading")
struct ConversationTests {
    let script = ConversationScript(id: "s", scenario: "x", turns: [
        .init(user: "Hola, me llamo Lucía.", recall: nil),
        .init(user: "¿Recuerdas mi nombre?", recall: ["Lucía"]),
    ])

    func report(_ replies: [String]) -> ConversationReport {
        ConversationReport(scripts: [script], records: replies.enumerated().map { i, r in
            ConversationRecord(scriptID: "s", repetition: 0, turn: i, user: "", reply: r, error: nil,
                               latencyMilliseconds: 0, inputTokens: nil, outputTokens: nil)
        })
    }

    @Test("Recall ignores case and accents")
    func recall() {
        #expect(report(["Hola.", "Claro, te llamas lucia."]).recallHit == 1)
        #expect(report(["Hola.", "No lo sé."]).recallHit == 0)
    }

    /// The first version of the pattern said "asistente virtual" and missed
    /// every reply of the long conversation.
    @Test("Out of role, including 'solo un asistente'", arguments: [
        ("No soy nadie en especial, solo un asistente.", true),
        ("Soy una inteligencia artificial.", true),
        ("Bienvenida a nuestro café.", false),
    ])
    func role(reply: String, out: Bool) {
        #expect(report([reply]).outOfRoleReplies.isEmpty != out)
    }

    @Test("A reply in English is not Spanish")
    func language() {
        #expect(report(["Of course, your name is Lucía and you are from Bilbao."]).notSpanish.count == 1)
    }
}

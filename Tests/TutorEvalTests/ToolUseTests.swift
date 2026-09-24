import Testing
@testable import TutorCore
@testable import TutorEval

@Suite("Tool trajectories")
struct ToolUseTests {
    let requests = [
        ToolRequest(id: "look", request: "What does 'maleta' mean?",
                    expected: [.init(tool: "lookUpWord", accepted: ["maleta"])], answerMustContain: ["suitcase"]),
        ToolRequest(id: "ask", request: "Is 'maleta' on my list?", expected: [], answerMustContain: nil),
    ]

    func record(_ id: String, _ calls: [(String, String)], _ answer: String) -> ToolRecord {
        ToolRecord(requestID: id, repetition: 0, calls: calls.map { .init(tool: $0.0, argument: $0.1) },
                   answer: answer, error: nil, latencyMilliseconds: 0)
    }

    @Test("Exact, extra read, and the side effect that matters")
    func classify() {
        let r = ToolReport(requests: requests, records: [
            record("look", [("lookUpWord", "Maleta")], "It means suitcase."),
            record("ask", [("lookUpWord", "maleta"), ("addToReviewList", "maleta")], "Added."),
        ])
        #expect(r.exact == 1 && r.extraReads == 1 && r.unwantedSideEffects.count == 1)
        #expect(r.answersGrounded == 1)
    }

    @Test("A wrong argument and a missing call are told apart")
    func wrong() {
        let r = ToolReport(requests: [requests[0]], records: [
            record("look", [("lookUpWord", "maletas")], "Suitcases."),
            record("look", [], "It means suitcase."),
        ])
        #expect(r.wrongArguments == 1 && r.missingCalls == 1 && r.exact == 0)
    }
}

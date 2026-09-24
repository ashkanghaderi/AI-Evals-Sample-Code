import Testing
@testable import EvalKit

@Suite("Similarity")
struct SimilarityTests {
    @Test("Identical after normalising is 1")
    func identical() {
        #expect(Similarity.ratio("Hace calor.", "Hace  calor") == 1)
    }

    /// The whole problem with fuzzy grading this feature, in one assertion:
    /// the uncorrected sentence is 88% similar (15 of 17) to the right answer.
    @Test("One wrong letter is a small distance")
    func oneLetter() {
        let r = Similarity.ratio("La agua está fría.", "El agua está fría.")
        // 17 characters each once the full stop is dropped; L→E and a→l.
        #expect(abs(r - 15.0 / 17.0) < 1e-9)
    }

    @Test("Distance counts insertions, deletions and substitutions", arguments: [
        ("gato", "gatos", 1), ("gatos", "gato", 1), ("gato", "pato", 1), ("", "abc", 3), ("abc", "", 3),
    ])
    func distance(a: String, b: String, d: Int) {
        #expect(Similarity.distance(Array(a), Array(b)) == d)
    }
}

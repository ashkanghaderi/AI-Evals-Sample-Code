import Foundation
import EvalKit

/// Chapter 11: the people in the loop.
///
/// `review-packet` writes one self-contained HTML page for a reviewer. It is
/// blind in two ways: the sentences come without our accepted answers, and the
/// explanations come without our labels, both in a shuffled order. A reviewer
/// who can see our answer is checking it, not writing their own, and agrees
/// with it more than they would have.
///
/// `review-compare` reads what the reviewer exported and measures agreement
/// with us - never overwriting anything. Disagreements go to a person for
/// adjudication, and the outcome becomes a new version of the dataset.
struct ReviewFile: Codable {
    struct Sentence: Codable {
        let caseID: String
        let hasError: Bool?
        let accepted: [String]
        let note: String?
    }
    struct Explanation: Codable {
        let caseID: String
        let explanation: String
        let label: String?
        let note: String?
    }
    let reviewer: String
    let native: Bool?
    let packet: String
    let sentences: [Sentence]
    let explanations: [Explanation]
}

enum ReviewPacket {
    static let version = "review-v2"

    static func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        var generator = SplitMix64(seed: seed)
        return items.shuffled(using: &generator)
    }

    /// The order the reviewer sees, and the opaque id each item carries.
    ///
    /// The first packet used the dataset's case IDs - "ok-calor",
    /// "estar-state" - which are invisible on the page but sit in its source
    /// and in the export, and give the answers away to anyone, or anything,
    /// that reads the file. Items are now "s01", "e01"..., and the mapping back
    /// is recomputed from the same seeded shuffle, never shipped.
    static func sentenceOrder(_ cases: [CorrectionCase]) -> [(String, CorrectionCase)] {
        shuffled(cases, seed: 11).enumerated().map { (String(format: "s%02d", $0.offset + 1), $0.element) }
    }

    static func explanationOrder<T>(_ items: [T]) -> [(String, T)] {
        shuffled(items, seed: 12).enumerated().map { (String(format: "e%02d", $0.offset + 1), $0.element) }
    }

    static func html(cases: [CorrectionCase], explanations: [(String, String, String, String)]) throws -> String {
        struct S: Encodable { let id: String; let sentence: String }
        struct E: Encodable { let id: String; let sentence: String; let correction: String; let explanation: String }
        let sentences = sentenceOrder(cases).map { S(id: $0.0, sentence: $0.1.input) }
        let items = explanationOrder(explanations).map {
            E(id: $0.0, sentence: $0.1.1, correction: $0.1.2, explanation: $0.1.3)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = """
            {"packet":"\(version)","sentences":\(String(decoding: try encoder.encode(sentences), as: UTF8.self)),\
            "explanations":\(String(decoding: try encoder.encode(items), as: UTF8.self))}
            """
        return template.replacingOccurrences(of: "__DATA__", with: data
            .replacingOccurrences(of: "</", with: "<\\/"))
    }

    static let template = #"""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tutor Review</title>
    <style>
    :root { --bg:#fbfaf7; --fg:#1d1c1a; --muted:#6b6760; --line:#e2ddd3; --accent:#c2410c; --card:#fff; }
    @media (prefers-color-scheme: dark) { :root { --bg:#161513; --fg:#ece9e3; --muted:#a39e95; --line:#34312c; --accent:#fb923c; --card:#1f1d1a; } }
    * { box-sizing: border-box; }
    body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 -apple-system, system-ui, sans-serif; }
    main { max-width: 760px; margin: 0 auto; padding: 24px 16px 96px; }
    h1 { font-size: 1.6rem; margin: 0 0 4px; } h2 { margin-top: 40px; }
    .muted { color: var(--muted); }
    .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 16px; margin: 12px 0; }
    .sentence { font-size: 1.15rem; font-weight: 600; }
    label { display: inline-flex; gap: 6px; align-items: center; margin-right: 16px; }
    textarea, input[type=text] { width: 100%; font: inherit; padding: 8px; border: 1px solid var(--line);
      border-radius: 6px; background: var(--bg); color: var(--fg); }
    textarea { min-height: 60px; }
    .row { margin-top: 10px; }
    .bar { position: fixed; left: 0; right: 0; bottom: 0; background: var(--card); border-top: 1px solid var(--line);
      padding: 12px 16px; display: flex; gap: 12px; justify-content: center; align-items: center; flex-wrap: wrap; }
    button { font: inherit; padding: 8px 16px; border-radius: 8px; border: 0; background: var(--accent); color: #fff; cursor: pointer; }
    dl { margin: 8px 0 0; } dt { color: var(--muted); font-size: .85rem; } dd { margin: 0 0 6px; }
    </style></head><body><main>
    <h1>Tutor Review</h1>
    <p class="muted">Thank you for reviewing. Please answer from your own knowledge of Spanish. You will not see our answers:
    that is on purpose, so that yours are independent of ours. Your progress is kept in this browser; when you finish,
    press <b>Export</b> and send us the file it saves.</p>
    <div class="card"><div class="row"><b>Your name</b><input type="text" id="reviewer"></div>
    <div class="row"><label><input type="checkbox" id="native"> Spanish is my native language</label></div></div>
    <h2>Part 1 · Sentences</h2>
    <p class="muted">For each sentence written by a learner: does it contain any error (grammar, agreement, verb form,
    word choice, spelling, accents or punctuation)? If it does, write <b>every</b> corrected version a teacher would
    accept, one per line, changing as little as possible.</p>
    <div id="sentences"></div>
    <h2>Part 2 · Explanations</h2>
    <p class="muted">An app corrected each sentence and explained why. Is the explanation right? It is right only if it
    identifies the actual error in the learner's sentence, or correctly says there is none. Use "arguable" when a
    careful teacher could go either way, and say why.</p>
    <div id="explanations"></div>
    </main>
    <div class="bar"><span id="progress" class="muted"></span><button id="export">Export</button></div>
    <script>
    const DATA = __DATA__;
    const KEY = "tutor-review-" + DATA.packet;
    let state = {};
    try { state = JSON.parse(localStorage.getItem(KEY) || "{}"); } catch (e) { state = {}; }
    function save() { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} progress(); }
    function el(tag, attrs, ...kids) { const n = document.createElement(tag);
      Object.entries(attrs || {}).forEach(([k, v]) => n.setAttribute(k, v));
      kids.forEach(k => n.append(k)); return n; }
    function radio(name, value, text) { const r = el("input", {type: "radio", name, value});
      if (state[name] === value) r.checked = true;
      r.addEventListener("change", () => { state[name] = value; save(); });
      return el("label", {}, r, text); }
    function text(name, area) { const t = el(area ? "textarea" : "input", area ? {} : {type: "text"});
      t.value = state[name] || ""; t.addEventListener("input", () => { state[name] = t.value; save(); }); return t; }
    DATA.sentences.forEach((s, i) => {
      document.getElementById("sentences").append(el("div", {class: "card"},
        el("div", {class: "muted"}, "Sentence " + (i + 1) + " of " + DATA.sentences.length),
        el("div", {class: "sentence"}, s.sentence),
        el("div", {class: "row"}, radio("e:" + s.id, "yes", "Has an error"), radio("e:" + s.id, "no", "Correct as written")),
        el("div", {class: "row"}, el("div", {class: "muted"}, "Every correction you would accept, one per line"), text("a:" + s.id, true)),
        el("div", {class: "row"}, el("div", {class: "muted"}, "Note (optional)"), text("n:" + s.id))));
    });
    DATA.explanations.forEach((x, i) => {
      document.getElementById("explanations").append(el("div", {class: "card"},
        el("div", {class: "muted"}, "Explanation " + (i + 1) + " of " + DATA.explanations.length),
        el("dl", {}, el("dt", {}, "Learner wrote"), el("dd", {class: "sentence"}, x.sentence),
          el("dt", {}, "App corrected to"), el("dd", {}, x.correction),
          el("dt", {}, "App explained"), el("dd", {}, x.explanation)),
        el("div", {class: "row"}, radio("l:" + x.id, "right", "Right"), radio("l:" + x.id, "wrong", "Wrong"),
          radio("l:" + x.id, "arguable", "Arguable")),
        el("div", {class: "row"}, el("div", {class: "muted"}, "Why (optional)"), text("w:" + x.id))));
    });
    document.getElementById("reviewer").value = state.reviewer || "";
    document.getElementById("reviewer").addEventListener("input", e => { state.reviewer = e.target.value; save(); });
    document.getElementById("native").checked = !!state.native;
    document.getElementById("native").addEventListener("change", e => { state.native = e.target.checked; save(); });
    function progress() {
      const done = DATA.sentences.filter(s => state["e:" + s.id]).length + DATA.explanations.filter(x => state["l:" + x.id]).length;
      document.getElementById("progress").textContent = done + " of " + (DATA.sentences.length + DATA.explanations.length) + " answered";
    }
    progress();
    document.getElementById("export").addEventListener("click", () => {
      const out = { reviewer: state.reviewer || "", native: !!state.native, packet: DATA.packet,
        sentences: DATA.sentences.map(s => ({ caseID: s.id,
          hasError: state["e:" + s.id] ? state["e:" + s.id] === "yes" : null,
          accepted: (state["a:" + s.id] || "").split("\n").map(t => t.trim()).filter(Boolean),
          note: state["n:" + s.id] || null })),
        explanations: DATA.explanations.map(x => ({ caseID: x.id, explanation: x.explanation,
          label: state["l:" + x.id] || null, note: state["w:" + x.id] || null })) };
      const blob = new Blob([JSON.stringify(out, null, 2)], {type: "application/json"});
      const a = el("a", {href: URL.createObjectURL(blob), download: "tutor-review.json"});
      document.body.append(a); a.click(); a.remove();
    });
    </script></body></html>
    """#
}

/// A reviewer's answers against ours.
struct ReviewComparison: Codable {
    struct Disagreement: Codable {
        let caseID: String
        let part: String
        let ours: String
        let theirs: String
        let note: String?
    }
    var reviewer = ""
    var native: Bool?
    // Part 1
    var sentencesAnswered = 0
    var hasErrorAgree = 0
    var hasErrorKappa: Double?
    /// Our accepted answers the reviewer did not write.
    var oursNotTheirs = 0
    /// The reviewer's answers missing from our key: proposals for the next version.
    var theirsNotOurs = 0
    // Part 2
    var explanationsAnswered = 0
    var labelAgree = 0
    var labelKappa: Double?
    var disagreements: [Disagreement] = []

    init(review: ReviewFile, cases: [CorrectionCase], labels: [ExplanationLabel],
         explanationCases: [String] = []) {
        reviewer = review.reviewer
        native = review.native
        var byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        // Opaque packet ids map back through the same seeded shuffle.
        for (opaque, item) in ReviewPacket.sentenceOrder(cases) { byID[opaque] = item }
        let explanationIDs = Dictionary(uniqueKeysWithValues:
            ReviewPacket.explanationOrder(explanationCases).map { ($0.0, $0.1) })
        var pairs: [Agreement.Pair] = []
        for s in review.sentences {
            guard let item = byID[s.caseID], let theirs = s.hasError else { continue }
            let caseID = item.id
            sentencesAnswered += 1
            pairs.append(Agreement.Pair(item.hasError, theirs))
            if theirs == item.hasError { hasErrorAgree += 1 } else {
                disagreements.append(Disagreement(caseID: caseID, part: "has an error",
                                                  ours: "\(item.hasError)", theirs: "\(theirs)", note: s.note))
            }
            guard item.hasError && theirs else { continue }
            let missing = item.accepted.filter { !TextComparison.matches($0, anyOf: s.accepted) }
            let extra = s.accepted.filter { !TextComparison.matches($0, anyOf: item.accepted) }
            oursNotTheirs += missing.count
            theirsNotOurs += extra.count
            if !missing.isEmpty || !extra.isEmpty {
                disagreements.append(Disagreement(
                    caseID: caseID, part: "accepted answers",
                    ours: item.accepted.joined(separator: " | "),
                    theirs: s.accepted.joined(separator: " | "), note: s.note))
            }
        }
        hasErrorKappa = Agreement.kappa(pairs)

        let labelFor = Dictionary(labels.map { ("\($0.caseID)|\($0.explanation)", $0.label) },
                                  uniquingKeysWith: { a, _ in a })
        var labelPairs: [Agreement.Pair] = []
        for x in review.explanations {
            let caseID = explanationIDs[x.caseID] ?? x.caseID
            guard let theirs = x.label, let ours = labelFor["\(caseID)|\(x.explanation)"] else { continue }
            explanationsAnswered += 1
            if theirs == ours { labelAgree += 1 } else {
                disagreements.append(Disagreement(caseID: caseID, part: "explanation label",
                                                  ours: ours, theirs: theirs, note: x.note))
            }
            if ours != "arguable" && theirs != "arguable" {
                labelPairs.append(Agreement.Pair(ours == "right", theirs == "right"))
            }
        }
        labelKappa = Agreement.kappa(labelPairs)
    }

    func print() {
        Swift.print("\nreview by \(reviewer.isEmpty ? "(no name)" : reviewer)\(native == true ? ", native speaker" : "")")
        Swift.print("sentences: \(hasErrorAgree) of \(sentencesAnswered) agree on whether there is an error"
                    + (hasErrorKappa.map { String(format: ", kappa %.2f", $0) } ?? ""))
        Swift.print("  our accepted answers they did not write: \(oursNotTheirs); theirs missing from our key: \(theirsNotOurs)")
        Swift.print("explanations: \(labelAgree) of \(explanationsAnswered) same label"
                    + (labelKappa.map { String(format: ", kappa %.2f (right/wrong only)", $0) } ?? ""))
        Swift.print("\(disagreements.count) disagreements to adjudicate:")
        for d in disagreements {
            Swift.print("  [\(d.caseID)] \(d.part): ours \(d.ours) / theirs \(d.theirs)\(d.note.map { " - \($0)" } ?? "")")
        }
    }
}

# Paragraph correction: decision

**Shipped:** `ParagraphCorrector` with `wholeUpTo: 16` — paragraphs of up to
16 sentences in one call, as before; longer ones sentence by sentence.

| Candidate | Criteria | Result |
|---|---|---|
| split every paragraph | `criteria.json` (v1) | passed — but v1 compared with the single-sentence baseline, not with what shipped; against that it was worse on 2–16 sentences and ~35x slower at 64 |
| whole up to 8 | `criteria-v2.json` | **failed**: 10 right at 16 sentences, against 13 shipped |
| whole up to 16 | `criteria-v2.json` | **passed**: at least as many right as shipped at every size, 99% of characters kept, no failures, 433 ms per sentence median |

Recordings: `runs/whole-baseline.jsonl`, `runs/split.jsonl`, `runs/hybrid.jsonl`, `runs/hybrid16.jsonl`.

**Not measured, and owed:** default sampling (all runs are greedy, one per size);
paragraphs that are not golden-set sentences; and 64 sentences take about a
minute, so the app should show each corrected sentence as it arrives.

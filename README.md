# It Worked in the Demo — Sample Code

Companion code for **It Worked in the Demo: Evals for AI features in iOS apps**
by Pooya Khoshbakht & Ashkan Ghaderi.

Everything here runs for free: the features use Apple's on-device model through
the Foundation Models framework, and every eval run is recorded so it can be
re-graded without calling any model at all.

## Run it

```bash
swift test --build-system native            # EvalKit's own tests
./scripts/eval.sh run --repeats 3           # evaluate "Correct my sentence" (~5 min)
./scripts/eval.sh grade evals/correction/runs/<file>.jsonl   # re-grade, no model needed
./scripts/eval.sh audit --cases evals/correction/<dataset>.jsonl   # check a dataset before trusting it
./scripts/eval.sh run --sampling greedy --explain-in German         # explanations in the learner's language
./scripts/eval.sh languages --check fa,de                           # what the on-device model supports
./scripts/eval.sh checks evals/correction/runs/<file>.jsonl --labels evals/correction/explanation-labels-v1.jsonl
./scripts/eval.sh judge-run --source evals/correction/runs/<file>.jsonl --reference --out <judge-run>.jsonl
./scripts/eval.sh judge-grade <judge-run>.jsonl            # the judge, graded against the labels
```

Requires Xcode 27, macOS 27, and Apple Intelligence enabled. The iOS app is in
`ios/` (generate it with `xcodegen generate`).

## Layout

| Path | What it is |
|---|---|
| `Sources/TutorCore` | The app's AI features — the same code the app ships |
| `Sources/EvalKit` | Recording, statistics, text comparison. No model inside |
| `Sources/TutorEval` | The eval runner: `run` and `grade` |
| `Sources/MinimalEval` | Chapter 2: a complete eval in one file, with no EvalKit |
| `evals/<feature>/cases-vN.jsonl` | Golden datasets — versioned, never edited in place |
| `evals/correction/synthetic-v1.jsonl` | Chapter 6: 30 cases the model wrote for itself, kept as a warning |
| `evals/correction/perturbed-vN.jsonl` | Chapter 6: cases made by breaking correct sentences in code |
| `evals/correction/*-review.jsonl` | Our reading of generated cases, case by case |
| `evals/correction/explanation-labels-v1.jsonl` | Chapter 8: our verdict on 29 explanations, keyed by their exact text |
| `evals/correction/judge-runs/` | Chapter 10: a model's verdicts on explanations, recorded like any run |
| `evals/correction/accepted-proposals.jsonl` | Chapter 9: answers the key may be missing, waiting for a reviewer |
| `evals/correction/prompt-history.md` | Every prompt a recorded run used, word for word |
| `evals/<feature>/runs/` | Recorded model outputs, committed on purpose |
| `ios/` | The Tutor app |

## License

MIT — the code. The book's text is a separate work.

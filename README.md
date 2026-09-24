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
| `evals/<feature>/runs/` | Recorded model outputs, committed on purpose |
| `ios/` | The Tutor app |

## License

MIT — the code. The book's text is a separate work.

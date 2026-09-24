# Prompt history — "Correct my sentence"

Every recorded run names the prompt that produced it (`prompt` in each record;
runs without one used v1). A prompt that is no longer in the code is kept here,
word for word, so every run in `runs/` can still be traced to its exact input.

## v1 — shipped

The code in `Sources/TutorCore/SentenceCorrector.swift`. The explanation's
guide says "in English". Every Part I run, and every English run since.

## v1 + translate explanation:LANGUAGE — shipped (Chapter 7)

v1, unchanged, followed — only when the explanation is not empty — by a second
session with these instructions:

> Translate the user's text from English into LANGUAGE. Keep Spanish words and
> quoted examples exactly as they are. Reply with the translation only.

If the translation call fails, the English explanation is kept. That fallback
was added after `runs/2026-09-24-translate-nofallback-greedy-turkish.jsonl`,
where a guardrail refused one translation and the whole answer was lost. The
prompt label did not change, because the prompts did not - the file name says
which code made the run.

## v2 — withdrawn (Chapter 7)

Explanation guide:

> one short sentence explaining the main error, in the language the
> instructions name, or an empty string if there is none

Instructions: v1's, plus one sentence at the end:

> Write the explanation in LANGUAGE.

Runs: `runs/2026-09-24-v2-greedy-explain-{english,german}.jsonl`. In English,
preservation fell from 9 of 9 correct sentences to 5 of 9.

## v3 — withdrawn (Chapter 7)

v2's guide. Instructions: v1's, plus:

> If there is an error, explain it in LANGUAGE. If there is none, leave the
> explanation empty.

Runs: `runs/2026-09-24-v3-greedy-explain-{english,japanese,turkish}.jsonl`.
In English, preservation 6 of 9.

The Japanese and Turkish v3 runs, and the German v2 run, were made by a loop
left running while the prompt was being edited; each record's `prompt` field
says which prompt produced it, and every file holds exactly one. They shared
the machine with other runs, so their latencies are not comparable.

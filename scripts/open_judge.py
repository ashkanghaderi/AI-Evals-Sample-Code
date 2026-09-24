#!/usr/bin/env python3
"""Chapter 10: an open-weights judge, from outside Apple's model family.

The requests come from `tutor-eval judge-requests`, so this model is asked
exactly what the on-device judge was asked, built by the same Swift code. This
script only runs the model and writes JudgeRecord lines; `tutor-eval
judge-grade` grades them like any other judge.

One difference is unavoidable and is recorded in every line's `prompt`: the
on-device judge fills a @Generable structure, and this model is asked for the
same two fields as JSON, described with the same words as the @Guide text.

    python3 -m venv ~/.venvs/judge && ~/.venvs/judge/bin/pip install mlx-lm
    ./scripts/eval.sh judge-requests --source <run.jsonl> --reference > requests.jsonl
    ~/.venvs/judge/bin/python scripts/open_judge.py requests.jsonl <out.jsonl>

Runs on Apple silicon; the model is about 4.3 GB and is downloaded once.
"""
import json
import re
import sys
import time
from pathlib import Path

from mlx_lm import generate, load
from mlx_lm.sample_utils import make_sampler

MODEL = "mlx-community/Qwen2.5-7B-Instruct-4bit"
JUDGE = "qwen2.5-7b-instruct-4bit"

# The same two fields as JudgeVerdict, described with its @Guide text, in the
# same order: reasoning first, so the verdict can depend on it.
FORMAT = (
    "Reply with only a JSON object with two keys, in this order: "
    '"reasoning": what the actual error in the learner\'s sentence is, if any, '
    "and whether the explanation identifies it; "
    '"explanationIsRight": true only if the explanation correctly identifies '
    "the error in the learner's sentence, or correctly says there is none."
)


def strict(text: str):
    """The reply as the JSON object that was asked for, or None."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    if not isinstance(data.get("explanationIsRight"), bool) or not isinstance(data.get("reasoning"), str):
        return None
    return {"reasoning": data["reasoning"], "explanationIsRight": data["explanationIsRight"]}


def lenient(text: str):
    """The verdict when the reply is not JSON but says it unambiguously.

    The first run of this script read replies strictly, and failed 14 of 78:
    the model wrote the two fields without the braces around them. The verdict
    was never in doubt, so it is read here - but only when the field appears
    exactly once with a literal true or false. Anything less clear stays a
    failed call. Whether each verdict came from `strict` or from this is
    recorded, so format failures are still counted.
    """
    verdicts = re.findall(r'"explanationIsRight"\s*:\s*(true|false)\b', text)
    if len(verdicts) != 1:
        return None
    reasoning = re.search(r'"reasoning"\s*:\s*"?(.*?)"?\s*,?\s*"explanationIsRight"', text, re.DOTALL)
    return {"reasoning": reasoning.group(1).strip() if reasoning else "",
            "explanationIsRight": verdicts[0] == "true"}


def main() -> None:
    requests_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    if out_path.exists():
        sys.exit(f"{out_path} exists; recordings are never overwritten")
    requests = [json.loads(line) for line in requests_path.read_text().splitlines() if line.strip()]
    model, tokenizer = load(MODEL)
    greedy = make_sampler(temp=0.0)

    with out_path.open("w") as out:
        for index, item in enumerate(requests, start=1):
            messages = [
                {"role": "system", "content": item["instructions"] + "\n\n" + FORMAT},
                {"role": "user", "content": item["request"]},
            ]
            prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True)
            start = time.monotonic()
            reply = generate(model, tokenizer, prompt=prompt, max_tokens=400, sampler=greedy)
            elapsed = int((time.monotonic() - start) * 1000)
            parsed = strict(reply)
            format_ok = parsed is not None
            parsed = parsed or lenient(reply)
            record = {
                "caseID": item["caseID"], "input": item["input"], "corrected": item["corrected"],
                "hasError": item["hasError"], "explanation": item["explanation"],
                "judge": JUDGE, "withReference": item["withReference"],
                "mismatched": item["mismatched"], "output": parsed,
                "error": None if parsed else f"unreadable reply: {reply[:300]}",
                "latencyMilliseconds": elapsed, "prompt": item["prompt"] + " + json",
                "formatFollowed": format_ok, "reply": reply,
            }
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
            out.flush()
            print(f"\r  {index}/{len(requests)}", end="", file=sys.stderr, flush=True)
    print(f"\nrecorded {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()

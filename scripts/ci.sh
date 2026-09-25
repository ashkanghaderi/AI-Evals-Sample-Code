#!/bin/bash
# Chapter 22: every check this repository can make without calling a model.
#
# Runs anywhere the package builds. Each gate prints PASS or FAIL; the script
# exits 1 if any gate failed. `set -o pipefail` is not decoration: without it,
# `swift test | tail` reports tail's exit status, and a failing test passes.
set -uo pipefail
cd "$(dirname "$0")/.."

SWIFT="swift"
BUILD="--build-system native"
EVAL=".build/out/Products/Release/tutor-eval"
[ -x "$EVAL" ] || EVAL=".build/arm64-apple-macosx/release/tutor-eval"
MINIMAL=".build/arm64-apple-macosx/release/minimal-eval"
BASELINE="evals/correction/runs/2026-09-24T140430Z-on-device-greedy.jsonl"
LATEST="${LATEST_RECORDING:-evals/correction/runs/2026-09-25-greedy-cap256.jsonl}"
# The bar the recording must clear. Chosen once, in writing, and changed only
# by a commit that says why - never adjusted to let a run through.
SHIP_BAR="${SHIP_BAR:-0.40}"
ONLY="${ONLY:-}"   # run a single gate, for break-checking
failed=0
results=()

gate() {   # gate NAME COMMAND...
    local name="$1"; shift
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return
    if "$@" > "/tmp/ci-$name.log" 2>&1; then
        results+=("PASS $name"); echo "PASS  $name"
    else
        results+=("FAIL $name"); echo "FAIL  $name   (see /tmp/ci-$name.log)"; failed=1
    fi
}

$SWIFT build $BUILD -c release > /tmp/ci-build.log 2>&1 || { echo "FAIL  build"; exit 1; }
EVAL=$(ls -t .build/*/release/tutor-eval .build/out/Products/Release/tutor-eval 2>/dev/null | head -1)
MINIMAL=$(ls -t .build/*/release/minimal-eval .build/out/Products/Release/minimal-eval 2>/dev/null | head -1)

gate tests         $SWIFT test $BUILD
gate audit-v1      "$EVAL" audit --cases evals/correction/cases-v1.jsonl
gate audit-v2      "$EVAL" audit --cases evals/correction/cases-v2.jsonl --against evals/correction/cases-v1.jsonl
gate audit-perturb "$EVAL" audit --cases evals/correction/perturbed-v2.jsonl --against evals/correction/cases-v1.jsonl
gate ship-bar      "$MINIMAL" evals/correction/cases-v1.jsonl --recording "$LATEST" --ship-if-at-least "$SHIP_BAR"
gate drift         "$EVAL" drift "$BASELINE" "$LATEST"

echo
[ $failed -eq 0 ] && echo "all ${#results[@]} gates passed" || echo "a gate failed"
exit $failed

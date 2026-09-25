#!/bin/bash
# Chapter 22: break each gate on purpose and record whether ci.sh noticed.
# Every change is undone afterwards; the result goes to evals/ci/breakcheck.jsonl.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=evals/ci/breakcheck.jsonl
mkdir -p evals/ci; : > "$OUT"
record() { # gate what exit
    printf '{"gate":"%s","break":"%s","ciExit":%s}\n' "$1" "$2" "$3" >> "$OUT"
    echo "$1: $2 -> ci.sh exit $3"
}

# tests: a test that fails
cat > Tests/EvalKitTests/BreakCheck.swift <<'SWIFT'
import Testing
@Test("Deliberately broken") func broken() { #expect(1 == 2) }
SWIFT
ONLY=tests ./scripts/ci.sh > /dev/null 2>&1; record tests "a failing test" $?
# The same failure behind a pipe, without and with pipefail.
bash -c 'swift test --build-system native 2>&1 | tail -1' > /dev/null; record pipe "failing test piped into tail, no pipefail" $?
bash -c 'set -o pipefail; swift test --build-system native 2>&1 | tail -1' > /dev/null; record pipe "failing test piped into tail, with pipefail" $?
rm Tests/EvalKitTests/BreakCheck.swift

# audit: a duplicated case
cp evals/correction/cases-v1.jsonl /tmp/cases-v1.bak
head -1 evals/correction/cases-v1.jsonl | sed 's/"ser-conjugation"/"ser-conjugation-copy"/' >> evals/correction/cases-v1.jsonl
ONLY=audit-v1 ./scripts/ci.sh > /dev/null 2>&1; record audit-v1 "a duplicated sentence in the key" $?
cp /tmp/cases-v1.bak evals/correction/cases-v1.jsonl

# ship-bar: a bar the recording cannot clear
SHIP_BAR=0.95 ONLY=ship-bar ./scripts/ci.sh > /dev/null 2>&1; record ship-bar "a bar of 0.95" $?

# drift: one answer changed in a copy of the latest recording
python3 - <<'PY'
import json
lines=open('evals/correction/runs/2026-09-25-greedy-cap256.jsonl').read().splitlines()
r=json.loads(lines[0]); r['output']['corrected']=r['output']['corrected']+' '
lines[0]=json.dumps(r, ensure_ascii=False)
open('/tmp/changed-recording.jsonl','w').write('\n'.join(lines)+'\n')
PY
LATEST_RECORDING=/tmp/changed-recording.jsonl ONLY=drift ./scripts/ci.sh > /dev/null 2>&1; record drift "one answer changed by a trailing space" $?

git status --porcelain Tests evals/correction/cases-v1.jsonl

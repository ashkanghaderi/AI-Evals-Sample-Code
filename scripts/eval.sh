#!/usr/bin/env bash
# Run the "Correct my sentence" eval on the on-device model, or re-grade a
# recorded run without calling any model.
#
#   ./scripts/eval.sh run --repeats 3
#   ./scripts/eval.sh grade evals/correction/runs/<file>.jsonl
#
# --build-system native: Xcode 27's default SwiftPM backend code-signs build
# products, and on a Mac whose ~/Documents is synced by iCloud Drive the File
# Provider attributes it stamps on them make codesign fail with "resource fork,
# Finder information, or similar detritus not allowed". The native backend does
# not sign, so it is unaffected.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift run --build-system native -c release tutor-eval "$@"

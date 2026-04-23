#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -L)"
PROMPT_FILE="$1"
TIMEOUT_SEC="$2"
STDOUT_FILE="$3"
STDERR_FILE="$4"
ALLOW_WRITES="${5:-false}"
MODEL_NAME="${6:-}"
OUTPUT_SCHEMA_FILE="${7:-}"

CMD=(timeout "$TIMEOUT_SEC" codex exec --skip-git-repo-check)
if [[ -n "$MODEL_NAME" ]]; then
  CMD+=(--model "$MODEL_NAME")
fi
if [[ -n "$OUTPUT_SCHEMA_FILE" ]]; then
  CMD+=(--output-schema "$OUTPUT_SCHEMA_FILE")
fi
if [[ "$ALLOW_WRITES" == "true" ]]; then
  CMD+=(--dangerously-bypass-approvals-and-sandbox)
fi

"${CMD[@]}" - <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"

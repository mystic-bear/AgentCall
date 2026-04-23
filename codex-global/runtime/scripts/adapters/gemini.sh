#!/usr/bin/env bash
set -euo pipefail

PROMPT_FILE="$1"
TIMEOUT_SEC="$2"
STDOUT_FILE="$3"
STDERR_FILE="$4"
ALLOW_WRITES="${5:-false}"
MODEL_NAME="${6:-}"
CMD=(timeout "$TIMEOUT_SEC" gemini -o text -p "")

if [[ -n "$MODEL_NAME" ]]; then
  CMD+=(--model "$MODEL_NAME")
fi

if [[ "$ALLOW_WRITES" == "true" ]]; then
  CMD+=(--yolo)
else
  CMD+=(--approval-mode plan)
fi

"${CMD[@]}" <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"

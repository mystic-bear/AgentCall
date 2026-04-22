#!/usr/bin/env bash
set -euo pipefail

PROMPT_FILE="$1"
TIMEOUT_SEC="$2"
STDOUT_FILE="$3"
STDERR_FILE="$4"
ALLOW_WRITES="${5:-false}"
MODEL_NAME="${6:-}"
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"

if [[ -n "$MODEL_NAME" ]]; then
  timeout "$TIMEOUT_SEC" gemini --yolo -o text --model "$MODEL_NAME" -p "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
else
  timeout "$TIMEOUT_SEC" gemini --yolo -o text -p "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
fi

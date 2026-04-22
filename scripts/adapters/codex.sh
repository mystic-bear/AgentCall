#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -L)"
PROMPT_FILE="$1"
TIMEOUT_SEC="$2"
STDOUT_FILE="$3"
STDERR_FILE="$4"
ALLOW_WRITES="${5:-false}"
MODEL_NAME="${6:-}"
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
LOCAL_CODEX_SCRIPT="$ROOT_DIR/scripts/local_codex.sh"

if [[ "$ALLOW_WRITES" == "true" ]]; then
  if [[ -n "$MODEL_NAME" ]]; then
    timeout "$TIMEOUT_SEC" "$LOCAL_CODEX_SCRIPT" exec --model "$MODEL_NAME" --dangerously-bypass-approvals-and-sandbox "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    timeout "$TIMEOUT_SEC" "$LOCAL_CODEX_SCRIPT" exec --dangerously-bypass-approvals-and-sandbox "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
else
  if [[ -n "$MODEL_NAME" ]]; then
    timeout "$TIMEOUT_SEC" "$LOCAL_CODEX_SCRIPT" exec --model "$MODEL_NAME" "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    timeout "$TIMEOUT_SEC" "$LOCAL_CODEX_SCRIPT" exec "$PROMPT_CONTENT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
fi

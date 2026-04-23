#!/usr/bin/env bash
set -euo pipefail

PROMPT_FILE="$1"
TIMEOUT_SEC="$2"
STDOUT_FILE="$3"
STDERR_FILE="$4"
ALLOW_WRITES="${5:-false}"
MODEL_NAME="${6:-}"

if [[ "$ALLOW_WRITES" == "true" ]]; then
  if [[ -n "$MODEL_NAME" ]]; then
    timeout "$TIMEOUT_SEC" claude --print --model "$MODEL_NAME" --permission-mode acceptEdits <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    timeout "$TIMEOUT_SEC" claude --print --permission-mode acceptEdits <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
else
  if [[ -n "$MODEL_NAME" ]]; then
    timeout "$TIMEOUT_SEC" claude --print --model "$MODEL_NAME" <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    timeout "$TIMEOUT_SEC" claude --print <"$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
fi

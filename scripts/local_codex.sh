#!/usr/bin/env bash
set -euo pipefail

normalize_path() {
  local path="$1"
  case "$path" in
    /mnt/d/Project/*)
      printf '/mnt/d/project/%s\n' "${path#/mnt/d/Project/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

ROOT_DIR="$(normalize_path "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)")"
CODEX_RUNTIME_HOME="$ROOT_DIR/.local-runtime/codex-home"

usage() {
  cat <<EOF
Usage:
  ./scripts/local_codex.sh login
  ./scripts/local_codex.sh exec [--model <name>] [--dangerously-bypass-approvals-and-sandbox] "<prompt>"
  ./scripts/local_codex.sh env
  ./scripts/local_codex.sh path

Behavior:
  - Uses project-local CODEX_HOME only
  - Does not touch global ~/.codex runtime
  - Stores local Codex state under:
    $CODEX_RUNTIME_HOME
EOF
}

ensure_runtime_home() {
  mkdir -p "$CODEX_RUNTIME_HOME"
}

subcommand="${1:-help}"
shift || true

case "$subcommand" in
  login)
    ensure_runtime_home
    echo "Using project-local CODEX_HOME: $CODEX_RUNTIME_HOME"
    CODEX_HOME="$CODEX_RUNTIME_HOME" codex login "$@"
    ;;
  exec)
    ensure_runtime_home
    MODEL_ARG=""
    EXTRA_ARGS=()
    PROMPT=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --model)
          MODEL_ARG="$2"
          shift 2
          ;;
        --dangerously-bypass-approvals-and-sandbox)
          EXTRA_ARGS+=("$1")
          shift
          ;;
        *)
          PROMPT="$1"
          shift
          ;;
      esac
    done
    if [[ -z "$PROMPT" ]]; then
      echo "ERROR: exec requires a prompt argument" >&2
      exit 1
    fi
    if [[ -n "$MODEL_ARG" ]]; then
      CODEX_HOME="$CODEX_RUNTIME_HOME" codex exec --skip-git-repo-check --model "$MODEL_ARG" "${EXTRA_ARGS[@]}" "$PROMPT"
    else
      CODEX_HOME="$CODEX_RUNTIME_HOME" codex exec --skip-git-repo-check "${EXTRA_ARGS[@]}" "$PROMPT"
    fi
    ;;
  env)
    ensure_runtime_home
    cat <<EOF
CODEX_HOME=$CODEX_RUNTIME_HOME
export CODEX_HOME="$CODEX_RUNTIME_HOME"
EOF
    ;;
  path)
    ensure_runtime_home
    printf '%s\n' "$CODEX_RUNTIME_HOME"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "ERROR: unknown subcommand: $subcommand" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

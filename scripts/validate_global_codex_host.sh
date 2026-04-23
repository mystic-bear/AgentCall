#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${HOME}/.codex"
PROJECT_ROOT=""
LIVE_SMOKE=false

usage() {
  cat <<EOF
Usage:
  ./scripts/validate_global_codex_host.sh [--install-root <path>] [--project-root <path>] [--live-smoke]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --live-smoke)
      LIVE_SMOKE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

SKILL_FILE="$INSTALL_ROOT/skills/AgentCall/SKILL.md"
WRAPPER="$INSTALL_ROOT/AgentCall/scripts/global_call_cli.sh"
NORMALIZER="$INSTALL_ROOT/AgentCall/scripts/normalize_agent_meta.sh"
MANIFEST="$INSTALL_ROOT/AgentCall/manifests/install-manifest.txt"

required_files=(
  "$SKILL_FILE"
  "$WRAPPER"
  "$NORMALIZER"
  "$INSTALL_ROOT/AgentCall/scripts/adapters/claude.sh"
  "$INSTALL_ROOT/AgentCall/scripts/adapters/codex.sh"
  "$INSTALL_ROOT/AgentCall/scripts/adapters/gemini.sh"
  "$INSTALL_ROOT/AgentCall/schema/common.schema.json"
  "$INSTALL_ROOT/AgentCall/agents/architect.md"
  "$MANIFEST"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || { echo "ERROR: missing required file: $file" >&2; exit 1; }
done

TMP_PROJECT=""
if [[ -z "$PROJECT_ROOT" ]]; then
  TMP_PROJECT="$(mktemp -d /tmp/agentcall-global-project.XXXXXX)"
  PROJECT_ROOT="$TMP_PROJECT"
fi

TMP_OUT="$(mktemp /tmp/agentcall-global-out.XXXXXX)"
trap 'rm -f "$TMP_OUT"; if [[ -n "$TMP_PROJECT" ]]; then rm -rf "$TMP_PROJECT"; fi' EXIT

"$WRAPPER" --agent architect --prompt "Global wrapper dry-run validation." --project-root "$PROJECT_ROOT" --dry-run > "$TMP_OUT"

grep -q '"status": "dry-run"' "$TMP_OUT" || { echo "ERROR: dry-run status missing" >&2; exit 1; }
grep -q '"agent": "architect"' "$TMP_OUT" || { echo "ERROR: architect routing missing" >&2; exit 1; }
grep -q '"state_mode": "global-fallback"' "$TMP_OUT" || { echo "ERROR: global fallback state mode missing" >&2; exit 1; }

if [[ "$LIVE_SMOKE" == "true" ]]; then
  "$WRAPPER" --agent frontend-designer --prompt "Briefly confirm the global fallback runtime is operational." --project-root "$PROJECT_ROOT" --execute > "$TMP_OUT"
  test -s "$TMP_OUT" || { echo "ERROR: live smoke returned empty output" >&2; exit 1; }
fi

echo "global_codex_host validation passed"

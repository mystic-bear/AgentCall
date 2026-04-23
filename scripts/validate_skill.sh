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

SCRIPT_ROOT="$(normalize_path "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)")"
CURRENT_DIR_NORMALIZED="$(normalize_path "$PWD")"
if [[ -f "$CURRENT_DIR_NORMALIZED/AGENTS.md" && -d "$CURRENT_DIR_NORMALIZED/scripts" && -d "$CURRENT_DIR_NORMALIZED/.docs/ai-workflow" ]]; then
  ROOT_DIR="$CURRENT_DIR_NORMALIZED"
else
  ROOT_DIR="$SCRIPT_ROOT"
fi
STATE_FILE="$ROOT_DIR/.docs/ai-workflow/state.md"

required_files=(
  "$ROOT_DIR/AGENTS.md"
  "$ROOT_DIR/.agents/architect.md"
  "$ROOT_DIR/.agents/frontend-designer.md"
  "$ROOT_DIR/.agents/integrator.md"
  "$ROOT_DIR/.agents/bug-reviewer.md"
  "$ROOT_DIR/.agents/test-hello.md"
  "$ROOT_DIR/scripts/call_cli.sh"
  "$ROOT_DIR/scripts/extract_response_body.mjs"
  "$ROOT_DIR/scripts/check_response_contract.mjs"
  "$ROOT_DIR/scripts/adapters/claude.sh"
  "$ROOT_DIR/scripts/adapters/codex.sh"
  "$ROOT_DIR/scripts/adapters/gemini.sh"
  "$ROOT_DIR/.docs/ai-workflow/schema/common.schema.json"
  "$ROOT_DIR/.docs/ai-workflow/model-defaults.env"
  "$ROOT_DIR/.docs/ai-workflow/state.md"
)

failures=0

check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    printf 'OK   %s\n' "${file#$ROOT_DIR/}"
  else
    printf 'FAIL missing %s\n' "${file#$ROOT_DIR/}"
    failures=$((failures + 1))
  fi
}

check_state_key() {
  local key="$1"
  if grep -q "^\*\*${key}\*\*:" "$STATE_FILE"; then
    printf 'OK   state key %s\n' "$key"
  else
    printf 'FAIL missing state key %s\n' "$key"
    failures=$((failures + 1))
  fi
}

for file in "${required_files[@]}"; do
  check_file "$file"
done

bash -n \
  "$ROOT_DIR/scripts/call_cli.sh" \
  "$ROOT_DIR/scripts/validate_skill.sh" \
  "$ROOT_DIR/scripts/adapters/claude.sh" \
  "$ROOT_DIR/scripts/adapters/codex.sh" \
  "$ROOT_DIR/scripts/adapters/gemini.sh" \
  && printf 'OK   bash syntax\n' \
  || { printf 'FAIL bash syntax\n'; failures=$((failures + 1)); }

if command -v node >/dev/null 2>&1; then
  if node --check "$ROOT_DIR/scripts/extract_response_body.mjs" >/dev/null 2>&1; then
    printf 'OK   node syntax extract_response_body\n'
  else
    printf 'FAIL node syntax extract_response_body\n'
    failures=$((failures + 1))
  fi
  if node --check "$ROOT_DIR/scripts/check_response_contract.mjs" >/dev/null 2>&1; then
    printf 'OK   node syntax check_response_contract\n'
  else
    printf 'FAIL node syntax check_response_contract\n'
    failures=$((failures + 1))
  fi
else
  printf 'FAIL node syntax (node missing)\n'
  failures=$((failures + 1))
fi

check_state_key "Skill Version"
check_state_key "Current Phase"
check_state_key "Current Owner"
check_state_key "Next Owner"
check_state_key "Last Gate Passed"
check_state_key "Current Delegation Depth"
check_state_key "Session ID"
check_state_key "Correlation ID"

if [[ "$failures" -gt 0 ]]; then
  printf '\nValidation failed with %s issue(s).\n' "$failures"
  exit 1
fi

printf '\nValidation passed.\n'

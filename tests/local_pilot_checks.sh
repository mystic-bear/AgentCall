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
FAILURES=0

assert_file() {
  local path="$1"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    printf 'OK   %s\n' "$path"
  else
    printf 'FAIL missing %s\n' "$path"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_grep() {
  local pattern="$1"
  local path="$2"
  if grep -q "$pattern" "$ROOT_DIR/$path"; then
    printf 'OK   %s contains %s\n' "$path" "$pattern"
  else
    printf 'FAIL %s missing pattern %s\n' "$path" "$pattern"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_file ".docs/ai-workflow/implementation-checklist.md"
assert_file "local-skills/AgentCall/SKILL.md"
assert_file "scripts/run_gate_s_checks.sh"
assert_file ".docs/ai-workflow/test-cases/gate-s-report.md"
assert_file ".agents/test-hello.md"

if [[ -f "$ROOT_DIR/.docs/ai-workflow/implementation-checklist.md" ]]; then
  assert_grep "^## Phase 1" ".docs/ai-workflow/implementation-checklist.md"
  assert_grep "^## Phase 2" ".docs/ai-workflow/implementation-checklist.md"
  assert_grep "^## Phase 3" ".docs/ai-workflow/implementation-checklist.md"
  assert_grep "^## Phase 4" ".docs/ai-workflow/implementation-checklist.md"
fi

if [[ -f "$ROOT_DIR/local-skills/AgentCall/SKILL.md" ]]; then
  assert_grep "^name: AgentCall" "local-skills/AgentCall/SKILL.md"
  assert_grep "When NOT to Use" "local-skills/AgentCall/SKILL.md"
  assert_grep "Safety Gates" "local-skills/AgentCall/SKILL.md"
fi

if [[ -f "$ROOT_DIR/scripts/run_gate_s_checks.sh" ]]; then
  bash -n "$ROOT_DIR/scripts/run_gate_s_checks.sh" || {
    printf 'FAIL scripts/run_gate_s_checks.sh syntax\n'
    FAILURES=$((FAILURES + 1))
  }
fi

if [[ "$FAILURES" -gt 0 ]]; then
  printf '\nlocal_pilot_checks failed: %s issue(s)\n' "$FAILURES"
  exit 1
fi

printf '\nlocal_pilot_checks passed\n'

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
REPORT_FILE="$ROOT_DIR/.docs/ai-workflow/test-cases/gate-s-report.md"
STATE_FILE="$ROOT_DIR/.docs/ai-workflow/state.md"
TMP_SECRET="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-secret.env"

PASS_COUNT=0
FAIL_COUNT=0
STATE_BACKUP=""

record() {
  local status="$1"
  local name="$2"
  local detail="$3"
  printf '| %s | %s | %s |\n' "$status" "$name" "$detail" >> "$REPORT_FILE"
  if [[ "$status" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

set_state_value() {
  local key="$1"
  local value="$2"
  python3 - <<PY
from pathlib import Path
path = Path(r"""$STATE_FILE""")
key = r"""$key"""
value = r"""$value"""
lines = path.read_text(encoding="utf-8").splitlines()
needle = f"**{key}**:"
for index, line in enumerate(lines):
    if line.startswith(needle):
        lines[index] = f"{needle} {value}"
        break
else:
    raise SystemExit(f"missing state key: {key}")
path.write_text("\\n".join(lines) + "\\n", encoding="utf-8")
PY
}

cleanup() {
  rm -f "$TMP_SECRET"
  if [[ -n "$STATE_BACKUP" ]]; then
    printf '%s' "$STATE_BACKUP" > "$STATE_FILE"
  fi
}
trap cleanup EXIT INT TERM ERR
STATE_BACKUP="$(cat "$STATE_FILE")"

cat > "$REPORT_FILE" <<EOF
# Gate S Report

Generated: $(date '+%Y-%m-%d %H:%M %z')

| Status | Check | Detail |
|--------|-------|--------|
EOF

if ./scripts/validate_skill.sh >/tmp/gate_s_validate.out 2>/tmp/gate_s_validate.err; then
  record "PASS" "baseline validation" "validate_skill.sh passed"
else
  record "FAIL" "baseline validation" "validate_skill.sh failed"
fi

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "Gate S dry-run smoke test" --context AGENTS.md --context .docs/ai-workflow/state.md --dry-run >/tmp/gate_s_dryrun.out 2>/tmp/gate_s_dryrun.err; then
  if grep -q '"status": "dry-run"' /tmp/gate_s_dryrun.out; then
    record "PASS" "dry-run smoke" "dry-run returned structured JSON"
  else
    record "FAIL" "dry-run smoke" "dry-run output missing expected marker"
  fi
else
  record "FAIL" "dry-run smoke" "dry-run command failed"
fi

set_state_value "Last Gate Passed" "0"

if ./scripts/call_cli.sh --agent .agents/design-synthesizer.md --prompt "This should not execute before Gate S" --execute >/tmp/gate_s_pre_execute.out 2>/tmp/gate_s_pre_execute.err; then
  record "FAIL" "pre-Gate-S execute block" "execute unexpectedly succeeded"
else
  if grep -q 'requires gate S' /tmp/gate_s_pre_execute.err; then
    record "PASS" "pre-Gate-S execute block" "execute correctly blocked"
  else
    record "FAIL" "pre-Gate-S execute block" "wrong failure mode"
  fi
fi

cat > "$TMP_SECRET" <<EOF
OPENAI_API_KEY=fake
EOF

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "Secret scan test" --context .docs/ai-workflow/test-cases/tmp-secret.env --dry-run >/tmp/gate_s_secret.out 2>/tmp/gate_s_secret.err; then
  record "FAIL" "secret scan" "secret-bearing file unexpectedly allowed"
else
  if grep -q 'secret-bearing file blocked' /tmp/gate_s_secret.err; then
    record "PASS" "secret scan" "secret-bearing file correctly blocked"
  else
    record "FAIL" "secret scan" "wrong failure mode"
  fi
fi

set_state_value "Current Delegation Depth" "1"

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "Recursion guard test" --dry-run >/tmp/gate_s_recur.out 2>/tmp/gate_s_recur.err; then
  record "FAIL" "recursion guard" "depth=1 unexpectedly allowed"
else
  if grep -q 'recursion blocked by state guard' /tmp/gate_s_recur.err; then
    record "PASS" "recursion guard" "depth guard correctly blocked"
  else
    record "FAIL" "recursion guard" "wrong failure mode"
  fi
fi

set_state_value "Current Delegation Depth" "0"
set_state_value "Last Gate Passed" "S"

if ./tests/local_pilot_checks.sh >/tmp/gate_s_local_checks.out 2>/tmp/gate_s_local_checks.err; then
  record "PASS" "artifact completeness" "local_pilot_checks.sh passed"
else
  record "FAIL" "artifact completeness" "local_pilot_checks.sh failed"
fi

{
  printf '\n'
  printf 'Summary: %s pass / %s fail\n' "$PASS_COUNT" "$FAIL_COUNT"
} >> "$REPORT_FILE"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

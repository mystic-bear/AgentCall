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
STATE_FILE="$ROOT_DIR/.docs/ai-workflow/state.md"
TMP_DIR="$ROOT_DIR/.docs/ai-workflow/test-cases/hardening-checks"
TMP_SAFE_ENV="$TMP_DIR/.env.example"
TMP_SECRET_ENV="$TMP_DIR/github-token.env"
TMP_AGENT="$TMP_DIR/tmp-frontmatter-agent.md"
TMP_BAD_SCHEMA_AGENT="$TMP_DIR/tmp-bad-schema-agent.md"
TMP_GATE_AGENT="$TMP_DIR/tmp-gate-agent.md"
TMP_OUT="$TMP_DIR/out.json"
TMP_ERR="$TMP_DIR/err.txt"
FAILURES=0
STATE_BACKUP=""

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
  rm -rf "$TMP_DIR"
  if [[ -n "$STATE_BACKUP" ]]; then
    printf '%s' "$STATE_BACKUP" > "$STATE_FILE"
  fi
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"
STATE_BACKUP="$(cat "$STATE_FILE")"
cd "$ROOT_DIR"

cat > "$TMP_SAFE_ENV" <<'EOF'
SAFE_SAMPLE=true
EOF

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "safe sample context" --context "$TMP_SAFE_ENV" --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  echo "OK   .env.example sample context is allowed"
else
  echo "FAIL .env.example sample context should be allowed"
  FAILURES=$((FAILURES + 1))
fi

cat > "$TMP_SECRET_ENV" <<'EOF'
GITHUB_TOKEN=fake
EOF

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "secret token check" --context "$TMP_SECRET_ENV" --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  echo "FAIL GITHUB_TOKEN-bearing context should be blocked"
  FAILURES=$((FAILURES + 1))
elif grep -q 'secret-bearing file blocked' "$TMP_ERR"; then
  echo "OK   GITHUB_TOKEN-bearing context is blocked"
else
  echo "FAIL secret-bearing context failed with the wrong error"
  FAILURES=$((FAILURES + 1))
fi

set_state_value "Current Phase" "post-review: hardening"

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "phase colon check" --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  if grep -q '"phase": "post-review: hardening"' "$TMP_OUT"; then
    echo "OK   state values with colons survive dry-run metadata"
  else
    echo "FAIL phase value containing colon was truncated"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL phase colon dry-run should succeed"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent .agents/architect.md --prompt "context canonicalization check" --context ./AGENTS.md --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  if grep -q '"context_files": \["AGENTS.md"\]' "$TMP_OUT"; then
    echo "OK   dry-run reports canonical root-relative context paths"
  else
    echo "FAIL dry-run still reports non-canonical context paths"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL context canonicalization dry-run should succeed"
  FAILURES=$((FAILURES + 1))
fi

cat > "$TMP_AGENT" <<'EOF'
---
run-agent: claude
role: tmp-frontmatter-check
call-type: review
response-mode: text
strict-schema: false
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 42
allow-recursion: false
requires-human-gate: C
---

# Tmp Frontmatter Check

Respond in concise Markdown.
EOF

if ./scripts/call_cli.sh --agent "$TMP_AGENT" --prompt "frontmatter metadata check" --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  if grep -q '"timeout_sec": 42' "$TMP_OUT" && grep -q '"required_gate": "C"' "$TMP_OUT" && grep -q '"output_schema": ".docs/ai-workflow/schema/common.schema.json"' "$TMP_OUT"; then
    echo "OK   dry-run exposes enforced frontmatter metadata"
  else
    echo "FAIL dry-run is missing enforced frontmatter metadata"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL frontmatter metadata dry-run should succeed"
  FAILURES=$((FAILURES + 1))
fi

cat > "$TMP_BAD_SCHEMA_AGENT" <<'EOF'
---
run-agent: claude
role: tmp-bad-schema-check
response-mode: json-fenced
strict-schema: true
output-schema: .docs/ai-workflow/schema/does-not-exist.json
requires-human-gate: S
---

# Tmp Bad Schema Check

Return JSON.
EOF

if ./scripts/call_cli.sh --agent "$TMP_BAD_SCHEMA_AGENT" --prompt "bad schema check" --dry-run > "$TMP_OUT" 2> "$TMP_ERR"; then
  echo "FAIL missing output schema should fail validation"
  FAILURES=$((FAILURES + 1))
elif grep -q 'output schema file missing' "$TMP_ERR"; then
  echo "OK   missing output schema is rejected"
else
  echo "FAIL missing output schema returned the wrong error"
  FAILURES=$((FAILURES + 1))
fi

cat > "$TMP_GATE_AGENT" <<'EOF'
---
run-agent: unknowncli
role: tmp-gate-check
response-mode: text
strict-schema: false
requires-human-gate: C
---

# Tmp Gate Check

Respond in Markdown.
EOF

set_state_value "Last Gate Passed" "A"

if ./scripts/call_cli.sh --agent "$TMP_GATE_AGENT" --prompt "gate enforcement check" --execute > "$TMP_OUT" 2> "$TMP_ERR"; then
  echo "FAIL insufficient human gate should block execution"
  FAILURES=$((FAILURES + 1))
elif grep -q 'requires gate C' "$TMP_ERR"; then
  echo "OK   insufficient human gate blocks execution before cli dispatch"
else
  echo "FAIL insufficient human gate returned the wrong error"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "hardening_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "hardening_checks passed"

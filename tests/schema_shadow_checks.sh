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
TMP_DIR="$ROOT_DIR/.docs/ai-workflow/test-cases/schema-shadow-checks"
BODY_FILE="$TMP_DIR/body.md"
RESULT_FILE="$TMP_DIR/result.json"
ERR_FILE="$TMP_DIR/err.txt"
FAILURES=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"
cd "$ROOT_DIR"

cat > "$BODY_FILE" <<'EOF'
Summary text.

```json
{
  "schema_version": "1.2",
  "agent": "design-synthesizer",
  "summary": "ok",
  "decisions": [],
  "risks": [],
  "open_questions": [],
  "action_items": [],
  "requested_context": [],
  "status": "completed",
  "needs_human_decision": false,
  "confidence": "0.9"
}
```
EOF

if node ./scripts/check_response_contract.mjs \
  --body-file "$BODY_FILE" \
  --schema-file .docs/ai-workflow/schema/common.schema.json \
  > "$RESULT_FILE" 2> "$ERR_FILE"; then
  echo "FAIL strict type mismatch should fail"
  FAILURES=$((FAILURES + 1))
elif grep -q '"error_kind": "type_mismatch"' "$RESULT_FILE" && grep -q 'confidence' "$RESULT_FILE"; then
  echo "OK   strict type mismatch is reported"
else
  echo "FAIL strict type mismatch returned the wrong result"
  FAILURES=$((FAILURES + 1))
fi

cat > "$BODY_FILE" <<'EOF'
Summary text.

```json
{
  "schema_version": "1.2",
  "agent": "design-synthesizer",
  "summary": [],
  "decisions": [],
  "risks": [],
  "open_questions": [],
  "action_items": [],
  "requested_context": [],
  "status": "completed",
  "needs_human_decision": false,
  "confidence": 0.9
}
```
EOF

if node ./scripts/check_response_contract.mjs \
  --body-file "$BODY_FILE" \
  --schema-file .docs/ai-workflow/schema/common.schema.json \
  > "$RESULT_FILE" 2> "$ERR_FILE"; then
  if grep -q '"ok": true' "$RESULT_FILE" && grep -q '"schema_warning": true' "$RESULT_FILE"; then
    echo "OK   schema mismatch is warning-only in shadow mode"
  else
    echo "FAIL schema mismatch did not stay in warning-only mode"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL schema mismatch should not fail shadow validation"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "schema_shadow_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "schema_shadow_checks passed"

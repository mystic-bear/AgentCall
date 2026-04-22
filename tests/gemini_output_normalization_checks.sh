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
TMP_DIR="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-gemini-normalization"
WRAPPED_IN="$TMP_DIR/wrapped.json"
WRAPPED_OUT="$TMP_DIR/wrapped.out"
PLAIN_IN="$TMP_DIR/plain.txt"
PLAIN_OUT="$TMP_DIR/plain.out"
FAILURES=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"

cat > "$WRAPPED_IN" <<'EOF'
{
  "session_id": "demo",
  "response": "# Review\n\nAll good.\n\n```json\n{\"schema_version\":1.2,\"agent\":\"frontend-designer\",\"summary\":\"ok\",\"decisions\":[],\"risks\":[],\"open_questions\":[],\"action_items\":[],\"requested_context\":[],\"status\":\"completed\",\"needs_human_decision\":false,\"confidence\":0.9}\n```"
}
EOF

cat > "$PLAIN_IN" <<'EOF'
# Plain Output

```json
{"schema_version":"1.2","agent":"architect","summary":"ok","decisions":[],"risks":[],"open_questions":[],"action_items":[],"requested_context":[],"status":"ok","needs_human_decision":false,"confidence":1}
```
EOF

node "$ROOT_DIR/scripts/extract_response_body.mjs" "$WRAPPED_IN" "$WRAPPED_OUT"
node "$ROOT_DIR/scripts/extract_response_body.mjs" "$PLAIN_IN" "$PLAIN_OUT"

if grep -q '^# Review' "$WRAPPED_OUT"; then
  echo "OK   wrapped Gemini JSON extracted into markdown body"
else
  echo "FAIL wrapped Gemini JSON was not extracted"
  FAILURES=$((FAILURES + 1))
fi

if grep -q '^# Plain Output' "$PLAIN_OUT"; then
  echo "OK   plain text output preserved"
else
  echo "FAIL plain text output was not preserved"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "gemini_output_normalization_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "gemini_output_normalization_checks passed"

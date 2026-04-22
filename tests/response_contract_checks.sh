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
TMP_OUT="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-response-contract-dryrun.json"
FAILURES=0

cleanup() {
  rm -f "$TMP_OUT"
}
trap cleanup EXIT

extract_prompt_file() {
  sed -n 's/.*"prompt_file": "\(.*\)",/\1/p' "$1"
}

if ./scripts/call_cli.sh --agent .agents/bug-reviewer.md --prompt "review contract check" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL bug-reviewer dry-run failed"
  exit 1
fi

BUG_PROMPT_FILE="$(extract_prompt_file "$TMP_OUT")"

if grep -q '"response_mode": "text"' "$TMP_OUT" && grep -q '"strict_schema": false' "$TMP_OUT"; then
  echo "OK   bug-reviewer defaults to text mode without strict schema"
else
  echo "FAIL bug-reviewer dry-run metadata did not switch to text mode"
  FAILURES=$((FAILURES + 1))
fi

if grep -q 'Respond in Markdown only\.' "$BUG_PROMPT_FILE" && ! grep -q 'End with a JSON fenced block\.' "$BUG_PROMPT_FILE"; then
  echo "OK   bug-reviewer prompt is text-first"
else
  echo "FAIL bug-reviewer prompt still looks strict-schema"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent .agents/bug-reviewer.md --prompt "review contract check" --strict-schema --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL bug-reviewer strict override dry-run failed"
  exit 1
fi

BUG_STRICT_PROMPT_FILE="$(extract_prompt_file "$TMP_OUT")"

if grep -q '"strict_schema": true' "$TMP_OUT"; then
  echo "OK   bug-reviewer strict-schema override is reflected"
else
  echo "FAIL bug-reviewer strict-schema override missing"
  FAILURES=$((FAILURES + 1))
fi

if grep -q 'End with a JSON fenced block\.' "$BUG_STRICT_PROMPT_FILE"; then
  echo "OK   strict override restores JSON-block instruction"
else
  echo "FAIL strict override did not restore JSON-block instruction"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent .agents/test-hello.md --prompt "smoke contract check" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL test-hello dry-run failed"
  exit 1
fi

HELLO_PROMPT_FILE="$(extract_prompt_file "$TMP_OUT")"

if grep -q '"response_mode": "json-fenced"' "$TMP_OUT" && grep -q '"strict_schema": true' "$TMP_OUT"; then
  echo "OK   test-hello keeps strict schema defaults"
else
  echo "FAIL test-hello strict defaults missing"
  FAILURES=$((FAILURES + 1))
fi

if grep -q 'End with a JSON fenced block\.' "$HELLO_PROMPT_FILE"; then
  echo "OK   test-hello prompt keeps strict JSON instruction"
else
  echo "FAIL test-hello prompt lost strict JSON instruction"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "response_contract_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "response_contract_checks passed"

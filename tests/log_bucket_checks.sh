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
TMP_OUT="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-log-bucket-dryrun.json"
FAILURES=0

cleanup() {
  rm -f "$TMP_OUT"
}
trap cleanup EXIT

if ./scripts/call_cli.sh --agent .agents/bug-reviewer.md --prompt "log bucket check" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL dry-run command failed"
  exit 1
fi

if grep -q '"log_bucket": "debug"' "$TMP_OUT"; then
  echo "OK   dry-run uses debug log bucket"
else
  echo "FAIL dry-run did not report debug log bucket"
  FAILURES=$((FAILURES + 1))
fi

if grep -q '/.docs/ai-workflow/logs/debug/' "$TMP_OUT"; then
  echo "OK   dry-run artifacts are written under logs/debug"
else
  echo "FAIL dry-run artifact paths are not under logs/debug"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "log_bucket_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "log_bucket_checks passed"

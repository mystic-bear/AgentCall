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
TMP_DIR="$ROOT_DIR/.docs/ai-workflow/test-cases/codex-promptfile-checks"
FAKE_BIN="$TMP_DIR/bin"
PROMPT_FILE="$TMP_DIR/prompt.txt"
ARGS_FILE="$TMP_DIR/args.txt"
STDIN_FILE="$TMP_DIR/stdin.txt"
OUT_FILE="$TMP_DIR/out.txt"
ERR_FILE="$TMP_DIR/err.txt"
FAILURES=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_CODEX_ARGS_FILE"
cat > "$FAKE_CODEX_STDIN_FILE"
printf 'fake-codex-ok\n'
EOF
chmod +x "$FAKE_BIN/codex"

cat > "$PROMPT_FILE" <<'EOF'
Prompt delivered through stdin.
EOF

if PATH="$FAKE_BIN:$PATH" FAKE_CODEX_ARGS_FILE="$ARGS_FILE" FAKE_CODEX_STDIN_FILE="$STDIN_FILE" ./scripts/adapters/codex.sh "$PROMPT_FILE" 30 "$OUT_FILE" "$ERR_FILE" false gpt-5.4 ""; then
  :
else
  echo "FAIL codex adapter prompt-file execution failed"
  exit 1
fi

if grep -q '^exec --skip-git-repo-check --model gpt-5.4 -$' "$ARGS_FILE"; then
  echo "OK   codex adapter passes stdin sentinel to codex exec"
else
  echo "FAIL codex adapter did not invoke codex exec with stdin sentinel"
  FAILURES=$((FAILURES + 1))
fi

if cmp -s "$PROMPT_FILE" "$STDIN_FILE"; then
  echo "OK   codex adapter forwards prompt-file content through stdin"
else
  echo "FAIL codex adapter did not forward prompt-file content through stdin"
  FAILURES=$((FAILURES + 1))
fi

if grep -q -- 'codex exec --skip-git-repo-check' "$ROOT_DIR/scripts/adapters/codex.sh" && grep -q -- '<"$PROMPT_FILE"' "$ROOT_DIR/scripts/adapters/codex.sh"; then
  echo "OK   codex adapter uses direct stdin prompt transport"
else
  echo "FAIL codex adapter transport pattern does not match expected stdin usage"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "codex_promptfile_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "codex_promptfile_checks passed"

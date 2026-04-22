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
TMP_AGENT="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-model-agent.md"
TMP_AGENT_NO_MODEL="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-model-default-agent.md"
TMP_AGENT_NO_MODEL_CLAUDE="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-model-default-claude-agent.md"
TMP_AGENT_NO_MODEL_CODEX="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-model-default-codex-agent.md"
TMP_OUT="$ROOT_DIR/.docs/ai-workflow/test-cases/tmp-model-dryrun.json"
FAILURES=0

cleanup() {
  rm -f "$TMP_AGENT" "$TMP_AGENT_NO_MODEL" "$TMP_AGENT_NO_MODEL_CLAUDE" "$TMP_AGENT_NO_MODEL_CODEX" "$TMP_OUT"
}
trap cleanup EXIT

cat > "$TMP_AGENT" <<'EOF'
---
run-agent: claude
role: tmp-model-check
model: claude-test-model
mode: read-only
write-policy: none
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 60
max-context-files: 1
max-context-bytes: 10000
allow-recursion: false
requires-human-gate: S
---

# Tmp Model Check

Return a json fenced block.
EOF

cat > "$TMP_AGENT_NO_MODEL" <<'EOF'
---
run-agent: gemini
role: tmp-provider-default-check
mode: read-only
write-policy: none
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 60
max-context-files: 1
max-context-bytes: 10000
allow-recursion: false
requires-human-gate: S
---

# Tmp Provider Default Check

Return a json fenced block.
EOF

cat > "$TMP_AGENT_NO_MODEL_CLAUDE" <<'EOF'
---
run-agent: claude
role: tmp-provider-default-check-claude
mode: read-only
write-policy: none
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 60
max-context-files: 1
max-context-bytes: 10000
allow-recursion: false
requires-human-gate: S
---

# Tmp Provider Default Check Claude

Return a json fenced block.
EOF

cat > "$TMP_AGENT_NO_MODEL_CODEX" <<'EOF'
---
run-agent: codex
role: tmp-provider-default-check-codex
mode: read-only
write-policy: none
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 60
max-context-files: 1
max-context-bytes: 10000
allow-recursion: false
requires-human-gate: S
---

# Tmp Provider Default Check Codex

Return a json fenced block.
EOF

if ./scripts/call_cli.sh --agent "$TMP_AGENT" --prompt "model check" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL dry-run command failed"
  exit 1
fi

if grep -q '"model": "claude-test-model"' "$TMP_OUT"; then
  echo "OK   frontmatter model appears in dry-run"
else
  echo "FAIL frontmatter model missing in dry-run"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent "$TMP_AGENT" --prompt "model override check" --model "claude-override-model" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL override dry-run command failed"
  exit 1
fi

if grep -q '"model": "claude-override-model"' "$TMP_OUT"; then
  echo "OK   explicit model override appears in dry-run"
else
  echo "FAIL explicit model override missing in dry-run"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent "$TMP_AGENT_NO_MODEL" --prompt "provider default check" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL provider default dry-run command failed"
  exit 1
fi

if grep -q '"model": "gemini-3.1-pro-preview"' "$TMP_OUT"; then
  echo "OK   provider default model appears in dry-run"
else
  echo "FAIL provider default model missing in dry-run"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent "$TMP_AGENT_NO_MODEL_CLAUDE" --prompt "provider default check claude" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL provider default claude dry-run command failed"
  exit 1
fi

if grep -q '"model": "claude-sonnet-4-6"' "$TMP_OUT"; then
  echo "OK   provider default claude model appears in dry-run"
else
  echo "FAIL provider default claude model missing in dry-run"
  FAILURES=$((FAILURES + 1))
fi

if ./scripts/call_cli.sh --agent "$TMP_AGENT_NO_MODEL_CODEX" --prompt "provider default check codex" --dry-run > "$TMP_OUT"; then
  :
else
  echo "FAIL provider default codex dry-run command failed"
  exit 1
fi

if grep -q '"model": "gpt-5.4"' "$TMP_OUT"; then
  echo "OK   provider default codex model appears in dry-run"
else
  echo "FAIL provider default codex model missing in dry-run"
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo
  echo "model_selection_checks failed: $FAILURES issue(s)"
  exit 1
fi

echo
echo "model_selection_checks passed"

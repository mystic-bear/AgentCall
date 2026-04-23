#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)"
INSTALL_ROOT="$(mktemp -d /tmp/agentcall-global-install.XXXXXX)"
trap 'rm -rf "$INSTALL_ROOT"' EXIT

"$ROOT_DIR/scripts/install_global_codex_host.sh" --install-root "$INSTALL_ROOT"
"$ROOT_DIR/scripts/validate_global_codex_host.sh" --install-root "$INSTALL_ROOT"

grep -q 'skills/AgentCall/SKILL.md' "$INSTALL_ROOT/AgentCall/manifests/install-manifest.txt" || {
  echo "ERROR: install manifest missing skill entry" >&2
  exit 1
}

TMP_OUT="$(mktemp /tmp/agentcall-global-install-check.XXXXXX)"
trap 'rm -rf "$INSTALL_ROOT"; rm -f "$TMP_OUT"' EXIT
"$INSTALL_ROOT/AgentCall/scripts/global_call_cli.sh" --agent architect --prompt "Global dry-run runtime check." --project-root "$INSTALL_ROOT" --dry-run > "$TMP_OUT"
grep -q '"runtime_root_mode": "tmp-fallback"' "$TMP_OUT" || {
  echo "ERROR: install check did not use tmp fallback runtime mode" >&2
  exit 1
}

if "$INSTALL_ROOT/AgentCall/scripts/global_call_cli.sh" --agent architect --prompt "invalid root should fail" --project-root /tmp/agentcall-missing-root-for-test --dry-run >/dev/null 2>&1; then
  echo "ERROR: invalid project root was accepted" >&2
  exit 1
fi

TMP_AGENT="$INSTALL_ROOT/invalid-side-effects-agent.md"
cat > "$TMP_AGENT" <<'EOF'
---
run-agent: claude
role: invalid-side-effects
side-effects: typo-value
requires-human-gate: A
---

# Invalid
EOF

if "$INSTALL_ROOT/AgentCall/scripts/normalize_agent_meta.sh" --agent-file "$TMP_AGENT" >/dev/null 2>&1; then
  echo "ERROR: invalid side-effects value was accepted" >&2
  exit 1
fi

echo "global_codex_install_checks passed"

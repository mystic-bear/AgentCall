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

echo "global_codex_install_checks passed"

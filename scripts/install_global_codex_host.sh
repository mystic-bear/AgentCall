#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)"
PACKAGE_ROOT="$ROOT_DIR/codex-global"
INSTALL_ROOT="${HOME}/.codex"
DRY_RUN=false
FORCE_MANAGED_OVERWRITE=false
PRINT_MANIFEST=false

usage() {
  cat <<EOF
Usage:
  ./scripts/install_global_codex_host.sh [--install-root <path>] [--dry-run] [--force-managed-overwrite] [--print-manifest]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force-managed-overwrite)
      FORCE_MANAGED_OVERWRITE=true
      shift
      ;;
    --print-manifest)
      PRINT_MANIFEST=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

SKILL_SRC="$PACKAGE_ROOT/skills/AgentCall"
RUNTIME_SRC="$PACKAGE_ROOT/runtime"
SKILL_DEST="$INSTALL_ROOT/skills/AgentCall"
RUNTIME_DEST="$INSTALL_ROOT/AgentCall"
BACKUP_ROOT="$INSTALL_ROOT/AgentCall-backups"
LEGACY_SKILL_DEST="$INSTALL_ROOT/skills/subagent-host"
LEGACY_RUNTIME_DEST="$INSTALL_ROOT/subagent-host"
LEGACY_BACKUP_ROOT="$INSTALL_ROOT/subagent-host-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
MANIFEST_DEST="$RUNTIME_DEST/manifests/install-manifest.txt"
META_DEST="$RUNTIME_DEST/manifests/install-meta.txt"

[[ -d "$SKILL_SRC" ]] || { echo "ERROR: missing package skill source" >&2; exit 1; }
[[ -d "$RUNTIME_SRC" ]] || { echo "ERROR: missing package runtime source" >&2; exit 1; }

print_manifest() {
  (
    cd "$PACKAGE_ROOT"
    find skills/AgentCall runtime -type f | sort
  )
}

if [[ "$PRINT_MANIFEST" == "true" ]]; then
  print_manifest
  exit 0
fi

if [[ -d "$RUNTIME_DEST" && ! -f "$RUNTIME_DEST/manifests/install-meta.txt" && "$FORCE_MANAGED_OVERWRITE" != "true" ]]; then
  echo "ERROR: existing runtime destination is not marked as managed: $RUNTIME_DEST" >&2
  echo "Use --force-managed-overwrite if you want to replace it." >&2
  exit 1
fi

if [[ -d "$LEGACY_RUNTIME_DEST" && ! -f "$LEGACY_RUNTIME_DEST/manifests/install-meta.txt" && "$FORCE_MANAGED_OVERWRITE" != "true" ]]; then
  echo "ERROR: legacy runtime destination exists but is not marked as managed: $LEGACY_RUNTIME_DEST" >&2
  echo "Use --force-managed-overwrite if you want to replace it." >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN"
  echo "Install root: $INSTALL_ROOT"
  echo "Skill source: $SKILL_SRC"
  echo "Runtime source: $RUNTIME_SRC"
  echo "Skill dest: $SKILL_DEST"
  echo "Runtime dest: $RUNTIME_DEST"
  echo "Backup dir: $BACKUP_DIR"
  echo
  print_manifest
  exit 0
fi

mkdir -p "$INSTALL_ROOT/skills" "$BACKUP_ROOT"

if [[ -d "$SKILL_DEST" ]]; then
  cp -R "$SKILL_DEST" "$BACKUP_DIR-skill"
fi
if [[ -d "$RUNTIME_DEST" ]]; then
  cp -R "$RUNTIME_DEST" "$BACKUP_DIR-runtime"
fi
if [[ -d "$LEGACY_SKILL_DEST" ]]; then
  mkdir -p "$LEGACY_BACKUP_ROOT"
  cp -R "$LEGACY_SKILL_DEST" "$LEGACY_BACKUP_ROOT/$TIMESTAMP-skill"
fi
if [[ -d "$LEGACY_RUNTIME_DEST" ]]; then
  mkdir -p "$LEGACY_BACKUP_ROOT"
  cp -R "$LEGACY_RUNTIME_DEST" "$LEGACY_BACKUP_ROOT/$TIMESTAMP-runtime"
fi

rm -rf "$SKILL_DEST" "$RUNTIME_DEST" "$LEGACY_SKILL_DEST" "$LEGACY_RUNTIME_DEST"
cp -R "$SKILL_SRC" "$SKILL_DEST"
cp -R "$RUNTIME_SRC" "$RUNTIME_DEST"

chmod +x \
  "$RUNTIME_DEST/scripts/global_call_cli.sh" \
  "$RUNTIME_DEST/scripts/normalize_agent_meta.sh" \
  "$RUNTIME_DEST/scripts/adapters/claude.sh" \
  "$RUNTIME_DEST/scripts/adapters/codex.sh" \
  "$RUNTIME_DEST/scripts/adapters/gemini.sh"

mkdir -p "$(dirname "$MANIFEST_DEST")"
{
  echo "# managed files"
  (
    cd "$INSTALL_ROOT"
    find skills/AgentCall AgentCall -type f | sort
  )
} > "$MANIFEST_DEST"

{
  echo "installed_at=$(date -Iseconds)"
  echo "install_root=$INSTALL_ROOT"
  if git -C "$ROOT_DIR" rev-parse --short HEAD >/tmp/agentcall_global_install_commit 2>/dev/null; then
    echo "source_commit=$(cat /tmp/agentcall_global_install_commit)"
  else
    echo "source_commit=unknown"
  fi
} > "$META_DEST"

while IFS= read -r relpath; do
  [[ -z "$relpath" || "$relpath" == \#* ]] && continue
  sha256sum "$INSTALL_ROOT/$relpath"
done < <(sed '1d' "$MANIFEST_DEST") >> "$MANIFEST_DEST"

if ! "$ROOT_DIR/scripts/validate_global_codex_host.sh" --install-root "$INSTALL_ROOT"; then
  echo "Validation failed. Restoring backup..." >&2
  rm -rf "$SKILL_DEST" "$RUNTIME_DEST"
  if [[ -d "$BACKUP_DIR-skill" ]]; then
    cp -R "$BACKUP_DIR-skill" "$SKILL_DEST"
  fi
  if [[ -d "$BACKUP_DIR-runtime" ]]; then
    cp -R "$BACKUP_DIR-runtime" "$RUNTIME_DEST"
  fi
  exit 1
fi

echo "Installed global Codex host to $INSTALL_ROOT"

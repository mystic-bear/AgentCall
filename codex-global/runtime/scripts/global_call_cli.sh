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

SCRIPT_DIR="$(normalize_path "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)")"
RUNTIME_ROOT="$(normalize_path "$(cd "$SCRIPT_DIR/.." && pwd -L)")"
MODEL_DEFAULTS_FILE="$RUNTIME_ROOT/model-defaults.env"
STATE_TEMPLATE="$RUNTIME_ROOT/templates/default-state.md"
NORMALIZER="$SCRIPT_DIR/normalize_agent_meta.sh"

TIMEOUT_SEC=600
MAX_CTX_FILES=10
MAX_CTX_BYTES=500000
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$}"
CORRELATION_ID="${CORRELATION_ID:-$SESSION_ID}"
ALLOW_WRITES="${ALLOW_WRITES:-false}"
EXECUTE=true
DRY_RUN=false
STRICT_SCHEMA_OVERRIDE=""
PROJECT_ROOT_OVERRIDE=""
TIMEOUT_OVERRIDE_SET=false
CLI=""
AGENT_SPEC=""
PROMPT=""
MODEL_NAME=""
CONTEXT_FILES=()
CONTEXT_FILES_CANONICAL=()

readonly EXIT_OK=0
readonly EXIT_CLI_ERROR=1
readonly EXIT_TIMEOUT=2
readonly EXIT_SCHEMA_VIOLATION=3
readonly EXIT_CONTEXT_LIMIT=4
readonly EXIT_USER_ERROR=5
readonly EXIT_RECURSION_BLOCKED=6
readonly EXIT_SECRETS_VIOLATION=7

LOG_BASE="$RUNTIME_ROOT/runtime-data/bootstrap/logs"
LOG_ROOT="$LOG_BASE"
WRAPPER_LOG_FILE="$LOG_BASE/wrapper-bootstrap.log"

log_line() {
  local log_root="${LOG_ROOT:-$LOG_BASE}"
  local wrapper_log="${WRAPPER_LOG_FILE:-$LOG_BASE/wrapper-bootstrap.log}"
  mkdir -p "$log_root"
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$wrapper_log"
}

prompt_hash() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    wc -c "$file" | awk '{print "bytes-" $1}'
  fi
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_array_from_args() {
  local first=true
  printf '['
  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

normalize_bool() {
  local value="${1:-}"
  local fallback="${2:-false}"
  case "$value" in
    true|TRUE|yes|YES|1) printf 'true' ;;
    false|FALSE|no|NO|0) printf 'false' ;;
    "") printf '%s' "$fallback" ;;
    *) printf '%s' "$fallback" ;;
  esac
}

load_model_defaults() {
  if [[ -f "$MODEL_DEFAULTS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$MODEL_DEFAULTS_FILE"
  fi
}

default_model_for_cli() {
  local cli="$1"
  case "$cli" in
    claude) printf '%s' "${CLAUDE_DEFAULT_MODEL:-}" ;;
    gemini) printf '%s' "${GEMINI_DEFAULT_MODEL:-}" ;;
    codex) printf '%s' "${CODEX_DEFAULT_MODEL:-}" ;;
    *) printf '' ;;
  esac
}

default_log_bucket() {
  local dry_run="$1"
  local role="${2:-}"
  local call_type="${3:-}"
  local session_id="${4:-}"

  if [[ "$dry_run" == "true" ]]; then
    printf 'debug'
    return
  fi
  case "$role" in
    test-hello|tmp-*|tmp_*) printf 'debug'; return ;;
  esac
  case "$call_type" in
    smoke) printf 'debug'; return ;;
  esac
  case "$session_id" in
    tmp-*|tmp_*) printf 'debug'; return ;;
  esac
  printf 'production'
}

validate_log_bucket() {
  case "${1:-}" in
    production|debug) return 0 ;;
    *) return 1 ;;
  esac
}

gate_rank() {
  local gate="${1:-none}"
  case "$gate" in
    none|0|"") printf '0' ;;
    A) printf '1' ;;
    B) printf '2' ;;
    C) printf '3' ;;
    S) printf '4' ;;
    *) printf '-1' ;;
  esac
}

gate_at_least() {
  local actual="$1"
  local required="$2"
  local actual_rank required_rank
  actual_rank="$(gate_rank "$actual")"
  required_rank="$(gate_rank "$required")"
  [[ "$actual_rank" -ge 0 && "$required_rank" -ge 0 && "$actual_rank" -ge "$required_rank" ]]
}

state_value() {
  local key="$1"
  awk -v prefix="**${key}**: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$STATE_FILE"
}

has_secrets() {
  local file="$1"
  local base
  base="$(basename "$file")"
  case "$base" in
    .env.example|.env.sample|.env.template|*.example.env|*.sample.env|*.template.env) ;;
    .env|*.pem|*.key|id_rsa|id_ed25519|secrets.*) return 0 ;;
    .env.*) return 0 ;;
  esac
  if grep -Eq 'OPENAI_API_KEY|ANTHROPIC_API_KEY|GOOGLE_API_KEY|AWS_SECRET_ACCESS_KEY|STRIPE_SECRET_KEY|GITHUB_TOKEN|HF_TOKEN|BEGIN [A-Z ]*PRIVATE KEY' "$file"; then
    return 0
  fi
  return 1
}

resolve_project_root() {
  if [[ -n "$PROJECT_ROOT_OVERRIDE" ]]; then
    normalize_path "$(cd "$PROJECT_ROOT_OVERRIDE" && pwd -L)"
    return
  fi
  if git -C "$PWD" rev-parse --show-toplevel >/tmp/agentcall_global_git_root 2>/dev/null; then
    normalize_path "$(cat /tmp/agentcall_global_git_root)"
    return
  fi
  normalize_path "$PWD"
}

project_key() {
  local path="$1"
  local base hash
  base="$(basename "$path")"
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(printf '%s' "$path" | sha256sum | awk '{print substr($1,1,8)}')"
  else
    hash="$(printf '%s' "$path" | shasum -a 256 | awk '{print substr($1,1,8)}')"
  fi
  printf '%s-%s' "$base" "$hash"
}

allowed_path() {
  local path="$1"
  case "$path" in
    "$PROJECT_ROOT"/*|"$RUNTIME_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

canonicalize_existing_file() {
  local input="$1"
  local path candidates=()
  if [[ "$input" == /* ]]; then
    candidates+=("$input")
  else
    candidates+=("$PWD/$input" "$PROJECT_ROOT/$input" "$RUNTIME_ROOT/$input")
  fi
  for path in "${candidates[@]}"; do
    if [[ -f "$path" ]]; then
      path="$(
        cd "$(dirname "$path")"
        printf '%s/%s\n' "$(pwd -L)" "$(basename "$path")"
      )"
      path="$(normalize_path "$path")"
      if allowed_path "$path"; then
        printf '%s\n' "$path"
        return 0
      fi
    fi
  done
  return 1
}

resolve_agent_file() {
  local spec="$1"
  local path=""
  if [[ "$spec" == */* || "$spec" == *.md ]]; then
    canonicalize_existing_file "$spec" && return 0
  fi

  for path in \
    "$PROJECT_ROOT/.agents/$spec" \
    "$PROJECT_ROOT/.agents/$spec.md" \
    "$RUNTIME_ROOT/agents/$spec" \
    "$RUNTIME_ROOT/agents/$spec.md"; do
    if [[ -f "$path" ]]; then
      normalize_path "$path"
      return 0
    fi
  done
  return 1
}

ensure_fallback_state() {
  [[ -f "$STATE_TEMPLATE" ]] || { echo "ERROR: missing fallback state template" >&2; exit "$EXIT_USER_ERROR"; }
  mkdir -p "$(dirname "$STATE_FILE")"
  if [[ ! -f "$STATE_FILE" ]]; then
    sed "s/__LAST_UPDATED__/$(date -Iseconds)/" "$STATE_TEMPLATE" > "$STATE_FILE"
  fi
}

resolve_schema_path() {
  local raw="${1:-}"
  local path
  [[ -n "$raw" ]] || return 0
  for path in \
    "$PROJECT_ROOT/$raw" \
    "$RUNTIME_ROOT/$raw" \
    "$RUNTIME_ROOT/${raw#.docs/ai-workflow/}"; do
    if [[ -f "$path" ]]; then
      normalize_path "$path"
      return 0
    fi
  done
  return 1
}

root_relative_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_ROOT"/* ]]; then
    printf '%s' "${path#$PROJECT_ROOT/}"
  elif [[ "$path" == "$RUNTIME_ROOT"/* ]]; then
    printf 'global:%s' "${path#$RUNTIME_ROOT/}"
  else
    printf '%s' "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli) CLI="$2"; shift 2 ;;
    --agent) AGENT_SPEC="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --model) MODEL_NAME="$2"; shift 2 ;;
    --context) CONTEXT_FILES+=("$2"); shift 2 ;;
    --timeout) TIMEOUT_SEC="$2"; TIMEOUT_OVERRIDE_SET=true; shift 2 ;;
    --project-root) PROJECT_ROOT_OVERRIDE="$2"; shift 2 ;;
    --session-id) SESSION_ID="$2"; CORRELATION_ID="${CORRELATION_ID:-$2}"; shift 2 ;;
    --correlation-id) CORRELATION_ID="$2"; shift 2 ;;
    --execute) EXECUTE=true; DRY_RUN=false; shift ;;
    --dry-run) DRY_RUN=true; EXECUTE=false; shift ;;
    --strict-schema) STRICT_SCHEMA_OVERRIDE="true"; shift ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit "$EXIT_USER_ERROR"
      ;;
  esac
done

[[ -n "$AGENT_SPEC" ]] || { echo "ERROR: --agent required" >&2; exit "$EXIT_USER_ERROR"; }
[[ -n "$PROMPT" ]] || { echo "ERROR: --prompt required" >&2; exit "$EXIT_USER_ERROR"; }

PROJECT_ROOT="$(resolve_project_root)"
PROJECT_KEY="$(project_key "$PROJECT_ROOT")"
LOCAL_STATE_FILE="$PROJECT_ROOT/.docs/ai-workflow/state.md"
LOCAL_LOG_BASE="$PROJECT_ROOT/.docs/ai-workflow/logs"
FALLBACK_ROOT="$RUNTIME_ROOT/runtime-data/$PROJECT_KEY"
FALLBACK_STATE_FILE="$FALLBACK_ROOT/state.md"
FALLBACK_LOG_BASE="$FALLBACK_ROOT/logs"

if [[ -f "$LOCAL_STATE_FILE" ]]; then
  STATE_FILE="$LOCAL_STATE_FILE"
  LOG_BASE="$LOCAL_LOG_BASE"
else
  STATE_FILE="$FALLBACK_STATE_FILE"
  LOG_BASE="$FALLBACK_LOG_BASE"
  ensure_fallback_state
fi

LOG_ROOT="$LOG_BASE"
WRAPPER_LOG_FILE="$LOG_BASE/wrapper-bootstrap.log"

AGENT_FILE="$(resolve_agent_file "$AGENT_SPEC")" || { echo "ERROR: agent file not found: $AGENT_SPEC" >&2; exit "$EXIT_USER_ERROR"; }
[[ -x "$NORMALIZER" ]] || { echo "ERROR: missing normalizer: $NORMALIZER" >&2; exit "$EXIT_USER_ERROR"; }
eval "$("$NORMALIZER" --agent-file "$AGENT_FILE")"

load_model_defaults

if [[ -z "$CLI" ]]; then
  CLI="$AGENT_RUN_AGENT"
fi
[[ -n "$CLI" ]] || { echo "ERROR: run-agent could not be resolved" >&2; exit "$EXIT_USER_ERROR"; }

if [[ -z "$MODEL_NAME" && -n "$AGENT_MODEL" ]]; then
  MODEL_NAME="$AGENT_MODEL"
fi
if [[ -z "$MODEL_NAME" ]]; then
  MODEL_NAME="$(default_model_for_cli "$CLI")"
fi

CALL_TYPE="$AGENT_CALL_TYPE"
RESPONSE_MODE="$AGENT_RESPONSE_MODE"
STRICT_SCHEMA="$AGENT_STRICT_SCHEMA"
REQUIRED_GATE="$AGENT_REQUIRED_GATE"
if [[ "$TIMEOUT_OVERRIDE_SET" != "true" && -n "${AGENT_TIMEOUT_SEC:-}" ]]; then
  TIMEOUT_SEC="$AGENT_TIMEOUT_SEC"
fi
if [[ -n "${AGENT_MAX_CONTEXT_FILES:-}" ]]; then
  MAX_CTX_FILES="$AGENT_MAX_CONTEXT_FILES"
fi
if [[ -n "${AGENT_MAX_CONTEXT_BYTES:-}" ]]; then
  MAX_CTX_BYTES="$AGENT_MAX_CONTEXT_BYTES"
fi
ALLOW_RECURSION="${AGENT_ALLOW_RECURSION:-false}"

if [[ -n "$STRICT_SCHEMA_OVERRIDE" ]]; then
  STRICT_SCHEMA="$STRICT_SCHEMA_OVERRIDE"
fi

OUTPUT_SCHEMA_FILE=""
OUTPUT_SCHEMA_RELATIVE=""
if [[ -n "${AGENT_OUTPUT_SCHEMA:-}" ]]; then
  OUTPUT_SCHEMA_FILE="$(resolve_schema_path "$AGENT_OUTPUT_SCHEMA")" || { echo "ERROR: output schema file missing: $AGENT_OUTPUT_SCHEMA" >&2; exit "$EXIT_USER_ERROR"; }
  OUTPUT_SCHEMA_RELATIVE="$(root_relative_path "$OUTPUT_SCHEMA_FILE")"
fi

CURRENT_DEPTH="$(state_value "Current Delegation Depth")"
LAST_GATE="$(state_value "Last Gate Passed")"
CURRENT_PHASE="$(state_value "Current Phase")"

if [[ "${CURRENT_DEPTH:-0}" != "0" && "${ALLOW_RECURSION:-false}" != "true" ]]; then
  echo "ERROR: recursion blocked by state guard" >&2
  exit "$EXIT_RECURSION_BLOCKED"
fi

if [[ ${#CONTEXT_FILES[@]} -gt "$MAX_CTX_FILES" ]]; then
  echo "ERROR: too many context files (${#CONTEXT_FILES[@]} > $MAX_CTX_FILES)" >&2
  exit "$EXIT_CONTEXT_LIMIT"
fi

LOG_BUCKET="$(default_log_bucket "$DRY_RUN" "$AGENT_ROLE" "$CALL_TYPE" "$SESSION_ID")"
SESSION_DIR="$LOG_BASE/$LOG_BUCKET/$SESSION_ID"
mkdir -p "$SESSION_DIR"
LOG_ROOT="$LOG_BASE/$LOG_BUCKET"
WRAPPER_LOG_FILE="$LOG_ROOT/wrapper.log"
STDOUT_FILE="$SESSION_DIR/${CLI}.stdout"
STDERR_FILE="$SESSION_DIR/${CLI}.stderr"
PROMPT_FILE="$SESSION_DIR/prompt.txt"
BODY_FILE="$SESSION_DIR/body.txt"
DECISION_FILE="$SESSION_DIR/host-skill-decision.json"

TOTAL_BYTES=0
CONTEXT_BLOCK=""
for item in "${CONTEXT_FILES[@]}"; do
  file="$(canonicalize_existing_file "$item")" || { echo "ERROR: missing context file: $item" >&2; exit "$EXIT_USER_ERROR"; }
  if has_secrets "$file"; then
    echo "ERROR: secret-bearing file blocked: $file" >&2
    exit "$EXIT_SECRETS_VIOLATION"
  fi
  CONTEXT_FILES_CANONICAL+=("$(root_relative_path "$file")")
  size="$(wc -c < "$file")"
  TOTAL_BYTES=$((TOTAL_BYTES + size))
  if [[ "$TOTAL_BYTES" -gt "$MAX_CTX_BYTES" ]]; then
    echo "ERROR: context bytes exceeded ($TOTAL_BYTES > $MAX_CTX_BYTES)" >&2
    exit "$EXIT_CONTEXT_LIMIT"
  fi
  CONTEXT_BLOCK+=$'\n\n--- File: '"$(root_relative_path "$file")"$' ---\n'
  CONTEXT_BLOCK+="$(cat "$file")"
done

AGENT_BODY="$(
  awk '
    BEGIN { fm=0 }
    /^---$/ { fm++; next }
    fm >= 2 { print }
  ' "$AGENT_FILE"
)"

if [[ "$STRICT_SCHEMA" == "true" ]]; then
  IMPORTANT_BLOCK=$'IMPORTANT:\n- End with a JSON fenced block.\n- Include all required common schema keys.\n- Do not add free-form prose after the JSON block.'
else
  IMPORTANT_BLOCK=$'IMPORTANT:\n- Respond in Markdown only.\n- Keep the output text-first.\n- Do not append a JSON block unless explicitly asked.'
fi

cat >"$PROMPT_FILE" <<EOF
You are acting according to the following role definition:

---
$AGENT_BODY
---

Global subagent host rules:
- Prefer the current project's local context when provided.
- Do not call another delegated agent.
- Stay read-only unless explicit write approval exists.
- If the current project does not have a local AgentCall runtime, you are operating in global fallback mode.

Current state snapshot:
- Phase: ${CURRENT_PHASE:-unknown}
- Last Gate Passed: ${LAST_GATE:-none}
- Delegation Depth: ${CURRENT_DEPTH:-0}
- Project Root: ${PROJECT_ROOT}

Task:
$PROMPT

Context:
$CONTEXT_BLOCK

$IMPORTANT_BLOCK
EOF

PROMPT_HASH="$(prompt_hash "$PROMPT_FILE")"

cat >"$DECISION_FILE" <<EOF
{
  "schema_version": "global-0.1",
  "agent": "host-skill",
  "selected_agent": "$(json_escape "${AGENT_ROLE:-unknown}")",
  "selected_cli": "$(json_escape "$CLI")",
  "model": "$(json_escape "${MODEL_NAME:-}")",
  "call_type": "$(json_escape "$CALL_TYPE")",
  "log_bucket": "$(json_escape "$LOG_BUCKET")",
  "response_mode": "$(json_escape "$RESPONSE_MODE")",
  "strict_schema": $( [[ "$STRICT_SCHEMA" == "true" ]] && printf 'true' || printf 'false' ),
  "timeout_sec": $TIMEOUT_SEC,
  "required_gate": "$(json_escape "$REQUIRED_GATE")",
  "output_schema": "$(json_escape "$OUTPUT_SCHEMA_RELATIVE")",
  "state_mode": "$( [[ -f "$LOCAL_STATE_FILE" ]] && printf 'project-local' || printf 'global-fallback' )",
  "project_root": "$(json_escape "$PROJECT_ROOT")",
  "context_files": $(json_array_from_args "${CONTEXT_FILES_CANONICAL[@]}"),
  "prompt_hash": "$(json_escape "$PROMPT_HASH")",
  "meta_source": "$(json_escape "${AGENT_META_SOURCE:-unknown}")",
  "last_gate_passed": "$(json_escape "${LAST_GATE:-none}")"
}
EOF

log_line "INVOKE session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI agent=$AGENT_ROLE project_root=$PROJECT_ROOT prompt_hash=$PROMPT_HASH dry_run=$DRY_RUN"

if [[ "$DRY_RUN" == "true" ]]; then
  cat <<EOF
{
  "status": "dry-run",
  "session_id": "$(json_escape "$SESSION_ID")",
  "cli": "$(json_escape "$CLI")",
  "model": "$(json_escape "${MODEL_NAME:-}")",
  "agent": "$(json_escape "${AGENT_ROLE:-unknown}")",
  "call_type": "$(json_escape "$CALL_TYPE")",
  "log_bucket": "$(json_escape "$LOG_BUCKET")",
  "response_mode": "$(json_escape "$RESPONSE_MODE")",
  "strict_schema": $( [[ "$STRICT_SCHEMA" == "true" ]] && printf 'true' || printf 'false' ),
  "required_gate": "$(json_escape "$REQUIRED_GATE")",
  "state_mode": "$( [[ -f "$LOCAL_STATE_FILE" ]] && printf 'project-local' || printf 'global-fallback' )",
  "project_root": "$(json_escape "$PROJECT_ROOT")",
  "prompt_file": "$(json_escape "$PROMPT_FILE")",
  "decision_file": "$(json_escape "$DECISION_FILE")",
  "context_files": $(json_array_from_args "${CONTEXT_FILES_CANONICAL[@]}")
}
EOF
  exit "$EXIT_OK"
fi

if ! gate_at_least "${LAST_GATE:-none}" "$REQUIRED_GATE"; then
  echo "ERROR: execution blocked because agent requires gate $REQUIRED_GATE but current gate is ${LAST_GATE:-none}" >&2
  exit "$EXIT_USER_ERROR"
fi

case "$CLI" in
  claude|codex|gemini) ;;
  *)
    echo "ERROR: unknown cli: $CLI" >&2
    exit "$EXIT_USER_ERROR"
    ;;
esac

ADAPTER="$SCRIPT_DIR/adapters/${CLI}.sh"
[[ -x "$ADAPTER" ]] || { echo "ERROR: missing adapter: $ADAPTER" >&2; exit "$EXIT_USER_ERROR"; }

set +e
"$ADAPTER" "$PROMPT_FILE" "$TIMEOUT_SEC" "$STDOUT_FILE" "$STDERR_FILE" "$ALLOW_WRITES" "$MODEL_NAME" "$OUTPUT_SCHEMA_FILE"
RC=$?
set -e

if [[ "$RC" -eq 124 ]]; then
  exit "$EXIT_TIMEOUT"
elif [[ "$RC" -ne 0 ]]; then
  exit "$EXIT_CLI_ERROR"
fi

if command -v node >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/extract_response_body.mjs" ]]; then
  node "$SCRIPT_DIR/extract_response_body.mjs" "$STDOUT_FILE" "$BODY_FILE"
else
  cp "$STDOUT_FILE" "$BODY_FILE"
fi

if [[ "$STRICT_SCHEMA" != "true" ]]; then
  cat "$BODY_FILE"
  exit "$EXIT_OK"
fi

JSON_BLOCK="$(awk '/^```json$/{flag=1; next} /^```$/{flag=0} flag' "$BODY_FILE" || true)"
if [[ -z "$JSON_BLOCK" ]]; then
  echo "ERROR: response missing required JSON block" >&2
  exit "$EXIT_SCHEMA_VIOLATION"
fi

REQUIRED_KEYS=(schema_version agent summary decisions risks open_questions action_items requested_context status needs_human_decision confidence)
for key in "${REQUIRED_KEYS[@]}"; do
  if command -v jq >/dev/null 2>&1; then
    if ! printf '%s\n' "$JSON_BLOCK" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
      echo "ERROR: response JSON missing required key: $key" >&2
      exit "$EXIT_SCHEMA_VIOLATION"
    fi
  else
    if ! printf '%s\n' "$JSON_BLOCK" | grep -q "\"$key\""; then
      echo "ERROR: response JSON missing required key: $key" >&2
      exit "$EXIT_SCHEMA_VIOLATION"
    fi
  fi
done

cat "$BODY_FILE"

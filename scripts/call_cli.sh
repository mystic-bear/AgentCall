#!/usr/bin/env bash
# Project-local delegated CLI wrapper.
# Defaults to execute for normal use; dry-run is reserved for wrapper/debug checks.

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

SCRIPT_ROOT="$(normalize_path "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)")"
CURRENT_DIR_NORMALIZED="$(normalize_path "$PWD")"
if [[ -f "$CURRENT_DIR_NORMALIZED/AGENTS.md" && -d "$CURRENT_DIR_NORMALIZED/scripts" && -d "$CURRENT_DIR_NORMALIZED/.docs/ai-workflow" ]]; then
  ROOT_DIR="$CURRENT_DIR_NORMALIZED"
else
  ROOT_DIR="$SCRIPT_ROOT"
fi
STATE_FILE="$ROOT_DIR/.docs/ai-workflow/state.md"
LOG_BASE="$ROOT_DIR/.docs/ai-workflow/logs"
MODEL_DEFAULTS_FILE="$ROOT_DIR/.docs/ai-workflow/model-defaults.env"

TIMEOUT_SEC=600
MAX_CTX_FILES=10
MAX_CTX_BYTES=500000
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$}"
CORRELATION_ID="${CORRELATION_ID:-$SESSION_ID}"
ALLOW_WRITES="${ALLOW_WRITES:-false}"
EXECUTE=true
DRY_RUN=false
STRICT_SCHEMA_OVERRIDE=""
LOG_BUCKET_OVERRIDE=""
TIMEOUT_OVERRIDE_SET=false

CLI=""
AGENT_FILE=""
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
LOG_ROOT="$LOG_BASE"
WRAPPER_LOG_FILE="$LOG_BASE/wrapper-bootstrap.log"

canonicalize_existing_file() {
  local input="$1"
  local path="$input"
  if [[ "$path" != /* ]]; then
    path="$ROOT_DIR/$path"
  fi
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  path="$(
    cd "$(dirname "$path")"
    printf '%s/%s\n' "$(pwd -L)" "$(basename "$path")"
  )"
  normalize_path "$path"
}

require_within_root() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*) ;;
    *)
      echo "ERROR: path outside project root is not allowed: $path" >&2
      exit "$EXIT_USER_ERROR"
      ;;
  esac
}

state_value() {
  local key="$1"
  awk -v prefix="**${key}**: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$STATE_FILE"
}

fm_value() {
  local key="$1"
  awk -v prefix="${key}: " '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm = !in_fm; next }
    in_fm && index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }
  ' "$AGENT_FILE"
}

extract_agent_body() {
  awk '
    BEGIN { fm=0 }
    /^---$/ { fm++; next }
    fm >= 2 { print }
  ' "$AGENT_FILE"
}

log_line() {
  local log_root="${LOG_ROOT:-$LOG_BASE}"
  local wrapper_log="${WRAPPER_LOG_FILE:-$LOG_BASE/wrapper-bootstrap.log}"
  mkdir -p "$log_root"
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$wrapper_log"
}

has_secrets() {
  local file="$1"
  local base
  base="$(basename "$file")"
  case "$base" in
    # Allowlist first: template/sample env files are safe to include as context.
    .env.example|.env.sample|.env.template|*.example.env|*.sample.env|*.template.env) ;;
    # Deny actual env files, key material, and conventionally sensitive filenames.
    .env|*.pem|*.key|id_rsa|id_ed25519|secrets.*) return 0 ;;
    .env.*) return 0 ;;
  esac

  if grep -Eq 'OPENAI_API_KEY|ANTHROPIC_API_KEY|GOOGLE_API_KEY|AWS_SECRET_ACCESS_KEY|STRIPE_SECRET_KEY|GITHUB_TOKEN|HF_TOKEN|BEGIN [A-Z ]*PRIVATE KEY' "$file"; then
    return 0
  fi
  return 1
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

load_model_defaults() {
  if [[ -f "$MODEL_DEFAULTS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$MODEL_DEFAULTS_FILE"
  fi
}

default_model_for_cli() {
  local cli="$1"
  case "$cli" in
    claude)
      printf '%s' "${CLAUDE_DEFAULT_MODEL:-}"
      ;;
    gemini)
      printf '%s' "${GEMINI_DEFAULT_MODEL:-}"
      ;;
    codex)
      printf '%s' "${CODEX_DEFAULT_MODEL:-}"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

root_relative_path() {
  local path="$1"
  printf '%s' "${path#$ROOT_DIR/}"
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

default_call_type_for_role() {
  local role="${1:-}"
  case "$role" in
    bug-reviewer|frontend-designer)
      printf 'review'
      ;;
    architect)
      printf 'design'
      ;;
    integrator)
      printf 'plan'
      ;;
    design-synthesizer)
      printf 'synthesis'
      ;;
    test-hello)
      printf 'smoke'
      ;;
    *)
      printf 'advisory'
      ;;
  esac
}

default_response_mode_for_call_type() {
  local call_type="${1:-advisory}"
  case "$call_type" in
    synthesis|smoke)
      printf 'json-fenced'
      ;;
    *)
      printf 'text'
      ;;
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
    test-hello|tmp-*|tmp_*)
      printf 'debug'
      return
      ;;
  esac

  case "$call_type" in
    smoke)
      printf 'debug'
      return
      ;;
  esac

  case "$session_id" in
    tmp-*|tmp_*)
      printf 'debug'
      return
      ;;
  esac

  printf 'production'
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

validate_log_bucket() {
  local bucket="${1:-}"
  case "$bucket" in
    production|debug) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli) CLI="$2"; shift 2 ;;
    --agent) AGENT_FILE="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --model) MODEL_NAME="$2"; shift 2 ;;
    --context) CONTEXT_FILES+=("$2"); shift 2 ;;
    --timeout) TIMEOUT_SEC="$2"; TIMEOUT_OVERRIDE_SET=true; shift 2 ;;
    --max-context-files) MAX_CTX_FILES="$2"; shift 2 ;;
    --max-context-bytes) MAX_CTX_BYTES="$2"; shift 2 ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --correlation-id) CORRELATION_ID="$2"; shift 2 ;;
    --execute) EXECUTE=true; DRY_RUN=false; shift ;;
    --dry-run) DRY_RUN=true; EXECUTE=false; shift ;;
    --strict-schema) STRICT_SCHEMA_OVERRIDE="true"; shift ;;
    --log-bucket) LOG_BUCKET_OVERRIDE="$2"; shift 2 ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit "$EXIT_USER_ERROR"
      ;;
  esac
done

[[ -f "$STATE_FILE" ]] || { echo "ERROR: missing state file: $STATE_FILE" >&2; exit "$EXIT_USER_ERROR"; }
[[ -n "$AGENT_FILE" ]] || { echo "ERROR: --agent required" >&2; exit "$EXIT_USER_ERROR"; }
[[ -n "$PROMPT" ]] || { echo "ERROR: --prompt required" >&2; exit "$EXIT_USER_ERROR"; }

load_model_defaults

AGENT_FILE="$(canonicalize_existing_file "$AGENT_FILE")" || { echo "ERROR: agent file missing" >&2; exit "$EXIT_USER_ERROR"; }
require_within_root "$AGENT_FILE"

if [[ -z "$CLI" ]]; then
  CLI="$(fm_value "run-agent")"
fi
[[ -n "$CLI" ]] || { echo "ERROR: run-agent missing in agent file" >&2; exit "$EXIT_USER_ERROR"; }

AGENT_ROLE="$(fm_value "role")"
FRONTMATTER_MODEL="$(fm_value "model" || true)"
ROLE_TIMEOUT_SEC="$(fm_value "timeout-sec" || true)"
ROLE_MAX_CTX_FILES="$(fm_value "max-context-files" || true)"
ROLE_MAX_CTX_BYTES="$(fm_value "max-context-bytes" || true)"
ALLOW_RECURSION="$(fm_value "allow-recursion" || true)"
CALL_TYPE="$(fm_value "call-type" || true)"
RESPONSE_MODE="$(fm_value "response-mode" || true)"
STRICT_SCHEMA_FRONTMATTER="$(fm_value "strict-schema" || true)"
OUTPUT_SCHEMA_RAW="$(fm_value "output-schema" || true)"
REQUIRED_GATE="$(fm_value "requires-human-gate" || true)"

if [[ -z "$MODEL_NAME" && -n "$FRONTMATTER_MODEL" ]]; then
  MODEL_NAME="$FRONTMATTER_MODEL"
fi
if [[ -z "$MODEL_NAME" ]]; then
  MODEL_NAME="$(default_model_for_cli "$CLI")"
fi

if [[ "$TIMEOUT_OVERRIDE_SET" != "true" && -n "$ROLE_TIMEOUT_SEC" ]]; then
  TIMEOUT_SEC="$ROLE_TIMEOUT_SEC"
fi
if [[ -n "$ROLE_MAX_CTX_FILES" ]]; then
  MAX_CTX_FILES="$ROLE_MAX_CTX_FILES"
fi
if [[ -n "$ROLE_MAX_CTX_BYTES" ]]; then
  MAX_CTX_BYTES="$ROLE_MAX_CTX_BYTES"
fi

if [[ -z "$CALL_TYPE" ]]; then
  CALL_TYPE="$(default_call_type_for_role "$AGENT_ROLE")"
fi
if [[ -z "$RESPONSE_MODE" ]]; then
  RESPONSE_MODE="$(default_response_mode_for_call_type "$CALL_TYPE")"
fi

STRICT_SCHEMA="$(normalize_bool "$STRICT_SCHEMA_FRONTMATTER" "")"
if [[ -z "$STRICT_SCHEMA" ]]; then
  if [[ "$RESPONSE_MODE" == "json-fenced" ]]; then
    STRICT_SCHEMA="true"
  else
    STRICT_SCHEMA="false"
  fi
fi
if [[ -n "$STRICT_SCHEMA_OVERRIDE" ]]; then
  STRICT_SCHEMA="$STRICT_SCHEMA_OVERRIDE"
fi

if [[ -z "$REQUIRED_GATE" ]]; then
  REQUIRED_GATE="S"
fi

OUTPUT_SCHEMA_FILE=""
OUTPUT_SCHEMA_RELATIVE=""
if [[ -n "$OUTPUT_SCHEMA_RAW" ]]; then
  OUTPUT_SCHEMA_FILE="$(canonicalize_existing_file "$OUTPUT_SCHEMA_RAW")" || { echo "ERROR: output schema file missing: $OUTPUT_SCHEMA_RAW" >&2; exit "$EXIT_USER_ERROR"; }
  require_within_root "$OUTPUT_SCHEMA_FILE"
  OUTPUT_SCHEMA_RELATIVE="$(root_relative_path "$OUTPUT_SCHEMA_FILE")"
fi

LOG_BUCKET="$(default_log_bucket "$DRY_RUN" "$AGENT_ROLE" "$CALL_TYPE" "$SESSION_ID")"
if [[ -n "$LOG_BUCKET_OVERRIDE" ]]; then
  if ! validate_log_bucket "$LOG_BUCKET_OVERRIDE"; then
    echo "ERROR: invalid --log-bucket value: $LOG_BUCKET_OVERRIDE" >&2
    exit "$EXIT_USER_ERROR"
  fi
  LOG_BUCKET="$LOG_BUCKET_OVERRIDE"
fi
LOG_ROOT="$LOG_BASE/$LOG_BUCKET"
WRAPPER_LOG_FILE="$LOG_ROOT/wrapper.log"

CURRENT_DEPTH="$(state_value "Current Delegation Depth")"
LAST_GATE="$(state_value "Last Gate Passed")"
CURRENT_PHASE="$(state_value "Current Phase")"

if [[ "${CURRENT_DEPTH:-0}" != "0" && "${ALLOW_RECURSION:-false}" != "true" ]]; then
  echo "ERROR: recursion blocked by state guard" >&2
  log_line "RECURSION_BLOCKED session=$SESSION_ID correlation=$CORRELATION_ID agent=$AGENT_ROLE cli=$CLI"
  exit "$EXIT_RECURSION_BLOCKED"
fi

if [[ ${#CONTEXT_FILES[@]} -gt "$MAX_CTX_FILES" ]]; then
  echo "ERROR: too many context files (${#CONTEXT_FILES[@]} > $MAX_CTX_FILES)" >&2
  exit "$EXIT_CONTEXT_LIMIT"
fi

SESSION_DIR="$LOG_ROOT/$SESSION_ID"
mkdir -p "$SESSION_DIR"
STDOUT_FILE="$SESSION_DIR/${CLI}.stdout"
STDERR_FILE="$SESSION_DIR/${CLI}.stderr"
PROMPT_FILE="$SESSION_DIR/prompt.txt"
BODY_FILE="$SESSION_DIR/body.txt"
DECISION_FILE="$SESSION_DIR/host-skill-decision.json"

TOTAL_BYTES=0
CONTEXT_BLOCK=""
for item in "${CONTEXT_FILES[@]}"; do
  file="$(canonicalize_existing_file "$item")" || { echo "ERROR: missing context file: $item" >&2; exit "$EXIT_USER_ERROR"; }
  require_within_root "$file"
  CONTEXT_FILES_CANONICAL+=("$(root_relative_path "$file")")

  if has_secrets "$file"; then
    echo "ERROR: secret-bearing file blocked: $file" >&2
    log_line "SECRETS_VIOLATION session=$SESSION_ID correlation=$CORRELATION_ID file=$file"
    exit "$EXIT_SECRETS_VIOLATION"
  fi

  size="$(wc -c < "$file")"
  TOTAL_BYTES=$((TOTAL_BYTES + size))
  if [[ "$TOTAL_BYTES" -gt "$MAX_CTX_BYTES" ]]; then
    echo "ERROR: context bytes exceeded ($TOTAL_BYTES > $MAX_CTX_BYTES)" >&2
    exit "$EXIT_CONTEXT_LIMIT"
  fi

  CONTEXT_BLOCK+=$'\n\n--- File: '"${file#$ROOT_DIR/}"$' ---\n'
  CONTEXT_BLOCK+="$(cat "$file")"
done

AGENT_BODY="$(extract_agent_body)"

if [[ "$STRICT_SCHEMA" == "true" ]]; then
  IMPORTANT_BLOCK=$'IMPORTANT:\n- End with a JSON fenced block.\n- Include all required common schema keys.\n- Do not add free-form prose after the JSON block.'
else
  IMPORTANT_BLOCK=$'IMPORTANT:\n- Respond in Markdown only.\n- Keep the output text-first.\n- Cover the role\'s expected sections if they fit the task.\n- Do not append a JSON block unless the task explicitly asks for one.'
fi

cat >"$PROMPT_FILE" <<EOF
You are acting according to the following role definition:

---
$AGENT_BODY
---

Project-local pilot rules:
- This delegation exists only inside the current repository.
- Do not rely on global skills, global memory, or global state.
- Do not call another delegated agent.
- If approval is missing, stay read-only.

Current state snapshot:
- Phase: ${CURRENT_PHASE:-unknown}
- Last Gate Passed: ${LAST_GATE:-none}
- Delegation Depth: ${CURRENT_DEPTH:-0}

Task:
$PROMPT

Context:
$CONTEXT_BLOCK

$IMPORTANT_BLOCK
EOF

PROMPT_HASH="$(prompt_hash "$PROMPT_FILE")"

cat >"$DECISION_FILE" <<EOF
{
  "schema_version": "1.2",
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
  "delegation_depth": ${CURRENT_DEPTH:-0},
  "writes_enabled": $( [[ "$ALLOW_WRITES" == "true" ]] && printf 'true' || printf 'false' ),
  "context_files": $(json_array_from_args "${CONTEXT_FILES_CANONICAL[@]}"),
  "status": "ok",
  "prompt_hash": "$(json_escape "$PROMPT_HASH")",
  "phase": "$(json_escape "${CURRENT_PHASE:-unknown}")",
  "last_gate_passed": "$(json_escape "${LAST_GATE:-none}")"
}
EOF

log_line "INVOKE session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI agent=$AGENT_ROLE phase=$CURRENT_PHASE gate=$LAST_GATE prompt_hash=$PROMPT_HASH dry_run=$DRY_RUN"

if [[ "$DRY_RUN" == "true" ]]; then
  cat <<EOF
{
  "status": "dry-run",
  "session_id": "$(json_escape "$SESSION_ID")",
  "correlation_id": "$(json_escape "$CORRELATION_ID")",
  "cli": "$(json_escape "$CLI")",
  "model": "$(json_escape "${MODEL_NAME:-}")",
  "agent": "$(json_escape "${AGENT_ROLE:-unknown}")",
  "call_type": "$(json_escape "$CALL_TYPE")",
  "log_bucket": "$(json_escape "$LOG_BUCKET")",
  "response_mode": "$(json_escape "$RESPONSE_MODE")",
  "strict_schema": $( [[ "$STRICT_SCHEMA" == "true" ]] && printf 'true' || printf 'false' ),
  "timeout_sec": $TIMEOUT_SEC,
  "required_gate": "$(json_escape "$REQUIRED_GATE")",
  "output_schema": "$(json_escape "$OUTPUT_SCHEMA_RELATIVE")",
  "phase": "$(json_escape "${CURRENT_PHASE:-unknown}")",
  "last_gate_passed": "$(json_escape "${LAST_GATE:-none}")",
  "prompt_file": "$(json_escape "$PROMPT_FILE")",
  "decision_file": "$(json_escape "$DECISION_FILE")",
  "prompt_hash": "$(json_escape "$PROMPT_HASH")",
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

ADAPTER="$ROOT_DIR/scripts/adapters/${CLI}.sh"
[[ -x "$ADAPTER" ]] || { echo "ERROR: missing adapter: $ADAPTER" >&2; exit "$EXIT_USER_ERROR"; }

set +e
"$ADAPTER" "$PROMPT_FILE" "$TIMEOUT_SEC" "$STDOUT_FILE" "$STDERR_FILE" "$ALLOW_WRITES" "$MODEL_NAME" "$OUTPUT_SCHEMA_FILE"
RC=$?
set -e

if [[ "$RC" -eq 124 ]]; then
  log_line "TIMEOUT session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI"
  exit "$EXIT_TIMEOUT"
elif [[ "$RC" -ne 0 ]]; then
  log_line "CLI_ERROR session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI rc=$RC"
  exit "$EXIT_CLI_ERROR"
fi

if command -v node >/dev/null 2>&1 && [[ -f "$ROOT_DIR/scripts/extract_response_body.mjs" ]]; then
  node "$ROOT_DIR/scripts/extract_response_body.mjs" "$STDOUT_FILE" "$BODY_FILE"
elif command -v jq >/dev/null 2>&1; then
  jq -r '.result // .content // .response // .text // empty' "$STDOUT_FILE" >"$BODY_FILE" 2>/dev/null || cp "$STDOUT_FILE" "$BODY_FILE"
else
  cp "$STDOUT_FILE" "$BODY_FILE"
fi

if [[ "$STRICT_SCHEMA" != "true" ]]; then
  log_line "OK session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI agent=$AGENT_ROLE prompt_hash=$PROMPT_HASH response_mode=$RESPONSE_MODE strict_schema=false"
  cat "$BODY_FILE"
  exit "$EXIT_OK"
fi

JSON_BLOCK="$(awk '/^```json$/{flag=1; next} /^```$/{flag=0} flag' "$BODY_FILE" || true)"

if [[ -z "$JSON_BLOCK" ]]; then
  log_line "SCHEMA_VIOLATION session=$SESSION_ID correlation=$CORRELATION_ID reason=no_json_block"
  echo "ERROR: response missing required JSON block" >&2
  exit "$EXIT_SCHEMA_VIOLATION"
fi

REQUIRED_KEYS=(schema_version agent summary decisions risks open_questions action_items requested_context status needs_human_decision confidence)
for key in "${REQUIRED_KEYS[@]}"; do
  if command -v jq >/dev/null 2>&1; then
    if ! printf '%s\n' "$JSON_BLOCK" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
      log_line "SCHEMA_VIOLATION session=$SESSION_ID correlation=$CORRELATION_ID missing_key=$key"
      echo "ERROR: response JSON missing required key: $key" >&2
      exit "$EXIT_SCHEMA_VIOLATION"
    fi
  else
    if ! printf '%s\n' "$JSON_BLOCK" | grep -q "\"$key\""; then
      log_line "SCHEMA_VIOLATION session=$SESSION_ID correlation=$CORRELATION_ID missing_key=$key"
      echo "ERROR: response JSON missing required key: $key" >&2
      exit "$EXIT_SCHEMA_VIOLATION"
    fi
  fi
done

log_line "OK session=$SESSION_ID correlation=$CORRELATION_ID cli=$CLI agent=$AGENT_ROLE prompt_hash=$PROMPT_HASH response_mode=$RESPONSE_MODE strict_schema=true"
cat "$BODY_FILE"

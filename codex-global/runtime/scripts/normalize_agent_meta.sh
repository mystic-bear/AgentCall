#!/usr/bin/env bash
set -euo pipefail

AGENT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-file)
      AGENT_FILE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

[[ -n "$AGENT_FILE" ]] || { echo "ERROR: --agent-file required" >&2; exit 1; }
[[ -f "$AGENT_FILE" ]] || { echo "ERROR: agent file not found: $AGENT_FILE" >&2; exit 1; }

fm_value() {
  local key="$1"
  awk -v prefix="${key}: " '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm = !in_fm; next }
    in_fm && index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }
  ' "$AGENT_FILE"
}

normalize_bool() {
  local value="${1:-}"
  case "$value" in
    true|TRUE|yes|YES|1) printf 'true' ;;
    false|FALSE|no|NO|0) printf 'false' ;;
    *) printf '%s' "" ;;
  esac
}

validate_side_effects() {
  local value="${1:-}"
  case "$value" in
    none|workspace-write|external-write) printf '%s' "$value" ;;
    *)
      echo "ERROR: invalid side-effects value: $value" >&2
      exit 1
      ;;
  esac
}

default_call_type_for_role() {
  local role="${1:-}"
  case "$role" in
    bug-reviewer|frontend-designer) printf 'review' ;;
    architect) printf 'design' ;;
    integrator) printf 'plan' ;;
    design-synthesizer) printf 'synthesis' ;;
    test-hello) printf 'smoke' ;;
    *) printf 'advisory' ;;
  esac
}

default_response_mode_for_call_type() {
  local call_type="${1:-advisory}"
  case "$call_type" in
    synthesis|smoke) printf 'json-fenced' ;;
    *) printf 'text' ;;
  esac
}

default_cli_for_role() {
  local role="${1:-}"
  case "$role" in
    frontend-designer) printf 'gemini' ;;
    architect|bug-reviewer|integrator) printf 'claude' ;;
    design-synthesizer|test-hello) printf 'codex' ;;
    *) printf '' ;;
  esac
}

default_gate_for_role() {
  local role="${1:-}"
  case "$role" in
    architect|frontend-designer|test-hello) printf 'A' ;;
    bug-reviewer|integrator) printf 'C' ;;
    design-synthesizer) printf 'S' ;;
    *) printf 'A' ;;
  esac
}

default_side_effects_for_role() {
  local role="${1:-}"
  case "$role" in
    architect|frontend-designer|bug-reviewer|integrator|design-synthesizer|test-hello) printf 'none' ;;
    *) printf 'workspace-write' ;;
  esac
}

source_role="frontmatter"
source_cli="frontmatter"
source_model="frontmatter"
source_schema="frontmatter"
source_strict="frontmatter"
source_call_type="frontmatter"
source_response_mode="frontmatter"
source_timeout="frontmatter"
source_gate="frontmatter"
source_side_effects="frontmatter"

ROLE="$(fm_value "role" || true)"
if [[ -z "$ROLE" ]]; then
  ROLE="$(basename "$AGENT_FILE" .md)"
  source_role="filename"
fi

RUN_AGENT="$(fm_value "run-agent" || true)"
if [[ -z "$RUN_AGENT" ]]; then
  RUN_AGENT="$(fm_value "cli" || true)"
  if [[ -n "$RUN_AGENT" ]]; then
    source_cli="alias:cli"
  fi
fi

MODEL="$(fm_value "model" || true)"
if [[ -z "$MODEL" ]]; then
  source_model="unset"
fi

OUTPUT_SCHEMA="$(fm_value "output-schema" || true)"
if [[ -z "$OUTPUT_SCHEMA" ]]; then
  OUTPUT_SCHEMA="$(fm_value "schema" || true)"
  if [[ -n "$OUTPUT_SCHEMA" ]]; then
    source_schema="alias:schema"
  fi
fi

STRICT_SCHEMA="$(normalize_bool "$(fm_value "strict-schema" || true)")"
if [[ -z "$STRICT_SCHEMA" ]]; then
  STRICT_SCHEMA="$(normalize_bool "$(fm_value "strict" || true)")"
  if [[ -n "$STRICT_SCHEMA" ]]; then
    source_strict="alias:strict"
  fi
fi

CALL_TYPE="$(fm_value "call-type" || true)"
if [[ -z "$CALL_TYPE" ]]; then
  CALL_TYPE="$(default_call_type_for_role "$ROLE")"
  source_call_type="role-default"
fi

RESPONSE_MODE="$(fm_value "response-mode" || true)"
if [[ -z "$RESPONSE_MODE" ]]; then
  RESPONSE_MODE="$(default_response_mode_for_call_type "$CALL_TYPE")"
  source_response_mode="call-type-default"
fi

if [[ -z "$STRICT_SCHEMA" ]]; then
  if [[ "$RESPONSE_MODE" == "json-fenced" ]]; then
    STRICT_SCHEMA="true"
    source_strict="response-mode"
  else
    STRICT_SCHEMA="false"
    source_strict="default:false"
  fi
fi

if [[ -z "$RUN_AGENT" ]]; then
  if [[ -n "$MODEL" ]]; then
    case "$MODEL" in
      claude-*) RUN_AGENT="claude"; source_cli="model-prefix" ;;
      gemini-*) RUN_AGENT="gemini"; source_cli="model-prefix" ;;
      gpt-*|o*) RUN_AGENT="codex"; source_cli="model-prefix" ;;
    esac
  fi
fi
if [[ -z "$RUN_AGENT" ]]; then
  RUN_AGENT="$(default_cli_for_role "$ROLE")"
  source_cli="role-default"
fi

TIMEOUT_SEC="$(fm_value "timeout-sec" || true)"
if [[ -z "$TIMEOUT_SEC" ]]; then
  TIMEOUT_SEC="600"
  source_timeout="default:600"
fi

MAX_CONTEXT_FILES="$(fm_value "max-context-files" || true)"
MAX_CONTEXT_BYTES="$(fm_value "max-context-bytes" || true)"
ALLOW_RECURSION="$(normalize_bool "$(fm_value "allow-recursion" || true)")"
if [[ -z "$ALLOW_RECURSION" ]]; then
  ALLOW_RECURSION="false"
fi

REQUIRED_GATE="$(fm_value "requires-human-gate" || true)"
if [[ -z "$REQUIRED_GATE" ]]; then
  REQUIRED_GATE="$(default_gate_for_role "$ROLE")"
  source_gate="role-default"
fi

SIDE_EFFECTS="$(fm_value "side-effects" || true)"
if [[ -z "$SIDE_EFFECTS" ]]; then
  SIDE_EFFECTS="$(default_side_effects_for_role "$ROLE")"
  source_side_effects="role-default"
fi
SIDE_EFFECTS="$(validate_side_effects "$SIDE_EFFECTS")"

printf 'AGENT_RUN_AGENT=%q\n' "$RUN_AGENT"
printf 'AGENT_ROLE=%q\n' "$ROLE"
printf 'AGENT_MODEL=%q\n' "$MODEL"
printf 'AGENT_OUTPUT_SCHEMA=%q\n' "$OUTPUT_SCHEMA"
printf 'AGENT_STRICT_SCHEMA=%q\n' "$STRICT_SCHEMA"
printf 'AGENT_CALL_TYPE=%q\n' "$CALL_TYPE"
printf 'AGENT_RESPONSE_MODE=%q\n' "$RESPONSE_MODE"
printf 'AGENT_TIMEOUT_SEC=%q\n' "$TIMEOUT_SEC"
printf 'AGENT_MAX_CONTEXT_FILES=%q\n' "$MAX_CONTEXT_FILES"
printf 'AGENT_MAX_CONTEXT_BYTES=%q\n' "$MAX_CONTEXT_BYTES"
printf 'AGENT_ALLOW_RECURSION=%q\n' "$ALLOW_RECURSION"
printf 'AGENT_REQUIRED_GATE=%q\n' "$REQUIRED_GATE"
printf 'AGENT_SIDE_EFFECTS=%q\n' "$SIDE_EFFECTS"
printf 'AGENT_META_SOURCE=%q\n' "role=$source_role,run-agent=$source_cli,model=$source_model,output-schema=$source_schema,strict=$source_strict,call-type=$source_call_type,response-mode=$source_response_mode,timeout=$source_timeout,gate=$source_gate,side-effects=$source_side_effects"

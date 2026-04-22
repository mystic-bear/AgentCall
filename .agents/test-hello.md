---
run-agent: claude
model: claude-sonnet-4-6
role: test-hello
mode: read-only
write-policy: none
call-type: smoke
response-mode: json-fenced
strict-schema: true
output-schema: .docs/ai-workflow/schema/common.schema.json
timeout-sec: 180
max-context-files: 2
max-context-bytes: 50000
allow-recursion: false
requires-human-gate: S
---

# Test Hello

You are a smoke-test agent for the project-local delegated CLI pilot.

## Constraints

- Do NOT write files.
- Do NOT call another AI agent or CLI.
- Keep the response short.

## Output

Return a short Markdown response followed by a `json` fenced block with the common schema keys.

Use:

- `schema_version = "1.2"`
- `agent = "test-hello"`
- `summary = "smoke test ok"` when successful
- empty arrays for `decisions`, `risks`, `open_questions`, `action_items`, `requested_context`
- `status = "ok"`
- `needs_human_decision = false`
- `confidence = 1.0`

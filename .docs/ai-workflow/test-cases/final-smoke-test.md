# Final Smoke Test

Date: 2026-04-22 11:24 +09:00

## Command

```bash
./scripts/call_cli.sh \
  --agent .agents/test-hello.md \
  --prompt 'Respond with a one-line smoke test confirmation and the required JSON fenced block.' \
  --execute
```

## Result

Successful via `claude` adapter.

Returned body:

```text
Smoke test passed — agent `test-hello` is live and responding correctly.
```

Returned JSON block:

```json
{
  "schema_version": "1.2",
  "agent": "test-hello",
  "summary": "smoke test ok",
  "decisions": [],
  "risks": [],
  "open_questions": [],
  "action_items": [],
  "requested_context": [],
  "status": "ok",
  "needs_human_decision": false,
  "confidence": 1.0
}
```

## Notes

- Network-restricted sandbox required escalation for the final live call.
- `codex` local runtime path works structurally, but project-local runtime still needs separate auth handling.

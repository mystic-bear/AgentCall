# Local Pilot Test Cases

## Recommended first checks

1. Validate scaffold files:

```bash
./scripts/validate_skill.sh
```

2. Dry-run against architect:

```bash
./scripts/call_cli.sh \
  --agent .agents/architect.md \
  --prompt "Summarize the local pilot structure" \
  --context AGENTS.md \
  --context .docs/ai-workflow/state.md \
  --dry-run
```

3. Wrong-path guard:

```bash
./scripts/call_cli.sh \
  --agent /etc/passwd \
  --prompt "should fail" \
  --dry-run
```

4. Secrets guard:

```bash
printf 'OPENAI_API_KEY=test\n' > /tmp/fake.env
./scripts/call_cli.sh \
  --agent .agents/architect.md \
  --prompt "should fail" \
  --context /tmp/fake.env \
  --dry-run
```

## Notes

- The pilot is project-local only.
- `--execute` is the normal path once the wrapper is stable, and `--dry-run` is reserved for wrapper/debug checks.
- Real execution is blocked until `Last Gate Passed` satisfies the agent's `requires-human-gate` value.

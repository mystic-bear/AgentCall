# Work Order

## Goal

Create a project-local only pilot for delegated AI CLI orchestration.

## Scope

- `AGENTS.md`
- `.agents/*.md`
- `scripts/call_cli.sh`
- `.docs/ai-workflow/`

## Constraints

- No global installation
- Dry-run first
- Read-only by default

## Unresolved Questions

- Which CLI should own each role after pilot tuning?
- How should project-local Codex runtime inherit or bootstrap auth safely?

## Results So Far

- Project-local scaffold completed
- Gate S checks passed
- Final live smoke test succeeded through `claude` using `.agents/test-hello.md`
- `codex` runtime isolation works structurally but still needs local auth strategy

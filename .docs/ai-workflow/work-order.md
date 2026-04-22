# Work Order

## Goal

Create a project-local first delegation foundation that can be expanded more broadly after validation.

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
- How should existing agent markdown files be adopted without requiring disruptive replacement?

## Results So Far

- Project-local scaffold completed
- Gate S checks passed
- Final live smoke test succeeded through `claude` using `.agents/test-hello.md`
- `codex` runtime isolation works structurally but still needs local auth strategy
- Local-first structure is stable enough that the next major step is compatibility with existing agent markdown rather than greenfield replacement

# Project-Local First, Global-Ready AgentCall

This repository contains a **project-local first** delegation foundation for bounded work across AI CLIs.

Rules:

- Use only the files inside this repository for the pilot:
  - `.agents/`
  - `scripts/`
  - `.docs/ai-workflow/`
- Do **not** rely on global skills or global `.codex/skills/` installation for this pilot.
- Treat this repo as read-only by default until human approval is explicit.
- Route delegation through `scripts/call_cli.sh` only.
- Do not invoke another delegated agent from inside a delegated agent.
- Use `.docs/ai-workflow/state.md` as the source of truth for phase, owner, next action, and blockers.
- Resolve models in this order:
  - explicit `--model`
  - agent frontmatter `model:`
  - provider default from `.docs/ai-workflow/model-defaults.env`
- Reduce overhead by avoiding unnecessary delegation and over-structured contracts.

Strict schema resolution:

1. `--strict-schema`
2. agent frontmatter `strict-schema:`
3. agent frontmatter `response-mode: json-fenced`
4. agent frontmatter `call-type: synthesis|smoke`
5. role-derived defaults for `design-synthesizer` and `test-hello`
6. otherwise `false`

Gate resolution:

- Gate rank is `none/0 < A < B < C < S`.
- `S` means skill validation readiness; `A/B/C` are lifecycle approval stages.
- The wrapper currently uses this single ordered scale for `requires-human-gate` checks.

Local pilot intent:

- Prove the structure works inside one project first.
- Preserve a path to wider/global expansion after local validation.
- Use `--execute` for normal work once the wrapper is stable.
- Reserve `--dry-run` for wrapper changes, contract checks, and debugging.
- Treat `logs/production/` as the real work log and `logs/debug/` as test/debug output.
- Keep logs, schemas, and test cases inside the repo so the pilot is portable.
- Prefer compatibility extension over replacement when adapting existing agent markdown assets.
- Enforce agent-specific `requires-human-gate` values at execution time instead of using one global execute gate.

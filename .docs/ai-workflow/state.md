# Project State

<!-- 아래 필드는 모두 필수. 순서 변경 금지 -->

**Skill Version**: 1.2
**Current Phase**: global-rollout-basis
**Current Owner**: codex
**Next Owner**: human
**Approved By Human**: partial
**Last Gate Passed**: S
**Current Delegation Depth**: 0
**Last Inputs**: rename the global skill/runtime from `subagent-host` to `AgentCall` and record the externally confirmed Claude/Gemini smoke results
**Last Outputs**: renamed local/global skill entries to `AgentCall`, migration-aware installer/validator updates, rollout docs updated with external smoke evidence, and actual `~/.codex/AgentCall` install plus live smoke validation
**Open Questions**: which legacy field variants must be supported first, whether global fallback should stay read-only-only longer, and whether a faster live smoke path than external CLI full execution should be added
**Blockers**: none
**Last Exit Code**: 0
**Retry Count**: 0
**Last Updated**: 2026-04-23T09:40:00+09:00
**Session ID**: bootstrap-local-pilot
**Correlation ID**: bootstrap-local-pilot

## Decisions Log (append-only, 최신이 위)

- 2026-04-23: Global Codex rollout should use a repo-native package plus installer model, not a thin shim tied to the source repo path.
- 2026-04-23: The first global basis must ship with a minimal compatibility layer and a global fallback runtime-data path rather than assuming project-local AgentCall state exists.
- 2026-04-23: The global skill/runtime identity should be `AgentCall`, and the previous managed `subagent-host` install should be migrated out of the active skill list during reinstall.
- 2026-04-23: The renamed global install must be proven after migration, so actual `~/.codex/AgentCall` validation and one live smoke run are part of completion.
- 2026-04-23: Existing-agent compatibility is no longer a future-only target; the current global basis already ships with minimal normalization, and follow-up work should focus on widening legacy coverage rather than introducing the compatibility layer itself.
- 2026-04-22: Wrapper hardening should enforce frontmatter timeout/gate/schema metadata, canonicalize logged context paths, move Codex prompt transport to stdin/prompt-file, and keep review/design outputs text-first by default.
- 2026-04-22: Gemini read-only delegation should continue to run through `--approval-mode plan`, and this mode must be proven by a live smoke execution rather than assumed from CLI help alone.
- 2026-04-22: A thin compatibility layer should preserve existing agent markdown files and normalize them at load time instead of replacing them.
- 2026-04-22: This repo should be described as a local-first foundation for broader expansion, with non-breaking compatibility for existing agent markdown files as a core requirement.
- 2026-04-22: Dry-run output should live under `logs/debug`, production work under `logs/production`, and the wrapper should default to execute for routine use.
- 2026-04-22: The wrapper now defaults review/design roles to text-first responses; strict schema is opt-in and remains default only for smoke/synthesis-style roles.
- 2026-04-22: Reviews should be requested only from explicitly chosen AIs, without reviewer consensus; Codex makes the final accept/reject decision and review outputs can be text-first.
- 2026-04-22: Simple edits are out of delegation scope; default operating model should favor local handling, single-reviewer delegation, and lighter advisory contracts.
- 2026-04-22: Start with project-local only pilot. No global activation.
- 2026-04-22: Local scaffold created and dry-run validation passed.
- 2026-04-22: Gate S checks passed locally (6/6).
- 2026-04-22: Final live smoke test passed via Claude `test-hello` agent.
- 2026-04-22: Pac-Man prototype implemented and passed delegated review/revision loop.

## Phase History (append-only)

- 2026-04-22T10:40: draft → skill-design (approved: human)
- 2026-04-22T11:08: skill-design → skill-validation (approved: human)
- 2026-04-22T11:21: skill-validation → skill-validation (gate S passed, next: CLI smoke test)
- 2026-04-22T11:24: skill-validation → post-review (final smoke test passed)
- 2026-04-22T12:36: post-review → post-review (prototype implementation, review loop, and verification complete)
- 2026-04-22T14:10: post-review → post-review (delegation overhead review documented with reduced-scope operating recommendations)
- 2026-04-22T14:18: post-review → post-review (review policy refined to explicit-request, Codex-final, text-first output model)
- 2026-04-22T14:31: post-review → post-review (wrapper and agent prompts updated to text-first review mode with strict-schema opt-in)
- 2026-04-22T15:31: post-review → post-review (wrapper switched to execute-first usage, log buckets split, and historical logs migrated)
- 2026-04-22T16:02: post-review → post-review (docs reframed toward broader expansion, with existing-agent-md compatibility recorded as the main next step)
- 2026-04-22T16:12: post-review → post-review (Claude draft received and finalized into existing-agent-md compatibility design doc)
- 2026-04-22T17:35: post-review → post-review (review-driven wrapper hardening completed: gate enforcement, secret scan expansion, prompt-file Codex transport, validation/doc updates)
- 2026-04-22T18:05: post-review → post-review (follow-up refinements applied and live Gemini smoke test passed under current read-only adapter mode)
- 2026-04-23T07:35: post-review → global-rollout-basis (global Codex rollout work order revised from Claude/Gemini review, `codex-global/` package created, and installer applied to `~/.codex`)
- 2026-04-23T09:25: global-rollout-basis → global-rollout-basis (global skill/runtime renamed to `AgentCall`, installer prepared to migrate legacy managed `subagent-host`, and external smoke evidence recorded)
- 2026-04-23T09:40: global-rollout-basis → global-rollout-basis (renamed `AgentCall` install applied to `~/.codex`, legacy active path removed, and live smoke validation passed)

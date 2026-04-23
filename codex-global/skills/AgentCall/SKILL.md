---
name: AgentCall
description: Use when Codex should delegate bounded work to Claude, Gemini, or a child Codex process through the globally installed runtime with local-first agent resolution and guarded fallback behavior
---

# Global AgentCall

## Overview

This is the **global Codex host skill** for bounded delegation.

It prefers project-local agent definitions when they exist. If the current project has no local AgentCall runtime, it falls back to the globally installed curated runtime under `$HOME/.codex/AgentCall/`.

## When to Use

- A bounded architecture question should go to `architect`
- A visual/layout critique should go to `frontend-designer`
- A focused bug review should go to `bug-reviewer`
- A synthesis/final recommendation step should go to `design-synthesizer`

## When NOT to Use

- The work is simpler to do directly in the current session
- The task requires broad autonomous orchestration
- The context set contains secret-bearing files
- The current project should remain fully local and already has its own wrapper workflow

## Runtime Entry

Run the installed global wrapper:

```bash
$HOME/.codex/AgentCall/scripts/global_call_cli.sh --agent architect --prompt "..."
```

## Routing Rules

- Prefer project-local `.agents/*.md` when present
- Fall back to globally curated agents only when no matching local agent exists
- Keep delegation read-only by default
- Do not recurse into another delegated agent

## Fallback Mode

If the current project does not have a local AgentCall state/runtime, the global wrapper uses:

- curated global agents
- global fallback state
- global fallback logs under `$HOME/.codex/AgentCall/runtime-data/<project-key>/`

In fallback mode, the safe default is read-only review/design delegation first.

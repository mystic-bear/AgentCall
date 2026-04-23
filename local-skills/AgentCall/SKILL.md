---
name: AgentCall
description: Use when the current repository should delegate bounded work to another AI CLI through the local wrapper with explicit gates, schema checks, and safety controls
max-delegation-depth: 1
default-mode: read-only
default-write-policy: deny
required-state-file: .docs/ai-workflow/state.md
required-wrapper: scripts/call_cli.sh
---

# AgentCall

## Overview

This is the **project-local** host skill for the delegated CLI pilot.

It is not a global skill installation. It exists only inside this repository and routes work through `scripts/call_cli.sh`.

## When to Use

- A bounded architecture question should be sent to `architect`
- A visual/layout critique should be sent to `frontend-designer`
- A scoped implementation plan should be sent to `integrator`
- A defect review should be sent to `bug-reviewer`

## When NOT to Use

- `state.md` is missing or cannot answer phase/owner/next action
- current phase is `blocked`
- current delegation depth is already `1`
- user approval is missing for the intended gate
- the work is better handled directly in the current session
- context budget would be exceeded

## Agent Selection Rules

- architecture, decomposition, risks -> `architect`
- layout, hierarchy, visual direction -> `frontend-designer`
- task mapping, integration steps, rollout -> `integrator`
- findings, regressions, test gaps -> `bug-reviewer`

## CLI Selection Rules

- default to the `run-agent` declared in the selected `.agents/*.md`
- do not override the target CLI unless the local pilot is being explicitly re-tuned

## Context Packing Rules

- default to path + summary
- only pass full content for role definitions, state, and current work-order level documents
- do not pass files outside this repository
- reject secret-bearing files

## Safety Gates

- never auto-propagate write permissions
- never allow recursive delegation during this pilot
- never execute before Gate `S`
- never continue on schema failure
- never silently fall back to another role if routing is ambiguous

## Failure Handling

- schema failure -> stop
- recursion attempt -> stop
- secrets violation -> stop
- blocked state -> stop
- pre-Gate-S execute attempt -> stop

## Output

Before any real execution, the host should be able to explain:

1. which agent was selected
2. which CLI will run
3. why the context set is sufficient
4. why execution is allowed at the current gate

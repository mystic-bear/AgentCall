# Global AgentCall Friction Work Order

작성일: 2026-04-23  
범위: `AgentCall` global Codex rollout 이후 확인된 운영 마찰 해소  
기준 자산: `codex-global/runtime/scripts/global_call_cli.sh`, `AGENTS.md`, `README.md`

## Review Inputs

외부 검토는 아래 두 세션을 기준으로 반영한다.

- Claude review: `.docs/ai-workflow/logs/production/global-friction-review-claude-20260423/`
- Gemini review: `.docs/ai-workflow/logs/production/global-friction-review-gemini-20260423/`

두 리뷰 모두 공통적으로 지적한 핵심은 아래 두 가지다.

1. 전역 wrapper가 project-local state가 없을 때 `~/.codex/AgentCall/runtime-data/<project-key>/`에 바로 쓰기 시작하므로, Codex sandbox 환경에서는 거의 매번 권한 상승을 유발한다.
2. 현재 `requires-human-gate` 해석이 lifecycle 단계와 execution permission을 한 축에 묶고 있어서, 실제로는 read-only인 agent 호출도 과도하게 차단한다.

## Problem Statement

현재 global AgentCall은 구조적으로는 동작하지만, 운영 마찰이 크다.

- validation이나 execute path가 global fallback state/log root를 eager하게 만들면서 sandbox boundary 밖 쓰기를 발생시킨다.
- `architect=A`, `bug-reviewer=C`, `design-synthesizer=S` 같은 설정 때문에 read-only advisory 호출도 기본적으로 막힌다.
- 결과적으로 “bounded delegation을 쉽게 부른다”는 목표보다 “wrapper 통과 자체가 어렵다”는 인상이 더 강해진다.

이번 작업의 목적은 **guard를 없애는 것**이 아니라, **위험이 낮은 read-only delegation은 friction 없이 통과시키고, mutation risk가 있는 경로만 계속 강하게 통제**하는 것이다.

## Reviewer Summary

### Claude

- `~/.codex` fallback은 eager/unconditional write라 sandbox escalation을 반복 유발한다고 봄
- fallback root는 lazy하게 만들고, 기본값은 `/tmp` 같은 scoped path로 내리자고 제안
- gate는 `ro < none < A < B < C < S` 같은 read-only tier를 추가해 분리하는 안을 권장

### Gemini

- `$PWD` 또는 현재 workspace boundary를 기준으로 state/log를 처리해야 friction이 줄어든다고 봄
- lifecycle gate와 execution permission을 분리하고, read-only / mutating 같은 action-based control로 바꾸자고 제안
- `--force-read-only` 같은 flag bypass보다 구조적으로 side-effect risk를 표현하는 모델을 선호

## Final Recommendation

이번 라운드의 권장안은 **Claude의 lazy fallback**과 **Gemini의 side-effect-based gate separation**을 결합한 형태다.

### 1. Fallback root는 lazy + non-global default로 바꾼다

기본 우선순위:

1. `AGENTCALL_LOG_ROOT` 또는 `AGENTCALL_RUNTIME_ROOT` 명시값
2. project-local `.docs/ai-workflow/` 가 이미 있으면 그 안의 기존 로그/상태 경로
3. `$TMPDIR/agentcall/<project-key>/`
4. `~/.codex/AgentCall/runtime-data/<project-key>/`는 `AGENTCALL_PERSIST_GLOBAL=1`일 때만 사용

핵심 원칙:

- `--dry-run`은 persistent/global fallback state root를 만들지 않는다.
- read-only agent는 가능한 한 persistent state/log 생성을 건너뛴다.
- global home은 “기본 저장소”가 아니라 “명시 opt-in persistence”로 낮춘다.

이 선택 이유:

- `/tmp`는 sandbox 안에서 기본적으로 쓰기 가능하고 repo를 더럽히지 않는다.
- workspace 루트에 숨김 디렉터리를 자동 생성하는 안보다 흔적이 적다.
- global home persistence가 필요한 사용자는 환경 변수로 명시 opt-in 할 수 있다.

### 2. Gate는 lifecycle metadata와 execution risk를 분리한다

새 frontmatter 필드:

```yaml
side-effects: none | workspace-write | external-write
```

해석 원칙:

- `side-effects: none`
  - read-only delegation
  - `requires-human-gate`가 있어도 execution block에 사용하지 않는다
  - 기본적으로 sandbox escalation을 유발하는 state/log write를 만들지 않는다
- `side-effects: workspace-write | external-write`
  - mutation-capable delegation
  - 이 경우에만 기존 `requires-human-gate`를 execution block에 사용한다

즉, `requires-human-gate`는 앞으로도 남기지만, **모든 agent의 실행 차단 키**가 아니라 **mutation-capable agent의 approval requirement**로 한정한다.

### 3. 현재 curated global agents는 전부 read-only로 재분류한다

이번 기준에서 아래 agent는 모두 `side-effects: none`으로 본다.

- `architect`
- `frontend-designer`
- `integrator`
- `bug-reviewer`
- `design-synthesizer`
- `test-hello`

이유:

- 현재 prompt와 adapter 설계상 이 agent들은 모두 advisory/read-only 역할이다.
- 실제 파일 쓰기나 외부 mutation은 허용하지 않는다.

따라서 현재 curated set은 전부 friction-free execute가 가능해야 하고, gate는 기록용 메타데이터로 남거나 future mutating roles를 위해 보존하는 쪽이 맞다.

## Locked Decisions

이번 작업지시서에서 아래는 잠근다.

1. global fallback default는 `~/.codex`가 아니라 `/tmp` 계열 path다.
2. `~/.codex/AgentCall/runtime-data`는 명시 opt-in persistence 경로다.
3. `requires-human-gate` 단독으로는 더 이상 read-only agent를 막지 않는다.
4. read-only/mutating 구분은 새 `side-effects` 필드로 표현한다.
5. 현재 curated global agents는 전부 `side-effects: none`으로 시작한다.

## Implementation Phases

## Phase 0. Immediate Cleanup

목표:

- project-local `local_codex.sh` 의존 제거
- npm global Codex 설치 충돌 해소

작업:

- `scripts/adapters/codex.sh`를 direct `codex exec` 기반으로 전환
- `scripts/local_codex.sh` 제거
- validation/test/README에서 local Codex launcher 참조 정리
- `~/.local/bin/codex`의 stale wrapper를 백업 후 `npm install -g @openai/codex` 재실행

완료 기준:

- `which codex`가 npm global symlink를 가리킴
- `codex --version` 동작
- project-local validation과 Codex adapter stdin transport test 통과

## Phase 1. Lazy Fallback Root

목표:

- global wrapper가 read-only/dry-run 경로에서 `~/.codex` write를 만들지 않게 함

작업:

- `global_call_cli.sh`의 eager fallback init 제거
- runtime root resolver 추가
- `--dry-run`에서는 persistent/global state root 생성을 suppress
- `AGENTCALL_PERSIST_GLOBAL=1`일 때만 `~/.codex/AgentCall/runtime-data` 사용

완료 기준:

- non-AgentCall project에서 dry-run 시 escalation 불필요
- read-only execute 시 기본적으로 `/tmp` 또는 caller-managed writable root만 사용
- global validator가 새 runtime root 규칙을 검증

## Phase 2. Side-Effect-Based Execution Control

목표:

- lifecycle gate 때문에 read-only delegation이 막히는 문제 해소

작업:

- `normalize_agent_meta.sh`와 wrapper parser에 `side-effects` 필드 추가
- agent frontmatter에 `side-effects: none` 반영
- gate enforcement를 `side-effects != none`일 때만 적용
- `test-hello`를 read-only smoke로 재정의하고 blocking default 제거

완료 기준:

- `architect`, `frontend-designer`, `bug-reviewer`, `integrator`, `design-synthesizer`, `test-hello`가 기본 execute 가능
- mutation-capable future agent만 gate block 적용
- 관련 문서와 validator가 새 규칙을 설명

## Phase 3. Validation and Rollout

작업:

- non-AgentCall project dry-run smoke
- non-AgentCall project read-only execute smoke
- explicit persistence opt-in smoke
- legacy frontmatter compatibility smoke

완료 기준:

- 권한 상승 없이 read-only global call 가능
- opt-in 했을 때만 persistent global runtime-data 생성
- existing-agent compatibility가 유지됨

## Concrete File Targets

- `codex-global/runtime/scripts/global_call_cli.sh`
- `codex-global/runtime/scripts/normalize_agent_meta.sh`
- `codex-global/runtime/agents/*.md`
- `scripts/validate_global_codex_host.sh`
- `tests/global_codex_install_checks.sh`
- `AGENTS.md`
- `README.md`

## Open Questions

1. `/tmp` 기본값과 workspace-local hidden dir 기본값 중 어떤 쪽이 운영적으로 더 낫나
2. read-only agent 호출에도 최소 decision log는 남길지, stdout만으로 충분한지
3. future mutating agent를 언제 실제로 도입할지
4. `requires-human-gate`를 장기적으로 유지할지, `approval-gate` 같은 새 이름으로 분리할지

# AgentCall

`AgentCall` is a Codex-first delegation runtime for calling bounded-role agents across `Claude`, `Gemini`, and `Codex` CLIs.

이 저장소는 원래 project-local pilot로 시작했지만, 현재는 **전역 Codex 설치까지 검증된 배포 기준 source repo**로 정리되어 있습니다. 핵심 목표는 두 가지입니다.

- 다른 AI CLI를 bounded role 단위로 안정적으로 호출
- 과도한 오버헤드 없이 safety guard와 추적성을 유지

## Highlights

- `Codex`, `Claude`, `Gemini` CLI를 role-based wrapper로 통합
- project-local agent 우선, 없으면 global curated agent fallback
- text-first review/design, strict schema opt-in
- frontmatter 기반 `model`, `timeout-sec`, `output-schema`, `requires-human-gate` 해석
- existing agent markdown을 깨지 않는 최소 호환 레이어 포함
- 전역 fallback runtime은 기본적으로 tmp 기반이라 sandbox friction을 줄임
- `AGENTCALL_PERSIST_GLOBAL=1`일 때만 `~/.codex/AgentCall/runtime-data/`에 persistent log/state 사용

## Current Status

현재 기준으로 아래까지 확인됐습니다.

- project-local wrapper/guard/schema/model selection 검증 완료
- 전역 설치용 `codex-global/` package, installer, validator 구현 완료
- 실제 `~/.codex/skills/AgentCall/SKILL.md`, `~/.codex/AgentCall/` 설치 검증 완료
- global dry-run validation 통과
- global live smoke 통과
- Claude/Gemini reviewer 실제 응답 확인
- global friction round 완료
  - tmp fallback 기본화
  - `side-effects` 기반 read-only gate 완화
  - local Codex shim 제거

즉, 지금 이 저장소는 “실험용 초안”보다 **AgentCall 배포 기준 저장소**에 가깝습니다.

## Architecture

핵심 구조는 아래처럼 보면 됩니다.

```text
Codex session
  -> AgentCall skill / wrapper entry
    -> agent metadata resolution
      -> provider adapter (Claude / Gemini / Codex)
        -> provider CLI response
          -> body extraction / contract handling
            -> caller
```

실제 파일 기준으로는 이렇습니다.

- `~/.codex/skills/AgentCall/SKILL.md`
  - Codex가 발견하는 전역 skill entry
- `~/.codex/AgentCall/scripts/global_call_cli.sh`
  - 전역 호출 진입점
- `~/.codex/AgentCall/scripts/normalize_agent_meta.sh`
  - agent frontmatter와 legacy field를 정규화
- `~/.codex/AgentCall/agents/*.md`
  - curated global agent definitions
- `~/.codex/AgentCall/scripts/adapters/*.sh`
  - provider별 CLI adapter

project-local에서는 같은 역할을 아래가 담당합니다.

- `scripts/call_cli.sh`
- `.agents/*.md`
- `.docs/ai-workflow/`

즉, **AgentCall은 “Codex가 다른 AI CLI를 직접 호출하는 공통 wrapper 계층”** 이고, agent markdown은 그 wrapper가 해석하는 role contract라고 보면 됩니다.

## Core Concepts

처음 읽을 때 중요한 개념은 다섯 가지입니다.

### 1. Project-Local First

AgentCall은 원래 project-local pilot로 시작했습니다. 그래서 같은 역할이라도 먼저 **현재 프로젝트 안의 `.agents/*.md`** 를 찾고, 없을 때만 전역 curated agent로 fallback 합니다.

### 2. Bounded Delegation

이 구조는 “자율 멀티에이전트 시스템”보다 **bounded role call** 에 가깝습니다.

- `architect`
- `frontend-designer`
- `bug-reviewer`
- `integrator`
- `design-synthesizer`
- `test-hello`

각 agent는 역할과 출력 기대치가 제한되어 있고, wrapper가 그 경계를 유지합니다.

### 3. Compatibility Layer

기존 agent markdown을 전부 새 포맷으로 교체하지 않기 위해 `normalize_agent_meta.sh` 가 최소 호환 레이어 역할을 합니다.

- canonical field 우선
- 일부 alias 허용
- 누락값은 role 기반 기본값으로 추론

즉, AgentCall의 목적은 “새 문법 강제”보다 **기존 agent 자산을 안 깨고 연결하는 것**에 더 가깝습니다.

### 4. Side-Effects Model

전역 runtime에서는 `requires-human-gate`만으로 read-only agent를 막지 않도록 `side-effects` 개념을 둡니다.

- `side-effects: none`
  - read-only delegation
  - lifecycle metadata는 남아도 실행 차단은 기본적으로 하지 않음
- `side-effects: workspace-write | external-write`
  - mutation-capable delegation
  - 이 경우 gate enforcement가 중요해짐

이 분리가 최근 global friction 완화의 핵심입니다.

### 5. Fallback Runtime Root

전역 install 환경에서 project-local state가 없더라도, 기본 fallback은 `~/.codex`가 아니라 tmp 기반입니다.

- 기본: `${TMPDIR:-/tmp}/agentcall/<project-key>/`
- opt-in persistent: `AGENTCALL_PERSIST_GLOBAL=1`

이렇게 해서 Codex sandbox 환경에서 매번 권한 상승을 요구하는 문제를 줄였습니다.

## Install

### Prerequisites

기본적으로 아래가 필요합니다.

- `bash`
- `git`
- `node` / `npm`
- `codex` CLI
- 선택:
  - `claude` CLI
  - `gemini` CLI

`Claude`나 `Gemini`가 PATH에 없으면, 해당 provider agent는 호출할 수 없습니다.

### 1. Clone

```bash
git clone git@github.com:mystic-bear/AgentCall.git
cd AgentCall
```

### 2. Ensure Codex CLI Is Installed

이미 `codex`가 있으면 건너뛰어도 됩니다.

```bash
npm install -g @openai/codex
```

설치 확인:

```bash
codex --version
```

만약 `npm error code EEXIST`가 난다면, 예전 수동 wrapper가 `~/.local/bin/codex`에 남아 있을 가능성이 큽니다. 그 경우 기존 파일을 백업하거나 제거한 뒤 다시 설치하면 됩니다.

### 3. Validate The Repo

```bash
./scripts/validate_skill.sh
```

추가 검증:

```bash
bash ./tests/codex_promptfile_checks.sh
bash ./tests/global_codex_install_checks.sh
```

### 4. Install Global AgentCall

전역 Codex 홈(`~/.codex`)에 `AgentCall`을 설치합니다.

```bash
./scripts/install_global_codex_host.sh
```

설치 후 검증:

```bash
./scripts/validate_global_codex_host.sh
```

live smoke까지 확인:

```bash
./scripts/validate_global_codex_host.sh --live-smoke
```

설치가 끝나면 실제 전역 진입점은 아래입니다.

```bash
$HOME/.codex/AgentCall/scripts/global_call_cli.sh
```

### 5. Optional Persistent Global Runtime

기본 global fallback은 `${TMPDIR:-/tmp}/agentcall/<project-key>/`를 사용합니다.  
전역 persistent state/log를 쓰고 싶을 때만 아래처럼 opt-in 하세요.

```bash
export AGENTCALL_PERSIST_GLOBAL=1
```

그때만 `~/.codex/AgentCall/runtime-data/<project-key>/`가 사용됩니다.

## Quick Start

### Global Smoke

```bash
$HOME/.codex/AgentCall/scripts/global_call_cli.sh \
  --agent architect \
  --prompt "Smoke test only. Reply briefly that you are reachable." \
  --execute
```

### Project-Local Call

```bash
./scripts/call_cli.sh \
  --agent .agents/architect.md \
  --prompt "Propose a minimal architecture for this workflow." \
  --execute
```

```bash
./scripts/call_cli.sh \
  --agent .agents/bug-reviewer.md \
  --prompt "Review only for meaningful bugs and test gaps." \
  --execute
```

strict schema가 꼭 필요할 때:

```bash
./scripts/call_cli.sh \
  --agent .agents/bug-reviewer.md \
  --prompt "Return a strictly structured review." \
  --strict-schema \
  --execute
```

## How It Works

전역 wrapper의 기본 동작은 이렇습니다.

1. 현재 프로젝트에 local `.agents/`가 있으면 그것을 우선 사용
2. 없으면 `~/.codex/AgentCall/agents/`의 curated agent를 fallback으로 사용
3. project-local state/runtime이 없으면 기본적으로 `${TMPDIR:-/tmp}/agentcall/<project-key>/`를 사용
4. `AGENTCALL_PERSIST_GLOBAL=1`일 때만 `~/.codex/AgentCall/runtime-data/<project-key>/`를 사용
5. `side-effects: none` 인 agent는 read-only delegation으로 간주하고 gate metadata만 유지

현재 curated global agents:

- `architect`
- `frontend-designer`
- `integrator`
- `bug-reviewer`
- `design-synthesizer`
- `test-hello`

현재 curated global agents는 모두 `side-effects: none` 기준으로 시작합니다.

## Runtime Model

모든 외부 호출은 wrapper를 통해 통일됩니다.

- project-local: `scripts/call_cli.sh`
- global: `~/.codex/AgentCall/scripts/global_call_cli.sh`

모델 해석 순서:

1. `--model`
2. agent frontmatter `model:`
3. provider default from `.docs/ai-workflow/model-defaults.env` or `model-defaults.env`

strict schema 해석 순서:

1. `--strict-schema`
2. agent frontmatter `strict-schema:`
3. `response-mode: json-fenced`
4. `call-type: synthesis|smoke`
5. role-derived defaults
6. otherwise `false`

## Safety Model

이 저장소는 아래 guard를 포함합니다.

- recursion 차단
- secret-bearing file 차단
- context file 수/크기 제한
- project root 바깥 경로 차단
- output-schema path 검증
- response contract 제어
- frontmatter 기반 timeout/gate 해석
- read-only agent는 `side-effects: none`으로 명시

중요한 점:

- `requires-human-gate`는 여전히 남아 있지만, 현재 global read-only curated agent에서는 execution block보다 lifecycle metadata에 가깝습니다.
- future mutating agent가 생기면 `side-effects != none`일 때 gate enforcement가 다시 강하게 적용됩니다.

## Repository Layout

- `AGENTS.md`
  - 운영 규칙
- `.agents/`
  - project-local agent definitions
- `scripts/`
  - local wrapper, adapters, install/validation helpers
- `codex-global/`
  - 전역 설치용 packaged runtime
- `.docs/ai-workflow/`
  - 상태 파일, 체크리스트, work order, 운영 문서
- `tests/`
  - wrapper / install / contract / transport 검증

## Documentation

주요 문서:

- `.docs/ai-workflow/state.md`
  - 현재 phase, owner, latest decisions
- `.docs/ai-workflow/implementation-checklist.md`
  - 전체 구현 상태 추적
- `.docs/ai-workflow/global-agentcall-friction-work-order.md`
  - recent friction 해소 작업지시서
- `.docs/ai-workflow/global-agentcall-friction-checklist.md`
  - 작업지시서 대비 완료 체크리스트
- `.docs/ai-workflow/overhead-reduction-review.md`
  - 운영 오버헤드 축소 방향

## What Is Not Committed

아래는 git에 올리지 않습니다.

- `.docs/ai-workflow/logs/`
- `.local-runtime/`

즉, 구조/문서/테스트는 저장소에 포함되지만, 실행 로그와 로컬 인증 상태는 포함되지 않습니다.

## License

This project is licensed under the **MIT License**.

자세한 내용은 [LICENSE](LICENSE) 를 참고하세요.

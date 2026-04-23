# AgentCall

project-local first로 시작해, 지금은 Codex 전역 홈까지 확장 가능한 `AgentCall` delegation 기반입니다.

이 저장소는 `Claude`, `Gemini`, `Codex` 같은 외부 CLI를 **bounded role 단위로 안전하게 호출**하기 위한 source repo입니다. 로컬 wrapper와 운영 규칙을 먼저 검증한 뒤, 같은 규칙을 `~/.codex` 전역 설치 형태로 옮길 수 있게 정리했습니다.

핵심 목표는 두 가지입니다.

- 다른 AI CLI를 bounded role 단위로 호출할 수 있는지 검증
- 실제 운영 시 오버헤드를 줄일 수 있는 구조로 정리

운영 철학은 불필요한 위임과 과도한 계약 강제를 줄이고, 필요한 guard와 추적성만 남기는 것입니다.

## Current Status

현재 기준으로는 아래까지 확인됐습니다.

- project-local wrapper, schema, gate, logging, model selection 검증 완료
- 전역 설치용 `codex-global/` package와 installer/validator 구현 완료
- 실제 `~/.codex/skills/AgentCall/SKILL.md`, `~/.codex/AgentCall/` 설치 확인
- 전역 설치 후 dry-run validation 통과
- 전역 설치 후 live smoke 통과
- 다른 프로젝트 기준 Claude/Gemini reviewer 응답 확인

즉, 지금 이 저장소는 “로컬 파일럿만 담은 실험 repo”라기보다, **AgentCall 전역 반영의 source of truth**에 가깝습니다.

## What This Repo Does

이 저장소는 아래 역할을 합니다.

- agent 역할 정의를 `.agents/*.md`로 관리
- 실제 호출은 `scripts/call_cli.sh` 한 곳으로 통일
- 상태, 스키마, 체크리스트, 테스트 케이스를 `.docs/ai-workflow/`에 보관
- dry-run/debug 로그와 실제 작업 로그를 분리
- 모델 기본값, response contract, guard rule을 프로젝트 내부에서만 고정
- frontmatter의 `timeout-sec`, `requires-human-gate`, `output-schema`를 wrapper가 실제로 해석

즉, “프로젝트 안에서 먼저 안정화한 구조를 전역/타 프로젝트에서도 재사용 가능하게 packaging한다”는 목적의 저장소입니다.

## Repository Layout

주요 구조는 이렇습니다.

- `AGENTS.md`
  - 이 저장소에서 지켜야 할 운영 규칙
- `.agents/`
  - 역할별 agent 정의
- `scripts/`
  - wrapper, adapter, validation, gate check
- `.docs/ai-workflow/`
  - 상태 파일, 체크리스트, 스키마, 테스트 케이스, 운영 문서
- `local-skills/AgentCall/`
  - project-local host skill 문서
- `codex-global/`
  - Codex 전역 홈 설치용 global package
- `tests/`
  - wrapper/contract/model/logging 검증 스크립트

## Agent Roles

현재 기본 agent는 다음과 같습니다.

- `architect`
  - 구조 제안, 가정, 리스크 정리
- `frontend-designer`
  - UI/UX/비주얼 피드백
- `bug-reviewer`
  - 결함/회귀/테스트 누락 리뷰
- `integrator`
  - 통합 순서와 적용 계획 정리
- `design-synthesizer`
  - 여러 입력을 하나의 최종안으로 합성
- `test-hello`
  - smoke test용 최소 agent

## Wrapper Behavior

모든 외부 호출은 `scripts/call_cli.sh`로만 수행합니다.

주요 동작 원칙:

- 일반 사용은 `--execute`
- `--dry-run`은 wrapper 점검/디버그용
- review/design 계열은 기본적으로 **text-first**
- strict schema는 **opt-in**
- smoke/synthesis 계열만 기본적으로 strict schema 유지

모델 해석 순서:

1. `--model`
2. agent frontmatter의 `model:`
3. `.docs/ai-workflow/model-defaults.env`

strict schema 해석 순서:

1. `--strict-schema`
2. agent frontmatter의 `strict-schema:`
3. agent frontmatter의 `response-mode: json-fenced`
4. agent frontmatter의 `call-type: synthesis|smoke`
5. role 기반 기본값 (`design-synthesizer`, `test-hello`)
6. 그 외 `false`

실행 gate 해석:

- `--execute`는 agent frontmatter의 `requires-human-gate:`를 기준으로 차단됩니다.
- `architect`는 `A`, `bug-reviewer`는 `C`, `design-synthesizer`는 `S`가 필요합니다.
- `--dry-run`은 실제 외부 CLI를 호출하지 않으므로 gate 확인 전 점검 용도로 유지됩니다.

## Compatibility Direction

기존 agent md를 교체하지 않고, 안 깨지게 이어서 쓰기 위한 **호환 레이어는 이미 현재 basis에 포함**되어 있습니다.

의도는 이렇습니다.

- 기존 `.md` 자산을 전면 교체하지 않음
- 필요한 메타데이터만 비파괴적으로 추가
- 기존 frontmatter가 없어도 가능한 범위에서 자동 추론
- 새 wrapper 규칙과 구 agent 문서를 함께 수용할 수 있게 확장

즉, 방향의 핵심은 “새 포맷으로 갈아타기”가 아니라 **기존 agent 문서를 그대로 살리면서 연결하는 것**입니다. 현재 단계에서는 `normalize_agent_meta` 기반의 최소 호환 레이어가 전역 basis에 포함되어 있고, 이후 보완 포인트는 “호환 범위 확대”이지 “호환 구조 신설”이 아닙니다.

## Logs

로그는 두 갈래로 분리됩니다.

- `.docs/ai-workflow/logs/production/`
  - 실제 작업용 실행 로그
  - 보통 `body.txt`가 있는 세션
- `.docs/ai-workflow/logs/debug/`
  - dry-run, wrapper 테스트, 임시 검증 로그

추가로:

- `.docs/ai-workflow/logs/legacy-wrapper.log`
  - 분리 정책 이전의 과거 wrapper 로그

정리 기준은 단순합니다.

- 결과물을 보려면 `production/`
- 테스트 흔적을 보려면 `debug/`

## Dry Run vs Execute

`--dry-run`은 실제 AI를 호출하지 않습니다.

하는 일:

- agent 선택
- 모델 선택
- context 파일 수집
- prompt 생성
- guard rule 검사
- `host-skill-decision.json` 생성

하지 않는 일:

- 실제 CLI 호출
- 응답 수신
- `body.txt` 생성

반대로 `--execute`는 실제 호출까지 수행합니다.

예시:

```bash
./scripts/call_cli.sh \
  --agent .agents/bug-reviewer.md \
  --prompt "Review this change for real bugs only." \
  --execute
```

```bash
./scripts/call_cli.sh \
  --agent .agents/bug-reviewer.md \
  --prompt "Wrapper contract check" \
  --dry-run
```

## Quick Start

먼저 기본 검증:

```bash
./scripts/validate_skill.sh
```

response contract 점검:

```bash
bash ./tests/response_contract_checks.sh
```

모델 선택 규칙 점검:

```bash
bash ./tests/model_selection_checks.sh
```

dry-run이 debug bucket으로 들어가는지 점검:

```bash
bash ./tests/log_bucket_checks.sh
```

hardening 회귀 점검:

```bash
bash ./tests/hardening_checks.sh
```

Codex prompt-file 전달 점검:

```bash
bash ./tests/codex_promptfile_checks.sh
```

global package install 검증:

```bash
bash ./tests/global_codex_install_checks.sh
```

## Global Rollout Basis

전역 Codex 반영용 basis는 `codex-global/` 아래에 분리해 두었습니다.

- `codex-global/skills/AgentCall/`
  - 전역 Codex skill entry
- `codex-global/runtime/`
  - 전역 curated agents, schema, wrapper, adapters, fallback state template
- `scripts/install_global_codex_host.sh`
  - `~/.codex` 설치/업데이트 스크립트
- `scripts/validate_global_codex_host.sh`
  - 전역 install 검증 스크립트

전역 설치 후 실제 진입점은 아래입니다.

```bash
$HOME/.codex/AgentCall/scripts/global_call_cli.sh --agent architect --prompt "..."
```

기본 설치:

```bash
./scripts/install_global_codex_host.sh
```

설치 검증:

```bash
./scripts/validate_global_codex_host.sh
```

현재 전역 설치 대상 이름은 `AgentCall`입니다.

- skill entry: `~/.codex/skills/AgentCall/SKILL.md`
- runtime root: `~/.codex/AgentCall/`
- global wrapper: `~/.codex/AgentCall/scripts/global_call_cli.sh`

전역 wrapper의 기본 동작은 다음과 같습니다.

- 현재 프로젝트에 `.agents/`가 있으면 project-local agent를 우선 사용
- 없으면 `~/.codex/AgentCall/agents/`의 curated agent를 fallback으로 사용
- project-local state/runtime이 없으면 기본적으로 `$TMPDIR/agentcall/<project-key>/`를 fallback runtime root로 사용
- `AGENTCALL_PERSIST_GLOBAL=1`일 때만 `~/.codex/AgentCall/runtime-data/<project-key>/`를 persistent fallback root로 사용
- 기본은 read-only delegation
- `side-effects: none` 인 agent는 `requires-human-gate`가 있어도 execution block 대상이 아니라 read-only metadata로 처리

추가로, 다른 프로젝트에서 실제 smoke 확인된 결과도 있습니다.

- Claude: `--agent architect` 응답 성공
- Gemini: `--agent frontend-designer` 응답 성공
- `test-hello`는 이제 read-only smoke 용도로 `requires-human-gate: none`으로 완화됨

그리고 이름 변경 후에도 새 경로 기준 검증을 다시 통과했습니다.

- `./scripts/validate_global_codex_host.sh` 통과
- `./scripts/validate_global_codex_host.sh --live-smoke` 통과

현재 curated global agents는 `side-effects: none` 기준으로 동작합니다.

- `architect`
- `frontend-designer`
- `integrator`
- `bug-reviewer`
- `design-synthesizer`
- `test-hello`

## Common Commands

전역 설치본 smoke 예시:

```bash
$HOME/.codex/AgentCall/scripts/global_call_cli.sh \
  --agent architect \
  --prompt "Smoke test only. Reply briefly to hi and confirm you are reachable." \
  --execute
```

`architect` 호출:

```bash
./scripts/call_cli.sh \
  --agent .agents/architect.md \
  --prompt "Propose a minimal architecture for this workflow." \
  --execute
```

`bug-reviewer` 호출:

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

## Validation and Safety

이 저장소는 아래 guard를 포함합니다.

- recursion 차단
- secrets-bearing file 차단
- context file 수/크기 제한
- project root 바깥 경로 차단
- 역할별 response contract 제어
- agent별 human gate enforcement
- frontmatter 기반 timeout/output-schema 해석

즉, “아무거나 바로 던지는 wrapper”가 아니라 최소한의 운영 제약을 둔 파일럿입니다.

## Documentation

주요 운영 문서는 여기 있습니다.

- `.docs/ai-workflow/state.md`
  - 현재 phase, owner, next action
- `.docs/ai-workflow/implementation-checklist.md`
  - 구현 상태 추적
- `.docs/ai-workflow/overhead-reduction-review.md`
  - 오버헤드 절감 운영안
- `.docs/ai-workflow/test-cases/`
  - smoke test, gate report, 설계/리뷰 사이클 기록

## What Is Not Committed

보안과 잡음 문제 때문에 아래는 git에서 제외합니다.

- `.docs/ai-workflow/logs/`
- `.local-runtime/`

즉, 저장소에는 구조와 문서와 테스트만 올라가고, 실행 로그나 로컬 인증 상태는 올라가지 않습니다.

## Current Operating Model

현재 권장 운영 방식은 이렇습니다.

- 단순수정은 delegation하지 않음
- 리뷰는 명시적으로 필요할 때만 호출
- reviewer 간 합의 단계는 두지 않음
- 최종 반영 판단은 Codex가 수행
- 일반 호출은 `--execute`
- dry-run은 wrapper/debug 확인용으로만 사용

현재 기준으로는 구조 검증과 최소 호환 레이어까지 포함한 전역 basis가 이미 성립한 상태로 보고 있습니다. 다음 준비 항목이 있다면 `기존 agent md 호환 구조` 자체가 아니라, 지원해야 할 legacy field 범위를 더 넓히고 운영 범위를 점진적으로 확대하는 쪽입니다.

이 방향은 초기 파일럿에서 확인된 오버헤드를 줄이기 위해 정리된 현재 기본 정책입니다.

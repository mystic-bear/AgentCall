# Global Codex Rollout Work Order

작성일: 2026-04-23  
기준 자산: `ETC/Skill_자체구현_작업지시서_개정본.md`, `AgentCall` project-local pilot

## Goal

project-local로 검증한 AgentCall 구조를 바탕으로, **Codex 전역 홈(`~/.codex`)에서 재사용 가능한 글로벌 기반**을 만든다.

이번 단계의 목적은 “모든 프로젝트에서 곧바로 자동 위임이 되게 한다”가 아니라 아래 두 가지다.

1. Codex 전역 홈에 설치 가능한 **글로벌 host skill 기반**을 만든다.
2. 이후 다른 프로젝트에서 **기존 agent markdown을 안 깨고 연결할 수 있도록** 설치/업데이트 구조를 준비한다.

이 문서는 전역 rollout 직전의 실행 문서다. 아래 결정은 이번 단계에서 열린 항목이 아니라 **구현 전에 잠그는 항목**이다.

## Why Now

현재 상태:

- project-local pilot은 wrapper, guard, gate, schema, logging, prompt transport까지 검증 완료
- Gemini/Claude/Codex 호출 경로가 실제로 동작함
- 다음 병목은 로컬 파일럿 자체가 아니라 **전역에서 반복 설치/업데이트 가능한 구조 부재**

즉, 지금 필요한 것은 “새 기능 추가”보다 **global-ready packaging and installation basis**다.

## Scope

이번 작업 범위는 Codex 전역 기반에 한정한다.

- `~/.codex/skills/` 아래에 설치 가능한 global host skill 구조
- `~/.codex` 아래에 둘 전역 지원 자산의 기준 경로
- repo 안에서 전역 설치본을 만들고 갱신하는 installer/update 경로
- 글로벌 설치 후 최소 smoke/validation 경로
- 최소 호환 레이어(`normalize_agent_meta`) 포함

## Explicit Non-Goals

이번 단계에서 하지 않는 것:

- Claude 전역 skill 설치
- Gemini 전역 skill 설치
- 프로젝트별 `.agents/*.md`를 전역에서 일괄 병합
- 기존 글로벌 skill 전체 재정렬
- 모든 legacy agent markdown 호환 구현 완료
- 전역 자동 위임 on-by-default 활성화

즉, 이번 작업은 **Codex host global basis**를 여는 단계다.

## Recommended Approach

권장안은 **“repo-native source + install to global home”** 방식이다.

```text
AgentCall repo
  ├── codex-global/
  │   ├── skills/AgentCall/SKILL.md
  │   ├── agents/
  │   ├── schema/
  │   ├── scripts/
  │   └── manifests/
  └── scripts/install_global_codex_host.sh

install_global_codex_host.sh
  -> copies curated files into ~/.codex
  -> rewrites install-root aware references
  -> records managed file checksums
  -> validates installed paths
  -> never overwrites unrelated global skills
```

이 방식의 장점:

- 전역 홈을 직접 수작업 수정하지 않아도 됨
- repo가 source of truth로 남음
- update/rollback 범위를 좁힐 수 있음
- 이후 portable distribution으로 확장하기 쉬움

## Rejected Approaches

### 1. Direct-in-place editing under `~/.codex`

문제:

- 변경 추적이 약함
- 되돌리기 어려움
- 설치 상태와 repo 상태가 쉽게 어긋남

### 2. Keep global skill thin and keep logic in project repo

문제:

- 전역 skill이 특정 repo 경로를 참조하게 됨
- 다른 프로젝트에서 재사용성이 낮음
- project-local 검증 구조와 global foundation을 분리하기 어려움

## Target Global Layout

초기 목표 레이아웃:

```text
~/.codex/
  ├── skills/
  │   └── AgentCall/
  │       ├── SKILL.md
  │       ├── references/
  │       └── manifests/
  └── AgentCall/
      ├── agents/
      ├── runtime-data/
      │   └── <project-key>/
      │       ├── state.md
      │       └── logs/
      ├── schema/
      ├── scripts/
      ├── templates/
      └── manifests/
```

원칙:

- skill discovery entry는 `~/.codex/skills/AgentCall/SKILL.md`
- 실행 자산은 `~/.codex/AgentCall/`에 둔다
- unrelated global skills는 건드리지 않는다
- 현재 Codex 환경에서 skill discovery path는 `~/.codex/skills/*/SKILL.md` 패턴으로 **관측 확인됨**

## Locked Decisions

이번 단계에서 아래는 잠금한다.

1. **shared runtime entry를 쓰지 않는다**
   - repo 경로를 참조하는 thin global shim은 채택하지 않는다.
   - 전역 install은 curated copy + manifest 관리 방식으로 간다.
2. **compatibility layer를 defer하지 않는다**
   - 최소 `normalize_agent_meta`는 이번 전역 기반에 포함한다.
3. **global fallback logs/state 경로를 명시한다**
   - project-local runtime이 없을 때는 `~/.codex/AgentCall/runtime-data/<project-key>/`를 사용한다.
4. **fallback mode는 read-only 중심으로 시작한다**
   - 우선 보장 대상은 `architect`, `frontend-designer`, `test-hello`다.
   - 더 높은 gate가 필요한 역할은 project-local state가 없으면 차단될 수 있다.

## Global Skill Responsibilities

전역 `AgentCall` skill은 아래만 책임진다.

1. Codex가 다른 CLI 위임이 필요한 상황을 식별
2. curated agent/role을 선택
3. 전역 wrapper 진입점으로 라우팅
4. global-safe constraints를 설명

전역 skill이 직접 책임지지 않는 것:

- 프로젝트별 상태 파일 강제 생성
- 프로젝트별 role set 자동 생성
- legacy markdown 대규모 자동 변환

## Global Wrapper Responsibilities

전역 wrapper는 project-local wrapper보다 **더 얇아야 한다**.

권장 책임:

- global install manifest 확인
- target project root 감지
- project-local config가 있으면 우선 사용
- 없으면 global default agent/schema/scripts 사용
- secrets / recursion / context budget / gate 같은 핵심 guard 유지
- compatibility normalization 선행

중요:

- 전역 wrapper는 기존 project-local 검증을 깨지 않게 해야 함
- 이번 단계에서는 shared runtime entry가 아니라 **install-time curated copy**를 택한다

## Target Project Root Detection

전역 wrapper는 아래 순서로 target project root를 결정한다.

1. explicit `--project-root`
2. `git rev-parse --show-toplevel`
3. current working directory

이 root는 아래 판단의 기준이 된다.

- project-local `.agents/` 존재 여부
- project-local state/log 위치 존재 여부
- local-first vs global-fallback mode 결정

## Compatibility Requirement

전역화가 의미 있으려면 아래 둘 중 하나는 반드시 지원해야 한다.

1. project-local `.agents/*.md`가 있으면 그것을 우선 사용
2. 없으면 global curated agents를 fallback으로 사용

우선순위는 다음처럼 고정한다.

```text
explicit CLI flag
> project-local agent file
> global curated agent file
> inferred fallback
```

이 규칙은 기존 agent markdown compatibility 설계와 충돌하면 안 된다.

단, 이 규칙이 안전하게 동작하려면 `normalize_agent_meta`가 전제되어야 한다.  
따라서 compatibility layer는 optional이 아니라 **phase entry requirement**다.

## Safety Requirements

전역 설치에서도 아래는 유지해야 한다.

- 기본 read-only
- write permission 비전파
- recursion 금지
- secret-bearing context 차단
- output schema path validation
- dry-run/debug path 분리
- execution gate enforcement

추가로 전역 설치 단계에서 필요한 것:

- install 대상 경로가 예상 위치인지 확인
- overwrite 대상이 managed file인지 확인
- rollback backup 경로 제공
- manifest checksum 기반 drift 감지

## Installer Requirements

`install_global_codex_host.sh` 또는 동등 스크립트는 최소한 아래를 만족해야 한다.

1. install target preview
2. managed file list 출력
3. backup 생성
4. curated file copy
5. install-root aware path rewrite
6. post-install validation
7. validation 실패 시 automatic rollback
8. dry-run mode

권장 옵션:

- `--dry-run`
- `--install-root <path>`
- `--force-managed-overwrite`
- `--print-manifest`

manifest는 최소한 아래를 남겨야 한다.

- managed file path
- sha256
- install timestamp
- installer version
- source repo snapshot or commit hash

## Validation Plan

최소 검증 항목:

1. installed `SKILL.md` exists
2. installed runtime scripts exist
3. global skill text references correct runtime paths
4. dry-run invocation works from a non-AgentCall project
5. live smoke invocation works with one read-only reviewer (`frontend-designer` or `architect`)
6. fallback mode writes state/logs into `runtime-data/<project-key>/`
7. managed file drift is detectable

## Deliverables

- revised work order for global Codex rollout
- repo-native global package directory
- install/update script for `~/.codex`
- validation script for global install
- install manifest / managed file list
- documentation for rollback and precedence rules
- minimal compatibility layer bundled with global runtime

## Completion Criteria

완료 판단 기준:

- repo에서 한 번의 installer 실행으로 `~/.codex` 전역 기반 설치 가능
- global host skill이 unrelated skills를 건드리지 않음
- global installed path와 repo source path가 명확히 구분됨
- non-AgentCall project에서도 dry-run 가능
- non-AgentCall project fallback mode에서 state/log 경로가 명확히 생성됨
- 최소 1회 live smoke 성공

## Open Questions for Review

Claude/Gemini 리뷰에서 특히 검토받을 것:

1. global skill entry와 runtime asset을 분리하는 현재 레이아웃이 타당한가
2. installer가 managed overwrite 방식을 취하는 게 맞는가
3. project-local agent 우선 / global fallback 규칙이 충분히 안전한가
4. 이번 단계에서 compatibility layer 일부를 같이 넣어야 하는가, 아니면 installer basis까지만 가는 게 맞는가

## Review Outcome Summary

2026-04-23 reviewer 반영 요약:

- **Claude**: install-root rewrite, manifest checksum, rollback unit, compatibility dependency를 명확히 하라고 지적
- **Gemini**: target project root 감지, fallback mode의 state/log 위치, compatibility layer 포함 여부를 명확히 하라고 지적

이번 개정본은 위 지적을 반영해:

- curated copy 방식을 잠그고
- minimal compatibility layer를 scope에 포함시키며
- fallback runtime-data 경로와 project-root detection 규칙을 고정한다

추가 현장 확인:

- 다른 프로젝트에서 기존 글로벌 설치 경로 기준 smoke를 수행했을 때
  - Claude `architect` 응답 성공
  - Gemini `frontend-designer` 응답 성공
  - `test-hello`는 `requires-human-gate: S` 때문에 의도대로 차단
- 따라서 global wrapper 경로 자체와 read-only reviewer 경로는 이미 실환경에서 동작 근거가 있다.

# Existing Agent Markdown Compatibility Design

작성일: 2026-04-22  
초안 입력: `logs/production/existing-agent-md-compat-claude-20260422/body.txt`

## Goal

기존 agent markdown 파일을 **교체하지 않고** 현재 AgentCall wrapper에서 그대로 쓸 수 있게 하는 호환 레이어를 설계한다.

핵심 목표:

- 기존 `.md` 자산을 비파괴적으로 수용
- 현재 wrapper 규칙과 충돌 없이 공존
- 새 메타데이터를 강제 마이그레이션하지 않음
- project-local 검증을 끝낸 뒤 더 넓은 범위로 확장 가능한 구조 유지

## Non-Goals

- 기존 agent 파일 자동 rewrite
- 대량 frontmatter 마이그레이션
- 기존 문서 스타일 통일
- 전역 skill 설치 전제 추가

즉, 이번 설계의 목적은 “새 포맷으로 갈아타기”가 아니라 **기존 자산을 깨지 않게 읽는 것**이다.

## Current Reality

현재 wrapper는 아래 canonical field를 가장 잘 이해한다.

- `run-agent`
- `role`
- `model`
- `output-schema`
- `strict-schema`
- `timeout-sec`
- `max-context-files`
- `max-context-bytes`
- `allow-recursion`

반면 실제 기존 자산에는 아래 변형이 섞여 있을 수 있다.

- frontmatter 없음
- field 일부만 존재
- 과거/타 시스템 필드명 사용
  - 예: `cli`, `schema`, `strict`
- 파일명 기반 역할 의미만 있고 메타데이터는 거의 없음

따라서 호환 레이어는 “파일을 수정”하는 대신 **로드 시점 정규화**를 해야 한다.

## Proposed Model

`call_cli.sh` 앞단에 얇은 정규화 단계 하나를 둔다.

```text
call_cli.sh
  -> normalize_agent_meta.(sh|mjs)
      -> canonical metadata export
  -> existing wrapper flow
```

이 레이어의 책임:

1. frontmatter 감지
2. canonical field 읽기
3. alias field 읽기
4. 누락 필드 추론
5. 정규화 결과를 wrapper에 넘기기

이 레이어는 **agent file을 수정하지 않는다**.

## Supported Input Shapes

호환 레이어는 최소한 아래 4가지를 지원해야 한다.

### 1. Fully current file

현재 AgentCall 형식 그대로.

처리:

- 그대로 사용
- 정규화는 no-op

### 2. Partial frontmatter file

예:

- `role`만 있음
- `model`만 있음
- `run-agent`만 없음

처리:

- 있는 값은 그대로 사용
- 없는 값만 추론

### 3. Alias frontmatter file

예:

- `cli` -> `run-agent`
- `schema` -> `output-schema`
- `strict` -> `strict-schema`

처리:

- alias를 canonical로 승격
- canonical field가 이미 있으면 canonical이 우선

### 4. No frontmatter file

파일 본문만 있고 frontmatter 없음.

처리:

- filename 기반 추론 시도
- 최소 필드만 채운 뒤 text-first safe mode로 실행
- 추론 실패 시 명확히 중단

## Canonical Precedence

우선순위는 아래처럼 고정한다.

```text
explicit CLI flag
> canonical frontmatter
> alias frontmatter
> inferred value
> provider default / wrapper fallback
```

예:

- `--model`은 항상 `model:`보다 우선
- `run-agent:`가 있으면 `cli:` alias는 무시
- `strict-schema:`가 있으면 role 기반 추론보다 우선
- 추론값은 명시값을 절대 덮어쓰지 않음

## Alias Mapping

1차 호환 범위는 아래 alias만 지원하면 충분하다.

| Legacy/Alias | Canonical |
|---|---|
| `cli` | `run-agent` |
| `schema` | `output-schema` |
| `strict` | `strict-schema` |

추가 alias는 나중에 늘릴 수 있지만, 초기에 너무 넓히면 wrapper 복잡도만 커진다.

## Inference Rules

추론은 최소한으로만 한다.

### Role

순서:

1. `role:`
2. filename stem
3. 실패 시 중단

권장 규칙:

- `bug-reviewer.md` -> `bug-reviewer`
- `frontend-designer.md` -> `frontend-designer`

filename으로도 추론이 안 되면 자동 fallback하지 않고 실패한다.

### run-agent

순서:

1. `run-agent:`
2. alias `cli:`
3. `model:` prefix 기반
4. role 기반 기본 provider mapping
5. 실패 시 중단

권장 model prefix mapping:

- `claude-*` -> `claude`
- `gemini-*` -> `gemini`
- `gpt-*` -> `codex`

권장 role 기반 fallback:

- `frontend-designer` -> `gemini`
- `architect` -> `claude`
- `bug-reviewer` -> `claude`
- `design-synthesizer` -> `codex`
- 나머지 -> `AGENTCALL_DEFAULT_CLI` 또는 명시 실패

### model

순서:

1. `model:`
2. role+provider 규칙에 따른 repo default
3. provider default from `model-defaults.env`

즉, model은 가장 공격적으로 추론해도 되지만, `run-agent` 추론이 애매하면 model만으로 실행을 강행하지는 않는다.

### output-schema

순서:

1. `output-schema:`
2. alias `schema:`
3. `strict-schema: true`이면 role별 기본 schema 추론
4. 없으면 빈 값 허용

text-first role은 schema 없이도 동작 가능해야 한다.

### strict-schema

순서:

1. `strict-schema:`
2. alias `strict:`
3. role 기본값

권장 role 기본값:

- `test-hello`, `design-synthesizer` -> `true`
- 그 외 review/design/plan role -> `false`

## Wrapper Behavior Changes

`call_cli.sh`는 정규화 결과를 받는 쪽으로 바뀐다.

권장 구현 형태:

```text
normalize_agent_meta -> exports:
  AGENT_RUN_AGENT
  AGENT_ROLE
  AGENT_MODEL
  AGENT_OUTPUT_SCHEMA
  AGENT_STRICT_SCHEMA
  AGENT_RESPONSE_MODE
  AGENT_CALL_TYPE
  AGENT_META_SOURCE
```

`AGENT_META_SOURCE`는 각 필드가 어디서 왔는지 남기는 디버그용 값이다.

예:

```text
role=frontmatter
run-agent=alias
model=inferred:model-defaults
strict-schema=role-default
```

이 정보는 `host-skill-decision.json`과 debug log에만 남기고, user-facing 출력에는 드러내지 않는다.

## Safe Mode for Legacy Files

frontmatter가 없거나 누락이 많은 legacy file은 기본적으로 더 보수적으로 처리한다.

safe mode 규칙:

- response는 기본 `text`
- `strict-schema`는 기본 `false`
- context limit은 wrapper 기본값 사용
- 추론 실패 시 다른 provider로 몰래 fallback하지 않음

즉, legacy file은 “최대한 살려서 읽되, 공격적으로 실행하지 않는다”가 원칙이다.

## Guardrails

### Hard Fail

아래는 즉시 중단한다.

- role 추론 실패
- `run-agent` 추론 실패
- malformed frontmatter
- inferred `run-agent`에 해당 CLI adapter 없음

### Soft Warning

아래는 경고 후 계속 진행 가능하다.

- `model` 누락 -> provider default 사용
- `output-schema` 누락 + text-first role
- alias 사용 감지
- deprecated field 사용 감지

경고는 `logs/debug/compat-warnings.log`에 구조화 라인으로 남긴다.

## Rollout Plan

### Phase 1. Local Normalization Layer

- `normalize_agent_meta` 추가
- 현재 `.agents/*.md`에 regression 없는지 확인
- dry-run/debug에서 field provenance 확인

Exit:

- `validate_skill.sh` 통과
- `response_contract_checks.sh` 통과
- 새 compatibility tests 통과

### Phase 2. Legacy Fixture Tests

- frontmatter 없음
- alias만 있음
- partial frontmatter
- malformed frontmatter

각 케이스를 fixture로 추가해 wrapper 동작을 고정한다.

Exit:

- expected inference와 fail path가 모두 test로 고정

### Phase 3. Cross-Repo Dry Validation

- 기존 agent markdown가 있는 다른 repo에 정규화 레이어만 복사
- `--dry-run` 기준으로 inference 보고서 확인
- 실제 파일 수정 없이 호환성 점검

Exit:

- 예상 밖 role/provider 추론 없음

### Phase 4. Broader Expansion

- standalone compatibility include로 분리 가능성 검토
- 전역 배포 시에도 기존 agent md 교체를 요구하지 않는 형태 유지

## Suggested Follow-Up Work

1. `scripts/normalize_agent_meta.sh` 또는 `.mjs` 추가
2. legacy fixture 테스트 세트 추가
3. `compat-warnings.log` 형식 정의
4. role/provider fallback table을 별도 data file로 분리
5. `COMPATIBILITY.md` 또는 동등 문서 추가

## Final Recommendation

다음 단계는 **새 agent md 포맷을 강제하는 것**이 아니라, `call_cli.sh` 앞단에 얇은 호환 레이어를 두는 것이다.

그 레이어는:

- canonical field 우선
- alias 허용
- 누락 필드 최소 추론
- legacy file safe mode
- 추론 실패는 명확히 중단

이 원칙으로 가면 지금까지 검증한 AgentCall 구조를 유지한 채, 기존 agent markdown 자산도 비파괴적으로 이어서 사용할 수 있다.

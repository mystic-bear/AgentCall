# Schema Validation Shadow Rollout Work Order

작성일: 2026-04-24  
범위: `AgentCall`의 output contract를 운영 소음 없이 보강하기 위한 staged validation 정리  
기준 자산: `scripts/call_cli.sh`, `codex-global/runtime/scripts/global_call_cli.sh`, `.docs/ai-workflow/schema/*.json`

## Review Inputs

초안 작성 후 아래 두 관점의 재검토를 반영한다.

- Claude: rollout / failure-mode / enforcement timing
- Gemini: usability / warning UX / friction

리뷰 공통 결론:

1. full JSON Schema hard fail은 지금 전면 도입하지 않는다.
2. `review/design`은 계속 text-first로 둔다.
3. strict path는 최소 타입 체크까지만 올리고, `output-schema`는 shadow validation으로 먼저 관측한다.
4. warning은 결과 본문을 막지 말고 눈에 띄되 과하게 장황하지 않게 surface 해야 한다.

## Problem Statement

현재 AgentCall의 contract 운영은 의도적으로 완화되어 있다.

- `review/design/analysis` 계열은 text-first다.
- `synthesis/smoke` 계열만 strict 응답을 기본으로 사용한다.
- strict 검증도 현재는 주로 `json` fenced block 존재와 공통 필수 키 확인에 가깝다.
- `output-schema`는 경로 검증과 metadata 기록에는 쓰이지만, wrapper가 full JSON Schema enforcement를 공통적으로 하지는 않는다.

이 상태는 운영 마찰을 줄이는 데는 성공했지만, 구조 보장 관점에서는 한계가 있다.

- 키는 있는데 타입이 틀린 JSON이 통과할 수 있다.
- role-specific schema가 있어도 wrapper-level 보장 수준이 낮다.
- 문서상 `output-schema`와 실제 enforcement 사이의 기대치 차이가 남는다.

반대로 full JSON Schema를 전면 hard fail로 도입하면 이전에 겪은 것처럼 실제 호출 실패율이 높아져 운영이 시끄러워질 가능성이 크다.

이번 작업의 목적은 **schema 강제 자체를 키우는 것**이 아니라, **strict path의 구조 신뢰를 조금 올리되 review/design 흐름의 저마찰 운영을 유지하는 것**이다.

## Review Goal

이번 라운드에서 확인하고 싶은 질문은 세 가지다.

1. wrapper-level full JSON Schema validation을 지금 전면 도입해야 하는가
2. 아니라면 strict path에서 유지할 최소 구조 보장은 어디까지인가
3. `output-schema`를 언제, 어떤 방식으로 actual enforcement로 승격할 것인가

## Current Baseline

현재 기준 동작은 다음과 같다.

- soft contract
  - 대상: `review`, `design`, `analysis`
  - 형식: Markdown/text-first
  - 실패 처리: 구조 검증으로 실행을 막지 않음
- hard-ish contract
  - 대상: `synthesis`, `smoke`
  - 형식: `json` fenced block + 공통 필수 키
  - 실패 처리: strict path에서는 wrapper failure

이 baseline은 유지한다.

## Final Recommendation

이번 라운드의 권장안은 **2-tier contract 유지 + strict path 최소 타입 체크 + output-schema shadow validation**이다.

### 1. Contract를 Soft / Hard-ish 두 단계로 유지한다

#### Soft contract

- 대상: `review`, `design`, `analysis`
- 형식: Markdown/text-first 유지
- 검증: 실행 차단 없음
- 목적: 사람이 읽기 좋은 응답 우선

#### Hard-ish contract

- 대상: `synthesis`, `smoke`, 향후 구조화 export
- 형식: strict 유지
- 현재 strict의 의미:
  - parse 가능한 `json` fenced block
  - 공통 필수 키 존재
  - 소수의 load-bearing 타입 체크

중요한 점은, 이번 라운드에서도 **full JSON Schema를 hard fail의 기본으로 만들지 않는다**는 것이다.

### 2. Strict path에는 최소 타입 체크만 추가한다

strict agent에 대해서 아래 항목만 wrapper-level 공통 검사로 추가한다.

- `confidence`는 number
- `needs_human_decision`은 boolean
- `decisions`는 array
- `risks`는 array
- `open_questions`는 array
- `action_items`는 array
- `requested_context`는 array

이 범위는 downstream에서 실제로 깨지기 쉬운 load-bearing shape만 막고, 나머지 세부 schema mismatch는 아직 hard fail로 보지 않는다.

type mismatch와 missing key는 서로 다른 failure로 기록한다.

### 3. `output-schema`는 shadow validation으로만 먼저 사용한다

strict path에서 `output-schema`가 존재할 경우:

1. 응답 생성 후 schema validation을 시도한다
2. mismatch가 나더라도 초기 단계에서는 실행 자체를 실패로 보지 않는다
3. 대신 warning/log/metadata로 기록한다

즉, 이 단계의 `output-schema`는 enforcement보다 **관측**이 목적이다.

### 4. Early rollout은 fail-open with warning을 기본으로 한다

shadow validation 또는 최소 타입 체크에서 문제가 발견되면:

- raw output은 유지한다
- warning을 `stderr`와 log/session artifact에 남긴다
- 초반 운영에서는 가능한 한 사용자에게 결과 본문을 보여준다

단, strict path의 기본 요건인 아래 두 조건은 유지한다.

- `json` fenced block 없음
- 공통 필수 키 누락

이 둘은 계속 failure로 본다.

### 5. selective enforcement는 data 기반으로만 승격한다

full schema enforcement는 전면 적용하지 않고 아래 순서로만 승격한다.

1. `output-schema` mismatch를 shadow mode로 기록
2. agent별 mismatch rate를 본다
3. mismatch rate가 낮고 구조적 소비가 확실한 agent만 선택적으로 fail-closed 승격

초기 후보는 아래처럼 본다.

- 먼저 검토할 후보: `test-hello`, `design-synthesizer`
- 아직 보류할 후보: `architect`, `frontend-designer`, `bug-reviewer`, `integrator`

## Locked Decisions

이번 작업지시서에서 아래는 잠근다.

1. full JSON Schema validation을 지금 전면 hard fail로 도입하지 않는다.
2. `review/design/analysis`는 text-first soft contract를 유지한다.
3. `synthesis/smoke`는 hard-ish contract를 유지한다.
4. strict path에는 최소 타입 체크만 추가한다.
5. `output-schema`는 먼저 shadow validation으로만 사용한다.
6. schema mismatch는 초기에는 fail-open with warning으로 처리한다.
7. selective enforcement는 mismatch rate를 본 뒤 agent별로만 승격한다.

## Implementation Phases

## Phase 0. Policy and Doc Alignment

목표:

- 문서가 실제 운영 모델을 정확히 설명하게 만든다.

작업:

- `README.md`에 contract tier와 shadow validation 정책 설명 추가
- `AGENTS.md`에 strict path 의미와 shadow validation 단계 추가
- 작업지시서와 체크리스트 baseline 작성

완료 기준:

- 문서가 “full schema 전면 강제”가 아니라 staged validation 정책을 명시

## Phase 1. Minimal Strict Validation Hardening

목표:

- strict path의 구조 신뢰를 소폭 강화한다.

작업:

- 로컬 wrapper와 global wrapper에 최소 타입 체크 추가
- 타입 mismatch 시 명확한 에러 메시지와 로그 남김
- regression test 추가

완료 기준:

- required key는 있지만 타입이 잘못된 strict output이 wrapper에서 검출됨
- 기존 정상 strict smoke/synthesis 응답은 계속 통과

## Phase 2. Shadow Validation Plumbing

목표:

- `output-schema`를 hard fail이 아닌 관측 채널로 연결한다.

작업:

- strict path에서 `output-schema` 존재 시 validation result 계산
- `schema_warning`, `schema_validation_mode`, `schema_mismatch_summary` 같은 metadata 필드 추가
- wrapper log와 decision JSON에 결과 남김
- raw body는 유지

완료 기준:

- schema mismatch가 실행 실패 대신 warning으로 기록됨
- agent별 mismatch 추적이 가능함

## Phase 3. Rollout Documentation

목표:

- 어떤 agent를 언제 enforcement 대상으로 올릴지 판단 기준을 남긴다.

작업:

- selective enforcement 승격 기준 문서화
- mismatch rate 집계 단위 정의
- future follow-up 항목 추가

완료 기준:

- 다음 라운드에서 임의가 아니라 data 기준으로 승격 판단 가능

## Concrete File Targets

- `scripts/call_cli.sh`
- `codex-global/runtime/scripts/global_call_cli.sh`
- `scripts/check_response_contract.mjs`
- `codex-global/runtime/scripts/check_response_contract.mjs`
- `tests/response_contract_checks.sh`
- `tests/schema_shadow_checks.sh`
- 새 validation regression test
- `README.md`
- `AGENTS.md`
- `.docs/ai-workflow/implementation-checklist.md`
- `.docs/ai-workflow/state.md`

## Review Inputs to Collect

## Open Questions

1. shadow mismatch rate를 어떤 threshold에서 selective enforcement 후보로 올릴지
2. provider-native schema enforcement가 가능한 경우(Codex)와 wrapper shadow 결과를 어떻게 함께 설명할지

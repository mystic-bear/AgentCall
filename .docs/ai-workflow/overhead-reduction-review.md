# Overhead Reduction Review

작성일: 2026-04-22
기준 범위: project-local delegation pilot, Pac-Man 설계/리뷰/수정 루프

## Goal

- 이 파일럿에서 실제로 발생한 delegation 오버헤드를 정리한다.
- 단순수정은 위임하지 않는다는 운영 전제를 반영한다.
- 바로 적용 가능한 축소안과 후속 개선안을 구분한다.

## Operating Assumption

- 단순수정은 delegated agent에 맡기지 않는다.
- 리뷰 delegation은 사람이 명시적으로 요청한 경우에만 수행한다.
- 리뷰 결과의 합의 과정은 따로 두지 않는다.
- 최종 반영 여부는 Codex가 로컬 문맥과 테스트 결과를 기준으로 판단한다.
- 여기서 단순수정은 아래에 해당한다.
  - 문구 변경
  - 명확한 1-file 버그 수정
  - 로컬 테스트로 즉시 검증 가능한 소규모 조정
  - 사람이 이미 원인을 특정했고 구현 경로가 분명한 수정

즉, 이 파일럿의 delegation 대상은 `탐색`, `교차검증`, `디자인 시안`, `명시 요청된 리뷰` 같은 작업으로 한정한다.

## Observed Overhead

### 1. Output contract overhead

실제 로그에서 반복적으로 아래 비용이 발생했다.

- `SCHEMA_VIOLATION missing_key=schema_version`
- `SCHEMA_VIOLATION reason=no_json_block`
- provider별 출력 포맷 차이로 body extraction 추가 구현 필요

영향:

- 실제 내용은 도착했는데 wrapper 레벨에서 실패로 처리됨
- 같은 요청을 v2 prompt로 다시 보내는 재시도 비용 발생
- advisory 성격의 리뷰 요청에도 과도한 구조화 요구가 붙음

## 2. Provider/runtime overhead

실제 로그와 구현 이력에서 아래 비용이 확인됐다.

- project-local Codex runtime auth 미완성으로 live smoke에서 우회 필요
- Gemini는 출력 포맷 정규화 보강이 필요했고, capacity/format 민감도가 상대적으로 높았음
- provider별 wrapper 예외 처리가 늘어남

영향:

- 동일한 역할이라도 provider별 adapter 보강 비용이 큼
- pilot 목적보다 runtime 유지보수에 시간이 들어감

## 3. Review fan-out overhead

Pac-Man 작업에서 설계와 리뷰를 Gemini/Claude/Codex로 병렬 호출한 구간은 분명 도움이 있었지만, 모든 구간에서 3-way fan-out이 필요했던 것은 아니다.

영향:

- 호출 수 증가
- 로그/결과 취합 비용 증가
- 상충하거나 부정확한 의견 필터링 필요
- 재리뷰를 다시 3-way로 돌리면 비용이 빠르게 커짐

## 4. Verification gap overhead

브라우저 자동화가 없어서 아래 흐름이 반복됐다.

- 구현
- delegated review
- 사람이 직접 플레이하며 문제 발견
- 다시 delegated review
- 수정

영향:

- 인간 관찰 기반 핫픽스 루프가 길어짐
- deterministic bug도 뒤늦게 발견됨

## 5. Process/logging overhead

state, checklist, logs, schemas를 모두 남기는 구조는 pilot portability에는 유리하지만, 작은 실험에서도 기록 비용이 발생한다.

영향:

- 실제 개발보다 운영 문서 유지 시간이 늘어남
- low-risk 호출에도 동일한 기록 밀도를 요구하게 됨

## What Was Still Worth It

아래 구간은 delegation 효용이 있었다.

- 캐릭터/비주얼 탐색
- 독립적인 리뷰 관점 수집
- 원인 가설 교차검증
- 합성안 초안 생성

즉, delegation은 `정답이 불명확하거나 관점이 여러 개 필요한 작업`에는 효과가 있었고, `명확한 단순수정`에는 효과가 거의 없었다.

## Recommended Operating Model

## 1. Non-Delegation Rule

기본 원칙:

- 단순수정은 Codex 단독 처리
- delegated agent는 아래 조건을 만족할 때만 호출
  - 요구가 탐색형이다
  - 시각/설계 대안이 필요하다
  - 독립 리뷰가 리스크를 실질적으로 줄인다
  - 결과를 합성할 가치가 호출 비용보다 크다

이 규칙을 기본값으로 두면 가장 큰 낭비를 먼저 제거할 수 있다.

## 2. Review Topology: Explicit Request Only

권장 기본형:

- 리뷰는 사람이 명시적으로 지정한 AI에게만 요청
- reviewer 간 합의 단계는 생략
- Codex가 각 리뷰를 읽고 로컬 코드/테스트 기준으로 반영 여부를 최종 결정
- 동일 변경에 여러 reviewer를 붙이는 경우도 `합의`가 아니라 `참고 의견 병렬 수집`으로 취급

권장 역할 매핑:

- frontend/visual 리뷰: Gemini
- backend/logic 리뷰: Claude 또는 Codex
- synthesis는 별도 단계가 아니라 Codex의 최종 판단/반영으로 흡수

## 3. Contract Simplification by Call Type

모든 호출에 동일한 JSON 계약을 강제하지 않는다.

권장 구분:

- design/review/advisory call:
  - plain text 허용
  - 필요한 항목만 prompt에서 지정
  - strict schema 검사 생략 또는 완화
- synthesis/final handoff call:
  - 구조화 출력이 꼭 필요할 때만 선택적으로 사용
  - 기본은 text 요약으로 충분

리뷰 요청에서 충분한 최소 항목 예:

- `핵심 문제`
- `근거`
- `권장 수정`
- `미확인 가정`

`schema_version`, fenced JSON block, 강제 key set 같은 메타 규약은 review/advisory call에는 불필요하다.

## 4. Provider Profile Narrowing

provider마다 동일한 wrapper 정책을 강제하지 말고, 역할별로 좁게 사용한다.

권장 예:

- Gemini:
  - 디자인 탐색, UI 피드백, 캐릭터 시안
  - plain text 우선
- Claude:
  - 로직 리뷰, 설계 검토, 안정성 리뷰
  - semi-structured text 우선
- Codex:
  - 구현, 최종 반영 판단, repo-aware 판단
  - 외부 리뷰 결과가 있어도 반영 여부는 Codex가 결정

이렇게 하면 adapter 복잡도를 줄이고, provider별 실패 패턴도 예측하기 쉬워진다.

## 5. Retry Budget and Fallback Rules

권장 규칙:

- schema/format 실패는 1회까지만 재시도
- 같은 provider에서 2회 실패하면 다른 provider로 넘기지 말고, 사람이 수동 판독 또는 Codex 직접 처리
- 디자인 요청만 provider fallback 허용
- 단순 리뷰 요청은 fallback보다 로컬 수정/테스트가 우선

이유:

- 작은 문제를 provider roulette로 키우지 않기 위해서다.

## 6. Verification First for Deterministic Bugs

버그성 이슈는 delegated review 전에 로컬 재현과 테스트 후보를 먼저 본다.

권장 흐름:

1. 로컬 재현
2. 테스트 추가 또는 계측
3. 원인이 여전히 불명확할 때만 delegated review

이번 Pac-Man 사례에서 이동/맵 이슈는 결국 로컬 테스트 강화가 가장 큰 효과를 냈다.

## 7. Logging Tiering

기록 강도를 두 단계로 나눈다.

- full log:
  - multi-agent 설계
  - high-risk 리뷰
  - synthesis
- light log:
  - 단일 reviewer 호출
  - exploratory prompt
  - 결과를 사람이 바로 소비하는 call

light log에는 아래만 남기면 충분하다.

- session id
- agent
- provider
- prompt 목적
- success/failure
- 결과 파일 경로

## Immediate Changes Recommended

우선순위 순서:

1. 단순수정 비위임 원칙을 운영 기본값으로 확정
2. 리뷰는 사람이 명시적으로 지정한 AI에게만 요청
3. reviewer 간 합의 단계와 별도 synthesis 단계를 제거
4. review/advisory call의 strict schema 요구 제거
5. deterministic bug는 delegated review 전에 테스트를 먼저 추가

예상 효과:

- 호출 수 감소
- 재시도 감소
- wrapper/정규화 코드 부담 감소
- 문서 유지 비용 감소

## Follow-Up Implementation Candidates

문서화만이 아니라 실제 운영 변경까지 한다면 아래 순서가 적절하다.

### Phase A. Process Tuning

- call 유형을 `simple`, `review`, `design`, `synthesis`로 분류
- `simple`은 무조건 local-only
- `review`는 explicit target만 호출
- 반영 결정은 Codex 단독 수행

### Phase B. Wrapper Tuning

- `--strict-schema`를 opt-in으로 전환
- review/advisory call은 text mode 기본
- light log 모드 추가
- dry-run/debug 로그와 production 로그를 분리

### Phase C. Verification Tuning

- 브라우저 smoke 자동화 1개 추가
- gameplay invariant 테스트를 계속 늘려 human rediscovery를 줄임

## Conclusion

이 pilot에서 줄여야 할 핵심 오버헤드는 `호출 수`보다도 `불필요한 위임`과 `과도한 계약 강제`였다.

단순수정을 위임 대상에서 제외하고, 리뷰를 명시 요청 기반으로만 수행하며, review call에서 strict schema를 빼면 현재 구조의 장점은 유지하면서 운영비를 눈에 띄게 낮출 수 있다.

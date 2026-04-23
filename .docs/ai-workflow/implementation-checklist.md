# Implementation Checklist

기준 문서: `Skill_자체구현_작업지시서_개정본.md`

목적:

- 작업지시서 대비 현재 구현 상태를 비교한다.
- phase별 남은 작업을 명확히 적는다.
- 구현이 진행될 때마다 상태를 업데이트한다.

## Status Legend

- `[x]` 구현/검증 완료
- `[~]` 부분 구현
- `[ ]` 미구현

## Phase 1. Project-Local Foundation

| 항목 | 기준 | 상태 | 메모 |
|------|------|------|------|
| 로컬 전용 운영 | 전역 설치 없이 프로젝트 내부 자산만 사용 | [x] | `AGENTS.md`, `.agents/`, `scripts/`, `.docs/ai-workflow/` 구성 완료 |
| 상태 파일 | `state.md`로 phase/owner/next action 복구 가능 | [x] | 핵심 필드 구성 완료 |
| 역할 정의 | architect / frontend-designer / integrator / bug-reviewer | [x] | `.agents/*.md` 생성 완료 |
| 기본 스키마 | common + role schema 존재 | [x] | `.docs/ai-workflow/schema/*.json` 생성 완료 |
| 로컬 검증기 | baseline validation 스크립트 | [x] | `scripts/validate_skill.sh` 구현 |

## Phase 2. Host Skill Contract

| 항목 | 기준 | 상태 | 메모 |
|------|------|------|------|
| host skill 문서 | project-local host skill 규약 문서 존재 | [x] | `local-skills/subagent-host/SKILL.md` 추가 |
| host skill 책임 | 언제 호출/호출 금지/안전 게이트 명시 | [x] | When to Use / When NOT to Use / Safety Gates 반영 |
| host skill 산출물 | decision log 또는 동등한 출력 규약 | [x] | dry-run JSON + `host-skill-decision.json` 기록 |

## Phase 3. Gate S Verification

| 항목 | 기준 | 상태 | 메모 |
|------|------|------|------|
| dry-run 검증 | wrapper dry-run 성공 | [x] | 검증 완료 |
| Gate S 자동 점검 | 반복 가능한 체크 스크립트 존재 | [x] | `scripts/run_gate_s_checks.sh` 추가 |
| pressure test 기록 | Gate S 결과 문서화 | [x] | `test-cases/gate-s-report.md` 갱신 완료 |
| pre-required-gate execute 차단 | agent 요구 gate 미충족 시 실실행 차단 | [x] | `call_cli.sh --execute` 가드 존재 |
| secrets 차단 | 민감 파일 입력 차단 | [x] | wrapper guard 구현 완료 |
| recursion 차단 | depth > 0에서 차단 | [x] | wrapper guard 구현 완료 |

## Phase 4. Execution Smoke Test

| 항목 | 기준 | 상태 | 메모 |
|------|------|------|------|
| Gate S 반영 | state.md에 Gate S 통과 반영 | [x] | `Last Gate Passed: S` 반영 완료 |
| 실제 CLI 왕복 | 실제 prompt 전송 후 응답 수신 | [x] | `claude` 기반 `test-hello` smoke test 성공 |
| 결과 기록 | 응답 결과를 work-order/state/checklist에 기록 | [x] | smoke test 결과와 잔여 리스크 기록 예정/완료 |
| 종료 정리 | 현재 phase와 다음 action 갱신 | [x] | phase 종료 상태로 정리 |

## Phase 5. Prototype Delivery Loop

| 항목 | 기준 | 상태 | 메모 |
|------|------|------|------|
| Gemini 응답 정규화 | wrapper JSON / plain text 둘 다 body 추출 가능 | [x] | `extract_response_body.mjs`, `gemini_output_normalization_checks.sh` 추가 |
| 웹 프로토타입 구현 | 브라우저에서 1판 플레이 가능한 Pac-Man 골격 | [x] | `index.html`, `styles.css`, `src/game.mjs`, `src/pacman-core.mjs` 구현 |
| 테스트 보강 | 핵심 게임 로직 테스트 추가 | [x] | `tests/pacman_core.test.mjs` 확장 |
| 문서화 | 실행 방법과 제약 사항 문서화 | [x] | `README.md` 추가, HTTP serving requirement 명시 |
| 1차 리뷰 루프 | Gemini / Claude / Codex 의견 수집 | [x] | `pacman-review-*` 로그 생성 완료 |
| 리뷰 반영 | 핵심 지적 수정 반영 | [x] | storage guard, bootstrap guard, touch input, DPR scaling, round resolution 보강 |
| 재리뷰 | 수정 후 남은 리스크 재확인 | [x] | `pacman-rereview-*` 로그 생성 완료 |
| 최종 검증 | 테스트/검증 스크립트 재실행 | [x] | node test + validate + normalization/model checks 재통과 |

## Current Snapshot

- 완료: 로컬 전용 파일럿 골격, 역할 정의, 상태 파일, 스키마, wrapper 기본 guard, host skill 문서, Gate S 자동 점검, 실제 CLI 왕복 테스트
- 완료: Gemini/Claude/Codex를 포함한 Pac-Man 설계 호출, Canvas 기반 웹 프로토타입 구현, 리뷰 수집과 수정 루프, 최종 재검증
- 완료: 오버헤드 절감 검토 문서 작성. 단순수정 비위임, 명시 요청 리뷰만 수행, Codex 최종판단, advisory call text 중심 방향 정리
- 완료: wrapper/process에 저오버헤드 정책 반영. `review/design`은 text-first, strict schema는 opt-in, `test-hello`/`design-synthesizer`만 기본 strict 유지
- 완료: dry-run/debug 로그와 production 로그 분리. wrapper 기본 사용을 `--execute` 중심으로 전환하고 기존 혼합 로그를 `production/debug/legacy-wrapper.log`로 정리
- 완료: review-driven hardening round. `requires-human-gate` 실행 enforcement, `timeout-sec`/`output-schema` 해석, Codex prompt-file transport, secret scan 확장, canonical context logging 반영
- 완료: follow-up polish round. role schema `allOf` 일관화, Codex test portability 개선, gate semantics 문서화, Gemini read-only live smoke 확인
- 완료: global Codex rollout basis. reviewer-refined work order, `codex-global/` package, installer/validator, `/tmp` install validation, actual `~/.codex` install 반영
- 완료: global naming alignment. local/global skill entry를 `AgentCall`로 통일하고, legacy managed `subagent-host` install을 migration 대상으로 정리
- 완료: renamed global validation. `~/.codex/AgentCall` 기준 dry-run/live-smoke 검증 완료, active legacy path는 제거되고 backup만 유지
- 완료: local Codex cleanup. project-local `local_codex.sh` 제거, Codex adapter를 direct `codex exec`로 단순화, npm global Codex wrapper conflict 해소
- 완료: global friction work-order drafted. Claude/Gemini review를 바탕으로 runtime root 및 gate 완화 방향 문서화
- 완료: global friction implementation. tmp fallback default, `side-effects` 해석, read-only gate relaxation, `test-hello` smoke 완화, validator/install test 보강
- 완료: post-implementation Claude review 반영. stale README, static temp path, invalid `side-effects` validation, work-order wording 정밀화
- 완료: schema validation shadow rollout. strict path 최소 타입 체크, shadow validation helper, warning artifact, regression test, README/AGENTS 정책 반영
- 남음: 브라우저 수준 자동화 테스트는 아직 없음. 현재는 로직 테스트 + 정적서버 smoke 수준 검증까지 완료

## Update Log

- 2026-04-22 11:15 +09:00: 초기 체크리스트 작성. 현재 구현 상태를 phase별로 분해해 기록.
- 2026-04-22 11:20 +09:00: Phase 2와 Phase 3 핵심 항목 구현 완료. Gate S report 생성.
- 2026-04-22 11:24 +09:00: Phase 4 완료. Claude 기반 `test-hello` smoke test 성공. Codex local runtime auth는 후속 과제로 기록.
- 2026-04-22 12:36 +09:00: Phase 5 완료. Gemini 응답 정규화, Pac-Man 프로토타입 구현, 1차 리뷰와 재리뷰, 최종 검증까지 반영.
- 2026-04-22 14:10 +09:00: 오버헤드 절감 검토 문서 추가. 단순수정 비위임 전제를 반영해 review topology와 schema 강도를 축소하는 안 정리.
- 2026-04-22 14:18 +09:00: 리뷰는 명시 요청 AI만 호출하고 합의 과정 없이 Codex가 최종판단하는 모델로 문서를 개정. review 출력은 text 중심으로 정리.
- 2026-04-22 14:31 +09:00: `call_cli.sh`에 text-first response contract와 `--strict-schema` opt-in 반영. agent frontmatter/본문 수정 및 `response_contract_checks.sh` 추가, 검증 통과.
- 2026-04-22 15:31 +09:00: `call_cli.sh` 기본 모드를 execute로 전환하고 dry-run은 debug bucket으로 분리. 기존 로그도 `logs/production`, `logs/debug`, `legacy-wrapper.log` 구조로 재정리.
- 2026-04-22 17:35 +09:00: review-driven hardening 반영. secret scan, gate enforcement, timeout/schema enforcement, prompt transport, validation/docs 보강 완료.
- 2026-04-22 18:05 +09:00: 후속 보완 반영. schema composition 일관화, 테스트 이식성 수정, gate 의미 문서화, Gemini `--approval-mode plan` 실환경 smoke 성공.
- 2026-04-23 07:35 +09:00: Claude/Gemini 리뷰 반영 후 global rollout work order 개정. `codex-global/` 패키지와 installer/validator 구현, `/tmp` install test 통과, 실제 `~/.codex` install 반영.
- 2026-04-23 09:25 +09:00: 전역 skill/runtime 이름을 `AgentCall`로 통일. installer/validator 경로와 문서를 갱신하고, 외부 프로젝트에서 확인된 Claude/Gemini smoke 결과를 rollout 근거로 기록.
- 2026-04-23 09:40 +09:00: `~/.codex/AgentCall`로 재설치 후 global validator와 live smoke를 다시 통과. `subagent-host` active install은 제거되고 backup 흔적만 남김.
- 2026-04-23 21:20 +09:00: stale npm `codex` wrapper를 백업하고 npm global install을 복구. project-local `local_codex.sh`를 제거하고, global AgentCall friction 완화 작업지시서를 Claude/Gemini 검토 기반으로 추가.
- 2026-04-23 21:35 +09:00: lazy tmp fallback, `side-effects` 기반 gate 완화, global validator/install check 보강, work-order 대비 체크리스트 작성, Claude post-implementation review 반영 완료.
- 2026-04-24 11:15 +09:00: staged schema validation work order 작성 후 Claude/Gemini 재검토 반영. strict path 최소 타입 체크와 `output-schema` shadow validation helper 추가, `schema-shadow.jsonl` 경고 기록과 회귀 테스트 반영.

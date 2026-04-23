# Schema Validation Shadow Rollout Checklist

기준 문서: `.docs/ai-workflow/schema-validation-shadow-work-order.md`

목적:

- staged validation 작업지시서 기준으로 구현 상태를 비교한다.
- Claude/Gemini 재검토 후 최종 설계와 실제 코드가 어긋나지 않는지 기록한다.

## Status Legend

- `[x]` 완료
- `[~]` 부분 완료
- `[ ]` 미완료

## Phase 0. Policy and Doc Alignment

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| 작업지시서 초안 작성 | staged validation 설계 문서화 | [x] | 본 문서와 `schema-validation-shadow-work-order.md` 작성 |
| 재검토 요청 | Claude/Gemini review 요청 | [x] | 2026-04-24 재검토 완료 |
| 정책 문서 반영 | README/AGENTS에 정책 반영 | [x] | contract tier, shadow validation, rollback env 반영 |

## Phase 1. Minimal Strict Validation Hardening

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| 최소 타입 체크 추가 | strict path에서 load-bearing type 검사 | [x] | `check_response_contract.mjs`, local/global wrapper 반영 |
| strict 실패 메시지 정리 | 타입 mismatch 로그/에러 구체화 | [x] | missing key / type mismatch 분리, dedicated exit path 추가 |
| 회귀 테스트 | 최소 타입 체크 regression 추가 | [x] | `tests/schema_shadow_checks.sh` 추가 |

## Phase 2. Shadow Validation Plumbing

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| schema shadow 실행 | `output-schema` 기반 validation result 계산 | [x] | helper script가 schema mismatch를 shadow mode로 계산 |
| warning metadata 기록 | decision/log에 shadow result 기록 | [x] | contract validation file, wrapper warning log, `schema-shadow.jsonl` 반영 |
| fail-open 유지 | mismatch 시 raw output 유지 | [x] | schema mismatch는 warning only, strict success 유지 |

## Phase 3. Rollout Documentation

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| selective enforcement 기준 | 승격 기준 문서화 | [x] | work order와 README에 staged rollout 방향 반영 |
| mismatch 관측 기준 | 측정 단위와 follow-up 정리 | [x] | warning artifact와 future threshold open question 정리 |

## Reviewer Feedback

| 검토자 | 상태 | 메모 |
|--------|------|------|
| Claude | [x] | rollout / failure-mode review 반영 |
| Gemini | [x] | warning UX / fail-open review 반영 |

## Notes

- 이번 라운드의 핵심은 “full schema hard fail 확대”가 아니라 “strict path의 최소 구조 보장 + schema 관측 채널 추가”다.
- review/design text-first 운영 철학은 유지한다.

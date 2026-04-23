# Global AgentCall Friction Checklist

기준 문서: `.docs/ai-workflow/global-agentcall-friction-work-order.md`

목적:

- 작업지시서의 phase별 요구사항을 구현 상태와 비교한다.
- 어떤 항목이 완료됐고 어떤 검증으로 확인했는지 남긴다.
- Claude 최종 검토 후 문서와 실제 코드가 어긋나지 않는지 재확인한다.

## Status Legend

- `[x]` 완료
- `[~]` 부분 완료
- `[ ]` 미완료

## Phase 0. Immediate Cleanup

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| 로컬 Codex 의존 제거 | `scripts/local_codex.sh` 제거, direct `codex exec` 전환 | [x] | `scripts/adapters/codex.sh` direct exec 반영, `scripts/local_codex.sh` 삭제 |
| npm Codex 충돌 해소 | stale wrapper 백업 후 npm global install 복구 | [x] | `~/.local/bin/codex.pre-npm-wrapper.20260423` 백업, `~/.local/bin/codex` npm symlink 재생성 |
| 로컬 검증기 정리 | validation/test/README에서 local launcher 참조 제거 | [x] | `validate_skill.sh`, `tests/codex_promptfile_checks.sh`, `README.md` 갱신 |
| 기본 검증 | adapter stdin transport와 validation 통과 | [x] | `./scripts/validate_skill.sh`, `bash ./tests/codex_promptfile_checks.sh`, `codex --version` |

## Phase 1. Lazy Fallback Root

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| eager global fallback 제거 | 기본 fallback write를 `~/.codex`에서 제거 | [x] | `codex-global/runtime/scripts/global_call_cli.sh`에서 tmp fallback 기본화 |
| runtime root resolver 추가 | env override / tmp / opt-in persistent 순서 | [x] | `AGENTCALL_LOG_ROOT`, `AGENTCALL_RUNTIME_ROOT`, `AGENTCALL_PERSIST_GLOBAL` 처리 추가 |
| dry-run no-global-write | dry-run에서 escalation 없는 fallback 사용 | [x] | validator가 `runtime_root_mode: tmp-fallback` 확인 |
| persistent global opt-in화 | `~/.codex/AgentCall/runtime-data`는 opt-in 전용 | [x] | README, global skill doc, wrapper 로직 반영 |

## Phase 2. Side-Effect-Based Execution Control

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| `side-effects` 필드 추가 | normalizer와 wrapper가 새 필드 해석 | [x] | `normalize_agent_meta.sh`, `global_call_cli.sh` 반영 |
| read-only agent 재분류 | curated global agents를 `side-effects: none`으로 표시 | [x] | `codex-global/runtime/agents/*.md` 갱신 |
| gate enforcement 완화 | `side-effects != none`일 때만 gate block | [x] | `global_call_cli.sh` gate enforcement 조건 변경 |
| `test-hello` 재정의 | smoke용 read-only 호출 가능화 | [x] | `codex-global/runtime/agents/test-hello.md`에서 `requires-human-gate: none` |

## Phase 3. Validation and Rollout

| 항목 | 작업지시서 기준 | 상태 | 근거 |
|------|------------------|------|------|
| temp install 검증 | install + validator 통과 | [x] | `bash ./tests/global_codex_install_checks.sh` |
| actual global reinstall | 새 정책을 `~/.codex/AgentCall`에 반영 | [x] | `./scripts/install_global_codex_host.sh` 실행 완료 |
| actual global validation | installed runtime validator + live smoke | [x] | `./scripts/validate_global_codex_host.sh --install-root /home/inyong_hwang/.codex --live-smoke` |
| non-AgentCall dry-run friction 확인 | tmp fallback 기반 dry-run 확인 | [x] | dry-run output `runtime_root_mode: tmp-fallback` 확인 |
| existing-agent compatibility 유지 | normalizer 기반 compatibility 보존 | [x] | `normalize_agent_meta.sh` 유지 + reviewer work order 반영 |

## Claude Review

| 항목 | 상태 | 메모 |
|------|------|------|
| 구현 후 Claude 검토 | [x] | `global-friction-post-impl-claude-review-20260423` |
| 리뷰 반영 | [x] | stale README 문구 수정, static temp path 제거, invalid `side-effects` 값 검증 추가, dry-run 문구 정밀화 |

## Notes

- 이번 라운드는 “guard 제거”가 아니라 “read-only delegation friction 완화”에 초점을 맞췄다.
- mutation-capable future agent는 여전히 `requires-human-gate` 기반 통제를 받을 수 있게 구조를 남겼다.

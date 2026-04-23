# Review Context: Global AgentCall Friction Round

이 문서는 Claude review용 요약본이다.

## Goal

전역 AgentCall의 두 가지 운영 마찰을 줄이는 것이 목표였다.

1. non-AgentCall project에서 global fallback write가 `~/.codex/AgentCall/runtime-data/`로 바로 가서 sandbox escalation을 반복 유발
2. `requires-human-gate`가 lifecycle metadata와 execution block을 같이 담당해 read-only advisory agent도 과도하게 차단

## Implemented Changes

### 1. Local Codex cleanup

- `scripts/local_codex.sh` 제거
- `scripts/adapters/codex.sh`는 direct `codex exec --skip-git-repo-check` + stdin prompt transport로 단순화
- stale npm wrapper `~/.local/bin/codex`를 백업하고 npm global install 복구

### 2. Global fallback root policy

- `codex-global/runtime/scripts/global_call_cli.sh`
  - bootstrap log root 기본값을 `~/.codex`가 아니라 `${TMPDIR:-/tmp}/agentcall/bootstrap/logs`로 변경
  - global fallback root 기본값을 `${TMPDIR:-/tmp}/agentcall/<project-key>`로 변경
  - `AGENTCALL_LOG_ROOT`, `AGENTCALL_RUNTIME_ROOT`, `AGENTCALL_PERSIST_GLOBAL=1` 지원
  - `AGENTCALL_PERSIST_GLOBAL=1`일 때만 `~/.codex/AgentCall/runtime-data/<project-key>` 사용
  - read-only or dry-run fallback 경로에서는 state file 생성을 건너뜀

### 3. Side-effect-based execution control

- `codex-global/runtime/scripts/normalize_agent_meta.sh`
  - `side-effects` frontmatter 해석 추가
  - 현재 curated role들의 default는 `none`
- `codex-global/runtime/scripts/global_call_cli.sh`
  - `side-effects != none`일 때만 `requires-human-gate` execution block 적용
  - decision/dry-run output에 `side_effects`, `runtime_root_mode` 추가

### 4. Curated agent updates

- `codex-global/runtime/agents/*.md`
  - 전부 `side-effects: none` 추가
  - `test-hello`는 `requires-human-gate: none`으로 변경

### 5. Docs and validation

- `scripts/validate_global_codex_host.sh`
  - dry-run 결과에 `runtime_root_mode: tmp-fallback`, `side_effects: none` 기대
- `tests/global_codex_install_checks.sh`
  - temp install 후 tmp fallback mode 확인 추가
- `AGENTS.md`, `README.md`, `codex-global/skills/AgentCall/SKILL.md`
  - 새 fallback/gate 정책 설명 반영
- `.docs/ai-workflow/global-agentcall-friction-work-order.md`
  - Claude/Gemini 의견을 반영한 작업지시서
- `.docs/ai-workflow/global-agentcall-friction-checklist.md`
  - 작업지시서 대비 구현 비교표

## Validation Already Run

- `./scripts/validate_skill.sh`
- `bash ./tests/codex_promptfile_checks.sh`
- `bash ./tests/global_codex_install_checks.sh`
- `./scripts/validate_global_codex_host.sh --install-root /home/inyong_hwang/.codex --live-smoke` on the currently installed version after reinstall

## Review Request

중점적으로 봐야 할 것은 아래다.

1. tmp fallback 정책이 sandbox friction을 줄이는 데 충분한가
2. `side-effects != none`일 때만 gate를 막는 규칙에 loophole은 없는가
3. 현재 curated agent를 전부 `side-effects: none`으로 둔 것이 과도하게 완화된 것은 아닌가
4. validator/test/doc이 실제 동작과 어긋나는 부분이 남아 있는가

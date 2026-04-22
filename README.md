# AgentCall

프로젝트 로컬 전용 AI CLI delegation 파일럿입니다.

## Core Paths

- `AGENTS.md`
- `.agents/`
- `scripts/`
- `.docs/ai-workflow/`
- `tests/`

## Quick Checks

```bash
./scripts/validate_skill.sh
```

```bash
bash ./tests/response_contract_checks.sh
```

```bash
bash ./tests/model_selection_checks.sh
```

## Notes

- review/design 계열 agent는 기본적으로 text-first 응답을 사용합니다.
- strict schema는 opt-in이며, smoke/synthesis 계열만 기본적으로 strict를 유지합니다.
- 일반 사용은 `--execute` 기준입니다.
- `--dry-run`은 wrapper 점검용이며 로그는 `logs/debug/`로 분리됩니다.
- 실제 작업 로그는 `logs/production/` 아래에 남습니다.

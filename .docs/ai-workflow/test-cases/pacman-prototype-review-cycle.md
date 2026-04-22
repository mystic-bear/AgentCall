# Pac-Man Prototype Review Cycle

## Scope

- Implement a lightweight browser-playable Pac-Man prototype
- Use the local delegation pilot for review collection
- Apply review feedback and re-verify

## Prototype Artifacts

- `index.html`
- `styles.css`
- `src/game.mjs`
- `src/pacman-core.mjs`
- `tests/pacman_core.test.mjs`
- `README.md`

## Review Round 1

### Gemini / Frontend

Source:

- `.docs/ai-workflow/logs/pacman-review-frontend-20260422/body.txt`

Main points:

- high-DPI canvas sharpness
- touch/mobile affordance
- overlay opacity balance

### Claude / Bug Review

Source:

- `.docs/ai-workflow/logs/pacman-review-claude-20260422/body.txt`

Main points:

- startup safety around storage and canvas/bootstrap assumptions
- round resolution on final collectible vs ghost collision
- missing browser-facing safety and test coverage

### Codex / Bug Review

Source:

- `.docs/ai-workflow/logs/pacman-review-codex-20260422/body.txt`

Main points:

- storage failure handling
- round resolution precedence
- bootstrap resilience

## Changes Applied

- Added Gemini response body normalization:
  - `scripts/extract_response_body.mjs`
  - `tests/gemini_output_normalization_checks.sh`
- Switched Gemini adapter output to plain text mode
- Added safe storage helpers and safe browser storage access
- Added bootstrap error handling for missing DOM / canvas context
- Added DPR-aware canvas configuration
- Added touch swipe support and `touch-action: none`
- Lowered overlay opacity so end-state board remains more visible
- Resolved round precedence so live ghost collision beats board-clear win
- Added README with HTTP serving instructions
- Expanded core tests for:
  - storage parsing and storage failure fallback
  - snap threshold
  - parseMap actor validation
  - blocked ghost path fallback
  - round resolution precedence
  - safe storage getter

## Review Round 2

Sources:

- `.docs/ai-workflow/logs/pacman-rereview-frontend-20260422/body.txt`
- `.docs/ai-workflow/logs/pacman-rereview-claude-20260422/body.txt`
- `.docs/ai-workflow/logs/pacman-rereview-codex-20260422/body.txt`

Outcome:

- Gemini re-review raised one valid touch-scrolling concern and one false-positive media-query concern.
- Touch scrolling concern was addressed by adding `touch-action: none`.
- Claude re-review mainly raised lower-priority cleanup/test-gap items.
- Codex re-review identified one remaining valid issue around `window.localStorage` property access; this was patched with `getSafeStorage(() => window.localStorage, null)`.

## Verification

Successful commands:

```bash
node --test tests/pacman_core.test.mjs
```

```bash
./scripts/validate_skill.sh
```

```bash
bash ./tests/gemini_output_normalization_checks.sh
```

```bash
bash ./tests/model_selection_checks.sh
```

```bash
python3 -m http.server 8123
curl -fsS http://127.0.0.1:8123/
```

## Residual Risk

- No headless browser automation yet; current confidence comes from logic tests, static serving smoke, and delegated review loops.

## Post-Review Hotfix

- User-reported symptom:
  - Pac-Man accepted input but barely moved
  - ghosts appeared frozen
  - mouth animation still updated
  - immediate start pressure left too little reaction time
- Additional delegated motion review:
  - Gemini, Claude, and Codex all pointed to repeated center-processing as the core movement bug
- Applied hotfix:
  - added one-time center-visit locking (`centerLockKey`)
  - added `shouldProcessCenterVisit`
  - removed immediate auto-movement by starting Pac-Man with `direction: null`
  - added a short round-start countdown
  - reduced ghost speed for a fairer opening beat
- Verification:
  - `node --test tests/pacman_core.test.mjs`
  - served `src/game.mjs` confirmed updated constants and countdown logic

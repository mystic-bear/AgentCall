# Pac-Man Design Brief

## Goal

Test the local multi-agent delegation flow by producing a lightweight design for a browser-playable Pac-Man clone.

## Scope

- One playable single-session round in the browser
- No login
- No leaderboard
- No persistence requirement beyond optional local state
- No multiplayer
- No account system
- No admin or CMS

## Product Intent

The main goal is **testing agent delegation**, not shipping a production game platform.

Therefore the design should prefer:

- low complexity
- quick implementation
- easy local running
- minimal moving parts

## Required Delegation Split

- Frontend design: Gemini
- Backend / serving design: Claude
- Final synthesis: Codex

## Assumptions

- Browser-only game is acceptable
- Backend can be minimal or even reduced to local static serving if justified
- A single-page app is preferred
- Desktop keyboard controls are enough for the first pass

## Open-Source Reference Notes

1. Phaser is an HTML5 game framework designed for web browsers, focused on fast 2D games, and expects development through a local web server rather than `file://` loading.
2. `jd-dev-studios/phaser-pacman` shows a Phaser 3 + JavaScript Pac-Man clone with classic mechanics such as ghost AI, power pellets, frightened states, warp tunnels, localStorage high score persistence, and browser controls.
3. `platzhersh/pacman-canvas` is an older HTML5 rewrite that runs locally with `npm start` and keeps most game customization in a single JavaScript file plus CSS/HTML.
4. `zukentag/Pacman` demonstrates a pure JavaScript + HTML canvas Pac-Man clone with collision detection, score updates, game end conditions, and simple/random ghost movement.

## What We Want From The Designers

### Frontend

- Recommended rendering approach
- Screen structure
- Game loop and scene structure
- Control model
- Asset strategy
- UI/UX simplifications suitable for a small pilot

### Backend / Serving

- Is a backend actually needed?
- Smallest sensible serving architecture
- Dev vs local preview flow
- What should remain out of scope
- How to keep the implementation simple while still "web-runnable"

### Final Synthesis

- Choose one recommended architecture
- Explain why it is the best fit for this delegation test
- Produce a concise implementation-oriented design outline

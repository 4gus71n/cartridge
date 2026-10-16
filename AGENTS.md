# Cartridge — agent checkpoint

Cold-start file for any agent session. Read this first, then `roadmap.md`
(product/engineering decisions), `games/BACKLOG.md` (game ideas) and
`games/AGENTS.md` (rules for building a game).

## Repo map
- `composeApp/` — KMP + Compose Multiplatform app (Android working; iOS = M6).
- `backend/` — FastAPI + SQLite (`backend/cartridge.db`, git-ignored).
  Run: `cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8123`
  (the app tries 127.0.0.1 / LAN IP / `agustins-macbook-pro.local` / 10.0.2.2 on :8123).
- `games/<slug>/` — our own games (Godot 4.7.2, web no-threads export).
  `games/AGENTS.md` = build rules + verification loop for each game.
- `tools/publish_game.py <slug> [--push]` — test gate → web export (Godot, or
  `tools/build.sh`/`web/` for plain HTML games) → copy to `~/cartridge-games/<slug>/`
  (+ `poster.png` → `thumbnail_url`) → deterministic zip in `packages/` →
  upsert `index.json`. Then `backend/.venv/bin/python backend/scripts/import_hosted.py`
  loads it into the DB.
- `tools/web_smoke.py <export_dir> <out_dir> [steps.json]` — headless Chromium at
  phone size, runs `games/<slug>/smoke.json` tap script, screenshots, fails on JS errors.
- `tools/open_game.sh <Title> [serial]` — on the Android emulator/phone: relaunch
  the app, scroll the feed to `<Title>`, tap Play.
- Hosting: `~/cartridge-games` = public repo `4gus71n/cartridge-games` on GitHub
  Pages (`https://4gus71n.github.io/cartridge-games/`).
- Git: `4gus71n/cartridge` (private), commit on `main`, repo-local email
  agustin.tomas.larghi@gmail.com.

## Current state (2026-10-16)
- Catalog (DB `status=verified`): 2048, Black Hole Square, Neon Flap, Dot Dodge,
  Tap Rush (local packages) + **Minefield** (GitHub Pages).
- **Minefield v1** published and now **verified in the app on the Android
  emulator** (feed → download from Pages → plays) after two fixes made this session:
  1. backend `game_to_out` rewrote *every* package_url to the local
     `/static/packages/` → hosted games 404'd. Now only local packages are rewritten.
  2. app `GameStorage.packageUrlCandidates` only retries other API base URLs for
     packages on our own hosts, and reports the first (canonical) error.
- **Minefield v2 (not yet published)**: no-guess board generation is now
  time-budgeted (~12 ms/frame) — on the emulator WebView the old loop froze
  the UI ~8 s with no "Generating…" label. Gate GREEN (140 checks), web smoke OK.
  `cartridge.json` already bumped to version 2.
- `tools/web_smoke.py` generalized (per-game `smoke.json`); `publish_game.py`
  supports posters + non-Godot games; `games/AGENTS.md` written as the brief for
  parallel game-building subagents.

## Paused 2026-10-16 (owner asked to pause)
- Done after the first checkpoint: **Minefield v2 published** (Pages + DB) and
  the app **auto-updated it on the emulator** (new per-game `.<slug>.sha256`
  marker in `files/games/`; a changed catalog sha triggers a re-download, the
  old copy is kept if offline). **App shows `thumbnail_url` posters** in the
  feed via Coil 3 (`coil-compose` + `coil-network-ktor3` 3.0.4), falling back
  to `PosterArt`. Builds; poster path not yet seen on device (no game has a
  poster.png yet).
- The parallel game build (9 subagents, step 3 below) was dispatched but
  **8 of 9 died instantly: Anthropic API credits exhausted** ("credit balance
  is too low"); the 9th (babel-ear) was stopped on pause. **No game folders
  were created** — step 3 must be re-run from scratch once billing is OK.
- Backend may not be running after a restart (start command above).

## Resumed 2026-10-16 (billing fixed)
All 9 game subagents re-dispatched in 3 units: {sudoku, trajectory, block-drop,
right-of-way}, {crossword, colossal-cave, roguelike}, {babel-ear, pinpoint}.
If a session restarts mid-build: check `games/<slug>/` for partial work; a
finished game has README.md + poster.png + a GREEN `tools/run_tests.sh`.

## Blocked again 2026-10-16 12:21 — API credits exhausted ~10 min into the run
All 9 subagents died at the same moment (credit balance too low). Partial work
committed as WIP (no game is finished; none has README/poster/GREEN gate yet):
| folder | game | state at stop |
|---|---|---|
| `sudoku` | Sudoku | early (14 files, no tests) |
| `trajectory` | Trajectory | most advanced: 8 test suites |
| `pentaprism` | block-drop (agent named it Pentaprism) | 8 test suites, exported once |
| `right-of-way` | Right of Way | early |
| `crossword` | Mini Crossword | word lists + filler (`tools/fill.py`) only |
| `colossal-cave` | Colossal Cave | Open Adventure vendored (`vendor/open-adventure`, BSD-2), web shim/patch, first wasm build in export/ |
| `delve` | roguelike (agent named it Delve) | early |
| `babel-ear` | Babel Ear | LibriVox survey: ~25 languages with ≥2 PD audiobooks |
| `pinpoint` | Pinpoint | fetch script; Wikimedia API 429s → needs policy User-Agent, sequential, maxlag, Retry-After, resumable cache |

## Resumed 2026-10-16 (credits bought; `hermes auth reset anthropic` cleared the
exhausted cooldown). Wave A running: trajectory, pentaprism, colossal-cave.
Wave B next: sudoku, right-of-way, crossword. Wave C: delve, babel-ear, pinpoint.

## Next steps (in order)
1. When credits are back: re-dispatch each game pointing at its partial folder
   ("continue from the existing files; read them first"). Run at most 3–4 at a
   time — 9 in parallel burned the quota in ~10 minutes.
2. For each finished game, step 4.
3. **Build all remaining games** — one subagent per game in parallel, each told
   to read `games/AGENTS.md` first, never commit (coordinator commits per game),
   never publish. Assignments / decisions already made:
   | slug | title (EN/ES) | engine | key decisions |
   |---|---|---|---|
   | `sudoku` | Sudoku / Sudoku | Godot | generator + unique-solution solver + technique-based grading, pencil marks, undo, daily puzzle |
   | `trajectory` | Trajectory / Trayectoria | Godot | rocket follows y=p(x); coefficient steppers/keypad, own expression parser, ~30 levels constants→cubic |
   | `block-drop` (agent picks final name) | — | Godot | must NOT look/feel like Tetris; needs a mechanical twist (pentominoes / hex / colour-match) |
   | `babel-ear` | Babel Ear / Oído de Babel | Godot | language-guess from audio; content from public-domain sources (LibriVox PD recordings) or CC0 (Common Voice needs an account → ask user); no CC-BY-SA/NC; skip country step unless reliable |
   | `crossword` | Mini Crossword / Minicrucigrama | Godot | 5×5/7×7 minis, EN + ES, our own clues |
   | `pinpoint` | Pinpoint / Pinpoint | Godot | Wikimedia Commons CC0/PD/CC-BY-4.0 geotagged photos (credits screen), Natural Earth (PD) map, 5 rounds |
   | `colossal-cave` | Colossal Cave | plain HTML/JS | Open Adventure (BSD-2) compiled to wasm with emscripten (`brew install emscripten`), touch verb/direction buttons + soft keyboard; fallback: own short adventure in JS |
   | `roguelike` (agent picks name) | — | Godot | own NetHack-style touch roguelike (NetHack/Brogue/DCSS are copyleft → no code); may reuse know-how from ~/shattered-cyberpunk |
   | `right-of-way` | Right of Way / Prioridad | Godot | traffic sign → pick action from 3–4 choices before ~4 s timer; signs drawn in code, Vienna-convention style; ~40 signs; 3 lives, streak |
4. For each finished game: review screenshots, run its gate + smoke, commit,
   `publish_game.py <slug> --push`, `import_hosted.py`, verify on emulator with
   `tools/open_game.sh "<Title>"`, update this checkpoint + `roadmap.md` status line.

## Pitfalls learned
- Emulator WebView wasm is slow: time-budget any heavy work per frame.
- The "Viewing full screen" Android system dialog covers the top of the first
  game launch; dismiss with "Got it" (≈ 1234,806 on the 1440×3120 emulator).
- Feed order isn't stable between launches; `open_game.sh` scrolls both ways.
- A stray backend can already be bound to :8123 (`lsof -iTCP:8123 -sTCP:LISTEN`).

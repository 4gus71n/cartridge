# Cartridge — agent checkpoint

Cold-start file for any agent session. Read this first, then `roadmap.md`
(product/engineering decisions), `games/BACKLOG.md` (game ideas) and
`games/AGENTS.md` (rules for building a game).

## Repo map
- `composeApp/` — KMP + Compose Multiplatform app (Android working; iOS = M6).
- `backend/` — FastAPI + SQLite (`backend/cartridge.db`, git-ignored). **Public run: `tools/run_server.sh`**
  (API on :8123 plus a free Cloudflare quick tunnel; it writes the tunnel URL to Pages `config.json`,
  which the app reads on start).
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

## Code navigation
- CodeGraph index in `.codegraph/` (git-ignored, auto-syncs). Use the
  `codegraph_explore` MCP tool first for Kotlin (`composeApp/`) and Python
  (`backend/`, `tools/`) questions. GDScript isn't indexed (unsupported
  language), so for `games/*` read files directly.

## Current state (2026-10-18) — all 10 originals live
Catalog (`status=verified`): 2048, Black Hole Square, Neon Flap, Dot Dodge, Tap Rush
(local packages) + 10 Cartridge originals on GitHub Pages, each verified in the
Android app on the emulator (feed poster renders, game boots, real play works):

| slug | game | engine | notes |
|---|---|---|---|
| `minefield` | Minefield (v2) | Godot | no-guess minesweeper |
| `trajectory` | Trajectory | Godot | 30 levels, rocket follows y=p(x) |
| `pentaprism` | Pentaprism | Godot | pentomino gem-drop, colour + row clears (not Tetris-like) |
| `colossal-cave` | Colossal Cave | HTML/JS + wasm | Open Adventure 1.22 (BSD-2), touch shell |
| `right-of-way` | Right of Way | Godot | 58 code-drawn Vienna-convention signs |
| `sudoku` | Sudoku | Godot | 900 graded unique puzzles, daily |
| `crossword` | Mini Crossword | Godot | 43 EN + 42 ES original minis |
| `delve` | Delve | Godot | roguelike, 12 floors, 17 monsters |
| `pinpoint` | Pinpoint | Godot | 194 CC0/PD/CC-BY Wikimedia photos, 24 MB package |
| `babel-ear` | Babel Ear | Godot | 23 languages, 225 LibriVox PD clips |

Each game's README lists features, tests and open review points. Common gaps:
no sound effects (except Babel Ear audio), no tablet screenshots.

Pipeline notes:
- **The feed comes from Pages `catalog.json`** (written and pushed by `backend/app/catalog.py`; the
  backend re-syncs originals from `index.json` every 10 min, or on `POST /admin/catalog/sync`).
  So `import_hosted.py` is no longer needed. The app works with the backend off; the API only
  adds live likes/comments. Installed games with a changed sha update in the background.
- Plan for hosting + the creator portal: `docs/plans/portal-and-hosting.md` (Phase 2 runs on
  branch `portal/v2` in worktree `~/cartridge-wt/portal`).
- App shows `thumbnail_url` posters (Coil 3, `ContentScale.Crop` → keep key art
  in the central ~80 % width) and re-downloads a game when its catalog sha changes.
- Backend `config.py` resolves sqlite paths against `backend/` (cwd-independent).
- `tools/open_game.sh` scan length follows the catalog size.
- Agent capacity: Hermes uses the personal subscription OAuth `anthropic-oauth-3`
  (priority 0; `hermes auth priority anthropic anthropic-oauth-3 0` after any
  refresh). It rate-limits (429, multi-hour lockouts) with >2 parallel builders.

## Next steps / ideas
- Babel Ear: re-run `tools/verify_lang.py` + `curate.py build` to restore Arabic,
  Tagalog, Hindi, Esperanto (cut but failed QA in the last run).
- Sound effects pass across games; tablet layout screenshots.
- Shared Godot engine `.wasm` across cartridges (each game re-downloads ~9 MB).
- iOS runtime (M6), SQLDelight local state (see `roadmap.md`).

## Pitfalls learned
- Emulator WebView wasm is slow: time-budget any heavy work per frame.
- The "Viewing full screen" Android system dialog covers the top of the first
  game launch; dismiss with "Got it" (≈ 1234,806 on the 1440×3120 emulator).
- Feed order isn't stable between launches; `open_game.sh` scrolls both ways.
- A stray backend can already be bound to :8123 (`lsof -iTCP:8123 -sTCP:LISTEN`).

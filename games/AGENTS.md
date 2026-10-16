# Building a Cartridge original — rules for every game

Read this whole file before writing code. `games/minefield/` is the reference
implementation: copy its structure (`project.godot`, `export_presets.cfg`,
`scripts/settings.gd`, `i18n/strings.csv`, `tools/run_tests.sh`,
`tests/*_check.gd`, `.gitignore`, `cartridge.json`, `smoke.json`) and adapt.

## What Cartridge is
A TikTok-style vertical feed of playable web games (Android/iOS app, each game
runs full-screen inside a WebView). Players open a game from the feed, play for
a minute or an hour, close it with the app's ✕ button. Games are downloaded as
a zip and must work **fully offline**.

## Hard requirements
- **Godot 4.7.2** (`godot` on PATH), **Compatibility renderer**, **Web export
  with thread support OFF** (`variant/thread_support=false`). Copy
  `games/minefield/export_presets.cfg` (keep `exclude_filter="tests/*, tools/*"`).
  Exception: games explicitly assigned as plain HTML/JS (see below).
- **Touch-first.** Every action must be possible with taps/swipes/long-press on
  a phone. No keyboard required, no hover, no right-click-only actions.
  Mouse must still work (desktop browser testing). Big hit targets (≥ 88 px at
  the 720×1280 base viewport).
- **Portrait 720×1280 base viewport**, `stretch/mode="canvas_items"`,
  `aspect="expand"` (copy minefield's `[display]` block). Lay out with anchors /
  containers so 9:16 → 9:21 phones and tablets all look right. Landscape only
  if the game truly needs it (then set `orientation` in cartridge.json).
- **Offline**: no network calls at runtime, all content bundled.
- **No threads, and the WebView CPU is slow** (Minefield's board generator
  froze the UI ~8 s on the Android emulator). Any search/generation must be
  time-budgeted across frames (do ~10 ms of work, `await
  get_tree().process_frame`, repeat) and show a "Generating…" label that
  actually paints (await one frame after setting it). Prefer precomputed
  content where that's cheaper.
- **Bilingual EN + ES** via `i18n/strings.csv` (keys, `en`, `es` columns) and
  the `Settings` autoload (language toggle in the menu, defaults to the device
  locale; persist settings/records in `user://` with `ConfigFile`).
- **Persistence**: best scores/times/progress in `user://` (IndexedDB on web).
  Resume an in-progress game where it makes sense (puzzles, roguelike).
- **Licensing** (see `../roadmap.md` §3): all code original. Content/assets must
  be original, CC0/public domain, or permissive (MIT/BSD/Apache/CC-BY-4.0 with
  credit). **No GPL/LGPL/AGPL, no CC-BY-SA, no NC, no "free for personal use",
  no ripped assets, no trademarked names** (Tetris, GeoGuessr, NetHack, Zork,
  Wordle…). If you bundle third-party content, add `CREDITS.md` in the game
  folder listing every source + license + URL, and show credits in-game
  (a "Credits" button). Fonts: Godot's default font is fine.
- **Package size**: engine is ~9–10 MB; keep game content ≤ ~15 MB.
- **Look**: polished, modern, dark UI consistent with Minefield (rounded panels,
  one accent colour per game, readable 26–32 px text, subtle tweens on
  important events). No placeholder programmer art in the final build.

## Required files in `games/<slug>/`
- `cartridge.json`: `slug, version (1), title, title_es, description,
  description_es (one short line each), author ("Cartridge Studio"), license
  ("All rights reserved" for our own code; mention bundled content licenses in
  CREDITS.md), orientation ("portrait"|"landscape"), tags [..], poster_style
  ("TAP" — the app shows poster.png instead), accent_top, accent_bottom
  (two hex colours for the reel gradient)`.
- `poster.png`: **720×1280 portrait** poster for the feed reel — a staged,
  attractive in-game screen (mid-game state, not the menu) captured from the
  web build (or a hermetic capture script); the app overlays the title at the
  bottom and a play button in the centre, so keep the important art in the
  upper-middle area. Must be a real screenshot of the game, not generated art.
- `README.md`: one-paragraph pitch, controls, rules/scoring, content sources,
  code map, how to test, known limitations / ideas for v2.
- `tools/run_tests.sh`: the gate (copy minefield's; RED on non-zero exit or
  `SCRIPT ERROR`). Must print GREEN.
- `tests/*_check.gd`: hermetic headless suites (`extends SceneTree`, run with
  `godot --headless --path . --script tests/x_check.gd`) covering the game
  logic: rules, generators/solvers, scoring, save/load, edge cases. Keep logic
  in plain classes (`class_name`, no scene dependency) so it's testable.
- `smoke.json`: tap script for `tools/web_smoke.py` (see its docstring) that
  boots the build, opens a game, plays a few moves and screenshots each step.

## Verification loop (all must pass before you report done)
1. `games/<slug>/tools/run_tests.sh` → GREEN.
2. Export: `cd games/<slug> && godot --headless --path . --import && godot
   --headless --path . --export-release "Web" export/web/index.html`
   (create `export/web/` first). Export must produce `index.wasm`/`index.pck`.
3. Browser smoke test at phone size:
   `~/cartridge/backend/.venv/bin/python ~/cartridge/tools/web_smoke.py
   games/<slug>/export/web $TMPDIR/<slug>-smoke` → exit 0, "errors: none".
4. **Look at every screenshot yourself** (vision) and fix layout, readability,
   overflow, clipping and ugliness. Iterate 2–3 times. Check both EN and ES
   (`"locale": "es-ES"` in a second smoke json) for text overflow.
5. Play a full game through the smoke script or a headless bot test (win and
   lose paths) so the end-of-game screen is verified too.

## Do NOT
- Do not run `git add/commit/push` or any git command that writes — several
  games are being built in parallel in this same repo; the coordinator commits.
- Do not run `tools/publish_game.py` or touch `~/cartridge-games`,
  `backend/`, `composeApp/` or another game's folder. Do not use adb/emulators.
- Do not edit `tools/web_smoke.py`; if you need extra smoke features, write a
  game-local script under `games/<slug>/tools/`.
- Use your own scratch dir under `$TMPDIR` (never `/tmp` shared names: other
  agents run concurrently). Kill any Godot/Chromium process you start.

## Plain HTML/JS games (only when assigned)
Same rules, but: put sources in `games/<slug>/web/` (entry `index.html`,
relative paths, no CDN — vendor everything), add `tools/build.sh` that fills
`games/<slug>/export/web/` (compiles if needed), and make `tools/run_tests.sh`
run the game's tests (node is on PATH). `web_smoke.py` works the same.

## Final report (your last message)
Slug, title EN/ES, what was built (features), test count + gate result, export
size, smoke result, screenshot paths you verified, content sources + licenses,
anything unfinished or any decision the product owner should review.

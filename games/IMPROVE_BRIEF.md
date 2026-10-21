# Game improvement round (2026-10-19): brief for every worker

Read `games/AGENTS.md` first (all of it still applies), then this file.

## Persistence: use the app bridge (overrides AGENTS.md "Persistence")
Inside the Cartridge app, `window.cartridge.storage` (getItem/setItem/removeItem/keys,
backed by Android SharedPreferences / iOS NSUserDefaults) survives force-stops and
WebView resets. IndexedDB / user:// alone did NOT survive reliably: players lost
all progress.
- **Godot:** never call `ConfigFile.load/save` on user:// directly. Use
  `CartridgeStore.load_cfg(cfg, path)`, `CartridgeStore.save_cfg(cfg, path)`,
  `CartridgeStore.exists(path)` and `CartridgeStore.remove(path)` (`scripts/cartridge_store.gd`). That file is a COPY of
  `games/_shared/cartridge_store.gd`: don't edit it. Outside the app it falls back
  to user:// files, so headless tests behave as before. `scripts/settings.gd` in
  every game already uses it; any NEW save file you add must use it too.
- **HTML/JS:** plain `localStorage` is mirrored into the bridge automatically. You
  may also use `window.cartridge.storage` directly (check that `window.cartridge` exists first).
- Save after each meaningful action (move, solved clue, piece locked, room
  entered), not only on exit: players kill the app without warning. Resume an
  in-progress game on the next launch where it makes sense.
- Old saves must keep loading. If you change a save format, version it and
  migrate (or discard safely); never crash on an old or corrupt save.

## Process
- Work ONLY in your game folder. No git writes, no `tools/publish_game.py`, no
  adb/emulator, no edits to `backend/`, `composeApp/`, `~/cartridge-games` or other games
  (`games/AGENTS.md` "Do NOT" applies).
- Be economical: this runs on a rate-limited subscription. Batch shell commands,
  keep outputs short, and take a few targeted screenshots rather than many.
- Expensive fetched or generated content (word lists, photo metadata, crawls) lives
  in the game folder under `tools/content/` and fetch scripts are resumable, so a
  restarted worker doesn't refetch.
- Keep `cartridge.json` metadata; bump `"version"` by 1.
- Gate GREEN, web export, `tools/web_smoke.py` smoke (EN + ES) with "errors: none",
  look at the screenshots, refresh `poster.png` if the look changed, update README.
- Final report: what changed (with numbers), tests + gate result, export size,
  smoke result, screenshot paths, content sources and licences, open questions.

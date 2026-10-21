# Colossal Cave (La Cueva Colosal)

The grandfather of every adventure game, playable on a phone. Crowther & Woods'
*Colossal Cave Adventure* (1977/1995, version 2.5 with 430 points) runs as the
real original engine — Eric S. Raymond's Open Adventure C port compiled to
WebAssembly — inside a mobile-first dark terminal: explore the cave beneath
the well house, collect treasures, dodge dwarves and the pirate, and talk to
the game in two-word commands — by typing or with big tap buttons.

## Controls
- **Type** any command in the input row (`enter building`, `take lamp`, `xyzzy`) and press Send / Enter.
- **Compass pad**: NW N NE / W LOOK E / SW S SE, plus UP, DOWN, IN — one tap moves.
- **Verbs**: INVENTORY, LIGHT, OFF send at once; TAKE, DROP, OPEN (and CLOSE,
  UNLOCK, READ, FILL, POUR, DRINK, EAT, WAVE, THROW, ATTACK, FEED, FIND in the
  scrolling chip row) *arm* the input — then tap a word in the story
  (e.g. "lamp") and the command is sent. Tapping the armed verb again sends it alone.
- **Tap any word** in the transcript to append it to the input; tap an old
  command to reuse it. When the game asks a question, big YES / NO chips appear.
- **History** button (↑, left of the input) lists recent commands; desktop ↑/↓ keys cycle them.
- **Map** (▣, in the header): the cave maps itself as you walk. A thumbnail in
  the corner shows where you are; tap it (or Menu → Map) for the full map with
  room names. The header button folds the thumbnail away when you want the whole
  screen for text. Dashed links are moves with no compass direction (xyzzy,
  plugh, falls).
- **Menu** (☰): New game (with confirm), language EN/ES, text size (16/17/18 px), Credits & license.
- The input row stays above the soft keyboard (visualViewport); the button pad
  hides while the keyboard is open.

## The map
Colossal Cave never had one — players drew theirs on paper. This build does it
for you, and only from where you have actually been: after every turn the shell
reads the player's location out of the engine's own save file (`game.loc`, at a
fixed offset in Open Adventure's `save_t`) and adds the room plus the link you
just used. Compass moves place rooms one step that way; up and down also change
depth; anything else (magic words, falls) still links the rooms but is drawn
dashed. Rooms never share a cell: collisions spiral outward. Labels come from
the dungeon's own `maptag`/short descriptions via `tools/build_mapdata.py`.
The map is stored with the save, so it survives closing the app, and a new game
clears it.

## Rules / scoring
Unchanged from the original: up to 430 points for exploring, treasures
deposited in the well house, and surviving to the endgame; the end screen
gives your score and rank. Death offers reincarnation (up to 3 times).

## Code map additions
- `web/cavemap.js` — `CaveMap`: the map graph (rooms, links, grid layout,
  save/restore) and `locFromSave`. Pure logic, no DOM; `tests/map.test.js`
  drives it and a real wasm playthrough.
- `web/mapdata.js` — generated room labels (`tools/build_mapdata.py`, re-run it
  after updating the vendored engine).
- Drawing and the map UI live in `web/shell.js` (`drawMap`, `refreshMap`).

## Persistence
After every command the engine writes its native save file (`ADVENT_AUTOSAVE`)
and the shell stores it in localStorage (base64) with the transcript and
command history. Reopening resumes exactly where you were (the engine prints
your score and the current location). When a game ends the save is deleted
and the end card ("Play again") is shown, also after reopening.
Manual SAVE/RESUME commands are disabled by the engine in this mode.

## Spanish
The game text stays in English (it is the 1977 original and its parser only
understands English). The whole shell UI is translated, Spanish players get a
note at the start of each game and in the menu, and command buttons show a
Spanish gloss under the English word (TAKE / *coger*).

## Content sources
See `CREDITS.md`. Open Adventure, BSD-2-Clause, pinned commit
`e6160529e70a8c7a06b9a5f190d69aa35c4c62f5` (1.22); Emscripten runtime MIT/NCSA.
License texts ship in `web/LICENSE` and `web/LICENSE.emscripten` and are shown in-game.

## Code map
- `vendor/open-adventure/` — upstream C source + regression logs (see `vendor/README.md`).
- `engine/web.patch` — autosave hook before each command; `engine/web_shim.c` —
  Asyncify `readline()` that awaits `Module.readLine()` from JS; `engine/include/` — readline header stub.
- `web/advent.js`, `web/advent.wasm` — committed build output (≈270 KB).
- `web/engine.js` — `CaveSession`: boots the wasm, queues input lines, `idle()`
  promise, save bytes in/out. Shared by the browser and node tests.
- `web/cavetext.js` — pure helpers: reflow of 70-column text, word-at-offset, base64, transcript trimming.
- `web/shell.js`, `web/shell.css`, `web/index.html` — the UI (pad, chips, tap-a-word,
  history, menu, credits, i18n, localStorage, visualViewport).
- `tools/build.sh` — compiles with emcc if present (PyYAML via a scratch venv
  for `make_dungeon.py`), otherwise reuses the committed wasm; then copies `web/` to `export/web/`.
  The build is byte-reproducible (`--no-emcc` to skip compiling).
- `tools/run_tests.sh` — the gate (prints GREEN/RED).
- `tools/shots.py` — browser walkthrough with assertions + screenshots (EN or `es`).
- `tools/poster.py` — captures `poster.png` from the real build.
- `smoke.json` / `smoke_es.json` — tap scripts for `tools/web_smoke.py`.

## How to test
```
tools/build.sh                     # or tools/build.sh --no-emcc
tools/run_tests.sh                 # node: engine, save/restore, helpers, 92 upstream regressions
~/cartridge/backend/.venv/bin/python ~/cartridge/tools/web_smoke.py games/colossal-cave/export/web $TMPDIR/cave-smoke
~/cartridge/backend/.venv/bin/python tools/shots.py export/web $TMPDIR/cave-shots [es]
~/cartridge/backend/.venv/bin/python tools/poster.py export/web poster.png
```

## Known limitations / ideas for v2
- Game text is English only (a translated dungeon would need a Spanish parser too).
- Tap-a-word sends the word as typed; the parser only reads the first 5
  letters, so most words work, but descriptive words (e.g. "shiny") are not objects.
- Autosave happens at each main command prompt, not inside yes/no questions.
- Ideas: auto-map of visited rooms, treasure checklist, hint button wired to the built-in hints.

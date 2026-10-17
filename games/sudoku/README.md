# Sudoku

Classic 9×9 sudoku, built for a quick tap-and-think session. Every bundled
puzzle has exactly one solution and is graded by the techniques a human needs
to crack it, so *Easy* really is easy and *Hard* really needs triples or
X-wings. A date-seeded **Daily puzzle** is the same for everyone and builds a
streak. Dark UI with a warm amber accent.

## Controls (touch first)
| Action | How |
|---|---|
| Select a cell | tap it (row, column, box and every equal digit light up) |
| Enter a digit | tap a number on the pad; tapping the same digit again clears it |
| Pencil marks | **Notes** toggles notes mode, then numbers toggle marks |
| Erase | **Erase** clears the digit (or the marks) of the selected cell |
| Undo | **Undo** — unlimited, multi-level (entries, marks, erases, hints) |
| Hint | **Hint** reveals the selected cell (or the easiest open cell); counted |
| Mistake check | **Check** toggles red highlighting of wrong digits |
| Back | ‹ saves and returns to the menu (**Continue** resumes) |

The number pad shows how many of each digit are still missing; finished
digits grey out. Placing a digit removes it from the pencil marks of its
peers; completed rows/columns/boxes flash.

## Rules & scoring
- Standard sudoku: fill every row, column and 3×3 box with 1–9.
- The puzzle is won when the grid equals its (unique) solution. A full grid
  with an error shows "Board full, but some digits are wrong".
- Timer runs while the board is open; best time per difficulty is kept.
  Mistakes (wrong digits entered) and hints are counted and shown on the win
  screen, but don't block a record.
- Daily puzzle: Medium, seeded from the calendar day. Solving consecutive
  dailies grows the streak; missing a day resets it. Once solved, the daily
  button is locked until tomorrow.
- Progress (current game incl. undo stack, notes, timer), records, streak,
  language and the mistake-check toggle persist in `user://settings.cfg`
  (IndexedDB on web). The game is saved after every move and every 5 s.

## Content sources
All code and content are original. Puzzles were generated offline by
`tools/gen_pool.gd` (our own generator/solver/grader, seed 20261017): 300
rotationally-symmetric puzzles per level, verified unique and graded. At play
time a random sudoku isomorphism (digit relabel, band/stack/row/column
permutations, transpose) disguises them, so each pick looks new. Godot's
default font. No third-party assets, so no CREDITS.md.

Grades (`SudokuGrader`): **Easy** = naked/hidden singles only (~36 clues);
**Medium** = + naked/hidden pairs, pointing, claiming (~30 clues);
**Hard** = needs naked/hidden triples, X-wing, swordfish or XY-wing (~28
clues). Puzzles needing more than that are discarded.

## Code map
- `scripts/sudoku_grid.gd` — `SudokuGrid`: geometry tables (units, peers), parse/stringify, validity.
- `scripts/sudoku_solver.gd` — `SudokuSolver`: bitmask backtracking; solution counting (uniqueness), random completion.
- `scripts/sudoku_grader.gd` — `SudokuGrader`: human-technique solver that grades puzzles.
- `scripts/sudoku_generator.gd` — `SudokuGenerator`: symmetric puzzle generator, clue top-up, isomorphic transforms.
- `scripts/puzzle_pool.gd` — `PuzzlePool`: GENERATED bundled pool (do not edit).
- `scripts/sudoku_game.gd` — `SudokuGame`: one session (entries, notes, undo, hints, timer, win, to/from dict, daily seed).
- `scripts/settings.gd` — `Settings` autoload: language, toggles, best times, streak, saved game.
- `scripts/main.gd` — menu, game screen, win overlay; `board_view.gd` (board drawing + taps), `pad_key.gd` (pad/tool keys), `menu_art.gd`.
- `tools/gen_pool.gd` — regenerates the pool: `godot --headless --path . --script tools/gen_pool.gd -- 300 20261017`.
- `tools/poster.gd` — poster capture (needs a display): `godot --path . --script tools/poster.gd -- poster.png`.

## Testing
- `tools/run_tests.sh` → GREEN. Suites in `tests/`:
  `solver_check` (solver, uniqueness, transforms, generator), `pool_check`
  (all 900 bundled puzzles unique + graded at their level), `grader_check`
  (tiers, technique usage, AI Escargot rejected), `game_check` (entry, pencil
  marks, multi-level undo, hints, win/full-but-wrong, save/load, records,
  daily + streak), `ui_check` (bot plays through the real scene: menu EN/ES,
  notes, undo, hint, check toggle, resume, full solve to the win screen, daily).
- Web: export `Web` preset, then `web_smoke.py games/sudoku/export/web <out>`
  with `smoke.json` (EN) / `smoke_es.json` (ES).

## Known limitations / v2 ideas
- No Expert tier (chains/fish beyond swordfish); the grader could add them.
- The daily puzzle uses the device's local date, so it can be gamed by
  changing the clock; streaks are local only.
- Auto-notes (fill all candidates) exists in `SudokuGame.auto_notes()` but is
  not exposed in the UI (kept the toolbar to five keys).
- No pause screen; the timer keeps running while the game screen is open.

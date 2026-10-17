# Mini Crossword / Minicrucigrama

Bite-size crosswords for the Cartridge feed: 43 English and 42 Spanish
original minis (mostly 5×5, six 7×7 per language), a daily puzzle, and a
custom on-screen keyboard, so the phone's soft keyboard never pops up. The
pack follows the language setting. Every grid and clue was made by Cartridge
Studio for this game.

## Controls
- **Tap a square** to select it. **Tap it again** to switch Across ↔ Down.
- **Clue bar** under the grid: ‹ / › jump to the previous / next clue
  (skipping filled clues). Tapping the clue text also switches direction.
- **Keyboard**: QWERTY (plus **Ñ** in Spanish) and backspace. Typing
  auto-advances to the next empty square, then on to the next clue.
  Backspace clears the square, or steps back when it is already empty.
- **Bulb button**: check letter / check word (wrong letters get a red slash)
  or reveal letter / reveal word (blue corner, locked).

## Rules and scoring
Fill every square so each row and column spells the answer to its clue. The
timer runs while the puzzle is open. Checks and reveals are counted. A solve
with no reveals records a **best time**. A solve with reveals still gets a
checkmark but no time. A full but wrong grid shows "Not quite". Solving plays a
green wave across the grid and opens the result card (time, best, counters,
Next puzzle).

**Daily puzzle**: `(day * 17 + 5) % pack_size` on the local calendar day, so
the daily pick goes through the whole pack before it repeats. **Progress**
(letters, marks, cursor, time, counters) is saved per puzzle in `user://`
(IndexedDB on the web), 1.2 s after the last edit and on leaving. The menu
offers **Continue**. The list shows checkmarks, best times and puzzles in
progress.

**Spanish**: accents are ignored in the grid (CAMIÓN → CAMION) and Ñ is its
own letter. The how-to explains this.

## Content
- `tools/content/words_<lang>.txt`: our own fill word lists (common,
  family-friendly words). `ban_<lang>.txt` lists words we never want.
- `tools/fill.py`: an offline filler. It builds a pool of fills for symmetric
  templates (`--pool`) and then picks a varied set (`--select`) into
  `fills_<lang>.json`.
- `tools/content/clues_<lang>.txt`: hand-written clues, one per answer.
- `tools/build_packs.py`: merges fills and clues into the shipped
  `data/puzzles_<lang>.json`. It fails on a missing clue, a clue that contains
  its answer, or a duplicate answer.

No third-party content is bundled. The font is Godot's default.

## Code map
- `scripts/puzzle.gd`: `Puzzle`: grid, standard numbering, entries and clues.
- `scripts/board.gd`: `Board`: play state: select/toggle, auto-advance,
  backspace, clue navigation, check/reveal, solved, save/load dict.
- `scripts/pack.gd`: `Pack`: loads packs, daily index, time format.
- `scripts/settings.gd`: autoload: language, best times, in-progress boards.
- `scripts/grid_view.gd`: draws the grid and handles cell taps (also the
  menu logo).
- `scripts/icon_button.gd`: vector glyph buttons (back, arrows, backspace,
  bulb, check).
- `scripts/main.gd`: all screens: menu, list, play screen, assist sheet,
  how-to, completion card.

## Testing
- `tools/run_tests.sh` is the gate. It runs:
  - `tests/data_check.gd`: every pack: counts and sizes, letters, crossings,
    clues, duplicates, daily cycle.
  - `tests/board_check.gd`: cursor and direction logic, auto-advance,
    backspace, navigation, check/reveal, completion, save/load, records.
  - `tests/ui_check.gd`: a UI bot that plays the real scene: it solves the
    daily puzzle on the keyboard, then covers the list checkmarks, resume from
    disk, the assist sheet, an assisted solve, the how-to and the ES keyboard
    with Ñ.
- `godot --path . --script tools/capture.gd -- <dir> [en|es] [height] [poster]`
  takes screenshots of every screen. `poster` writes `poster.png`.
- `smoke.json` / `smoke_es.json`: browser smoke tests that solve puzzle 1
  with taps on the custom keyboard.

## Limitations / v2 ideas
- Keyboard keys are 98 px tall but only about 62 px wide (10 per row on a
  720 px screen).
- One clue per answer word. An answer used in several puzzles gets the same
  clue each time.
- Ideas: a streak counter for daily puzzles, a pencil mode, a "clear
  puzzle" button, and more 7×7 grids.

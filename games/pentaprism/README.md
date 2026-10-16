# Pentaprism

A falling-gem puzzle with its own rules: two-colour **pentominoes** (plus a few
single-colour trominoes — never tetrominoes) drop into a 9×16 well of faceted
gems. When a piece lands, every gem falls straight down on its own, then any
**4+ touching gems of one colour** shatter, and so does any completely filled
row (a *prism line*). Gems above fall into the gaps and can set off more clears:
chain reactions multiply the points. Distinct look on purpose (dark well with a
dot lattice, octagonal gems with per-colour glyphs, purple accent) — it is not a
line-clear tetromino game.

## Controls (touch first)
| Gesture | Action |
|---|---|
| Drag sideways | move one column per ~cell dragged |
| Tap the well | rotate clockwise |
| Swipe down (≥ 1 cell) | hard drop (ghost lights up while armed) |
| Swipe up (≥ 1 cell) | hold / swap with the hold slot |
| Tap HOLD panel | hold |
| ⏸ button | pause (Resume / Restart / Menu) |

Keyboard (desktop): ←/→ or A/D move, ↑/W/X rotate, Z rotate CCW, ↓/S soft
drop, Space hard drop, C/Shift hold, Esc/P pause. Gestures are classified by
distance on release, not speed, because slow WebViews deliver touch events in
bursts.

## Rules & scoring
- Ghost piece, 3-piece next preview, hold (once per piece), 0.5 s lock delay
  with up to 15 resets, small wall kicks.
- Clear step: `(gems × 10 + prism lines × 100) × chain step × level`.
- Combo: consecutive pieces that clear something earn `50 × (combo − 1) × level`.
- Soft drop +1/row, hard drop +2/row.
- Level = 1 + cleared gems / 40 (max 20); gravity `0.85 s × 0.86^(level−1)`,
  floor 0.06 s.
- Game over when a new piece can't spawn or a piece locks above the well.
- Randomiser: shapes from a shuffled 16-piece bag (12 pentominoes once, 2
  trominoes twice); colour pairs and pure colours from their own bags, so no
  shape or colour is starved.
- Best score + best chain persist in `user://settings.cfg` (IndexedDB on web).

## Content sources
All code, art (gems are drawn procedurally) and text are original. Godot's
default font. No third-party assets, so no CREDITS.md.

## Code map
- `scripts/pieces.gd` — `Pieces`: shape catalogue, piece colouring, fair `Bag`.
- `scripts/prism_board.gd` — `PrismBoard`: all rules (movement, rotation +
  kicks, gravity/lock delay, hold, settle, clears, chains, combos, levels).
  No scene dependency; the view drives resolution step by step to animate it.
- `scripts/board_view.gd` — `BoardView`: drawing, juice (fall slides, clear
  flash + rings, particles, popups, screen shake, danger glow, game-over
  greying) and gesture → action mapping.
- `scripts/gem.gd` — `Gem`: faceted gem / ghost drawing, colour-blind glyphs.
- `scripts/piece_preview.gd`, `scripts/menu_art.gd` — hold/next panels, title art.
- `scripts/main.gd` — menu, HUD, pause and game-over overlays, theme.
- `scripts/settings.gd` — `Settings` autoload: language + records.
- `tools/poster.gd` — hermetic poster capture (staged real board mid-chain);
  `tools/capture_over.gd` — game-over screen capture; `tools/smoke_es.json` —
  Spanish smoke script.

## Testing
```
tools/run_tests.sh            # gate: all tests/*_check.gd, prints GREEN
godot --headless --path . --import
godot --headless --path . --export-release "Web" export/web/index.html
~/cartridge/backend/.venv/bin/python ~/cartridge/tools/web_smoke.py games/pentaprism/export/web $TMPDIR/pentaprism-smoke
~/cartridge/backend/.venv/bin/python ~/cartridge/tools/web_smoke.py games/pentaprism/export/web $TMPDIR/pentaprism-smoke-es games/pentaprism/tools/smoke_es.json
godot --path . --resolution 720x1280 --script tools/poster.gd -- poster.png en   # needs a display
```
Suites: `board_check` (shapes, rotation, collision, kicks, settle, colour and
row clears, chains, scoring, combo, gravity, lock delay, hard drop/ghost, hold,
level speed, game over), `bag_check` (bag fairness, colour balance,
determinism, max drought), `gesture_check` (tap/drag/swipe mapping incl.
burst events), `save_check` (records persistence), `main_check` (real scene:
menu EN/ES, actions, pause, a full bot game to the game-over overlay, best
score saved).

## Known limitations / v2 ideas
- No sound yet (could add short synthesized clicks/chimes).
- No touch soft drop (swipe down always hard-drops); keyboard has soft drop.
- Ideas: daily seed challenge, "prism" special gem that clears a whole colour,
  marathon vs. 3-minute sprint modes, chain replay on the game-over screen.

# Pentaprism

A falling-gem puzzle with its own rules: two-colour **pentominoes** (plus a few
single-colour trominoes — never tetrominoes) drop into a 9×16 well of faceted
gems. Pieces land **rigid**, so overhangs leave holes you have to live with.
Then **5+ touching gems of one colour** shatter, and so does any completely
filled row (a *prism line*). Only gems above a clear fall into the gaps, which
can set off more clears: chain reactions multiply the points. Every few pieces a
**stone row rises from the floor** and pushes your stack towards the ceiling;
stones never match, and the only way to break one is to clear gems next to it.
Distinct look on purpose (dark well with a dot lattice, octagonal gems with
per-colour glyphs, purple accent) — it is not a line-clear tetromino game.

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
- Pieces lock **rigid**: no per-gem collapse on landing, so sloppy stacking
  leaves holes. Gravity after a clear is per column, above the cleared cells.
- **5 gem colours**; a match needs **5+ orthogonally connected** gems of one hue,
  so random dropping almost never clears.
- **Stone rows**: the well starts with 2, and another rises every 10 locked
  pieces at level 1, shrinking to a floor of 4 (one piece less every 2 levels).
  Each has 1–2 gaps, the HUD counts down to the next one, and a rising row pushes
  the whole stack up. A stone orthogonally next to a clearing gem **cracks** into
  a random gem: that is how you dig out.
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
- Points come only from clears (plus ≤ 1/row for drops): placing pieces alone
  scores nothing.
- Best score + best chain persist through `CartridgeStore` (the app's durable
  storage, `user://` fallback), under v2 keys so the old, much easier records
  don't mix in. The run in progress autosaves after every locked piece, so the
  menu offers **Continue** even after the app is force-stopped.

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
level speed, game over, stone rows + cracking), `difficulty_check` (bot
measurements, see below), `corrupt_probe` (truncated/garbage saves),
`bag_check` (bag fairness, colour balance,
determinism, max drought), `gesture_check` (tap/drag/swipe mapping incl.
burst events), `save_check` (records persistence), `main_check` (real scene:
menu EN/ES, actions, pause, a full bot game to the game-over overlay, best
score saved).

## Difficulty (measured by `tests/difficulty_check.gd`)
Bots over fixed seeds, printed by the gate:

| Bot | Pieces survived | Score |
|---|---|---|
| Random column + rotation | 11 | 100 |
| Always centre column | 6 (cap 10) | — |
| Greedy (clears, then fewest holes / lowest stack) | 117 | 116,815 |

Skill is worth about 10× survival, and careless play tops out quickly — the v1
board was effectively unloseable.

## Known limitations / v2 ideas
- No sound yet (could add short synthesized clicks/chimes).
- No touch soft drop (swipe down always hard-drops); keyboard has soft drop.
- Ideas: daily seed challenge, "prism" special gem that clears a whole colour,
  marathon vs. 3-minute sprint modes, chain replay on the game-over screen.

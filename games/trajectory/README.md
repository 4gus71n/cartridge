# Trajectory / Trayectoria

A math puzzle about flight paths: the rocket launches from the left edge and
flies along **y = f(x)**, and the player picks f. Every ring and the final
star have to be on the path, and asteroids and energy walls have to stay off
it. There are 30 hand-designed levels in six worlds. They start with flat lines y = c, then
move to slopes and intercepts, parabolas in vertex, standard and roots form,
and cubics. After that the player types formulas freely on a custom keypad and finishes with sine waves.
Each new idea comes with a short bilingual (EN/ES) teaching card. Once a
level is solved, the game shows the ideal answer next to the player's own curve.

## Controls (touch-first, no soft keyboard)
- **Steppers** (worlds 1–4): tap − / + on each coefficient, or hold to repeat.
  Values are coloured to match the equation above them, e.g. y = **0.5**(x − **2**)² + **3**.
  Locked coefficients are greyed out.
- **Math keypad** (worlds 5–6): digits, `.`, `x`, `x²`, `+ − × ÷ ^ ( )`,
  backspace (deletes `sin(` or `²` as one unit), `C`. World 6 adds `sin cos π`.
  Implicit multiplication works (`2x`, `3(x+1)`, `(x−1)(x+3)`, `2sin(x)`), and
  missing closing parentheses are added automatically (shown as ghost `)`).
- **LAUNCH** flies the rocket. ‹ goes back to level select, and (i) opens the teaching card again.

## Rules & scoring
- Easy levels show a live preview of the curve while you edit. Hard levels hide it.
  After a failed launch, its path stays on screen as a faint "ghost".
- Stars are based on launches: 1 launch = ★★★, 2–3 = ★★, 4 or more = ★. The game keeps your best result.
  A formula that doesn't parse shows an error and doesn't count as a launch.
- The rocket touches a ring when its path passes within 0.6 units of the
  centre. It crashes if the path comes within radius + 0.15 of an asteroid or touches a wall.
  The path can leave the plot vertically (an edge chevron shows where the rocket is).
  The flight breaks where f is undefined (e.g. 1/x at x = 0).
- Solving a level unlocks the next one. Stars, seen teaching cards, and in-progress
  drafts (current input + launch count) are saved in `user://trajectory.cfg`
  (IndexedDB on web). Reopening a level resumes the draft, so attempts don't reset.

## Content sources
Everything is original: code, levels, texts, and art (all drawn in code).
The only font is Godot's default. No third-party assets, so there is no CREDITS.md.
Graphwar inspired the concept only. No code or assets come from it.

## Code map
- `scripts/math_expr.gd`: recursive-descent parser → RPN evaluator (`^`
  right-assoc, unary minus, implicit multiplication, sin/cos/π, i18n error keys).
- `scripts/flight.gd`: pure flight simulation. It samples the path every 0.02, then
  runs segment–target, segment–circle and segment–rect (Liang–Barsky) checks.
- `scripts/levels.gd`: the 30 levels (targets, rocks, walls, ideal answer,
  preview flag, intro key). `scripts/forms.gd` covers stepper forms, ranges and pretty
  printing. `scripts/poly.gd` expands the ideal answer to standard form.
- `scripts/key_buffer.gd`: keypad token buffer. `scripts/progress.gd`: stars,
  drafts, save/load. `scripts/settings.gd`: autoload (language + persistence).
- `scripts/plot_view.gd`: plot drawing, rocket animation, trail, particles.
  `scripts/main.gd` builds every screen in code (menu, level select, game, teaching card, result sheet).
  It also has `icon_button.gd` and `stars_view.gd`, which draw glyphs the font lacks.

## How to test
- `tools/run_tests.sh` is the gate (GREEN). It runs six suites: parser, flight/forms/poly,
  levels (every level is solved by its ideal answer, the start values don't
  solve it, and the content is sane), keypad buffer, progress save/load, and a UI bot (`ui_check.gd`).
  The bot boots the real scene, covers the miss / asteroid / wall / undefined / parse-error paths,
  wins and checks the stars, the drafts and the result sheet, and then **solves all 30 levels through the UI**.
- Export: `godot --headless --path . --export-release "Web" export/web/index.html`.
- Smoke: `~/cartridge/backend/.venv/bin/python ~/cartridge/tools/web_smoke.py games/trajectory/export/web <out>`
  (also `smoke_es.json` for Spanish).
- `tools/capture.py` is a game-local screenshot helper. The query strings `?level=N&nointro` and
  `?screen=levels` are QA shortcuts. `?poster=21&x=0.3` stages the poster (level 21 with the
  rocket frozen mid-flight) and is captured at 360×640 @2x into `poster.png`.

## Known limitations / ideas for v2
- The plot is fixed to x, y ∈ [−10, 10]. Zoom and scrolling worlds would allow bigger curves.
- Stepper levels can have more than one solution (e.g. level 10 has 5). Any
  valid solution counts, and the ideal shown is the designed one.
- Ideas: piecewise functions, a parametric "time" world, an exponential/log world,
  par formulas (shortest expression), a daily challenge, sound effects.

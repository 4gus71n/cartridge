# Right of Way / Prioridad

A traffic sign flashes up on a roadside. Pick what to do (stop, give way, slow
down, no entry…) before the timer bar empties. It's a reflex game that doubles
as a road-sign trainer: every mistake shows what the sign means.

## Modes
- **Endless run**: 3 lives. The timer starts at 4.5 s and loses 0.125 s per
  streak step, down to 2.0 s (reached at streak 20). The first 5 questions have
  3 choices, after that 4. Score per correct answer = 100 base + up to 100 speed
  bonus, multiplied by the streak multiplier (+1 every 5 in a row, max ×5).
  A wrong answer or a timeout costs a life and shows the sign's meaning. The
  game-over screen offers a review of the signs you missed.
- **Learn the signs**: no timer. Browse all 58 signs by category with what each
  one means and what to do.

Best score is saved in `user://` (IndexedDB on the web). EN/ES toggle on the menu
(defaults to the device locale).

## Signs
58 signs drawn entirely in code (`scripts/sign_painter.gd`) in Vienna Convention
style, as used in Europe and most of South America (Uruguay included):
priority (stop, give way, priority road…), prohibitions (no entry, speed limits,
no overtaking, no parking/stopping, turns, vehicle types…), mandatory (blue
circles), warnings (red-bordered triangles) and information signs. No images, so
there's nothing to license. Distractors come from related signs (same category
or shape) so the wrong answers are plausible.

## Code map
- `scripts/sign_catalog.gd`: sign data (id, category, action, distractor pool, EN/ES text)
- `scripts/sign_painter.gd` / `sign_view.gd` / `sign_tile.gd`: drawing
- `scripts/sign_quiz.gd`: question generation (correct exactly once, no repeats within N)
- `scripts/run_state.gd`: timer, score, streak, lives
- `scripts/road_scene.gd`, `timer_bar.gd`, `lives_view.gd`: scene pieces
- `scripts/main.gd`: screens (menu, run, pause, game over, guide)

## Tests
`tools/run_tests.sh` → `tests/signs_check.gd` (data integrity: every sign has a
draw routine, action and EN/ES text), `quiz_check.gd`, `run_check.gd`,
`ui_check.gd` (bot plays the real scene). Web smoke: `smoke.json`, `smoke_es.json`.
`tools/contact_sheet.gd` renders every sign on one sheet (needs a display);
`tools/capture.gd` makes the poster.

## Ideas for v2
- Country packs (US MUTCD style signs, Uruguay-specific variants).
- Scenario rounds: sign plus a road situation.
- Sound effects. `priority_junction` should get a thicker main-road stroke to
  tell it apart from `crossroads` at a glance.

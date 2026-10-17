# Delve

A pocket roguelike built for one thumb. Descend twelve procedurally generated
floors, fight a scaling bestiary, gamble on unidentified potions, scrolls and
wands, keep your belly full, and face the Ashen King on the last floor to claim
the Heart of Embers. One life per run: death is permanent, but every run lands
on the high-score table. Turn-based, so it plays equally well in thirty seconds
or thirty minutes, and it autosaves after every move.

## Controls (touch-first, mouse works too)
- **Tap a tile**: walk there (auto-path through explored map; stops when a
  monster comes into view). Tap an adjacent monster to attack.
- **Swipe** anywhere on the map: take one step / attack in that direction (8-way).
- **Long-press** a tile: inspect it (monster, item, terrain).
- **Action bar**: Wait · Search (reveals hidden doors/traps nearby) · Grab ·
  Stairs · Pack · Map. Buttons light up when they're useful.
- **Pack**: tap an item to Use / Equip / Remove / Eat / Read / Zap / Throw / Drop.
  Throwing and zapping enter aim mode: tap a target tile, or Cancel.
- **☰** opens Pause: resume, message log, how to play, language, save & quit,
  abandon run. Desktop keys (optional): arrows/numpad move, `.`/space wait,
  `g`/`,` grab, `>`/Enter stairs, `i` pack, `m` map.

## Rules & scoring
- 12 depths; the Ashen King waits on depth 12. Kill him, he drops the Heart
  of Embers, and picking it up wins the run.
- Field of view with shadow-casting; explored tiles are remembered and drawn dimmed.
- Potions (9 kinds), scrolls (8) and wands (3) get **random appearances per run**
  (colours, gibberish labels, materials); use or Identify scrolls to learn them.
- Hunger: food drains each turn (Hungry → Weak → Starving, which hurts); eat
  rations or apples.
- XP and levels raise max HP and to-hit; weapons/armour can be enchanted.
- 17 monster types (16 regulars + boss) with depth bands, so each floor's roster
  shifts deeper: rats/bats/slimes at the top, trolls, wraiths and ogres below.
  AIs: melee, erratic, ranged, thief, skittish, boss (summons).
- Score = gold + XP + 200 per depth below the first + 5 per kill, +5000 for a
  win. Top runs are kept in `user://` with cause of death, depth, level and seed.

## Content sources
All code, monsters, items, names and text are original (Cartridge Studio).
Glyph-style tiles are drawn procedurally; Godot's default font. No third-party
assets, so no CREDITS.md is needed.

## Code map
- `scripts/defs.gd` — static content: monsters, items, appearance pools, traps.
- `scripts/run.gd` — the whole game state & rules (turns, combat, AI, hunger,
  items, identification, save/load). Scene-free, fully testable.
- `scripts/level.gd`, `level_gen.gd`, `spawn.gd`, `seeds.gd` — map model,
  seeded rooms-and-corridors generator (time-budgeted on web), spawning.
- `scripts/fov.gd`, `pathing.gd` — shadow-casting FOV, BFS/A* travel.
- `scripts/main.gd` — UI: menu, HUD, overlays (pack/map/pause/log/help/end),
  input (tap/swipe/long-press), autosave. `map_view.gd`, `minimap.gd`,
  `hud_bar.gd`, `action_icon.gd` draw the board and icons.
- `scripts/settings.gd` (autoload), `txt.gd`, `i18n/strings.csv` — EN/ES.
- `tools/poster.gd` — hermetic poster capture (stages a real depth-6 fight).

## Testing
- `tools/run_tests.sh` → GREEN: `logic_check` (77), `gen_check` (27),
  `ui_check` (41), `bot_check` (12; seeded bots play full runs to death and,
  in god mode, to the final floor/victory).
- Web: export `Web` preset to `export/web/`, then
  `web_smoke.py games/delve/export/web <out>` with `smoke.json` (EN) and
  `smoke_es.json` (ES): menu → new run → swipes → search/wait → long-press
  inspect → pack/item detail → map → pause → abandon → death screen.
- Poster: `godot --path . --script tools/poster.gd -- poster.png en 60`.

## Known limitations / v2 ideas
- No sound yet; no rings/amulets beyond the Heart; no shops or altars.
- Map overlay is a small minimap; pinch-zoom could help on tablets.
- Ideas: daily seeded challenge, more boss variety, class choice at start.

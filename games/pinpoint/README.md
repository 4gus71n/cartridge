# Pinpoint

A photo from somewhere on Earth fills the top of the screen; a world map fills
the bottom. Pinch and pan both, drop a pin where you think the photo was taken,
confirm, and watch a line fly from your guess to the real spot. Five photos per
game, from Lisbon alleys to Antarctic stations — closer guesses score more, and
naming the right country earns a bonus. Fully offline: the photos and the map
ship inside the game.

## Controls
- **Photo / map:** drag to pan, pinch (or mouse wheel / trackpad) to zoom,
  double-tap to zoom in. The map also has +/− buttons and a chevron button that
  gives it more of the screen.
- **Tap the map** to drop (or move) your pin, then **Confirm guess**.
- **≡** (top left) pauses: continue, or save & exit (the game resumes from the
  menu, also after closing the app).
- Menu: language (EN/ES, defaults to the device locale), units (km/miles,
  defaults to miles for en-US/en-GB), Credits.

## Rules and scoring
- 5 rounds, each a different photo from a different country (recently seen
  photos are avoided for ~18 games).
- Distance points: `round(5000 · e^(−d / 2000 km))` — 5,000 within 500 m,
  ~1,839 at 2,000 km, ~0 at the antipode (great-circle distance).
- Country bonus: +1,000 when your pin is in the photo's country (pins within
  30 km of a coast count for the nearest country, so harbour cities work with
  the simplified coastline). Max 6,000 per round, 30,000 per game.
- Best score and games played are saved in `user://settings.cfg` (IndexedDB on
  the web) together with language, units, recent photos and the game in progress.

## Content sources (see CREDITS.md)
- **Photos:** Wikimedia Commons, only **CC0, public domain, CC BY 4.0/3.0/2.0**
  (CC BY-SA, GFDL, NC and anything else is rejected by the pipeline and by
  `PhotoDeck.validate()`), camera-geotagged (`{{Location}}` GPS). Resized to
  900 px long side, WebP. Author + license are shown after every round and on
  the Credits screen; CREDITS.md links every source page.
- **Map:** Natural Earth 1:50m Admin 0 countries (public domain), simplified
  to ~40k points. Same polygons drive drawing and the country bonus. (1:50m
  instead of 1:110m so small island nations — Malta, Mauritius, Samoa, Cape
  Verde — exist for the bonus.)

## Code map
- `scripts/main.gd` — all screens (menu, round, reveal card, pause, summary,
  credits); public entry points used by the UI bot.
- `scripts/game_state.gd` (`PinpointGame`) — rounds, scoring, (de)serialise.
- `scripts/geo_math.gd` (`GeoMath`) — haversine, score curve, units, geodesic.
- `scripts/map_projection.gd` (`MapProjection`) — Miller projection + view transform.
- `scripts/world_data.gd` (`WorldData`) — country polygons, point-in-country, land mesh.
- `scripts/photo_deck.gd` (`PhotoDeck`) — manifest, license allow-list, round picker.
- `scripts/pan_zoom_view.gd` → `photo_view.gd`, `map_view.gd` — shared
  touch/mouse pan-pinch-wheel-tap control; map draws land once into a
  transformed Node2D and pins/lines on a screen-space overlay.
- `scripts/settings.gd` — persistence autoload. `scripts/icon_button.gd` — vector icons.
- `content/` — `world.json/.bin` (map), `photos.json` + `photos/*.webp`
  (`importer="keep"` so the raw WebP bytes ship and decode at runtime).
- `tools/` — content pipeline (below), `capture.gd` (screens + poster),
  `contact_sheet.gd` (photo review sheets), `run_tests.sh` (gate).

## Rebuilding content
```
PY=~/cartridge/backend/.venv/bin/python
$PY tools/build_map.py                  # Natural Earth -> content/world.*
$PY tools/fetch_candidates.py           # Commons geosearch + license search, cached in $TMPDIR/pinpoint-work
$PY tools/select_photos.py 3            # license/shape/GPS/keyword filter + ranking
$PY tools/build_photos.py download      # 960px thumbs -> 900px WebP (polite, resumable)
godot --headless --path . --script tools/contact_sheet.gd -- $TMPDIR/pinpoint-work/webp $TMPDIR/pinpoint-work/sheet 6 5
# review sheets, list bad ids in tools/rejects.txt
$PY tools/build_photos.py finalize      # content/photos*, CREDITS.md
```
All Commons requests are sequential with a descriptive User-Agent (contact
included), `maxlag=5`, ≥ 1 s spacing and Retry-After/exponential backoff.

## Testing
`tools/run_tests.sh` (must print GREEN): `geo_check` (distance, scoring,
units, projection round trip, geodesic/antimeridian), `world_check`
(triangulation, point-in-country incl. enclaves/islands/sea, names),
`deck_check` (manifest, files decode, license allow-list, size budget,
countries vs map, credits, rounds without repeats), `save_check` (game
serialisation, settings persistence), `ui_check` (bot plays perfect and bad
games, pause/save/resume across restart, credits, toggles, pinch/drag/tap/wheel
input, ≥ 88 px targets). Web smoke: `smoke.json` / `smoke_es.json`.

## Known limitations / v2 ideas
- Photo place names are the curation seed (city/area); a few photos are a few
  km outside that town. Spanish shows the same place names (country names are
  localised).
- Some coordinates come from Panoramio/Unsplash imports (user-placed, usually
  accurate to a few hundred metres — irrelevant at this score scale).
- v2: daily challenge (same 5 photos for everyone), continent-only modes,
  timed rounds, a pin-drag fine adjustment, a larger photo pool via streaming.

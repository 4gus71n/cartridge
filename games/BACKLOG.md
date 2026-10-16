# Cartridge Originals — Game Backlog

Games we build ourselves (Godot 4.7, web export) and host on GitHub Pages
(`cartridge-games` public repo: playable build + downloadable zip + sha256 in
`index.json`). Source lives in `cartridge/games/<slug>/`.

**Build defaults for every game**
- Godot 4.7.2, **Compatibility renderer** (WebGL 2), **no-threads** web export
  (GitHub Pages can't send COOP/COEP headers).
- Touch-first: no keyboard required. Portrait unless the game needs landscape.
- Fully offline after download: no network calls, all content bundled.
- Content licenses: original, CC0, or the permissive list in `roadmap.md` §3.
- Engine overhead ≈ 9–10 MB gzipped per game. Mitigation (later): share one
  engine `.wasm` across cartridges so each game only downloads its `.pck`.
- No trademarked names (Tetris, GeoGuessr, NetHack, Zork…).

**Suggested build order:** Minesweeper → Sudoku → Rocket Math → Block-drop →
Language Guesser → Crossword → Geo guesser → Text adventure → Roguelike → Traffic signs.

**Status (2026-10-16):** Minesweeper = **Minefield**, shipped (v1 live, v2 with
faster generation ready to publish). The rest are planned with slugs and
decisions in `../AGENTS.md` → "Next steps", to be built in parallel per `AGENTS.md`.

---

## 1. Language Guesser (working title: *Babel Ear*)
Play a short voice clip → pick the language (dropdown/searchable list) → if
correct, earn points and pick the country → bonus points.

- **Content:** Mozilla **Common Voice** — CC0, 100+ languages. Curate ~10 clean
  5–8 s clips per language, transcode to Ogg Vorbis (~40 KB each). 30 languages
  ≈ 12 MB. Download via Mozilla Data Collective (account + terms; terms forbid
  trying to identify speakers — fine for us).
- **Country step is the hard part:** most languages span many countries.
  Only ask for a country when the clip has a reliable country signal (locale
  variants like `zh-TW`/`zh-HK`, `pt` vs `pt-BR`, self-reported accent tags like
  "México"). Accept any country in the clip's tag; skip the step otherwise.
- **MVP:** 20 languages, 10 rounds per game, replay button, streak multiplier,
  show transcript + map after each round.
- **Later:** difficulty tiers (Spanish vs Basque), daily challenge.

## 2. Minesweeper
- Tap reveal, long-press flag, tap a number to chord. Pinch/zoom for big boards.
- **Twist:** "no-guess" board generation (always solvable by logic).
- Easy/medium/hard + timer + local best times. Fully procedural, tiny package.
- **Role:** first Godot cartridge — proves the export → Pages → app pipeline.

## 3. Roguelike ("NetHack clone")
- **NetHack itself is out:** NetHack General Public License is copyleft
  (GPL-family), excluded by our license policy. Same for Brogue CE (AGPL),
  DCSS (GPL).
- **Option A (quick, wrap existing):** original **Rogue 5.4.4** is BSD-3-Clause.
  Compile C → wasm (emscripten) with a curses→canvas shim and touch controls.
  Not Godot; ships as a plain HTML5 cartridge.
- **Option B (recommended, own):** touch-first Godot roguelike, NetHack-style
  (ASCII or tiles, items, identify, permadeath). Reuse know-how from
  *Shattered: Cyberpunk*. Bigger scope — do it last.

## 4. Geo guesser (working title: *Pinpoint*)
Show a photo → tap the world map → score by great-circle distance.

- **Imagery is the problem:** Google Street View terms forbid this. Mapillary
  is CC-BY-SA (excluded for now). Use **Wikimedia Commons** geotagged photos
  filtered to CC0 / CC-BY 4.0 (credits screen), or Panoramax items with
  CC-BY/etalab licenses. Curate ~150 photos as WebP (~100 KB) ≈ 15 MB.
- **Map:** Natural Earth (public domain) country polygons drawn in Godot —
  no tile server, works offline.
- **MVP:** 5 rounds, distance score, country-correct bonus, reveal line on map.

## 5. Block-drop puzzle ("Tetris clone")
- **Legal care:** The Tetris Company enforces trademark *and* trade dress;
  *Tetris Holding v. Xio* (2012) ruled a close-copy clone infringed. Use our own
  name and a distinct look, ideally a mechanical twist (pentominoes, hex grid,
  gravity flips, color-match clears).
- Swipe to move, tap to rotate, swipe down to drop. Ghost piece, hold, levels.

## 6. Text adventure
- **Option A:** **Open Adventure** (Colossal Cave Adventure 2.5, BSD-2-Clause)
  compiled to wasm. Cleanest license, historic.
- **Option B:** **Zork I–III** — source MIT since Nov 2025, but the *Zork* name and
  brand are not licensed, so we'd ship it under another title. Compile ZIL →
  z-code (ZILF) and run in an MIT-licensed JS Z-machine.
- **Option C:** write our own short adventure (Inform 7 → z-code).
- **Engine note:** typing on a phone is the UX problem. A plain HTML/JS shell
  (native soft keyboard, verb/direction buttons, tap words to insert them) fits
  the WebView better than Godot, whose mobile text input is weak and whose
  9 MB engine is overkill for text. Recommend non-Godot for this one.

## 7. Sudoku
- Generator + unique-solution solver + difficulty grading by solving techniques.
- Pencil marks, undo, highlight same number, error check toggle, daily puzzle.
  Procedural → tiny package, infinite content.

## 8. Crossword
- Content is the bottleneck, not code. Small 5×5 / 7×7 "mini" crosswords.
- Grid filler from a word list; clues: our own writing (LLM-drafted, human
  reviewed), WordNet definitions as a fallback (permissive license).
- Decide language(s): English, Spanish, or both.

## 9. Rocket Math (working title: *Trajectory*)
Rocket follows the curve `y = p(x)` you enter; hit every target, avoid obstacles.
A math-learning game.

- **Levels teach progressively:** constants → linear (`mx + b`) → quadratic
  (vertex, roots) → cubic → combos. Later: sine, piecewise.
- **Input on mobile:** coefficient steppers/sliders per degree, or a custom
  math keypad (`x`, `^`, digits). No soft keyboard. Write a small expression
  parser (Godot's `Expression` uses `pow()`, not `^`).
- **Feedback:** curve preview on easy levels, hidden on hard ones; stars for
  fewer attempts; show the "ideal" polynomial after solving.
- Inspiration: *Graphwar* (GPL — design inspiration only, no code).
- Most original idea on the list.

## 10. Traffic signs (working title: *Right of Way*)
A traffic sign appears → pick what to do from 3–4 multiple-choice actions
(stop, yield, slow down, no entry, turn only…) before a short timer runs out
(~4 s, shrinking as the streak grows).

- **Signs drawn in code** (shapes + pictograms) in Vienna Convention style
  (Europe / South America, close to Uruguay's) — no image licensing at all.
- Score for speed + correctness, streak multiplier, 3 lives. Explanation of
  the sign after each mistake so it doubles as learning.
- **MVP:** ~40 signs (regulatory, warning, mandatory, priority), EN/ES.
- **Later:** country packs (US MUTCD style), scenario rounds (sign + road
  situation picture).

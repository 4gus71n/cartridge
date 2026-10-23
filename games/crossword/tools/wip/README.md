# Crossword v2 — work in progress (English shipped, Spanish not yet)

English now ships v2: 40 Mini 5×5 + 7 Midi 7×7 (47 puzzles), tiers,
never-repeated answers (except a capped 3-letter pool), daily-by-weekday,
resumable per-tier progress. Spanish still ships the old v1: 42 untracked-
by-tier 5×5-mostly minis. `scripts/{main,pack,puzzle,settings}.gd` and
`tests/{data_check,flow_check}.gd` handle both: a pack is treated as "v2" iff
its first puzzle JSON object has a `tier` key (see `data_check.gd`'s
`rebuilt` flag), so the two languages can ship different pipeline versions
side by side without breaking the gate.

## What already works
- `tools/templates.py` → `tools/content/templates.json`: 180°-symmetric block
  patterns, every cell checked, no 2-letter entries, connected. 3 mini, 37 midi,
  200 big patterns. `--stats` prints length histograms.
- `tools/dict.py` → `tools/content/fillwords_<lang>.txt`: grows the filler's
  dictionary from our own clued vocabulary plus regular inflections, validated
  against the public-domain web2 list (EN) / our own bulk list (ES).
- `tools/build.py`: backtracking filler with a per-puzzle time budget, resumable
  through `tools/content/fills_<lang>.json`, enforcing the no-repeat rules
  (4+ letters once per pack, 3-letter answers at most 3× with different clues)
  and unique clue text. `--report` prints vocabulary supply vs. template demand.
- `tools/content/vocab/en_{mini,midi,big}_*.txt`: ~3,900 hand-written English
  `ANSWER = clue` lines, already split by tier difficulty. English Mini (40)
  and Midi (7) are built and shipped (`data/puzzles_en.json`); Big ships 0.
- `tools/content/vocab/es_{mini,midi,big}_*.txt`: ~1,150 hand-written Spanish
  `ANSWER = clue` lines, also split by tier — but the v2 build for Spanish
  isn't shippable yet (see "Why Spanish is not shipped" below).
- `tests/flow_check.gd`: the tier/daily/never-repeat flow test, now live in
  `tests/` (it used to be parked at `tools/wip/flow_check.gd.wip`; that copy
  is now a stale duplicate and can be deleted once nothing references it).

## Why English Midi stopped at 7 (target was 24)
`tools/build.py en` genuinely exhausts under the current vocabulary: giving
it the full 900s per-tier time budget and many more consecutive-failure
retries (tested) still stalls at 7/24 — it's not a budget/retry problem, the
backtracking filler just can't find a 7x7 grid that (a) only uses
already-clued answers, (b) never reuses a 4+ letter answer already placed
elsewhere in the pack, and (c) fits one of the 37 Midi templates, often
enough within a 12s-per-attempt budget. `--report` shows the *aggregate*
vocabulary supply is ample (it counts words by length, not by how well they
cross each other), so the real fix is writing more Midi-tier vocab biased
towards the letter patterns the templates actually need (vowel-rich,
common consonant clusters) — not just more words of the right length.

## Why Spanish is not shipped
Running `tools/build.py es` with the newly-written vocab gets only 25/30
Mini grids and 0/14 Midi grids (fails fast, ~15s per tier) — worse than
nothing, since the shipped v1 pack already has 42 puzzles. Likely the same
cause as the English Midi shortfall (not enough *crossing-compatible*
vocabulary, not raw supply) but worse because Spanish started from a smaller
base. Do not rerun `tools/build.py es` and ship its output until it beats
42 puzzles with a non-empty Midi tier — check with `--report` first, then a
real build, and compare `data/puzzles_es.json` puzzle counts before
committing over the working v1 file.

## To finish
1. Grow English Midi past 7: write more Midi vocab (and/or more Midi
   templates) aimed at word patterns that cross well, not just raw counts;
   re-run `tools/build.py en --report` then `tools/build.py en` after each
   batch until it stops stalling before 24.
2. Grow Spanish the same way, then past parity with the v1 pack (42) before
   it can replace it; Big tier (9x9) for both languages needs much more
   vocabulary before `WANT_BY_LANG[...]["big"]` can go above 0.
3. Once Spanish v2 beats v1, delete `tools/content/words_es.txt`,
   `ban_es.txt`, `clues_es.txt`, `tools/fill.py`, `tools/build_packs.py` (the
   old v1 pipeline) and drop the `rebuilt` flag logic in `data_check.gd`
   since both packs will be v2.
4. Re-run the full verification loop (gate, export, web smoke, EN+ES
   screenshots, poster) before shipping any content change.

# Crossword v2 — work in progress (NOT shipped)

The shipped game is still v1: 43 EN + 42 ES 5×5 minis. This folder and
`tools/{build,dict,templates}.py` + `tools/content/{vocab,templates.json,
fillwords_*,needclues_*}` are a **half-finished** rebuild towards three tiers
(Mini 5×5, Midi 7×7, Big 9×9) with no repeated answers and harder clues.

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
  `ANSWER = clue` lines, already split by tier difficulty.
- `tools/wip/flow_check.gd.wip`: the tier/daily/never-repeat flow test. It is
  parked here (not in `tests/`) because it asserts the v2 behaviour the shipped
  v1 game does not have yet — moving it back into `tests/` is part of finishing.

## Why it is not shipped
The filler places words from the *fill dictionary*, which is much larger than
the clued vocabulary, so a solved grid can contain answers with no clue. The
pipeline refuses to ship those and drops the puzzle, which is correct but left
only 2 EN puzzles on the last run. `tools/content/needclues_en.txt` lists the
443 answers that were placed and still need a hand-written clue.

## To finish
1. Write clues for the answers in `needclues_<lang>.txt` (append to the right
   `vocab/<lang>_<tier>_*.txt`), re-run `tools/build.py <lang>`, repeat. Each
   pass shrinks the list.
2. Spanish needs its midi and big vocabulary written from scratch
   (`vocab/es_mini_a.txt` is the only ES file today) — natively written clues,
   not translations.
3. Target: Mini ≥ 40, Midi ≥ 60, Big ≥ 50 per language.
4. Move `flow_check.gd.wip` back to `tests/flow_check.gd`, update
   `scripts/{main,pack,puzzle}.gd` for tier selection, daily-by-weekday and
   never-re-serving a solved puzzle, then gate + export + smoke + poster.

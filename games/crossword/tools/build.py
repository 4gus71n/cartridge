#!/usr/bin/env python3
"""Mini Crossword content pipeline (offline authoring tool, not shipped).

Reads the clued vocabulary (tools/content/vocab/<lang>_<tier>*.txt, lines
"ANSWER = clue"), fills the 180-degree symmetric block patterns in
tools/content/templates.json with backtracking under a time budget, and writes
the shipped packs data/puzzles_<lang>.json.

Rules enforced while filling (per language pack, across all tiers):
  * an answer of length >= 4 is used at most ONCE in the whole pack, and only
    in the tier whose vocabulary file it was written in (so its clue matches
    that tier's difficulty);
  * a 3-letter answer is used at most 3 times, each time with a different
    clue. Three-letter answers come from one pool shared by all tiers: there
    are not enough short words in either language to partition them, and a
    three-letter answer is easy whatever the tier. Difficulty tiering applies
    to the 4+ letter answers, which carry the puzzle.
  * every clue text is unique in the pack.

Resumable: every solved grid is appended to tools/content/fills_<lang>.json
immediately, so a restart continues instead of redoing the work.

  python3 tools/build.py en            # fill + write pack (resumes)
  python3 tools/build.py en --report   # vocabulary supply vs. template demand
  python3 tools/build.py en --reset    # throw the fills away and start over
  python3 tools/build.py all           # both languages
"""

import json
import pathlib
import random
import sys
import time
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "tools" / "content"
VOCAB = CONTENT / "vocab"
TEMPLATES = CONTENT / "templates.json"
TIERS = ("mini", "midi", "big")
# Puzzles shipped per tier.
WANT = {"mini": 40, "midi": 60, "big": 50}
# Seconds of backtracking allowed per puzzle attempt.
BUDGET = 3.5
# A 3-letter answer may be re-used this many times in one pack.
SHORT_USES = 3
# Candidates tried per slot before backtracking.
WIDTH = 90
# Wall-clock cap per tier: the build always terminates and ships what it got.
TIER_SECONDS = 600


def fill_words(lang: str):
    """The fill dictionary built by tools/dict.py."""
    path = CONTENT / f"fillwords_{lang}.txt"
    if not path.exists():
        return []
    return sorted({norm(w) for w in path.read_text(encoding="utf-8").split()})


def norm(word: str) -> str:
    """Upper-case, accents stripped; N-with-tilde stays its own letter."""
    out = []
    for ch in word.strip().upper():
        out.append(ch if ch == "Ñ" else unicodedata.normalize("NFD", ch)[0])
    return "".join(out)


# --- vocabulary -------------------------------------------------------------

class Vocab:
    """Clued answers: `tier[t]` = {ANSWER: [clue, ...]} for 4+ letters,
    `short` = {ANSWER: [clue, ...]} for the shared 3-letter pool."""

    def __init__(self, lang: str):
        self.tier = {t: {} for t in TIERS}
        self.short = {}
        for tier in TIERS:
            for path in sorted(VOCAB.glob(f"{lang}_{tier}*.txt")):
                for ln, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" not in line:
                        raise SystemExit(f"{path.name}:{ln}: no '=' in {line!r}")
                    w, clue = line.split("=", 1)
                    w, clue = norm(w), clue.strip()
                    if not w.isalpha() or len(w) < 3:
                        raise SystemExit(f"{path.name}:{ln}: bad answer {w!r}")
                    target = self.short if len(w) == 3 else self.tier[tier]
                    target.setdefault(w, []).append(clue)
        # A 4+ letter answer lives in one tier only; the earlier tier keeps it.
        taken = set()
        for tier in TIERS:
            for w in sorted(self.tier[tier]):
                if w in taken:
                    del self.tier[tier][w]
                else:
                    taken.add(w)
        # Drop duplicate clue texts (the pack must not repeat a clue).
        seen = set()
        for bag in [self.short] + [self.tier[t] for t in TIERS]:
            for w, clues in bag.items():
                keep = []
                for c in clues:
                    k = c.lower()
                    if k not in seen:
                        seen.add(k)
                        keep.append(c)
                bag[w] = keep

    def words(self, tier: str):
        """Answers usable in `tier`."""
        return sorted([w for w, c in self.tier[tier].items() if c]
                      + [w for w, c in self.short.items() if c])

    def cap(self, word: str) -> int:
        """How many times `word` may appear in the pack."""
        return SHORT_USES if len(word) == 3 else 1

    def clued(self):
        """Every answer that already has at least one clue."""
        return ({w for w, c in self.short.items() if c}
                | {w for t in TIERS for w, c in self.tier[t].items() if c})

    def clues_for(self, word: str, tier: str):
        return self.short[word] if len(word) == 3 else self.tier[tier].get(word, [])


def demand(templates: dict) -> dict:
    """tier -> {length: expected slots} for WANT puzzles of each tier."""
    out = {}
    for tier, grids in templates.items():
        tot = {}
        for g in grids:
            for _, cells in runs(g):
                tot[len(cells)] = tot.get(len(cells), 0) + 1
        out[tier] = {L: round(k / len(grids) * WANT[tier]) for L, k in sorted(tot.items())}
    return out


def report(lang: str) -> None:
    templates = json.loads(TEMPLATES.read_text())
    vocab = Vocab(lang)
    need = demand(templates)
    short_uses = sum(min(SHORT_USES, len(c)) for c in vocab.short.values())
    short_need = sum(d.get(3, 0) for d in need.values())
    print(f"{lang} shared 3-letter pool: {len(vocab.short)} answers, "
          f"{sum(len(c) for c in vocab.short.values())} clues, {short_uses} uses "
          f"(need {short_need}) {'OK' if short_uses >= short_need else 'SHORT'}")
    for tier in TIERS:
        words = vocab.tier[tier]
        have = {}
        for w in words:
            have[len(w)] = have.get(len(w), 0) + 1
        print(f"{lang} {tier}: {len(words)} tier answers")
        for L in sorted(set(need[tier]) | set(have)):
            if L == 3:
                continue
            n = need[tier].get(L, 0)
            h = have.get(L, 0)
            print(f"   len {L}: need {n:4d} slots, have {h:4d}  "
                  f"{'OK ' if h >= n else 'SHORT'}")


# --- grid helpers -----------------------------------------------------------

def runs(grid):
    """[(dir, cells)] for every across/down run of white cells."""
    n = len(grid)
    out = []
    for r in range(n):
        c = 0
        while c < n:
            if grid[r][c] != "#":
                s = c
                while c < n and grid[r][c] != "#":
                    c += 1
                out.append(("A", [(r, k) for k in range(s, c)]))
            else:
                c += 1
    for c in range(n):
        r = 0
        while r < n:
            if grid[r][c] != "#":
                s = r
                while r < n and grid[r][c] != "#":
                    r += 1
                out.append(("D", [(k, c) for k in range(s, r)]))
            else:
                r += 1
    return out


def numbering(grid):
    """[(dir_name, number, answer)] with standard crossword numbering."""
    h, w = len(grid), len(grid[0])

    def white(r, c):
        return 0 <= r < h and 0 <= c < w and grid[r][c] != "#"

    out, n = [], 0
    for r in range(h):
        for c in range(w):
            if not white(r, c):
                continue
            a = not white(r, c - 1) and white(r, c + 1)
            d = not white(r - 1, c) and white(r + 1, c)
            if not (a or d):
                continue
            n += 1
            for flag, dr, dc, name in ((a, 0, 1, "across"), (d, 1, 0, "down")):
                if flag:
                    s, rr, cc = "", r, c
                    while white(rr, cc):
                        s += grid[rr][cc]
                        rr, cc = rr + dr, cc + dc
                    out.append((name, n, s))
    return out


class Index:
    """Words by length and by (length, position, letter) for fast matching."""

    def __init__(self, words):
        self.by_len = {}
        self.pos = {}
        for w in words:
            self.by_len.setdefault(len(w), set()).add(w)
            for i, ch in enumerate(w):
                self.pos.setdefault((len(w), i, ch), set()).add(w)

    def matches(self, pattern):
        result = None
        for i, ch in enumerate(pattern):
            if ch is None:
                continue
            s = self.pos.get((len(pattern), i, ch))
            if not s:
                return set()
            result = set(s) if result is None else result & s
            if not result:
                return set()
        return set(self.by_len.get(len(pattern), ())) if result is None else result


def fill(template, index, rng, blocked, deadline, width=60, pref=frozenset()):
    """Backtracking fill. `blocked` = answers that may not be used any more."""
    grid = [[None if ch != "#" else "#" for ch in row] for row in template]
    slots = [cells for _, cells in runs(template)]
    chosen = [None] * len(slots)

    def pattern(k):
        return [grid[r][c] for r, c in slots[k]]

    def solve():
        if time.time() > deadline:
            return False
        used = {w for w in chosen if w}
        best, best_c = None, None
        for k in range(len(slots)):
            if chosen[k]:
                continue
            p = pattern(k)
            if all(c is not None for c in p):
                w = "".join(p)
                if w in used or w in blocked or w not in index.by_len.get(len(w), ()):
                    return False
                chosen[k] = w
                used.add(w)
                continue
            cands = index.matches(p) - used - blocked
            if not cands:
                return False
            if best is None or len(cands) < len(best_c):
                best, best_c = k, cands
        if best is None:
            return len(set(chosen)) == len(chosen)
        good = sorted(best_c & pref)
        rest = sorted(best_c - pref)
        rng.shuffle(good)
        rng.shuffle(rest)
        order = good + rest
        for w in order[:width]:
            saved = [grid[r][c] for r, c in slots[best]]
            snap = list(chosen)
            for (r, c), ch in zip(slots[best], w):
                grid[r][c] = ch
            chosen[best] = w
            if solve():
                return True
            chosen[:] = snap
            for (r, c), ch in zip(slots[best], saved):
                grid[r][c] = ch
        return False

    if solve():
        return ["".join(row) for row in grid]
    return None


# --- pack building ----------------------------------------------------------

def used_from(fills):
    """(global counts, per-tier counts) of answers consumed by saved fills."""
    counts = {}
    per_tier = {t: {} for t in TIERS}
    for f in fills:
        for _, _, ans in numbering(f["grid"]):
            counts[ans] = counts.get(ans, 0) + 1
            d = per_tier[f["tier"]]
            d[ans] = d.get(ans, 0) + 1
    return counts, per_tier


def build(lang: str, reset=False, seed=11) -> int:
    templates = json.loads(TEMPLATES.read_text())
    vocab = Vocab(lang)
    path = CONTENT / f"fills_{lang}.json"
    fills = []
    if path.exists() and not reset:
        try:
            fills = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            fills = []
        fills = [f for f in fills if isinstance(f, dict) and f.get("tier") in TIERS]
    rng = random.Random(seed)
    counts, _ = used_from(fills)
    for tier in TIERS:
        have = sum(1 for f in fills if f["tier"] == tier)
        if have >= WANT[tier]:
            continue
        words = fill_words(lang)
        if not words:
            print(f"{lang} {tier}: no fill dictionary, skipped")
            continue
        index = Index(words)
        pref = frozenset(vocab.clued())
        pool = list(templates[tier])
        shapes = {tuple(f["grid"]) for f in fills}
        fails = 0
        t0 = time.time()
        while have < WANT[tier] and fails < 120 and time.time() - t0 < TIER_SECONDS:
            template = pool[(have * 7 + fails) % len(pool)]
            blocked = {w for w, n in counts.items() if n >= vocab.cap(w)}
            g = fill(template, index, rng, blocked, time.time() + BUDGET,
                     width=WIDTH, pref=pref)
            if not g or tuple(g) in shapes:
                fails += 1
                continue
            fails = 0
            shapes.add(tuple(g))
            fills.append({"tier": tier, "grid": g})
            for _, _, ans in numbering(g):
                counts[ans] = counts.get(ans, 0) + 1
            have += 1
            path.write_text(json.dumps(fills, ensure_ascii=False), encoding="utf-8")
        print(f"{lang} {tier}: {have}/{WANT[tier]} grids ({time.time() - t0:.0f}s)")
    path.write_text(json.dumps(fills, ensure_ascii=False), encoding="utf-8")
    return write_pack(lang, fills, vocab)


def write_pack(lang: str, fills, vocab: Vocab) -> int:
    """Attach clues and write data/puzzles_<lang>.json. Returns error count."""
    order = {t: i for i, t in enumerate(TIERS)}
    fills = sorted(fills, key=lambda f: order[f["tier"]])
    short = {w: list(c) for w, c in vocab.short.items()}
    tiered = {t: {w: list(c) for w, c in vocab.tier[t].items()} for t in TIERS}
    seen_clues = set()
    need = {}
    dropped = {}
    errors = []
    pack = []
    per_tier = {t: 0 for t in TIERS}
    for f in fills:
        tier = f["tier"]
        pid = f"{lang}-{tier}-{per_tier[tier] + 1:02d}"
        p = {"id": pid, "tier": tier, "grid": f["grid"], "across": {}, "down": {}}
        taken = []          # (bag, answer, clue) popped for this puzzle
        missing = []
        for d, n, ans in numbering(f["grid"]):
            bag = short if len(ans) == 3 else tiered[tier]
            clues = bag.get(ans)
            if not clues:
                missing.append(ans)
                continue
            clue = clues.pop(0)
            taken.append((bag, ans, clue))
            if clue.lower() in seen_clues:
                errors.append(f"{pid}: duplicate clue text {clue!r}")
            seen_clues.add(clue.lower())
            p[d][str(n)] = clue
        if missing:
            # Not every answer is clued yet: put the clues back and skip the
            # puzzle, so the shipped pack is always fully clued.
            for bag, ans, clue in reversed(taken):
                bag[ans].insert(0, clue)
                seen_clues.discard(clue.lower())
            for ans in missing:
                need.setdefault((tier, len(ans)), []).append(ans)
            dropped[tier] = dropped.get(tier, 0) + 1
            continue
        per_tier[tier] += 1
        pack.append(p)
    out = ROOT / "data" / f"puzzles_{lang}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(pack, ensure_ascii=False, indent=0), encoding="utf-8")
    answers = {}
    for p in pack:
        for _, _, ans in numbering(p["grid"]):
            answers[ans] = answers.get(ans, 0) + 1
    todo = ROOT / "tools" / "content" / f"needclues_{lang}.txt"
    lines = []
    total = 0
    for (tier, L), ws in sorted(need.items()):
        uniq = sorted(set(ws))
        total += len(ws)
        lines.append(f"# {tier} len {L}: {len(uniq)} answers, {len(ws)} clue slots")
        lines += [f"{w} = " for w in uniq]
    todo.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if total:
        print(f"{lang}: {total} clue slots unwritten, dropped {dropped} "
              f"-> {todo.name}")
    for e in errors[:20]:
        print("ERROR", e)
    print(f"{lang}: {len(pack)} puzzles {per_tier}, {len(answers)} distinct answers, "
          f"{sum(answers.values())} entries, {len(errors)} errors -> {out.name}")
    return len(errors)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    langs = ("en", "es") if sys.argv[1] == "all" else (sys.argv[1],)
    if "--report" in sys.argv:
        for lang in langs:
            report(lang)
        return 0
    bad = 0
    for lang in langs:
        bad += build(lang, reset="--reset" in sys.argv)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

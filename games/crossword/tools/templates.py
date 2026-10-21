#!/usr/bin/env python3
"""Block-pattern generator for Mini Crossword (offline authoring tool).

Produces 180-degree symmetric block patterns where every white cell is in an
across AND a down entry of length >= 3, the white area is connected and the
block density is within the tier's band. Patterns are written to
tools/content/templates.json and reused by tools/fill.py.

  python3 tools/templates.py            # (re)generate templates.json
  python3 tools/templates.py --stats    # print length histograms
"""

import json
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "content" / "templates.json"

# size -> (min blocks, max blocks, max entry length, max 3-letter entries, wanted)
#
# Midi and big are deliberately blocky (~28-33% blocks instead of the 15-25%
# of a newspaper grid). Every answer in this game carries a clue we wrote
# ourselves, so the fill vocabulary is a few thousand curated words rather
# than the 50k+ list a professional constructor uses; low-interlock grids are
# what that vocabulary can fill while keeping every answer a fair, common
# word. All the structural rules still hold: 180-degree symmetry, every white
# cell in an across AND a down entry, no 2-letter entries, one connected area.
TIERS = {
    "mini": (5, 4, 6, 5, 4, 80),
    "midi": (7, 12, 18, 6, 12, 400),
    "big": (9, 22, 30, 8, 18, 400),
}

# Puzzles shipped per tier (per language).
WANT = {"mini": 40, "midi": 60, "big": 50}


def runs(grid):
    """[(dir, cells, length)] of every across/down run of white cells."""
    n = len(grid)
    out = []
    for r in range(n):
        c = 0
        while c < n:
            if grid[r][c] == ".":
                s = c
                while c < n and grid[r][c] == ".":
                    c += 1
                out.append(("A", [(r, k) for k in range(s, c)]))
            else:
                c += 1
    for c in range(n):
        r = 0
        while r < n:
            if grid[r][c] == ".":
                s = r
                while r < n and grid[r][c] == ".":
                    r += 1
                out.append(("D", [(k, c) for k in range(s, r)]))
            else:
                r += 1
    return out


def valid(grid):
    n = len(grid)
    for d, cells in runs(grid):
        if len(cells) < 3:
            return False
    whites = [(r, c) for r in range(n) for c in range(n) if grid[r][c] == "."]
    if not whites:
        return False
    seen = {whites[0]}
    stack = [whites[0]]
    while stack:
        r, c = stack.pop()
        for rr, cc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
            if 0 <= rr < n and 0 <= cc < n and grid[rr][cc] == "." and (rr, cc) not in seen:
                seen.add((rr, cc))
                stack.append((rr, cc))
    return len(seen) == len(whites)


def canon(grid):
    """Key that treats transposes / mirrors as the same pattern."""
    n = len(grid)
    variants = []
    g = [list(row) for row in grid]
    for _ in range(2):
        for _ in range(4):
            variants.append("".join("".join(row) for row in g))
            g = [list(row) for row in zip(*g[::-1])]
        g = [row[::-1] for row in g]
    return min(variants)


def exhaustive(tier):
    """Every valid pattern for a small size (5x5: 2^13 symmetric subsets)."""
    n, bmin, bmax, maxlen, max3, _ = TIERS[tier]
    orbits = [(r, c) for r in range(n) for c in range(n) if (r, c) <= (n - 1 - r, n - 1 - c)]
    found = {}
    for mask in range(1 << len(orbits)):
        g = [["."] * n for _ in range(n)]
        blocks = 0
        for b, (r, c) in enumerate(orbits):
            if mask >> b & 1:
                g[r][c] = "#"
                g[n - 1 - r][n - 1 - c] = "#"
                blocks += 1 if (r, c) == (n - 1 - r, n - 1 - c) else 2
        if not (bmin <= blocks <= bmax):
            continue
        grid = ["".join(row) for row in g]
        if not valid(grid):
            continue
        lens = [len(c) for _, c in runs(grid)]
        if max(lens) > maxlen or sum(1 for x in lens if x == 3) > max3:
            continue
        found.setdefault(canon(grid), grid)
    return list(found.values())


def generate(tier, seed=7):
    n, bmin, bmax, maxlen, max3, wanted = TIERS[tier]
    if n <= 5:
        return exhaustive(tier)
    rng = random.Random(seed)
    found = {}
    tries = 0
    while len(found) < wanted and tries < 20000:
        tries += 1
        target = rng.randint(bmin, bmax)
        g = [["."] * n for _ in range(n)]
        orbits = [(r, c) for r in range(n) for c in range(n) if (r, c) <= (n - 1 - r, n - 1 - c)]
        rng.shuffle(orbits)
        blocks = 0
        # Greedy: add symmetric block pairs that keep the pattern valid.
        for r, c in orbits:
            if blocks >= target:
                break
            add = 1 if (r, c) == (n - 1 - r, n - 1 - c) else 2
            if blocks + add > bmax:
                continue
            g[r][c] = "#"
            g[n - 1 - r][n - 1 - c] = "#"
            if valid(["".join(row) for row in g]):
                blocks += add
            else:
                g[r][c] = "."
                g[n - 1 - r][n - 1 - c] = "."
        grid = ["".join(row) for row in g]
        if not (bmin <= blocks <= bmax):
            continue
        rs = runs(grid)
        lens = [len(c) for _, c in rs]
        if max(lens) > maxlen or sum(1 for x in lens if x == 3) > max3:
            continue
        key = canon(grid)
        if key not in found:
            found[key] = grid
    return list(found.values())


def stats(grid):
    lens = [len(c) for _, c in runs(grid)]
    return {L: lens.count(L) for L in sorted(set(lens))}


if __name__ == "__main__":
    if "--demand" in sys.argv:
        data = json.loads(OUT.read_text())
        for tier, grids in data.items():
            tot = {}
            for g in grids:
                for L, k in stats(g).items():
                    tot[L] = tot.get(L, 0) + k
            per = {L: k / len(grids) for L, k in tot.items()}
            want = WANT[tier]
            need = {L: round(v * want) for L, v in sorted(per.items())}
            # 3-letter answers may repeat up to 3x in a pack.
            distinct = {L: (round(v / 3) if L == 3 else v) for L, v in need.items()}
            print(tier, "puzzles", want, "slots", need, "distinct words needed", distinct,
                  "total", sum(distinct.values()))
        sys.exit(0)
    if "--stats" in sys.argv:
        data = json.loads(OUT.read_text())
        for tier, grids in data.items():
            tot = {}
            for g in grids:
                for L, k in stats(g).items():
                    tot[L] = tot.get(L, 0) + k
            print(tier, len(grids), "avg entries %.1f" % (sum(tot.values()) / len(grids)),
                  {L: round(k / len(grids), 2) for L, k in tot.items()})
        sys.exit(0)
    data = {}
    for t in TIERS:
        found = {}
        for seed in range(1, 9):
            for g in generate(t, seed):
                found.setdefault(canon(g), g)
            if len(found) >= TIERS[t][5]:
                break
        data[t] = list(found.values())
    OUT.write_text(json.dumps(data, indent=1))
    for t, g in data.items():
        print(t, len(g))

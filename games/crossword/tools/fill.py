#!/usr/bin/env python3
"""Grid filler for Mini Crossword (offline authoring tool, not shipped).

Fills symmetric grid templates with words from our own hand-written word list
(tools/content/words_<lang>.txt) and writes tools/content/fills_<lang>.json.
Clues are written by hand afterwards in tools/content/clues_<lang>.txt and
merged by tools/build_packs.py.

Usage:
  python3 tools/fill.py <lang> [--n5 36] [--n7 8] [--seed 1]
  python3 tools/fill.py <lang> --probe     # report fill rate per template

Spanish: Ñ is its own letter; accents are stripped (Á→A, Ü→U).
"""

import json
import pathlib
import random
import sys
import time
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent
CONTENT = ROOT / "content"

# 180°-symmetric templates, every across/down run >= 3 letters.
T5 = {
    "corners2": ["##...", "#....", ".....", "....#", "...##"],
    "corners2b": ["...##", "....#", ".....", "#....", "##..."],
    "corners4": ["#...#", ".....", ".....", ".....", "#...#"],
    "corners1": ["#....", ".....", ".....", ".....", "....#"],
    "corners1b": ["....#", ".....", ".....", ".....", "#...."],
    "open": [".....", ".....", ".....", ".....", "....."],
}
T7 = {
    "cross": ["...#...", "...#...", ".......", "##...##", ".......", "...#...", "...#..."],
    "bars": ["#....##", "#......", ".......", "...#...", ".......", "......#", "##....#"],
    "stair": ["###....", "##.....", "#......", "...#...", "......#", ".....##", "....###"],
    "stairb": ["....###", ".....##", "......#", "...#...", "#......", "##.....", "###...."],
    "steps": ["....###", ".....##", ".....##", "...#...", "##.....", "##.....", "###...."],
    "wedge": ["###...#", "##.....", "##.....", "...#...", ".....##", ".....##", "#...###"],
}


def valid_template(grid):
    """Every white cell in an across AND a down run of length >= 3, connected."""
    h, w = len(grid), len(grid[0])
    for r in range(h):
        for run in grid[r].split("#"):
            if 0 < len(run) < 3:
                return False
    for c in range(w):
        col = "".join(grid[r][c] for r in range(h))
        for run in col.split("#"):
            if 0 < len(run) < 3:
                return False
    whites = [(r, c) for r in range(h) for c in range(w) if grid[r][c] != "#"]
    seen = {whites[0]}
    stack = [whites[0]]
    while stack:
        r, c = stack.pop()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (r + dr, c + dc)
            if 0 <= q[0] < h and 0 <= q[1] < w and grid[q[0]][q[1]] != "#" and q not in seen:
                seen.add(q)
                stack.append(q)
    return len(seen) == len(whites)


def random_template(n, blacks, rng):
    cells = [(r, c) for r in range(n) for c in range(n) if (r, c) <= (n - 1 - r, n - 1 - c)]
    for _ in range(20000):
        g = [["."] * n for _ in range(n)]
        k = 0
        while k < blacks:
            r, c = rng.choice(cells)
            if g[r][c] == "#":
                continue
            g[r][c] = "#"
            g[n - 1 - r][n - 1 - c] = "#"
            k += 1 if (r, c) == (n - 1 - r, n - 1 - c) else 2
        grid = ["".join(row) for row in g]
        if valid_template(grid):
            return grid
    return None


def norm(word: str) -> str:
    out = []
    for ch in word.strip().upper():
        if ch == "Ñ":
            out.append("Ñ")
            continue
        base = unicodedata.normalize("NFD", ch)[0]
        out.append(base)
    w = "".join(out)
    return w


def load_words(lang: str) -> list[str]:
    words = []
    seen = set()
    for line in (CONTENT / f"words_{lang}.txt").read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0]
        for tok in line.split():
            w = norm(tok)
            if len(w) >= 3 and w not in seen and all(c.isalpha() for c in w):
                seen.add(w)
                words.append(w)
    return words


def slots_of(grid: list[str]) -> list[dict]:
    h, w = len(grid), len(grid[0])
    slots = []
    for r in range(h):
        c = 0
        while c < w:
            if grid[r][c] != "#" and (c == 0 or grid[r][c - 1] == "#"):
                cells = []
                k = c
                while k < w and grid[r][k] != "#":
                    cells.append((r, k))
                    k += 1
                if len(cells) >= 2:
                    slots.append({"dir": "A", "cells": cells})
                c = k
            else:
                c += 1
    for c in range(w):
        r = 0
        while r < h:
            if grid[r][c] != "#" and (r == 0 or grid[r - 1][c] == "#"):
                cells = []
                k = r
                while k < h and grid[k][c] != "#":
                    cells.append((k, c))
                    k += 1
                if len(cells) >= 2:
                    slots.append({"dir": "D", "cells": cells})
                r = k
            else:
                r += 1
    return slots


class Index:
    def __init__(self, words):
        self.by_len = {}
        self.pos = {}
        for w in words:
            self.by_len.setdefault(len(w), []).append(w)
        for n, ws in self.by_len.items():
            for w in ws:
                for i, ch in enumerate(w):
                    self.pos.setdefault((n, i, ch), set()).add(w)
            self.by_len[n] = set(ws)

    def matches(self, pattern):
        n = len(pattern)
        result = None
        for i, ch in enumerate(pattern):
            if ch is None:
                continue
            s = self.pos.get((n, i, ch), set())
            result = s if result is None else result & s
            if not result:
                return set()
        return set(self.by_len.get(n, set())) if result is None else result


def fill(template, index, rng, banned, node_limit=20000):
    grid = [[None if ch != "#" else "#" for ch in row] for row in template]
    slots = slots_of(template)
    assigned = [None] * len(slots)
    nodes = [0]

    def pattern(s):
        return [grid[r][c] for r, c in s["cells"]]

    def cands(i):
        return index.matches(pattern(slots[i])) - banned

    def solve():
        nodes[0] += 1
        if nodes[0] > node_limit:
            return False
        best, best_c = None, None
        used = {a for a in assigned if a}
        for i in range(len(slots)):
            if assigned[i]:
                continue
            p = pattern(slots[i])
            if all(p):
                w = "".join(p)
                if w in used or w not in index.by_len.get(len(w), ()) or w in banned:
                    return False
                continue
            c = cands(i) - used
            if not c:
                return False
            if best is None or len(c) < len(best_c):
                best, best_c = i, c
        if best is None:
            # all slots fully lettered: record words
            for i in range(len(slots)):
                if not assigned[i]:
                    assigned[i] = "".join(pattern(slots[i]))
            words = [a for a in assigned]
            return len(set(words)) == len(words)
        order = sorted(best_c)
        rng.shuffle(order)
        for w in order[:60]:
            saved = [grid[r][c] for r, c in slots[best]["cells"]]
            for (r, c), ch in zip(slots[best]["cells"], w):
                grid[r][c] = ch
            assigned[best] = w
            snapshot = list(assigned)
            if solve():
                return True
            assigned[:] = snapshot
            assigned[best] = None
            for (r, c), ch in zip(slots[best]["cells"], saved):
                grid[r][c] = ch
        return False

    if solve():
        return ["".join(row) for row in grid]
    return None


def read_set(path):
    if not path.exists():
        return set()
    out = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        out |= {norm(w) for w in line.split("#", 1)[0].split()}
    return out


def entries_of(template, grid):
    return ["".join(grid[r][c] for r, c in s["cells"]) for s in slots_of(template)]


def build_pool(lang, index, rng, templates, tries, seconds):
    """Random fills per template; a random 35% of the list is banned on each
    try so the pool is varied. Writes tools/content/pool_<lang>.json."""
    hard_ban = read_set(CONTENT / f"ban_{lang}.txt")
    all_words = sorted(set().union(*index.by_len.values()))
    path = CONTENT / f"pool_{lang}.json"
    pool = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
    seen = {tuple(p["grid"]) for p in pool}
    for name in templates:
        template = {**T5, **T7}[name]
        t0 = time.time()
        got = 0
        for _ in range(tries):
            if time.time() - t0 > seconds:
                break
            banned = hard_ban | {w for w in all_words if rng.random() < 0.35}
            g = fill(template, index, rng, banned, 3000 if len(template) == 5 else 8000)
            if g and tuple(g) not in seen:
                seen.add(tuple(g))
                pool.append({"template": name, "grid": g})
                got += 1
        print(f"  pool {name}: +{got} in {time.time() - t0:.0f}s")
    path.write_text(json.dumps(pool, ensure_ascii=False), encoding="utf-8")
    print(f"pool size {len(pool)}")


def select(lang, n5, n7, rng):
    """Greedy pick from the pool: fewest weak words, least overlap with answers
    already chosen. Writes tools/content/fills_<lang>.json."""
    pool = json.loads((CONTENT / f"pool_{lang}.json").read_text(encoding="utf-8"))
    hard_ban = read_set(CONTENT / f"ban_{lang}.txt")
    weak = read_set(CONTENT / f"weak_{lang}.txt")
    cands = []
    for p in pool:
        t = {**T5, **T7}[p["template"]]
        ents = entries_of(t, p["grid"])
        if set(ents) & hard_ban:
            continue
        cands.append((p, ents))
    used = {}
    chosen = []
    tcount = {}
    for want, size in ((n5, 5), (n7, 7)):
        for _ in range(want):
            best, best_s = None, None
            for p, ents in cands:
                if len(p["grid"]) != size or p in chosen:
                    continue
                s = sum(3 for e in ents if e in weak)
                s += sum(4 * used.get(e, 0) for e in ents)
                s += 2 * tcount.get(p["template"], 0)
                s += rng.random()
                if best_s is None or s < best_s:
                    best, best_s = (p, ents), s
            if best is None:
                break
            chosen.append(best[0])
            tcount[best[0]["template"]] = tcount.get(best[0]["template"], 0) + 1
            for e in best[1]:
                used[e] = used.get(e, 0) + 1
    fives = [p for p in chosen if len(p["grid"]) == 5]
    sevens = [p for p in chosen if len(p["grid"]) == 7]
    rng.shuffle(fives)
    order = list(fives)
    for j, p in enumerate(sevens):
        order.insert(min(len(order), 5 + j * 6), p)
    for i, p in enumerate(order):
        t = {**T5, **T7}[p["template"]]
        ents = entries_of(t, p["grid"])
        flags = [e + ("*" if e in weak else "") + ("+" if used[e] > 1 else "") for e in ents]
        print(f"  {i + 1:2d} {p['template']:9s} {' '.join(flags)}")
    out = CONTENT / f"fills_{lang}.json"
    out.write_text(json.dumps(order, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {out}: {len(order)} puzzles, {len(used)} distinct answers, "
          f"{sum(1 for e in used if e in weak)} weak, reused {sorted(e for e, k in used.items() if k > 1)}")


def main():
    lang = sys.argv[1]
    args = sys.argv[2:]
    words = load_words(lang)
    index = Index(words)
    counts = {n: len(ws) for n, ws in sorted(index.by_len.items())}
    print(f"{lang}: {len(words)} words {counts}")
    rng = random.Random(int(args[args.index("--seed") + 1]) if "--seed" in args else 1)
    if "--pool" in args:
        names = args[args.index("--pool") + 1].split(",")
        build_pool(lang, index, rng, names, 400, 60)
        return
    if "--select" in args:
        n5 = int(args[args.index("--n5") + 1]) if "--n5" in args else 36
        n7 = int(args[args.index("--n7") + 1]) if "--n7" in args else 6
        select(lang, n5, n7, rng)
        return
    if "--search7" in args:
        found = {}
        for blacks in (12, 14, 16, 18, 20):
            for _ in range(25):
                t = random_template(7, blacks, rng)
                if not t or tuple(t) in found:
                    continue
                ok = sum(1 for _ in range(4) if fill(t, index, rng, set(), 8000))
                found[tuple(t)] = ok
                if ok >= 2:
                    print(f"  {ok}/4 b={blacks} {t}")
        return
    if "--probe" in args:
        for name, t in {**T5, **T7}.items():
            ok = 0
            t0 = time.time()
            for k in range(10):
                if fill(t, index, rng, set(), 6000):
                    ok += 1
            print(f"  {name}: {ok}/10 in {time.time() - t0:.1f}s")
        return
    n5 = int(args[args.index("--n5") + 1]) if "--n5" in args else 36
    n7 = int(args[args.index("--n7") + 1]) if "--n7" in args else 8
    t5 = [x for x in (args[args.index("--t5") + 1].split(",") if "--t5" in args else T5)]
    t7 = [x for x in (args[args.index("--t7") + 1].split(",") if "--t7" in args else T7)]
    ban_file = CONTENT / f"ban_{lang}.txt"
    hard_ban = set()
    if ban_file.exists():
        hard_ban = {norm(w) for w in ban_file.read_text(encoding="utf-8").split()}
    use_count = {}
    puzzles = []
    plan = [("5", t5[i % len(t5)]) for i in range(n5)]
    # spread the 7x7s through the list
    for j in range(n7):
        plan.insert(min(len(plan), 4 + j * 5), ("7", t7[j % len(t7)]))
    for kind, name in plan:
        template = (T5 if kind == "5" else T7)[name]
        grid = None
        for attempt in range(80):
            # Unused words only at first; slowly allow words used once.
            limit = 0 if attempt < 40 else 1
            banned = hard_ban | {w for w, n in use_count.items() if n > limit}
            grid = fill(template, index, rng, banned, 4000 if kind == "5" else 12000)
            if grid:
                break
        if not grid:
            print(f"  FAILED {name}")
            continue
        for s in slots_of(template):
            w = "".join(grid[r][c] for r, c in s["cells"])
            use_count[w] = use_count.get(w, 0) + 1
        puzzles.append({"template": name, "grid": grid})
        print(f"  {len(puzzles):2d} {name:10s} {' '.join(grid)}")
    out = CONTENT / f"fills_{lang}.json"
    out.write_text(json.dumps(puzzles, ensure_ascii=False, indent=1), encoding="utf-8")
    reused = sorted(w for w, n in use_count.items() if n > 1)
    print(f"wrote {out} ({len(puzzles)} puzzles, {len(use_count)} distinct answers, reused: {reused})")


if __name__ == "__main__":
    main()

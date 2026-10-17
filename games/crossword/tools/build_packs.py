#!/usr/bin/env python3
"""Merge filled grids + hand-written clues into the shipped packs.

  python3 tools/build_packs.py        # writes data/puzzles_en.json, data/puzzles_es.json

Inputs: tools/content/fills_<lang>.json (from tools/fill.py) and
tools/content/clues_<lang>.txt ("ANSWER = clue" per line). Fails loudly on a
missing clue, a clue that contains its own answer, or a duplicate answer.
"""

import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "tools" / "content"


def strip(s: str) -> str:
    out = []
    for ch in s.upper():
        out.append(ch if ch == "Ñ" else unicodedata.normalize("NFD", ch)[0])
    return "".join(out)


def entries(grid):
    """Standard numbering. Returns [(dir, number, answer)]."""
    h, w = len(grid), len(grid[0])
    white = lambda r, c: 0 <= r < h and 0 <= c < w and grid[r][c] != "#"
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


def build(lang: str) -> int:
    fills = json.loads((CONTENT / f"fills_{lang}.json").read_text(encoding="utf-8"))
    clues = {}
    for line in (CONTENT / f"clues_{lang}.txt").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        k, v = line.split("=", 1)
        clues[strip(k.strip())] = v.strip()
    pack, errors = [], []
    for i, f in enumerate(fills):
        grid = f["grid"]
        p = {"id": f"{lang}-{i + 1:02d}", "grid": grid, "across": {}, "down": {}}
        seen = set()
        for d, n, ans in entries(grid):
            if ans in seen:
                errors.append(f"{p['id']}: duplicate {ans}")
            seen.add(ans)
            clue = clues.get(ans)
            if not clue:
                errors.append(f"{p['id']}: no clue for {ans}")
                continue
            words = re.findall(r"\w+", strip(clue))
            if ans in words:
                errors.append(f"{p['id']}: clue for {ans} contains the answer")
            p[d][str(n)] = clue
        pack.append(p)
    for e in errors:
        print("ERROR", e)
    out = ROOT / "data" / f"puzzles_{lang}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(pack, ensure_ascii=False, indent=0), encoding="utf-8")
    print(f"{lang}: {len(pack)} puzzles -> {out.relative_to(ROOT)}")
    return len(errors)


if __name__ == "__main__":
    sys.exit(1 if sum(build(l) for l in ("en", "es")) else 0)

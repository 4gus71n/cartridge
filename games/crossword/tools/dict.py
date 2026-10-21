#!/usr/bin/env python3
"""Builds the fill dictionary for Mini Crossword (offline authoring tool).

The shipped answers must all carry a hand-written clue, but a backtracking
crossword filler needs a far larger pool than the number of answers it places.
This script grows the pool from our own clued vocabulary without importing a
third-party word list into the game:

  * every clued answer (tools/content/vocab/<lang>_*.txt);
  * regular inflections of those answers (plural, -ED, -ING, -ER, -LY, ...),
    kept only when the result is a real word. For English that check uses the
    system word list /usr/share/dict/words (web2, Webster's Second
    International 1934, copyright lapsed -> public domain); for Spanish it uses
    our own hand-written list tools/content/words_es_bulk.txt, so nothing
    third-party is needed.
  * plus the hand-written bulk lists tools/content/words_<lang>_bulk.txt.

Output: tools/content/fillwords_<lang>.txt (one word per line, committed), and
it is cheap to regenerate.

  python3 tools/dict.py en
  python3 tools/dict.py all
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "tools" / "content"
WEB2 = pathlib.Path("/usr/share/dict/words")
VOWELS = set("AEIOU")

sys.path.insert(0, str(ROOT / "tools"))
from build import Vocab, norm, TIERS  # noqa: E402


def system_words():
    """Public-domain web2 list, upper-cased, 3-9 letters. Empty if absent."""
    if not WEB2.exists():
        return set()
    out = set()
    for line in WEB2.read_text(encoding="utf-8", errors="ignore").splitlines():
        w = line.strip()
        if 3 <= len(w) <= 9 and w.isascii() and w.isalpha() and w.islower():
            out.add(w.upper())
    return out


def bulk(lang: str):
    path = CONTENT / f"words_{lang}_bulk.txt"
    if not path.exists():
        return set()
    out = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        for tok in line.split("#", 1)[0].split():
            w = norm(tok)
            if 3 <= len(w) <= 9 and all(c.isalpha() for c in w):
                out.add(w)
    return out


def variants_en(w: str):
    """Regular English inflections of `w` (candidates, checked by the caller)."""
    out = {w + "S", w + "ES", w + "ED", w + "ING", w + "ER", w + "EST", w + "LY"}
    if w.endswith("E"):
        s = w[:-1]
        out |= {s + "ED", s + "ING", s + "ER", s + "EST"}
    if w.endswith("Y"):
        out |= {w[:-1] + "IES", w[:-1] + "IED", w[:-1] + "IER", w[:-1] + "IEST", w[:-1] + "ILY"}
    if len(w) >= 3 and w[-1] not in VOWELS and w[-2] in VOWELS and w[-3] not in VOWELS:
        out |= {w + w[-1] + "ED", w + w[-1] + "ING", w + w[-1] + "ER"}
    return {v for v in out if 3 <= len(v) <= 9}


def variants_es(w: str):
    """Regular Spanish forms that are always real words, so no dictionary is
    needed: plural, the feminine of an -O word, and the regular present /
    past participle / gerund of an -AR, -ER or -IR verb."""
    out = set()
    if w.endswith(("A", "E", "I", "O", "U")):
        out.add(w + "S")
    elif w.endswith(("D", "L", "N", "R", "S", "Z", "J")):
        out.add(w[:-1] + "CES" if w.endswith("Z") else w + "ES")
    if w.endswith("O"):
        out |= {w[:-1] + "A", w[:-1] + "AS", w[:-1] + "OS"}
    if len(w) > 3 and w.endswith(("AR", "ER", "IR")):
        stem, end = w[:-2], w[-2:]
        if end == "AR":
            out |= {stem + "A", stem + "AN", stem + "ABA", stem + "ADO",
                    stem + "ADA", stem + "ANDO", stem + "AMOS", stem + "ARON"}
        else:
            out |= {stem + "E", stem + "EN", stem + "IDO", stem + "IDA",
                    stem + "IENDO", stem + "IMOS", stem + "IERON"}
    return {v for v in out if 3 <= len(v) <= 9}


def build(lang: str) -> None:
    vocab = Vocab(lang)
    clued = set(vocab.short) | {w for t in TIERS for w in vocab.tier[t]}
    extra = bulk(lang)
    real = (system_words() if lang == "en" else set()) | clued | extra
    words = set(clued) | extra
    if lang == "en":
        for w in sorted(clued | extra):
            words |= {v for v in variants_en(w) if v in real}
    else:
        # Spanish morphology below is regular enough to trust on its own.
        for w in sorted(clued | extra):
            words |= variants_es(w)
    words = {w for w in words if 3 <= len(w) <= 9}
    out = CONTENT / f"fillwords_{lang}.txt"
    out.write_text("\n".join(sorted(words)) + "\n", encoding="utf-8")
    hist = {}
    for w in words:
        hist[len(w)] = hist.get(len(w), 0) + 1
    print(f"{lang}: {len(words)} fill words ({len(clued)} clued, {len(extra)} bulk) "
          f"{dict(sorted(hist.items()))} -> {out.name}")


if __name__ == "__main__":
    langs = ("en", "es") if (len(sys.argv) > 1 and sys.argv[1] == "all") else (sys.argv[1],)
    for lang in langs:
        build(lang)

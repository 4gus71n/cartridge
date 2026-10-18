#!/usr/bin/env python3
"""Babel Ear content pipeline: LibriVox (public domain) -> short Ogg clips.

Stdlib only (uses `certifi` for TLS roots when available; never disables
certificate verification). Run with any Python >= 3.9, e.g.
    ~/cartridge/backend/.venv/bin/python tools/curate.py discover
    ~/cartridge/backend/.venv/bin/python tools/curate.py cut
    <whisper venv>/bin/python tools/verify_lang.py      # optional QA, dev only
    ~/cartridge/backend/.venv/bin/python tools/curate.py build

Steps
  discover  Pull the LibriVox catalogue, pick candidate sections per language
            (long multi-section books, different readers), confirm each
            archive.org item carries a public-domain licence URL, and write the
            pinned list to tools/candidates.json.
  cut       For every candidate, download ~24 s from the middle of the 64 kbps
            MP3 with an HTTP Range request (no full download, skips the
            LibriVox intro/outro disclaimers), pick the most speech-dense
            5.5-7 s window that starts on a speech onset, normalise loudness
            (two-pass EBU R128), and encode mono Ogg Vorbis into the cache.
  build     Keep clips that passed QA (tools/lang_check.json, if present),
            cap per language, copy into content/audio/, and write
            content/clips.json + the clip table in CREDITS.md.

Cache dir: $BABEL_CACHE or $TMPDIR/babel-cache (never inside the repo).
"""

import json
import os
import pathlib
import random
import re
import shutil
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
CONTENT = ROOT / "content"
AUDIO = CONTENT / "audio"
CACHE = pathlib.Path(os.environ.get("BABEL_CACHE") or
                     (pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "babel-cache"))
FFMPEG = os.environ.get("FFMPEG") or str(
    pathlib.Path.home() / ".hermes/tools/ffmpeg-9.0.1-darwin-arm64/ffmpeg")
if not pathlib.Path(FFMPEG).exists():
    FFMPEG = shutil.which("ffmpeg") or "ffmpeg"

# Game language code -> LibriVox catalogue language name.
LANGS = {
    "en": "English", "de": "German", "nl": "Dutch", "sv": "Swedish", "da": "Danish",
    "es": "Spanish", "fr": "French", "it": "Italian", "pt": "Portuguese",
    "ca": "Catalan", "ro": "Romanian", "la": "Latin",
    "ru": "Russian", "pl": "Polish", "uk": "Ukrainian", "bg": "Bulgarian",
    "fi": "Finnish", "hu": "Hungarian", "el": "Greek",
    "zh": "Chinese", "ja": "Japanese", "ko": "Korean",
    "he": "Hebrew", "ar": "Arabic", "tl": "Tagalog", "hi": "Hindi", "eo": "Esperanto",
}
CANDIDATES_PER_LANG = 18
MAX_SECTIONS_PER_BOOK = 3
MIN_BOOK_SECS = 900
MIN_SECTION_SECS = 150
KEEP_PER_LANG = 10
WINDOW_SECS = 24
CLIP_MIN, CLIP_MAX = 5.5, 7.0
BYTES_PER_SEC = 8000  # LibriVox *_64kb.mp3 is 64 kbit/s CBR
OGG_BITRATE = "40k"
SEED = 20261016

try:
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # system roots
    _CTX = ssl.create_default_context()
UA = {"User-Agent": "cartridge-babel-ear-curator/1.0 (offline game content; agustin.tomas.larghi@gmail.com) python-urllib"}
POLITE_SLEEP = 1.5  # seconds between archive.org requests (strictly sequential)


def http_get(url, headers=None, retries=4):
    h = dict(UA)
    h.update(headers or {})
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, context=_CTX, timeout=90) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - network flakiness, retry
            if attempt == retries - 1:
                raise
            print(f"  retry {url[:80]}… ({e})", flush=True)
            time.sleep(2 + attempt * 3)


def get_json(url):
    return json.loads(http_get(url))


# --- discover ---------------------------------------------------------------

def catalogue():
    path = CACHE / "librivox_catalogue.json"
    if path.exists():
        return json.loads(path.read_text())
    books, off = [], 0
    fields = "{id,title,language,url_iarchive,url_librivox,totaltimesecs,num_sections}"
    while True:
        q = urllib.parse.urlencode({"format": "json", "limit": 500, "offset": off, "fields": fields})
        page = get_json("https://librivox.org/api/feed/audiobooks/?" + q).get("books", [])
        books += page
        off += 500
        print(f"catalogue: {len(books)}", flush=True)
        if len(page) < 500:
            break
    path.write_text(json.dumps(books))
    return books


def book_details(book_id):
    path = CACHE / "books" / f"{book_id}.json"
    if path.exists():
        return json.loads(path.read_text())
    d = get_json(f"https://librivox.org/api/feed/audiobooks/?id={book_id}&extended=1&format=json")
    b = d["books"][0]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(b))
    return b


def ia_license(identifier):
    path = CACHE / "ia" / f"{identifier}.json"
    if path.exists():
        meta = json.loads(path.read_text())
    else:
        meta = get_json(f"https://archive.org/metadata/{identifier}/metadata").get("result", {})
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(meta))
    return meta.get("licenseurl", "")


def is_public_domain(license_url):
    return "publicdomain" in license_url.replace("-", "").lower()


def discover():
    rng = random.Random(SEED)
    books = catalogue()
    out = []
    for code, lang in LANGS.items():
        pool = [b for b in books if b["language"] == lang and int(b.get("totaltimesecs") or 0) >= MIN_BOOK_SECS]
        rng.shuffle(pool)
        picked, readers_seen, spare = [], {}, []
        for b in pool:
            if len(picked) >= CANDIDATES_PER_LANG:
                break
            try:
                det = book_details(b["id"])
            except Exception as e:  # noqa: BLE001
                print(f"  skip book {b['id']}: {e}")
                continue
            genres = " ".join(g["name"] for g in det.get("genres") or [])
            if "Multi-version" in genres:
                continue  # weekly poetry: many non-native readers
            ident = det["url_iarchive"].rstrip("/").split("/")[-1]
            lic = ia_license(ident)
            if not is_public_domain(lic):
                print(f"  skip {ident}: licence '{lic}' not PD")
                continue
            secs = [s for s in det.get("sections") or []
                    if int(s.get("playtime") or 0) >= MIN_SECTION_SECS and s.get("listen_url")]
            rng.shuffle(secs)
            # Prefer readers we haven't used yet.
            secs.sort(key=lambda s: readers_seen.get(_reader(s), 0))
            authors = ", ".join(f"{a['first_name'].strip()} {a['last_name'].strip()}".strip()
                                for a in det.get("authors") or [])
            entries = [{
                "id": f"{code}_{s['id']}", "lang": code, "book_id": det["id"],
                "title": det["title"].strip(), "authors": authors,
                "reader": _reader(s), "section": s.get("title", "").strip(),
                "playtime": int(s["playtime"]), "listen_url": s["listen_url"],
                "librivox_url": det["url_librivox"], "archive_id": ident,
                "license_url": lic,
            } for s in secs]
            for e in entries[:MAX_SECTIONS_PER_BOOK]:
                if len(picked) >= CANDIDATES_PER_LANG:
                    break
                readers_seen[e["reader"]] = readers_seen.get(e["reader"], 0) + 1
                picked.append(e)
            spare += entries[MAX_SECTIONS_PER_BOOK:MAX_SECTIONS_PER_BOOK + 6]
        # Few books in this language: take more sections from the same books.
        while len(picked) < CANDIDATES_PER_LANG and spare:
            picked.append(spare.pop(0))
        print(f"{code} {lang}: {len(picked)} candidates from {len({p['book_id'] for p in picked})} books, "
              f"{len({p['reader'] for p in picked})} readers", flush=True)
        out += picked
    (TOOLS / "candidates.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))


def _reader(section):
    rs = section.get("readers") or []
    return ", ".join(r["display_name"] for r in rs) or "LibriVox volunteer"


# --- cut ----------------------------------------------------------------------

def ff(*args, capture=False):
    res = subprocess.run([FFMPEG, "-hide_banner", "-nostdin", "-y", *args],
                         capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(res.stderr[-600:])
    return res.stderr


def speech_segments(wav, total):
    """Return [(start, end)] of non-silent stretches using silencedetect."""
    log = ff("-i", str(wav), "-af", "silencedetect=noise=-38dB:d=0.22", "-f", "null", "-")
    starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    silences = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else total
        silences.append((max(0.0, s), e))
    segs, t = [], 0.0
    for s, e in silences:
        if s > t:
            segs.append((t, s))
        t = e
    if t < total:
        segs.append((t, total))
    return segs


def best_window(segs, total):
    """Pick (start, length): start on a speech onset, maximise speech ratio,
    prefer ending right after a speech segment ends (natural pause)."""
    best = None
    onsets = [s for s, _ in segs if s > 0.3 and s < total - CLIP_MIN]
    for st in onsets:
        for length in (CLIP_MAX, 6.5, 6.0, CLIP_MIN):
            en = st + length
            if en > total - 0.2:
                continue
            speech = sum(max(0.0, min(e, en) - max(s, st)) for s, e in segs)
            ratio = speech / length
            # Bonus when the cut lands in a pause (not mid-word).
            in_pause = not any(s < en < e for s, e in segs)
            score = ratio + (0.08 if in_pause else 0) + length * 0.01
            if best is None or score > best[0]:
                best = (score, st, length, ratio)
    return best


def peaks(wav_path, bins=64):
    import wave, array
    with wave.open(str(wav_path)) as w:
        data = array.array("h", w.readframes(w.getnframes()))
    n = max(1, len(data) // bins)
    vals = []
    for i in range(bins):
        chunk = data[i * n:(i + 1) * n]
        if not chunk:
            vals.append(0.0)
            continue
        vals.append((sum(x * x for x in chunk[::4]) / max(1, len(chunk[::4]))) ** 0.5)
    m = max(vals) or 1.0
    return [round(v / m, 3) for v in vals]


def cut_one(c, rng):
    work = CACHE / "work"
    work.mkdir(parents=True, exist_ok=True)
    clips = CACHE / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    cid = c["id"]
    ogg = clips / f"{cid}.ogg"
    meta_path = clips / f"{cid}.json"
    if meta_path.exists():
        return json.loads(meta_path.read_text())
    frac = rng.uniform(0.3, 0.7)
    start = max(60.0, min(c["playtime"] - 60.0, c["playtime"] * frac))  # skip the LibriVox intro
    off = int(start * BYTES_PER_SEC)
    raw = work / f"{cid}.mp3"
    if not raw.exists():
        data = http_get(c["listen_url"].replace("http://", "https://"),
                        {"Range": f"bytes={off}-{off + WINDOW_SECS * BYTES_PER_SEC}"})
        if len(data) > (WINDOW_SECS + 30) * BYTES_PER_SEC:
            raise RuntimeError("server ignored Range request")
        raw.write_bytes(data)
        time.sleep(POLITE_SLEEP)
    win = work / f"{cid}.win.wav"
    ff("-i", str(raw), "-ac", "1", "-ar", "16000", str(win))
    import wave
    with wave.open(str(win)) as w:
        total = w.getnframes() / w.getframerate()
    segs = speech_segments(win, total)
    # Read speech pauses every few seconds; music / noise beds barely do.
    pauses = max(0, len(segs) - 1)
    if pauses < max(3, int(total / 6)):
        raise RuntimeError(f"too few pauses ({pauses} in {total:.0f}s): music or noise bed?")
    vol = ff("-i", str(win), "-af", "volumedetect", "-f", "null", "-")
    mean_db = float(re.search(r"mean_volume: (-?[\d.]+) dB", vol).group(1))
    if mean_db < -40:
        raise RuntimeError(f"too quiet (mean {mean_db} dB)")
    pick = best_window(segs, total)
    if pick is None or pick[3] < 0.72:
        raise RuntimeError(f"not enough continuous speech (best={pick and round(pick[3], 2)})")
    _, st, length, ratio = pick
    # Two-pass loudness normalisation to -18 LUFS.
    trim = f"atrim={st:.3f}:{st + length:.3f},asetpts=N/SR/TB"
    m = ff("-i", str(win), "-af", f"{trim},loudnorm=I=-18:TP=-2:LRA=9:print_format=json", "-f", "null", "-")
    js = json.loads(m[m.rindex("{"):m.rindex("}") + 1])
    norm = (f"loudnorm=I=-18:TP=-2:LRA=9:measured_I={js['input_i']}:measured_TP={js['input_tp']}:"
            f"measured_LRA={js['input_lra']}:measured_thresh={js['input_thresh']}:offset={js['target_offset']}:linear=true")
    fade = f"afade=t=in:d=0.06,afade=t=out:st={length - 0.12:.3f}:d=0.12"
    clip_wav = clips / f"{cid}.wav"
    ff("-i", str(win), "-af", f"{trim},{norm},{fade}", "-ar", "16000", "-ac", "1", str(clip_wav))
    ff("-i", str(clip_wav), "-ar", "22050", "-ac", "1", "-c:a", "libvorbis", "-b:a", OGG_BITRATE,
       "-map_metadata", "-1", str(ogg))
    meta = dict(c)
    meta.update({"source_offset": round(start + st, 2), "duration": round(length, 2),
                 "speech_ratio": round(ratio, 3), "pauses": pauses, "mean_db": mean_db, "peaks": peaks(clip_wav), "bytes": ogg.stat().st_size})
    meta_path.write_text(json.dumps(meta, ensure_ascii=False))
    return meta


def cut():
    cands = json.loads((TOOLS / "candidates.json").read_text())
    # Round-robin across languages so a partial run is usable for every language.
    per = {}
    for c in cands:
        per.setdefault(c["lang"], []).append(c)
    order, k = [], 0
    while any(k < len(v) for v in per.values()):
        order += [v[k] for v in per.values() if k < len(v)]
        k += 1
    limit = int(os.environ.get("BABEL_CUT_PER_LANG", "99"))
    cands = [c for c in order if per[c["lang"]].index(c) < limit]
    ok = bad = 0
    for i, c in enumerate(cands):
        if (CACHE / "clips" / f"{c['id']}.fail").exists():
            continue
        rng = random.Random(f"{SEED}:{c['id']}")
        try:
            m = cut_one(c, rng)
            ok += 1
            print(f"[{i + 1}/{len(cands)}] {c['id']} ok {m['duration']}s speech={m['speech_ratio']}", flush=True)
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"[{i + 1}/{len(cands)}] {c['id']} FAIL {str(e)[:160]}", flush=True)
            (CACHE / "clips" / f"{c['id']}.fail").write_text(str(e))
    print(f"cut: {ok} ok, {bad} failed")


# --- build ----------------------------------------------------------------------

def build():
    cands = json.loads((TOOLS / "candidates.json").read_text())
    qa_path = TOOLS / "lang_check.json"
    qa = json.loads(qa_path.read_text()) if qa_path.exists() else {}
    overrides = json.loads((TOOLS / "overrides.json").read_text()) if (TOOLS / "overrides.json").exists() else {}
    min_clips = overrides.get("min_clips_per_language", 6)
    rejected = set(overrides.get("reject", []))
    dropped_langs = set(overrides.get("drop_languages", []))
    by_lang = {}
    for c in cands:
        mp = CACHE / "clips" / f"{c['id']}.json"
        if not mp.exists() or c["id"] in rejected or c["lang"] in dropped_langs:
            continue
        q = qa.get(c["id"])
        if qa and (q is None or not q.get("accept")):
            continue
        meta = json.loads(mp.read_text())
        by_lang.setdefault(c["lang"], []).append(meta)
    if AUDIO.exists():
        shutil.rmtree(AUDIO)
    AUDIO.mkdir(parents=True)
    clips, report = [], []
    for code in LANGS:
        pool = by_lang.get(code, [])
        # Round-robin across readers so one voice doesn't dominate.
        by_reader = {}
        for m in sorted(pool, key=lambda m: -m["speech_ratio"]):
            by_reader.setdefault(m["reader"], []).append(m)
        chosen = []
        while len(chosen) < KEEP_PER_LANG and any(by_reader.values()):
            for r in list(by_reader):
                if by_reader[r] and len(chosen) < KEEP_PER_LANG:
                    chosen.append(by_reader[r].pop(0))
        if len(chosen) < min_clips:
            report.append(f"drop {code}: only {len(chosen)} clean clips")
            continue
        for n, m in enumerate(chosen):
            fname = f"{code}_{n + 1:02d}.ogg"
            shutil.copy(CACHE / "clips" / f"{m['id']}.ogg", AUDIO / fname)
            clips.append({
                "id": f"{code}_{n + 1:02d}", "language": code, "file": f"audio/{fname}",
                "duration": m["duration"], "peaks": m["peaks"],
                "book": m["title"], "author": m["authors"], "reader": m["reader"],
                # The game ships only Godot's default font (Latin/Greek/Cyrillic),
                # so in-game credits use a display-safe version of each string.
                "book_display": display_safe(m["title"], "LibriVox #" + str(m["book_id"])),
                "author_display": display_safe(m["authors"], ""),
                "reader_display": display_safe(m["reader"], "LibriVox volunteer"),
                "section": m["section"], "url": m["librivox_url"],
                "audio_url": m["listen_url"], "source_offset_s": m["source_offset"],
                "archive_id": m["archive_id"], "license": "Public domain (LibriVox)",
                "license_url": m["license_url"],
            })
        report.append(f"{code}: {len(chosen)} clips, {len({m['reader'] for m in chosen})} readers")
    manifest = {"version": 1, "source": "LibriVox (librivox.org) via archive.org",
                "license_note": "All LibriVox recordings are dedicated to the public domain.",
                "clips": clips}
    (CONTENT / "clips.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    total = sum(p.stat().st_size for p in AUDIO.glob("*.ogg"))
    print("\n".join(report))
    print(f"build: {len(clips)} clips, {len({c['language'] for c in clips})} languages, {total / 1e6:.2f} MB")
    write_credits(clips)


_TRANSLIT = {"\u02bf": "'", "\u02be": "'", "\u2019": "'", "\u2018": "'", "\u201c": '"', "\u201d": '"',
             "\u2013": "-", "\u2014": "-", "\u2026": "...", "\uff1a": ":", "\u00b7": "-"}


def _font_ok(ch):
    o = ord(ch)
    return o <= 0x24F or 0x370 <= o <= 0x3FF or 0x400 <= o <= 0x4FF


def display_safe(text, fallback):
    """Keep only what Godot's default font can draw (Latin, Greek, Cyrillic).
    Prefer an all-Latin parenthetical ('阿Q正傳 (The True Story of Ah Q)')."""
    t = "".join(_TRANSLIT.get(ch, ch) for ch in str(text)).strip()
    if all(_font_ok(ch) for ch in t):
        return re.sub(r"\s+", " ", t)
    groups = [g.strip() for g in re.findall(r"[(\[]([^()\[\]]+)[)\]]", t)]
    groups = [g for g in groups if g and all(_font_ok(ch) for ch in g) and re.search(r"[A-Za-z]", g)]
    if groups:
        return " - ".join(groups)
    toks = [w for w in re.split(r"\s+", re.sub(r"[()\[\]]", " ", t)) if w and all(_font_ok(ch) for ch in w)]
    out = " ".join(toks).strip(" -:/,")
    return out if re.search(r"[A-Za-z]", out) else fallback


def write_credits(clips):
    path = ROOT / "CREDITS.md"
    head = path.read_text().split("<!-- CLIPS -->")[0] if path.exists() else "# Credits\n\n"
    lines = [head.rstrip() + "\n\n<!-- CLIPS -->\n",
             "| Clip | Language | Work | Author | Reader | Section | Source | Licence |",
             "|---|---|---|---|---|---|---|---|"]
    for c in clips:
        esc = lambda s: str(s).replace("|", "/")  # noqa: E731
        lines.append(f"| {c['id']} | {c['language']} | {esc(c['book'])} | {esc(c['author'])} | {esc(c['reader'])} | "
                     f"{esc(c['section'])} (at {c['source_offset_s']:.0f} s) | [LibriVox]({c['url']}) · "
                     f"[audio]({c['audio_url']}) | [Public domain]({c['license_url']}) |")
    path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    CACHE.mkdir(parents=True, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"discover": discover, "cut": cut, "build": build}.get(cmd, lambda: print(__doc__))()

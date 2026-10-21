"""Optional step 3b: automatic screening of the encoded photos.

Usage: python tools/screen_photos.py [--write]

Looks at the encoded WebP files (in $PINPOINT_WORK/webp) and flags images that
the keyword filter cannot catch: near-monochrome scans, flat diagram/map-like
graphics, very low-detail (blurred or foggy) frames, and frames that are mostly
one flat colour (sky-only, white documents). With --write the flagged ids are
appended to tools/rejects.txt with a reason comment, so the manual contact
sheet review only has to deal with what is left.

Needs Pillow; run it with a venv that has it, e.g.
  $PINPOINT_WORK/venv/bin/python tools/screen_photos.py --write
"""

import collections
import json
import os
import pathlib
import sys

from PIL import Image, ImageFilter, ImageStat

ROOT = pathlib.Path(__file__).resolve().parent.parent
CANDIDATES = ROOT / "tools/content/candidates.json"
REJECTS = ROOT / "tools/rejects.txt"
WORK = pathlib.Path(os.environ.get("PINPOINT_WORK")
                    or (pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"))
WEBP = WORK / "webp"

MIN_SATURATION = 9.0      # mean saturation: below this it is effectively grey
MIN_DETAIL = 7.0          # edge energy: below this it is blurred / foggy
MAX_FLAT_SHARE = 0.62     # share of pixels in the single most common tone
MIN_COLOURS = 2500        # distinct quantised colours: fewer = graphic / diagram


def measure(path):
    img = Image.open(path).convert("RGB")
    img.thumbnail((360, 360))
    hsv = img.convert("HSV")
    sat = ImageStat.Stat(hsv.getchannel("S")).mean[0]
    grey = img.convert("L")
    detail = ImageStat.Stat(grey.filter(ImageFilter.FIND_EDGES)).stddev[0]
    hist = grey.histogram()
    flat = max(hist) / float(sum(hist))
    colours = len(img.quantize(colors=256).convert("RGB").getcolors(60000) or [])
    distinct = len(img.getcolors(maxcolors=200000) or [])
    return {"sat": sat, "detail": detail, "flat": flat, "colours": colours,
            "distinct": distinct}


def verdict(m):
    if m["sat"] < MIN_SATURATION:
        return "grey/monochrome"
    if m["detail"] < MIN_DETAIL:
        return "low detail"
    if m["flat"] > MAX_FLAT_SHARE:
        return "mostly flat"
    if m["distinct"] < MIN_COLOURS:
        return "graphic/diagram"
    return ""


def main():
    write = "--write" in sys.argv
    cands = json.loads(CANDIDATES.read_text())
    flagged, reasons = [], collections.Counter()
    for c in cands:
        path = WEBP / f"{c['id']}.webp"
        if not path.exists():
            continue
        try:
            why = verdict(measure(path))
        except Exception as e:  # noqa: BLE001
            why = "unreadable"
            print("  ", c["id"], repr(e), file=sys.stderr)
        if why:
            flagged.append((c["id"], why))
            reasons[why] += 1
    print(f"{len(flagged)} of {len(cands)} flagged: {dict(reasons)}")
    for cid, why in flagged[:20]:
        print("  ", cid, why)
    if write:
        existing = set()
        if REJECTS.exists():
            existing = {ln.split("#")[0].strip() for ln in REJECTS.read_text().splitlines()}
        with REJECTS.open("a", encoding="utf-8") as f:
            f.write("\n# --- automatic screening (tools/screen_photos.py)\n")
            for cid, why in flagged:
                if cid not in existing:
                    f.write(f"{cid}  # {why}\n")
        print("appended to", REJECTS)


if __name__ == "__main__":
    main()

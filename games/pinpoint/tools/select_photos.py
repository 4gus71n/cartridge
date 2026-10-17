"""Step 2 of photo curation: filter + rank the cached Commons candidates.

Usage: python tools/select_photos.py [per_seed=2]

Reads $TMPDIR/pinpoint-work/cache/*.json (from fetch_candidates.py) and keeps
only files that are:
  * licensed CC0 / Public domain / CC BY 4.0 / 3.0 / 2.0 (everything else,
    notably CC BY-SA, GFDL, NC and "Attribution"-only, is rejected),
  * JPEG photos, landscape (aspect 1.25-2.1), >= 1200 px wide,
  * camera-geotagged ({{Location}} GPS in the description page),
  * without restrictions (personality rights, trademarks, ...),
  * not obviously indoor / close-up / people / text (keyword filter on the
    title and categories).
Ranks by Featured > Quality > Valued + landscape-ish keywords and writes the
best `per_seed` per seed to $TMPDIR/pinpoint-work/candidates.json.
The visual pass (contact sheet + manual reject list) happens afterwards.
"""

import html
import json
import os
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from seeds import SEEDS  # noqa: E402
import geo  # noqa: E402

SCRATCH = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"
CACHE = SCRATCH / "cache"
ALLOWED = {"CC0": "CC0", "Public domain": "Public domain", "CC BY 4.0": "CC BY 4.0",
           "CC BY 3.0": "CC BY 3.0", "CC BY 2.0": "CC BY 2.0"}
LICENSE_CODES = {"cc0", "pd", "cc-by-4.0", "cc-by-3.0", "cc-by-2.0"}
REJECT = re.compile(
    r"interior|inside|indoor|museum|exhibit|collection|painting|fresco|mosaic|icon\b|altar|nave|ceiling|"
    r"organ\b|stained|window|food|dish|cuisine|restaurant|menu|meal|dessert|drink|beer|wine|coffee|"
    r"portrait|people|person|selfie|woman|women|\bman\b|\bmen\b|child|girl|boy|wedding|actor|politic|"
    r"player|athlet|football|soccer|match|concert|performance|protest|demonstration|parade|conference|"
    r"logo|\bmap\b|maps\b|plan\b|diagram|\bsign\b|signs\b|signage|plaque|inscription|graffiti|poster|"
    r"advert|document|book|manuscript|coin|stamp|banknote|"
    r"insect|butterfl|moth|bee\b|spider|beetle|dragonfl|bird|aves\b|animal|mammal|dog|cat\b|cats\b|"
    r"horse|cow|captive|zoo\b|aquarium|flower|blossom|plant|leaf|leaves|fung|mushroom|macro|close-up|"
    r"closeup|detail|texture|\bcar\b|cars\b|automobile|vehicle|truck|\bbus\b|buses|tram|train|locomotive|"
    r"railcar|aircraft|airplane|aeroplane|airliner|boeing|airbus|helicopter|motorcycle|bicycle|"
    r"at night|by night|night view|\bnight\b|nocturn|fireworks|statue|sculpture|bust\b|grave|tomb|"
    r"cemetery|memorial plaque|lamp|shop window|mannequin|x-ray|microscop|screenshot|drawing|engraving|"
    r"lithograph|postcard|historical image|\b1[89]\d\d\b|black and white|monochrome|aerial|satellite|"
    r"iss0|nasa|from space|astronaut|panorama|360",
    re.I)
GOOD = re.compile(r"landscape|skyline|cityscape|street|view|beach|coast|mountain|village|square|plaza|"
                  r"harbou?r|port\b|river|lake|valley|canyon|desert|old town|town|bridge|market|"
                  r"waterfall|glacier|fjord|island|bay\b|hill|temple|mosque|church|castle|fort", re.I)


def strip_html(s):
    s = re.sub(r"<[^>]+>", " ", s or "")
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip()


def meta(m, key):
    v = m.get(key, {})
    return v.get("value", "") if isinstance(v, dict) else ""


def clean_author(raw):
    a = strip_html(raw)
    a = re.sub(r"\s*\(talk\)|\s*\(contribs?\)", "", a)
    a = re.sub(r"\bfrom\s+\S+(\s+\S+)?,?\s*(USA|UK)?$", "", a).strip(" ,;")
    if len(a) > 60:
        a = a[:57].rstrip() + "..."
    return a


def evaluate(page, seed):
    ii = (page.get("imageinfo") or [None])[0]
    if not ii:
        return None, "no imageinfo"
    m = ii.get("extmetadata", {})
    lic = meta(m, "LicenseShortName").strip()
    code = meta(m, "License").strip().lower()
    if lic not in ALLOWED or (code and code not in LICENSE_CODES):
        return None, "license"
    if meta(m, "Restrictions").strip():
        return None, "restrictions"
    if ii.get("mime") != "image/jpeg":
        return None, "mime"
    w, h = ii.get("width", 0), ii.get("height", 0)
    if w < 1200 or not (1.25 <= w / max(h, 1) <= 2.1):
        return None, "shape"
    try:
        lat = float(meta(m, "GPSLatitude"))
        lon = float(meta(m, "GPSLongitude"))
    except ValueError:
        return None, "no gps"
    if geo.haversine_km(lat, lon, seed[1], seed[2]) > 15:
        return None, "far"
    title = page["title"]
    cats = meta(m, "Categories")
    text = title + " | " + cats + " | " + strip_html(meta(m, "ObjectName"))
    if REJECT.search(text):
        return None, "keyword"
    author = clean_author(meta(m, "Artist"))
    if not author or "unknown" in author.lower():
        return None, "author"
    score = 0
    if "Featured pictures" in cats:
        score += 6
    if "Quality images" in cats:
        score += 4
    if "Valued images" in cats:
        score += 2
    score += min(3, len(GOOD.findall(text)))
    score += min(2, w / 3000)
    return {
        "title": title, "pageid": page["pageid"], "lat": round(lat, 5), "lon": round(lon, 5),
        "license": ALLOWED[lic], "license_url": meta(m, "LicenseUrl"), "author": author,
        "thumb": ii.get("thumburl", ""), "width": w, "height": h, "score": round(score, 2),
        "source": "https://commons.wikimedia.org/wiki/" + title.replace(" ", "_"),
    }, "ok"


def slug(label):
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def main():
    per_seed = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    out, stats = [], {}
    for seed in SEEDS:
        path = CACHE / f"{slug(seed[0])}.json"
        if not path.exists():
            stats["missing seed"] = stats.get("missing seed", 0) + 1
            continue
        pages = json.loads(path.read_text())["pages"]
        extra = CACHE / f"search_{slug(seed[0])}.json"
        if extra.exists():
            seen = {p["pageid"] for p in pages}
            pages += [p for p in json.loads(extra.read_text())["pages"] if p["pageid"] not in seen]
        good = []
        for p in pages:
            c, why = evaluate(p, seed)
            stats[why] = stats.get(why, 0) + 1
            if c:
                good.append(c)
        good.sort(key=lambda c: -c["score"])
        picked = []
        for c in good:
            # Avoid near-duplicates (same spot, same photographer).
            if any(geo.haversine_km(c["lat"], c["lon"], q["lat"], q["lon"]) < 0.3 or q["author"] == c["author"]
                   for q in picked):
                continue
            picked.append(c)
            if len(picked) >= per_seed:
                break
        for i, c in enumerate(picked):
            c["seed"] = seed[0]
            c["id"] = f"{slug(seed[0]).replace('_', '-')}-{i + 1}"
            out.append(c)
    (SCRATCH / "candidates.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(len(out), "candidates;", json.dumps(stats))


if __name__ == "__main__":
    main()

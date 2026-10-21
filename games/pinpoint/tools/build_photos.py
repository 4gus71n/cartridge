"""Steps 3-4 of photo curation: download, recompress, review, finalize.

  python tools/build_photos.py download   # Commons thumbs -> work/raw, cwebp -> work/webp
  python tools/build_photos.py finalize   # -> content/photos/*.webp, content/photos.json, CREDITS.md

`download` is sequential and polite (descriptive User-Agent with a contact
address, >= DELAY s between requests, Retry-After / exponential backoff on
429/5xx) and fully resumable: files already on disk are skipped, so a
restarted run refetches nothing. The work directory is $PINPOINT_WORK (default
$TMPDIR/pinpoint-work).

Each image is re-encoded to WebP with the quality tuned per image so it lands
under TARGET_KB; that is what keeps 600+ photos inside the package budget.

Between the two steps, review the contact sheets (tools/contact_sheet.gd) and
list rejected ids, one per line, in tools/rejects.txt (indoor, close-ups,
people, text giveaways, duplicates, poor quality).

`finalize` assigns every photo its country by point-in-polygon on the same
simplified Natural Earth polygons the game uses (content/world.json/.bin);
coastal points that fall in the simplified sea snap to the nearest country
within 30 km. It also enforces the pack limits (<= MAX_PER_COUNTRY per
country, <= MAX_PER_PLACE per place) and writes the difficulty tag.
"""

import collections
import json
import os
import pathlib
import shutil
import ssl
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import geo  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CANDIDATES = ROOT / "tools/content/candidates.json"
WORK = pathlib.Path(os.environ.get("PINPOINT_WORK")
                    or (pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"))
RAW = WORK / "raw"
WEBP = WORK / "webp"
UA = ("CartridgePinpoint/1.1 (https://github.com/4gus71n/cartridge; "
      "agustin.tomas.larghi@gmail.com) python-urllib")
THUMB_PX = 1280          # source thumb width asked from Commons (the only
                         # width upload.wikimedia.org still renders on demand)
LONG_SIDE = 760          # preferred final long edge in the game
SIZE_STEPS = [760, 680, 600]
TARGET_KB = 22           # aim per photo (850+ photos must fit ~19 MB)
MAX_KB = 34              # hard ceiling per photo
QUALITY_STEPS = [68, 58, 50, 43, 36, 30]
DELAY = 0.45
MAX_PER_COUNTRY = 8
MAX_PER_PLACE = 2
try:
    import certifi
    SSL = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover
    SSL = ssl.create_default_context()

# Display names for seeds whose label is a search hint, not a place name.
PLACE = {
    "Pyrenees Ordesa": "Ordesa Valley", "Provence Gordes": "Gordes", "Bavaria Alps": "Füssen",
    "Iceland Vik": "Vík", "Iceland Jokulsarlon": "Jökulsárlón", "Transylvania Sibiu": "Sibiu",
    "Malta Valletta": "Valletta", "Bishkek Issyk": "Issyk-Kul", "Kerala Alleppey": "Alappuzha",
    "Leh Ladakh": "Leh", "Sri Lanka Ella": "Ella", "Hokkaido Biei": "Biei",
    "Guilin Yangshuo": "Yangshuo", "Bali Ubud": "Ubud", "Bromo": "Mount Bromo",
    "Palawan El Nido": "El Nido", "Borneo Kinabalu": "Kinabalu", "Sahara Merzouga": "Merzouga",
    "Cairo Giza": "Giza", "Timbuktu Djenne": "Djenné", "Namib Sossusvlei": "Sossusvlei",
    "Madagascar Morondava": "Morondava", "Mauritius": "Port Louis", "Cape Verde": "Mindelo",
    "Texas Austin": "Austin", "Denver Rockies": "Denver", "Alaska Denali": "Denali",
    "Hawaii Oahu": "Oahu", "Nova Scotia": "Halifax", "Nunavut Iqaluit": "Iqaluit",
    "Greenland Nuuk": "Nuuk", "Greenland Ilulissat": "Ilulissat", "Yucatan Merida": "Mérida",
    "Costa Rica Arenal": "Arenal", "San Jose Costa Rica": "San José", "San Juan PR": "San Juan",
    "Jamaica": "Kingston", "Dominican Rep": "Santo Domingo", "Kimberley Broome": "Broome",
    "Queenstown NZ": "Queenstown", "Fiji Suva": "Suva", "Samoa Apia": "Apia",
    "New Caledonia": "Nouméa", "Antarctic Peninsula Paradise": "Paradise Harbour",
    "McMurdo": "McMurdo Station", "Svalbard": "Longyearbyen",
    "Atacama": "San Pedro de Atacama", "Galapagos": "Galápagos", "Okavango": "Okavango Delta",
    "Washington DC": "Washington, D.C.", "Zanzibar": "Stone Town", "Tasmania": "Hobart",
    "Maasai Mara": "Maasai Mara", "King George Island": "King George Island",
    "Agra Taj Mahal": "Agra", "Mount Fuji Hakone": "Hakone", "Shiraz Persepolis": "Shiraz",
    "Everest Namche": "Namche Bazaar", "Male Maldives": "Malé", "Goa Panaji": "Panaji",
    "Penang George Town": "George Town", "Yogyakarta Borobudur": "Borobudur",
    "Komodo Labuan Bajo": "Labuan Bajo", "Sumatra Lake Toba": "Lake Toba",
    "Tripoli Libya": "Tripoli", "Lake Malawi Cape Maclear": "Cape Maclear",
    "Victoria Seychelles": "Victoria", "Moroni Comoros": "Moroni", "Sao Tome": "São Tomé",
    "Faroe Torshavn": "Tórshavn", "Azores Ponta Delgada": "Ponta Delgada",
    "Madeira Funchal": "Funchal", "Algarve Lagos": "Lagos", "Tenerife Teide": "Teide",
    "Corsica Bonifacio": "Bonifacio", "Sicily Taormina": "Taormina",
    "Sardinia Alghero": "Alghero", "Bath England": "Bath", "Cornwall St Ives": "St Ives",
    "Crete Chania": "Chania", "High Tatras": "High Tatras", "Dead Sea Masada": "Masada",
    "Gobi Dalanzadgad": "Dalanzadgad", "Pamir Khorog": "Khorog", "Charyn Canyon": "Charyn",
    "Song Kol": "Song-Kul", "Taroko Hualien": "Taroko", "Granada Nicaragua": "Granada",
    "Trinidad Cuba": "Trinidad", "Merida Venezuela": "Mérida",
    "Georgetown Guyana": "Georgetown", "Banos Ecuador": "Baños",
    "Lake Titicaca Puno": "Puno", "Easter Island": "Easter Island",
    "Stanley Falklands": "Stanley", "Lencois Maranhenses": "Lençóis Maranhenses",
    "St Georges Grenada": "St. George's", "Saint Johns Antigua": "St. John's",
    "Oranjestad Aruba": "Oranjestad", "Hamilton Bermuda": "Hamilton",
    "Hagatna Guam": "Hagåtña", "Palikir Pohnpei": "Palikir", "Koror Palau": "Koror",
    "Yaren Nauru": "Yaren", "Alofi Niue": "Alofi", "Rarotonga": "Rarotonga",
    "Nukualofa": "Nuku'alofa", "South Georgia Grytviken": "Grytviken",
    "Saint-Louis Senegal": "Saint-Louis", "Ilha de Mocambique": "Ilha de Moçambique",
    "Great Ocean Road": "Great Ocean Road", "Mount Hagen": "Mount Hagen",
    "Lake Baikal": "Lake Baikal", "Lake Balaton": "Lake Balaton", "Lake Bled": "Bled",
    "Lake Atitlan": "Lake Atitlán", "Cabo San Lucas": "Cabo San Lucas",
}
CONTINENT = {"North America": "NA", "South America": "SA", "Europe": "EU", "Asia": "AS",
             "Africa": "AF", "Oceania": "OC", "Antarctica": "AN",
             "Seven seas (open ocean)": "OC"}


def thumb_urls(c):
    """Candidate download URLs for a Commons file, best first."""
    url = c["url"].split("?")[0]
    if "/commons/" not in url:
        return []
    head, tail = url.split("/commons/", 1)
    name = tail.rsplit("/", 1)[-1]
    return [f"{head}/commons/thumb/{tail}/{THUMB_PX}px-{name}", url]


def fetch(url, dest):
    for attempt in range(6):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=90, context=SSL) as r:
                data = r.read()
            if len(data) < 2000:
                return False
            dest.write_bytes(data)
            return True
        except urllib.error.HTTPError as e:
            if e.code in (400, 403, 404):
                print("  http", e.code, url, file=sys.stderr, flush=True)
                return False
            wait = int(e.headers.get("Retry-After") or 0) or min(120, 15 * (2 ** attempt))
            print("  retry", attempt, e.code, "wait", wait, file=sys.stderr, flush=True)
            time.sleep(wait)
        except Exception as e:  # noqa: BLE001
            print("  retry", attempt, repr(e), file=sys.stderr, flush=True)
            time.sleep(3 + 3 * attempt)
    return False


def encode(src, dest):
    """WebP-encode `src` as small as the budget needs while keeping it sharp.

    Tries decreasing quality at the preferred size, then smaller sizes: the
    first encode at or under TARGET_KB wins, otherwise the smallest result at
    or under MAX_KB. Detailed city scenes need the lower rungs; most photos
    land on the first one. Returns the final byte size, or 0 on failure.
    """
    tmp = dest.with_suffix(".tmp.webp")
    fallback = None            # (size, bytes) best <= MAX_KB seen so far
    for side in SIZE_STEPS:
        for q in QUALITY_STEPS:
            r = subprocess.run(["cwebp", "-quiet", "-q", str(q), "-m", "6", "-sharp_yuv",
                                "-resize", str(side), "0", str(src), "-o", str(tmp)],
                               capture_output=True)
            if r.returncode != 0 or not tmp.exists():
                return 0
            size = tmp.stat().st_size
            if size <= TARGET_KB * 1024:
                tmp.replace(dest)
                return size
            if size <= MAX_KB * 1024 and (fallback is None or size < fallback[0]):
                fallback = (size, tmp.read_bytes())
            tmp.unlink(missing_ok=True)
    if fallback:
        dest.write_bytes(fallback[1])
        return fallback[0]
    return 0


def download():
    cands = json.loads(CANDIDATES.read_text())
    RAW.mkdir(parents=True, exist_ok=True)
    WEBP.mkdir(parents=True, exist_ok=True)
    ok = fail = 0
    for i, c in enumerate(cands):
        raw = RAW / f"{c['id']}.{'png' if c.get('mime') == 'image/png' else 'jpg'}"
        out = WEBP / f"{c['id']}.webp"
        if out.exists():
            ok += 1
            continue
        if not raw.exists():
            urls = thumb_urls(c)
            if not urls:
                print("  no url", c["id"], file=sys.stderr)
                fail += 1
                continue
            got = False
            for u in urls:
                got = fetch(urllib.parse.quote(u, safe=":/%"), raw)
                time.sleep(DELAY)
                if got:
                    break
            if not got:
                fail += 1
                continue
        size = encode(raw, out)
        if size == 0:
            print("  encode failed", c["id"], file=sys.stderr)
            fail += 1
            continue
        ok += 1
        if (i + 1) % 25 == 0:
            print(f"[{i + 1}/{len(cands)}] ok={ok} fail={fail} last={size // 1024} KB", flush=True)
    print(f"download done: {ok} encoded, {fail} failed, of {len(cands)} candidates", flush=True)


def load_world():
    meta = json.loads((ROOT / "content/world.json").read_text())
    raw = (ROOT / "content/world.bin").read_bytes()
    pts = [struct.unpack_from("<ff", raw, i * 8) for i in range(len(raw) // 8)]
    for c in meta["countries"]:
        c["ring_pts"] = [pts[s:s + n] for s, n in c["rings"]]
    return meta["countries"]


def country_of(lat, lon, countries):
    """Same rule as WorldData.country_at: inside a polygon, else nearest <= 30 km."""
    for c in sorted(countries, key=lambda c: c["area"]):
        x0, y0, x1, y1 = c["bbox"]
        if not (x0 - 0.01 <= lon <= x1 + 0.01 and y0 - 0.01 <= lat <= y1 + 0.01):
            continue
        if any(geo.point_in_ring(lon, lat, r) for r in c["ring_pts"]):
            return c, 0.0
    best, best_d = None, 30.0
    for c in countries:
        x0, y0, x1, y1 = c["bbox"]
        if not (x0 - 1 <= lon <= x1 + 1 and y0 - 1 <= lat <= y1 + 1):
            continue
        for r in c["ring_pts"]:
            d = geo.dist_point_ring_km(lat, lon, r)
            if d < best_d:
                best, best_d = c, d
    return best, best_d


def finalize():
    cands = json.loads(CANDIDATES.read_text())
    rej_path = ROOT / "tools/rejects.txt"
    rejects = set()
    if rej_path.exists():
        rejects = {ln.split("#")[0].strip() for ln in rej_path.read_text().splitlines()} - {""}
    countries = load_world()
    out_dir = ROOT / "content/photos"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    # Best (highest score) first so the caps keep the best photos.
    cands = sorted(cands, key=lambda c: (-float(c.get("score") or 0), c["id"]))
    photos, total = [], 0
    per_country, per_place, skipped = collections.Counter(), collections.Counter(), collections.Counter()
    for c in cands:
        src = WEBP / f"{c['id']}.webp"
        if c["id"] in rejects:
            skipped["rejected"] += 1
            continue
        if not src.exists():
            skipped["no file"] += 1
            continue
        country, d = country_of(c["lat"], c["lon"], countries)
        if country is None:
            skipped["no country"] += 1
            continue
        place = PLACE.get(c["seed"], c["seed"])
        if per_country[country["k"]] >= MAX_PER_COUNTRY:
            skipped["country cap"] += 1
            continue
        if per_place[place] >= MAX_PER_PLACE:
            skipped["place cap"] += 1
            continue
        size = src.stat().st_size
        if size > MAX_KB * 1024:
            skipped["too big"] += 1
            continue
        per_country[country["k"]] += 1
        per_place[place] += 1
        shutil.copy(src, out_dir / src.name)
        (out_dir / (src.name + ".import")).write_text('[remap]\n\nimporter="keep"\n')
        total += size
        # Public-domain Commons uploads (mostly US-government works) often carry no
        # licence URL; point at the standard PD mark instead of leaving it blank.
        license_url = c["license_url"] or (
            "https://creativecommons.org/publicdomain/mark/1.0/" if c["license"] == "Public domain" else ""
        )
        photos.append({
            "id": c["id"], "file": src.name, "lat": c["lat"], "lon": c["lon"],
            "country": country["k"], "continent": CONTINENT.get(country.get("cont", ""), "??"),
            "place": place, "difficulty": c.get("difficulty", "medium"),
            "author": c["author"], "license": c["license"],
            "license_url": license_url, "source": c["source"],
            "title": c["title"][5:] if c["title"].startswith("File:") else c["title"],
        })
    photos.sort(key=lambda p: p["id"])
    (ROOT / "content/photos.json").write_text(
        json.dumps({"photos": photos}, ensure_ascii=False, indent=1))
    lic_counts = collections.Counter(p["license"] for p in photos)
    conts = collections.Counter(p["continent"] for p in photos)
    lines = [
        "# Pinpoint credits", "",
        "Game code: Cartridge Studio (all rights reserved).", "",
        "## World map", "",
        "Country polygons: [Natural Earth](https://www.naturalearthdata.com/) 1:50m Admin 0 - Countries, "
        "public domain. Simplified by `tools/build_map.py`.", "",
        "## Photos", "",
        f"{len(photos)} photos from [Wikimedia Commons](https://commons.wikimedia.org/), each used under the "
        "licence shown. Only CC0, public domain and CC BY 2.0/2.5/3.0/4.0 are accepted - CC BY-SA, GFDL, "
        "NC and ND files are rejected by `tools/fetch_candidates.py`, again by `tools/select_photos.py` "
        f"and once more by `PhotoDeck.validate()`. Licence breakdown: "
        + ", ".join(f"{k} x{v}" for k, v in sorted(lic_counts.items())) + ". "
        f"Every photo was resized to {LONG_SIDE} px on the long side and recompressed as WebP; no other "
        "changes. The game shows the author and licence after each round and lists all of them on the "
        "in-game Credits screen.", "",
        "| Photo | Place | Country | Author | Licence | Source |", "|---|---|---|---|---|---|",
    ]
    for p in photos:
        lic = f"[{p['license']}]({p['license_url']})" if p["license_url"] else p["license"]
        title = p["title"].replace("|", "/")
        lines.append(f"| `{p['file']}` | {p['place'] or p['country']} | {p['country']} | "
                     f"{p['author'].replace('|', '/')} | {lic} | [{title}]({p['source']}) |")
    (ROOT / "CREDITS.md").write_text("\n".join(lines) + "\n")
    print(f"{len(photos)} photos, {len(per_country)} countries, {total / 1e6:.2f} MB, "
          f"avg {total / max(1, len(photos)) / 1024:.0f} KB")
    print("  continents:", dict(conts))
    print("  difficulty:", dict(collections.Counter(p["difficulty"] for p in photos)))
    print("  licences:", dict(lic_counts))
    print("  skipped:", dict(skipped))


if __name__ == "__main__":
    {"download": download, "finalize": finalize}[sys.argv[1]]()

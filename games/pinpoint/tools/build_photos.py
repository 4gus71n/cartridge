"""Steps 3-4 of photo curation: download, recompress, review, finalize.

  python tools/build_photos.py download   # 960px thumbs -> scratch/raw, cwebp -> scratch/webp
  python tools/build_photos.py finalize   # -> content/photos/*.webp, content/photos.json, CREDITS.md

`download` is sequential and polite (descriptive User-Agent with contact,
>= 1 s between requests, Retry-After / exponential backoff on 429/5xx) and
resumable (files already on disk are skipped).

Between the two steps, review the contact sheet (tools/contact_sheet.gd) and
list rejected ids, one per line, in tools/rejects.txt (indoor, close-ups,
people, text giveaways, duplicates, poor quality).

`finalize` assigns each photo its country by point-in-polygon on the same
simplified Natural Earth polygons the game uses (content/world.json/.bin);
coastal points that fall in the simplified sea snap to the nearest country
within 30 km.
"""

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
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import geo  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRATCH = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"
RAW = SCRATCH / "raw"
WEBP = SCRATCH / "webp"
UA = ("CartridgePinpoint/1.0 (https://github.com/4gus71n/cartridge; "
      "agustin.tomas.larghi@gmail.com) python-urllib")
LONG_SIDE = 900
QUALITY = 74
try:
    import certifi
    SSL = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover
    SSL = ssl.create_default_context()

# Display names for seeds whose label is a search hint, not a place.
PLACE = {
    "Pyrenees Ordesa": "Ordesa Valley", "Provence Gordes": "Gordes", "Bavaria Alps": "Füssen",
    "Iceland Vik": "Vík", "Transylvania Sibiu": "Sibiu", "Malta Valletta": "Valletta",
    "Bishkek Issyk": "Issyk-Kul", "Kerala Alleppey": "Alappuzha", "Leh Ladakh": "Leh",
    "Sri Lanka Ella": "Ella", "Hokkaido Biei": "Biei", "Guilin Yangshuo": "Yangshuo",
    "Bali Ubud": "Ubud", "Bromo": "Mount Bromo", "Palawan El Nido": "El Nido",
    "Borneo Kinabalu": "Kinabalu", "Sahara Merzouga": "Merzouga", "Cairo Giza": "Giza",
    "Timbuktu Djenne": "Djenné", "Namib Sossusvlei": "Sossusvlei", "Madagascar Morondava": "Morondava",
    "Mauritius": "", "Cape Verde": "", "Texas Austin": "Austin", "Denver Rockies": "Denver",
    "Alaska Denali": "Denali", "Hawaii Oahu": "Oahu", "Nova Scotia": "Halifax",
    "Nunavut Iqaluit": "Iqaluit", "Greenland Nuuk": "Nuuk", "Greenland Ilulissat": "Ilulissat",
    "Yucatan Merida": "Mérida", "Costa Rica Arenal": "Arenal", "San Juan PR": "San Juan",
    "Jamaica": "Kingston", "Dominican Rep": "Santo Domingo", "Kimberley Broome": "Broome",
    "Queenstown NZ": "Queenstown", "Fiji Suva": "Suva", "Samoa Apia": "Apia",
    "New Caledonia": "Nouméa", "Antarctic Peninsula Paradise": "Paradise Harbour",
    "McMurdo": "McMurdo Station", "Svalbard": "Longyearbyen", "Atacama": "San Pedro de Atacama",
    "Galapagos": "Galápagos", "Okavango": "Okavango Delta", "Washington DC": "Washington, D.C.",
    "Zanzibar": "Stone Town", "Tasmania": "Hobart", "Maasai Mara": "Maasai Mara",
    "King George Island": "King George Island", "Rio de Janeiro": "Rio de Janeiro",
}
CONTINENT = {"North America": "NA", "South America": "SA", "Europe": "EU", "Asia": "AS",
             "Africa": "AF", "Oceania": "OC", "Antarctica": "AN",
             "Seven seas (open ocean)": "OC"}


def fetch(url, dest):
    for attempt in range(8):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60, context=SSL) as r:
                dest.write_bytes(r.read())
            return True
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print("  404", url, file=sys.stderr)
                return False
            wait = int(e.headers.get("Retry-After") or 0) or 30 * (2 ** attempt)
            print("  retry", attempt, e.code, "wait", wait, file=sys.stderr, flush=True)
            time.sleep(wait)
        except Exception as e:  # noqa: BLE001
            print("  retry", attempt, e, file=sys.stderr, flush=True)
            time.sleep(5 + 5 * attempt)
    return False


def download():
    cands = json.loads((SCRATCH / "candidates.json").read_text())
    RAW.mkdir(parents=True, exist_ok=True)
    WEBP.mkdir(parents=True, exist_ok=True)
    for i, c in enumerate(cands):
        raw = RAW / f"{c['id']}.jpg"
        if not raw.exists():
            url = c["thumb"].replace("/330px-", "/960px-")
            if "/960px-" not in url:
                print("  no thumb", c["id"], file=sys.stderr)
                continue
            ok = fetch(url, raw)
            time.sleep(1.2)
            if not ok:
                continue
        out = WEBP / f"{c['id']}.webp"
        if not out.exists():
            subprocess.run(["cwebp", "-quiet", "-q", str(QUALITY), "-m", "6", "-resize", str(LONG_SIDE), "0",
                            str(raw), "-o", str(out)], check=True)
        print(f"[{i + 1}/{len(cands)}] {c['id']} {out.stat().st_size // 1024} KB", flush=True)


def load_world():
    meta = json.loads((ROOT / "content/world.json").read_text())
    raw = (ROOT / "content/world.bin").read_bytes()
    pts = [struct.unpack_from("<ff", raw, i * 8) for i in range(len(raw) // 8)]
    for c in meta["countries"]:
        c["ring_pts"] = [pts[s:s + n] for s, n in c["rings"]]
    return meta["countries"]


def country_of(lat, lon, countries):
    """Same rule as WorldData.country_at: inside a polygon, else nearest within 30 km."""
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
    cands = json.loads((SCRATCH / "candidates.json").read_text())
    rej_path = ROOT / "tools/rejects.txt"
    rejects = set()
    if rej_path.exists():
        rejects = {ln.split("#")[0].strip() for ln in rej_path.read_text().splitlines()} - {""}
    countries = load_world()
    out_dir = ROOT / "content/photos"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    photos, total = [], 0
    for c in cands:
        src = WEBP / f"{c['id']}.webp"
        if c["id"] in rejects or not src.exists():
            continue
        country, d = country_of(c["lat"], c["lon"], countries)
        if country is None:
            print("  no country", c["id"], file=sys.stderr)
            continue
        place = PLACE.get(c["seed"], c["seed"])
        shutil.copy(src, out_dir / src.name)
        (out_dir / (src.name + ".import")).write_text('[remap]\n\nimporter="keep"\n')
        total += src.stat().st_size
        photos.append({
            "id": c["id"], "file": src.name, "lat": c["lat"], "lon": c["lon"],
            "country": country["k"], "continent": CONTINENT.get(country.get("cont", ""), "??"),
            "place": place, "author": c["author"], "license": c["license"],
            "license_url": c["license_url"], "source": c["source"], "title": c["title"][5:],
        })
        if d > 0:
            print(f"  {c['id']}: snapped to {country['k']} ({d:.1f} km)")
    (ROOT / "content/photos.json").write_text(json.dumps({"photos": photos}, ensure_ascii=False, indent=1))
    lines = [
        "# Pinpoint credits", "",
        "Game code: Cartridge Studio (all rights reserved).", "",
        "## World map", "",
        "Country polygons: [Natural Earth](https://www.naturalearthdata.com/) 1:50m Admin 0 - Countries, "
        "public domain. Simplified by `tools/build_map.py`.", "",
        "## Photos", "",
        f"{len(photos)} photos from [Wikimedia Commons](https://commons.wikimedia.org/), each used under the "
        "license shown (only CC0, public domain and CC BY 2.0/3.0/4.0 are accepted; CC BY-SA, GFDL and NC "
        "files are rejected by `tools/select_photos.py`). Every photo was resized to 900 px on the long side "
        "and recompressed as WebP; no other changes. The game shows the author and license after each round "
        "and lists all of them on the in-game Credits screen.", "",
        "| Photo | Place | Author | License | Source |", "|---|---|---|---|---|",
    ]
    for p in photos:
        lic = f"[{p['license']}]({p['license_url']})" if p["license_url"] else p["license"]
        title = p["title"].replace("|", "/")
        lines.append(f"| `{p['file']}` | {p['place'] or p['country']} | {p['author'].replace('|', '/')} | {lic} | "
                     f"[{title}]({p['source']}) |")
    (ROOT / "CREDITS.md").write_text("\n".join(lines) + "\n")
    conts = {}
    for p in photos:
        conts[p["continent"]] = conts.get(p["continent"], 0) + 1
    print(f"{len(photos)} photos, {total / 1e6:.2f} MB, avg {total / max(1, len(photos)) / 1024:.0f} KB, {conts}")


if __name__ == "__main__":
    {"download": download, "finalize": finalize}[sys.argv[1]]()

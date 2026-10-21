"""Step 1 of photo curation: harvest geotagged Wikimedia Commons candidates.

Usage: python tools/fetch_candidates.py [--limit N] [--delay S]

For every seed in seeds.py this asks the Commons API twice:
  1. generator=geosearch  - the 50 geotagged files nearest the seed,
  2. generator=search     - `nearcoord:` CirrusSearch restricted to the allowed
     licenses via structured data, most-linked first (files used in articles
     tend to be representative; geosearch alone often returns one uploader's
     CC BY-SA batch).
Both ask for imageinfo + extmetadata (license, author, EXIF GPS, categories)
and page coordinates.

Output (both under tools/content/, so a restarted worker never refetches):
  harvest.jsonl.gz     one compact record (gzip, append-only) per accepted file (license + mime +
                       coordinates already checked; everything else is decided
                       later by select_photos.py)
  harvest_done.json    seed labels already harvested

The full API responses are additionally cached in $TMPDIR/pinpoint-work/cache/
so re-running within a session is free even for seeds whose records were all
rejected.

Etiquette: sequential requests, descriptive User-Agent with a contact address,
maxlag=5, >= `--delay` seconds between calls, Retry-After / exponential backoff.
"""

import gzip
import json
import os
import pathlib
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from seeds import SEED_ROWS  # noqa: E402

API = "https://commons.wikimedia.org/w/api.php"
UA = ("CartridgePinpoint/1.1 (https://github.com/4gus71n/cartridge; "
      "agustin.tomas.larghi@gmail.com) python-urllib")
ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "tools/content"
HARVEST = CONTENT / "harvest.jsonl.gz"
DONE = CONTENT / "harvest_done.json"
SCRATCH = pathlib.Path(os.environ.get("PINPOINT_WORK")
                       or (pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"))
CACHE = SCRATCH / "cache"
try:
    import certifi
    SSL = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover
    SSL = ssl.create_default_context()
DELAY = 1.1  # seconds between requests
FIELDS = ("LicenseShortName|License|Artist|Credit|GPSLatitude|GPSLongitude|Categories|"
          "Restrictions|LicenseUrl|ObjectName|ImageDescription|AttributionRequired|Copyrighted")
# Licenses that may ever ship (roadmap 3): CC0, public domain, CC BY 4/3/2.5/2.
ALLOWED_LICENSE_NAMES = {
    "cc0": "CC0", "cc0 1.0": "CC0", "public domain": "Public domain",
    "cc by 4.0": "CC BY 4.0", "cc by 3.0": "CC BY 3.0",
    "cc by 2.5": "CC BY 2.5", "cc by 2.0": "CC BY 2.0",
}
ALLOWED_LICENSE_CODES = {"cc0", "pd", "cc-by-4.0", "cc-by-3.0", "cc-by-2.5", "cc-by-2.0"}
# SDC "copyright license" (P275) items for the allowed licenses.
LICENSE_Q = ("haswbstatement:P275=Q20007257|P275=Q14947546|P275=Q18810333|"
             "P275=Q19125117|P275=Q6938433|P275=Q98923445")


def api(params, delay):
    params = {"format": "json", "formatversion": "2", "maxlag": "5", **params}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(8):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
        try:
            with urllib.request.urlopen(req, timeout=90, context=SSL) as r:
                data = json.loads(r.read())
            if "error" in data and data["error"].get("code") == "maxlag":
                time.sleep(5 + attempt * 5)
                continue
            return data
        except urllib.error.HTTPError as e:
            wait = int(e.headers.get("Retry-After") or 0) or min(120, 15 * (2 ** attempt))
            print("  retry", attempt, e, "wait", wait, file=sys.stderr, flush=True)
            time.sleep(wait)
        except Exception as e:  # noqa: BLE001
            print("  retry", attempt, repr(e), file=sys.stderr, flush=True)
            time.sleep(5 + attempt * 5)
    print("  GIVE UP", url, file=sys.stderr, flush=True)
    return {}


def slug(label):
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def _cached(name, build):
    path = CACHE / f"{name}.json"
    if path.exists():
        try:
            data = json.loads(path.read_text())
            if isinstance(data, list) and all(isinstance(d, dict) for d in data):
                return data
        except ValueError:
            pass
    data = build()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))
    return data


def fetch_seed(label, lat, lon, delay):
    def build():
        data = api({
            "action": "query", "generator": "geosearch", "ggscoord": f"{lat}|{lon}",
            "ggsradius": "10000", "ggslimit": "50", "ggsnamespace": "6",
            "prop": "imageinfo|coordinates", "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": "330", "iiextmetadatafilter": FIELDS,
        }, delay)
        time.sleep(delay)
        return data.get("query", {}).get("pages", [])
    return _cached(slug(label), build)


def fetch_search(label, lat, lon, delay):
    def build():
        data = api({
            "action": "query", "generator": "search", "gsrnamespace": "6", "gsrlimit": "50",
            "gsrsearch": f"nearcoord:16km,{lat},{lon} filetype:bitmap {LICENSE_Q}",
            "gsrsort": "incoming_links_desc",
            "prop": "imageinfo|coordinates", "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": "330", "iiextmetadatafilter": FIELDS,
        }, delay)
        time.sleep(delay)
        return data.get("query", {}).get("pages", [])
    return _cached("search_" + slug(label), build)


def _meta(m, key):
    v = m.get(key, {})
    return v.get("value", "") if isinstance(v, dict) else ""


def license_of(m):
    """Returns the canonical short license name, or None when not allowed."""
    short = _meta(m, "LicenseShortName").strip()
    code = _meta(m, "License").strip().lower()
    key = short.lower().replace("cc-by", "cc by").replace("  ", " ")
    name = ALLOWED_LICENSE_NAMES.get(key)
    if name is None and key.startswith("public domain"):
        name = "Public domain"
    if name is None:
        return None
    if code and code not in ALLOWED_LICENSE_CODES and not code.startswith("pd"):
        return None
    # Belt and braces: never accept share-alike / non-commercial / no-derivs / GFDL,
    # whatever the short name claims.
    blob = (short + "|" + code + "|" + _meta(m, "LicenseUrl")).lower()
    for bad in ("-sa", " sa", "/sa", "sharealike", "share-alike", "-nc", "-nd",
                "noncommercial", "noderiv", "gfdl", "fdl"):
        if bad in blob:
            return None
    return name


def reduce_page(page, seed_label):
    """Compact record for one Commons file, or None if it can never be used."""
    ii = (page.get("imageinfo") or [None])[0]
    if not ii:
        return None
    m = ii.get("extmetadata", {})
    name = license_of(m)
    if name is None:
        return None
    if ii.get("mime") not in ("image/jpeg", "image/png"):
        return None
    lat = lon = None
    gps = False
    try:
        lat = float(_meta(m, "GPSLatitude"))
        lon = float(_meta(m, "GPSLongitude"))
        gps = True
    except (TypeError, ValueError):
        coords = page.get("coordinates") or []
        if coords:
            lat, lon = float(coords[0]["lat"]), float(coords[0]["lon"])
    if lat is None or lon is None or not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
        return None
    return {
        "seed": seed_label, "t": page["title"], "p": page["pageid"],
        "lat": round(lat, 5), "lon": round(lon, 5), "gps": gps,
        "lic": name, "licurl": _meta(m, "LicenseUrl")[:120],
        "art": _meta(m, "Artist")[:260], "w": ii.get("width", 0), "h": ii.get("height", 0),
        "mime": ii.get("mime"), "u": ii.get("url", "").split("?")[0],
        "cat": _meta(m, "Categories")[:400],
        "obj": _meta(m, "ObjectName")[:120],
        "restr": _meta(m, "Restrictions")[:80],
    }


def main():
    args = sys.argv[1:]
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else None
    delay = float(args[args.index("--delay") + 1]) if "--delay" in args else DELAY
    CACHE.mkdir(parents=True, exist_ok=True)
    CONTENT.mkdir(parents=True, exist_ok=True)
    done = set(json.loads(DONE.read_text())) if DONE.exists() else set()
    rows = [r for r in SEED_ROWS if r[0] not in done]
    if limit:
        rows = rows[:limit]
    print(f"{len(done)} seeds already harvested, {len(rows)} to go", flush=True)
    with gzip.open(HARVEST, "at", encoding="utf-8") as out:
        for i, (label, lat, lon, _iso, _diff) in enumerate(rows):
            pages = [p for p in fetch_seed(label, lat, lon, delay) if isinstance(p, dict)]
            seen = {p["pageid"] for p in pages}
            pages += [p for p in fetch_search(label, lat, lon, delay)
                      if isinstance(p, dict) and p.get("pageid") not in seen]
            kept = 0
            for p in pages:
                rec = reduce_page(p, label)
                if rec:
                    out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    kept += 1
            out.flush()
            done.add(label)
            DONE.write_text(json.dumps(sorted(done)))
            print(f"[{i + 1}/{len(rows)}] {label}: {len(pages)} files -> {kept} kept", flush=True)


if __name__ == "__main__":
    main()

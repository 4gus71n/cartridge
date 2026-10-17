"""Step 1 of photo curation: geosearch Wikimedia Commons around every seed.

Usage: python tools/fetch_candidates.py

For each seed in seeds.py this asks the Commons API for up to 50 geotagged
files within 10 km (generator=geosearch, namespace File) with imageinfo +
extmetadata (license, author, GPS, categories). Raw responses are cached in
$TMPDIR/pinpoint-work/cache/ so re-runs are free. Requests are throttled
(~1/s) and carry a descriptive User-Agent, per Wikimedia API etiquette.
"""

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
from seeds import SEEDS  # noqa: E402

API = "https://commons.wikimedia.org/w/api.php"
UA = ("CartridgePinpoint/1.0 (https://github.com/4gus71n/cartridge; "
      "agustin.tomas.larghi@gmail.com) python-urllib")
SCRATCH = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"
CACHE = SCRATCH / "cache"
try:
    import certifi
    SSL = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover
    SSL = ssl.create_default_context()
DELAY = 2.0  # seconds between requests (Commons rate-limits bursts)
FIELDS = ("LicenseShortName|License|Artist|Credit|GPSLatitude|GPSLongitude|Categories|"
          "Restrictions|LicenseUrl|ObjectName|ImageDescription|AttributionRequired|Copyrighted")


def api(params):
    params = {"format": "json", "formatversion": "2", "maxlag": "5", **params}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(8):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
        try:
            with urllib.request.urlopen(req, timeout=60, context=SSL) as r:
                data = json.loads(r.read())
            if "error" in data and data["error"].get("code") == "maxlag":
                time.sleep(5 + attempt * 5)
                continue
            return data
        except urllib.error.HTTPError as e:
            wait = int(e.headers.get("Retry-After") or 0) or 30 * (2 ** attempt)
            print("  retry", attempt, e, "wait", wait, file=sys.stderr, flush=True)
            time.sleep(wait)
        except Exception as e:  # noqa: BLE001
            print("  retry", attempt, e, file=sys.stderr, flush=True)
            time.sleep(5 + attempt * 5)
    raise RuntimeError("API failed: " + url)


def slug(label):
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def fetch_seed(label, lat, lon):
    path = CACHE / f"{slug(label)}.json"
    if path.exists():
        return json.loads(path.read_text())
    pages = {}
    cont = {}
    while True:
        data = api({
            "action": "query", "generator": "geosearch", "ggscoord": f"{lat}|{lon}",
            "ggsradius": "10000", "ggslimit": "50", "ggsnamespace": "6",
            "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "330",
            "iiextmetadatafilter": FIELDS, **cont,
        })
        time.sleep(DELAY)
        for p in data.get("query", {}).get("pages", []):
            cur = pages.setdefault(p["pageid"], p)
            if "imageinfo" in p:
                cur["imageinfo"] = p["imageinfo"]
        if "continue" not in data or len(pages) >= 50:
            break  # one batch of 50 per seed is plenty (keeps request count low)
        cont = data["continue"]
    result = {"label": label, "lat": lat, "lon": lon, "pages": list(pages.values())}
    path.write_text(json.dumps(result))
    return result


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    for i, (label, lat, lon) in enumerate(SEEDS):
        res = fetch_seed(label, lat, lon)
        print(f"[{i + 1}/{len(SEEDS)}] {label}: {len(res['pages'])} files", flush=True)


if __name__ == "__main__":
    main()

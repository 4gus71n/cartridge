"""Build the offline world map for Pinpoint from Natural Earth (public domain).

Usage: python tools/build_map.py [ne_50m_admin_0_countries.geojson]

Downloads Natural Earth 1:50m admin-0 countries (GeoJSON mirror of the
official release, github.com/nvkelso/natural-earth-vector) into the scratch
dir if no path is given, simplifies the outer rings (Douglas-Peucker, rings
kept simple so Godot can triangulate them) and writes:

  content/world.json  country metadata + ring index
  content/world.bin   little-endian float32 lon,lat pairs for every ring

Holes (enclaves) are dropped: the game draws big countries first and tests
small countries first, so enclaves (Lesotho, San Marino, ...) still win.
"""

import json
import os
import pathlib
import struct
import sys
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import geo  # noqa: E402

NE_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/"
          "geojson/ne_50m_admin_0_countries.geojson")
ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRATCH = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "pinpoint-work"
TOL = 0.06            # degrees (~6 km)
MIN_AREA = 0.02       # deg²; smaller islands dropped unless a country's largest


def load_geojson(path=None):
    if path is None:
        path = SCRATCH / "ne50.geojson"
        if not path.exists():
            SCRATCH.mkdir(parents=True, exist_ok=True)
            req = urllib.request.Request(NE_URL, headers={"User-Agent": "CartridgePinpointBuild/1.0"})
            path.write_bytes(urllib.request.urlopen(req).read())
    return json.loads(pathlib.Path(path).read_text())


def outer_rings(geometry):
    polys = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    out = []
    for poly in polys:
        ring = [(round(x, 4), round(y, 4)) for x, y in poly[0]]
        if ring[0] == ring[-1]:
            ring = ring[:-1]
        # drop consecutive duplicates
        clean = [ring[0]]
        for p in ring[1:]:
            if p != clean[-1]:
                clean.append(p)
        out.append(clean)
    return out


def country_key(props):
    return props["ADM0_A3"]


def iso2(props):
    for k in ("ISO_A2_EH", "ISO_A2"):
        v = props.get(k, "-99")
        if v and v != "-99":
            return v
    return ""


def main():
    data = load_geojson(sys.argv[1] if len(sys.argv) > 1 else None)
    countries = []
    points = []
    for f in data["features"]:
        p = f["properties"]
        rings = outer_rings(f["geometry"])
        rings.sort(key=lambda r: -abs(geo.ring_area(r)))
        kept = []
        for i, r in enumerate(rings):
            if i > 0 and abs(geo.ring_area(r)) < MIN_AREA:
                continue
            tol = TOL
            s = geo.simplify_ring(r, tol)
            while (len(s) < 4 or not geo.ring_is_simple(s)) and tol > 0.002:
                tol /= 2
                s = geo.simplify_ring(r, tol)
            if len(s) < 3 or not geo.ring_is_simple(s):
                s = r if geo.ring_is_simple(r) else None
            if s is None or len(s) < 3:
                print("skip ring", p["NAME"], i, file=sys.stderr)
                continue
            kept.append(s)
        if not kept:
            print("skip country", p["NAME"], file=sys.stderr)
            continue
        ring_index = []
        xs, ys = [], []
        for r in kept:
            ring_index.append([len(points), len(r)])
            points.extend(r)
            xs += [q[0] for q in r]
            ys += [q[1] for q in r]
        countries.append({
            "k": country_key(p),
            "iso": iso2(p),
            "en": p.get("NAME_EN") or p["NAME"],
            "es": p.get("NAME_ES") or p.get("NAME_EN") or p["NAME"],
            "c": int(p.get("MAPCOLOR7", 1)),
            "area": round(sum(abs(geo.ring_area(r)) for r in kept), 4),
            "bbox": [min(xs), min(ys), max(xs), max(ys)],
            "rings": ring_index,
        })
    countries.sort(key=lambda c: -c["area"])  # draw order: big first
    out = ROOT / "content"
    out.mkdir(exist_ok=True)
    (out / "world.json").write_text(json.dumps({
        "source": "Natural Earth 1:50m Admin 0 - Countries (public domain), simplified",
        "points": len(points),
        "countries": countries,
    }, ensure_ascii=False, separators=(",", ":")))
    with open(out / "world.bin", "wb") as fh:
        for x, y in points:
            fh.write(struct.pack("<ff", x, y))
    print(f"{len(countries)} countries, {len(points)} points, "
          f"json {(out / 'world.json').stat().st_size // 1024} KB, bin {(out / 'world.bin').stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()

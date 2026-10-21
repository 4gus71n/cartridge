"""Step 2 of photo curation: filter, rank and balance the harvested candidates.

Usage: python tools/select_photos.py [--per-seed 2]

Reads tools/content/harvest.jsonl.gz (from fetch_candidates.py) and keeps only
files that are
  * licensed CC0 / public domain / CC BY 4.0 / 3.0 / 2.5 / 2.0 (CC BY-SA,
    GFDL, NC and ND were already dropped at harvest time and are re-checked),
  * JPEG/PNG photos, roughly landscape (aspect 1.15 - 2.4), >= 900 px wide,
  * geotagged (EXIF GPS, else the Commons page coordinate) within 20 km of
    the seed,
  * free of restrictions (personality rights, trademarks, ...),
  * not obviously a studio shot / map / diagram / document / indoor-only /
    close-up / vehicle / portrait (keyword filter over title + categories),
  * attributable (a usable author string for every CC BY file).

Then it balances the pack: at most `--per-seed` per seed (place), at most
MAX_PER_COUNTRY per country, and photographers/spots are de-duplicated. Seeds
in under-represented countries get a relaxed second chance so rare countries
still make it in.

Output: tools/content/candidates.json (list of candidate dicts, each with a
difficulty tag) - consumed by build_photos.py.
"""

import collections
import html
import json
import pathlib
import re
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from seeds import SEED_ROWS, SEED_INFO  # noqa: E402
import geo  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "tools/content"
HARVEST = CONTENT / "harvest.jsonl.gz"
OUT = CONTENT / "candidates.json"

ALLOWED = {"CC0", "Public domain", "CC BY 4.0", "CC BY 3.0", "CC BY 2.5", "CC BY 2.0"}
MAX_PER_COUNTRY = 8
MAX_PER_SEED = 2          # hard cap: at most 2 photos per city/place
MIN_WIDTH = 900
MAX_SEED_KM = 20.0

# Subjects that could be anywhere, are not a place, or are unusable in game.
REJECT = re.compile(
    r"interior|inside\b|indoor|museum|exhibit|gallery|collection|painting|fresco|mosaic|icon\b|"
    r"altar|nave|ceiling|organ\b|stained|chandelier|food|dish|cuisine|restaurant|menu|meal|"
    r"dessert|drink|beer|wine|coffee|bottle|"
    r"portrait|selfie|\bwoman\b|\bwomen\b|\bman\b|\bmen\b|child|girl|\bboy\b|wedding|actor|"
    r"politic|president|minister|player|athlet|football|soccer|match\b|concert|performance|"
    r"protest|demonstration|parade|conference|ceremony|festival dance|"
    r"logo|\bmap\b|maps\b|\bplan\b|diagram|chart|schem|\bsign\b|signs\b|signage|plaque|"
    r"inscription|graffiti|poster|advert|billboard|document|book|manuscript|coin|stamp|"
    r"banknote|flag\b|coat of arms|"
    r"insect|butterfl|moth\b|\bbee\b|spider|beetle|dragonfl|bird|aves\b|animal|mammal|\bdog\b|"
    r"\bcat\b|cats\b|horse|\bcow\b|cattle|captive|\bzoo\b|aquarium|flower|blossom|\bplant\b|"
    r"leaf\b|leaves|fung|mushroom|macro|close-?up|closeup|\bdetail|texture|specimen|"
    r"\bcar\b|cars\b|automobile|vehicle|truck|\bbus\b|buses|tram\b|train\b|locomotive|railcar|"
    r"rolling stock|aircraft|airplane|aeroplane|airliner|boeing|airbus|helicopter|motorcycle|"
    r"bicycle|\bship\b|ferry\b|yacht|"
    r"at night|by night|night view|\bnight\b|nocturn|firework|statue|sculpture|bust\b|grave|"
    r"tomb\b|cemetery|memorial plaque|\blamp\b|shop window|mannequin|x-ray|microscop|"
    r"screenshot|drawing|engraving|lithograph|postcard|historical image|\b1[89]\d\d\b|"
    r"black and white|monochrome|grayscale|greyscale|sepia|"
    r"aerial|satellite|iss0|nasa|from space|astronaut|orthophoto|panorama|360|spheric|"
    r"stereo|gigapan|composite|collage|montage|test image|blurred",
    re.I)
# Milder filter used for countries that would otherwise have no photo at all.
REJECT_SOFT = re.compile(
    r"interior|indoor|museum|exhibit|painting|fresco|mosaic|altar|food|dish|cuisine|"
    r"portrait|selfie|wedding|logo|\bmap\b|diagram|chart|plaque|inscription|poster|advert|"
    r"document|manuscript|coin|stamp|banknote|coat of arms|insect|butterfl|spider|beetle|"
    r"\bbird\b|flower|blossom|fung|mushroom|macro|close-?up|closeup|texture|specimen|"
    r"\bcar\b|automobile|truck|locomotive|aircraft|airplane|airliner|helicopter|x-ray|"
    r"microscop|screenshot|drawing|engraving|lithograph|black and white|monochrome|"
    r"satellite|from space|orthophoto|360|collage|montage",
    re.I)
GOOD = re.compile(r"landscape|skyline|cityscape|street|view of|view from|beach|coast|mountain|"
                  r"village|square|plaza|place\b|harbou?r|port\b|river|lake|valley|canyon|desert|"
                  r"old town|\btown\b|bridge|market|waterfall|glacier|fjord|island|\bbay\b|hill|"
                  r"temple|mosque|church|cathedral|castle|fort|palace|monastery|stupa|pagoda|"
                  r"ruins|rooftops|panoramic view|national park", re.I)
# Titles that make a photo instantly recognisable -> easy, whatever the seed says.
LANDMARK = re.compile(
    r"eiffel|colosseum|coliseo|big ben|tower bridge|statue of liberty|golden gate|"
    r"taj mahal|machu picchu|great wall|forbidden city|petra|treasury|pyramid|sphinx|"
    r"acropolis|parthenon|sagrada fam|alhambra|notre.dame|brandenburg|times square|"
    r"opera house|christ the redeemer|corcovado|sugarloaf|uluru|ayers rock|mount fuji|"
    r"matterhorn|neuschwanstein|angkor|borobudur|burj khalifa|empire state|"
    r"leaning tower|st\.? peter|st\.? basil|kremlin|red square|white house|capitol|"
    r"hagia sophia|blue mosque|table mountain|victoria falls|niagara|stonehenge|"
    r"moai|chich[eé]n|mont saint.michel|charles bridge|grand canal|rialto|"
    r"san marco|st mark|tower of london|buckingham|arc de triomphe|louvre|"
    r"space needle|cn tower|petronas|marina bay|gateway of india|wat arun|"
    r"grand palace|potala|kinkaku|fushimi|itsukushima|shibuya|burj al arab", re.I)


def strip_html(s):
    s = re.sub(r"<[^>]+>", " ", s or "")
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def clean_author(raw):
    a = strip_html(raw)
    a = re.sub(r"\s*\(talk\)|\s*\(contribs?\)", "", a)
    a = re.sub(r"\bfrom\s+\S+(\s+\S+)?,?\s*(USA|UK)?$", "", a).strip(" ,;")
    if len(a) > 60:
        a = a[:57].rstrip() + "..."
    return a


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


def read_harvest():
    """Yield every harvested record. The file is append-only gzip, so it can
    hold several members and an interrupted run can leave the last one
    truncated; members are decompressed one after another and a damaged tail is
    reported, not fatal."""
    raw = HARVEST.read_bytes()
    text, pos = [], 0
    while pos < len(raw):
        if raw[pos:pos + 3] != b"\x1f\x8b\x08":
            print(f"  warning: harvest not a gzip member at {pos}", file=sys.stderr)
            break
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            text.append(d.decompress(raw[pos:]))
        except zlib.error:
            print(f"  warning: damaged harvest member at {pos}", file=sys.stderr)
            break
        consumed = len(raw) - pos - len(d.unused_data)
        if consumed <= 0:
            break
        pos += consumed
    seen = set()
    for line in b"".join(text).decode("utf-8", "ignore").splitlines():
        line = line.strip()
        if not (line.startswith("{") and line.endswith("}")):
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        key = (rec.get("seed"), rec.get("p"))
        if key in seen:
            continue
        seen.add(key)
        yield rec


def slug(label):
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def evaluate(rec, soft=False):
    """Returns (candidate, reason). `candidate` is None when rejected."""
    if rec["lic"] not in ALLOWED:
        return None, "license"
    if (rec.get("restr") or "").strip():
        return None, "restrictions"
    w, h = int(rec.get("w") or 0), int(rec.get("h") or 0)
    if w < (700 if soft else MIN_WIDTH):
        return None, "small"
    if w > 9000 or h > 9000:
        return None, "huge"      # stitched panoramas, satellite mosaics, scans
    aspect = w / max(h, 1)
    if not (1.05 <= aspect <= 2.6 if soft else 1.15 <= aspect <= 2.4):
        return None, "shape"
    info = SEED_INFO[rec["seed"]]
    km = geo.haversine_km(rec["lat"], rec["lon"], info["lat"], info["lon"])
    if km > (35.0 if soft else MAX_SEED_KM):
        return None, "far"
    text = rec["t"] + " | " + (rec.get("cat") or "") + " | " + strip_html(rec.get("obj") or "")
    if (REJECT_SOFT if soft else REJECT).search(text):
        return None, "keyword"
    author = clean_author(rec.get("art") or "")
    if rec["lic"] in ("CC0", "Public domain"):
        author = author or "Unknown (public domain)"
    if not author or "unknown" in author.lower() and rec["lic"].startswith("CC BY"):
        return None, "author"
    cats = rec.get("cat") or ""
    score = 0.0
    if "Featured pictures" in cats:
        score += 6
    if "Quality images" in cats:
        score += 4
    if "Valued images" in cats:
        score += 2
    score += min(3, len(GOOD.findall(text)))
    score += min(2.0, w / 3000.0)
    if rec.get("gps"):
        score += 1.5          # camera GPS beats a hand-placed page coordinate
    if soft:
        score -= 2
    difficulty = "easy" if LANDMARK.search(text) else info["difficulty"]
    title = rec["t"]
    base = title[5:] if title.startswith("File:") else title
    stem = re.sub(r"[^A-Za-z0-9]+", "_", base.rsplit(".", 1)[0])[:70].strip("_")
    ext = base.rsplit(".", 1)[-1].lower()
    return {
        "title": title, "pageid": rec["p"], "lat": rec["lat"], "lon": rec["lon"],
        "license": rec["lic"], "license_url": rec.get("licurl") or "", "author": author,
        "url": rec["u"], "width": w, "height": h, "score": round(score, 2),
        "gps": bool(rec.get("gps")), "seed": rec["seed"], "difficulty": difficulty,
        "mime": rec.get("mime"), "stem": stem, "ext": ext,
        "source": "https://commons.wikimedia.org/wiki/" + title.replace(" ", "_"),
    }, "ok"


def dedupe_ok(c, picked):
    for q in picked:
        if q["pageid"] == c["pageid"]:
            return False
        if q["author"] == c["author"] and geo.haversine_km(c["lat"], c["lon"], q["lat"], q["lon"]) < 3:
            return False
        if geo.haversine_km(c["lat"], c["lon"], q["lat"], q["lon"]) < 0.25:
            return False
    return True


def main():
    args = sys.argv[1:]
    per_seed = int(args[args.index("--per-seed") + 1]) if "--per-seed" in args else MAX_PER_SEED
    countries = load_world()
    by_seed = collections.defaultdict(list)
    for rec in read_harvest():
        if rec["seed"] in SEED_INFO:
            by_seed[rec["seed"]].append(rec)
    stats = collections.Counter()
    strict, relaxed = {}, {}
    for label in by_seed:
        for soft, bucket in ((False, strict), (True, relaxed)):
            good, seen_page = [], set()
            for rec in by_seed[label]:
                c, why = evaluate(rec, soft=soft)
                if not soft:
                    stats[why] += 1
                if c and c["pageid"] not in seen_page:
                    seen_page.add(c["pageid"])
                    good.append(c)
            good.sort(key=lambda c: -c["score"])
            bucket[label] = good

    # Pass 1: strict candidates, at most per_seed per seed and 8 per country.
    picked, per_country, country_of_seed = [], collections.Counter(), {}

    def take(pool, limit_per_seed):
        added = 0
        for label, _lat, _lon, _iso, _diff in SEED_ROWS:
            taken = [c for c in picked if c["seed"] == label]
            for c in pool.get(label, []):
                if len(taken) >= limit_per_seed:
                    break
                country, dist = country_of(c["lat"], c["lon"], countries)
                if country is None:
                    stats["no country"] += 1
                    continue
                if per_country[country["k"]] >= MAX_PER_COUNTRY:
                    break
                if not dedupe_ok(c, picked):
                    continue
                c["country"] = country["k"]
                c["country_dist"] = round(dist, 1)
                picked.append(c)
                taken.append(c)
                per_country[country["k"]] += 1
                country_of_seed[label] = country["k"]
                added += 1
        return added

    take(strict, per_seed)
    # Pass 2: countries that still have < 2 photos get relaxed candidates.
    thin = {k for k, v in per_country.items() if v < 2}
    thin_pool = {}
    for label, pool in relaxed.items():
        want = country_of_seed.get(label)
        if want is None or want in thin:
            thin_pool[label] = pool
    take(thin_pool, per_seed)

    # Stable ids: <seed-slug>-<n>.
    out, n_by_seed = [], collections.Counter()
    picked.sort(key=lambda c: (c["seed"], -c["score"]))
    for c in picked:
        n_by_seed[c["seed"]] += 1
        c["id"] = f"{slug(c['seed']).replace('_', '-')}-{n_by_seed[c['seed']]}"
        out.append(c)
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False))
    conts = collections.Counter()
    for c in out:
        k = c["country"]
        conts[next((x["cont"] for x in countries if x["k"] == k), "?")] += 1
    print(f"{len(out)} candidates, {len(per_country)} countries")
    print("  continents:", dict(conts))
    print("  difficulty:", dict(collections.Counter(c["difficulty"] for c in out)))
    print("  licenses:", dict(collections.Counter(c["license"] for c in out)))
    print("  reject reasons:", dict(stats.most_common(12)))


if __name__ == "__main__":
    main()

"""Import permissively-licensed game candidates from GitHub into the database.

Candidates land with status='candidate' and are NOT shown in the app until
they are license-verified and packaged. Raw API results are saved to
data/github_candidates.json for provenance.

Run from backend/:  python scripts/import_github_candidates.py [--pages 1]
Requires network access. Set GITHUB_TOKEN for higher rate limits.
"""

import argparse
import json
import os
import pathlib
import re
import sys
import time
from datetime import datetime

import httpx

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.db import Base, SessionLocal, engine  # noqa: E402
from app import models  # noqa: E402,F401
from app.models import Game  # noqa: E402

DATA = BACKEND / "data"
API = "https://api.github.com/search/repositories"

ALLOWED_LICENSES = {
    "MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "ISC",
    "CC0-1.0", "CC-BY-4.0", "Unlicense", "MPL-2.0", "0BSD",
}

QUERIES = [
    ("MIT", "html5-game"),
    ("MIT", "javascript-game"),
    ("MIT", "canvas-game"),
    ("MIT", "browser-game"),
    ("MIT", "js13k"),
    ("MIT", "phaser"),
    ("MIT", "pixijs"),
    ("Apache-2.0", "html5-game"),
    ("Apache-2.0", "javascript-game"),
    ("BSD-3-Clause", "html5-game"),
    ("BSD-3-Clause", "javascript-game"),
    ("BSD-2-Clause", "javascript-game"),
    ("ISC", "javascript-game"),
    ("CC0-1.0", "html5-game"),
    ("CC0-1.0", "javascript-game"),
    ("Unlicense", "javascript-game"),
    ("MPL-2.0", "javascript-game"),
    ("MIT", "game"),
    ("Apache-2.0", "game"),
    ("CC0-1.0", "game"),
]


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")[:120]


def fetch_pages(client: httpx.Client, license_id: str, topic: str, pages: int) -> list[dict]:
    results = []
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "cartridge-import"}
    token = os.getenv("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    for page in range(1, pages + 1):
        params = {
            "q": f"topic:{topic} license:{license_id}",
            "sort": "stars",
            "order": "desc",
            "per_page": 100,
            "page": page,
        }
        for attempt in range(2):
            response = client.get(API, params=params, headers=headers, timeout=30)
            if response.status_code == 403:
                print("  rate limited, sleeping 60s...")
                time.sleep(60)
                continue
            response.raise_for_status()
            results.extend(response.json().get("items", []))
            break
        time.sleep(7 if not token else 2.5)
    return results


def acceptable(item: dict) -> bool:
    if item.get("fork") or item.get("archived"):
        return False
    license_info = item.get("license") or {}
    if license_info.get("spdx_id") not in ALLOWED_LICENSES:
        return False
    if not (item.get("description") or "").strip():
        return False
    if (item.get("size") or 0) > 150_000:  # KB, skip repos > ~150MB
        return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pages", type=int, default=1)
    args = parser.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    raw: dict[str, dict] = {}
    with httpx.Client() as client:
        for license_id, topic in QUERIES:
            print(f"searching license:{license_id} topic:{topic} ...")
            for item in fetch_pages(client, license_id, topic, args.pages):
                raw[item["full_name"]] = item

    print(f"\n{len(raw)} unique repositories fetched")
    candidates = {k: v for k, v in raw.items() if acceptable(v)}
    print(f"{len(candidates)} pass filters")

    (DATA / "github_candidates.json").write_text(
        json.dumps(
            {"fetched_at": datetime.utcnow().isoformat(), "items": list(raw.values())},
            indent=1,
        )
    )

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    inserted = 0
    try:
        for full_name, item in sorted(candidates.items()):
            owner, name = full_name.split("/", 1)
            slug = f"gh-{slugify(owner)}-{slugify(name)}"
            if db.query(Game).filter(Game.slug == slug).first():
                continue
            license_info = item.get("license") or {}
            game = Game(
                slug=slug,
                title=name.replace("-", " ").replace("_", " ").strip() or name,
                description=(item.get("description") or "")[:2000],
                author=owner,
                license_spdx=license_info.get("spdx_id") or "",
                source_url=item.get("html_url") or "",
                play_url=item.get("homepage") or "",
                bundled=False,
                status="candidate",
                tags="github-import",
                stars=item.get("stargazers_count") or 0,
            )
            db.add(game)
            inserted += 1
        db.commit()
        total = db.query(Game).filter(Game.status == "candidate").count()
        print(f"inserted {inserted} new candidates; {total} candidates in database")
    finally:
        db.close()


if __name__ == "__main__":
    main()

"""Load Cartridge originals hosted on GitHub Pages into the catalog DB.

Reads the hosting repo's index.json (URL by default, or a local path) and
upserts each game as verified + downloadable (not bundled).

Run from backend/:
  .venv/bin/python scripts/import_hosted.py
  .venv/bin/python scripts/import_hosted.py --index ~/cartridge-games/index.json
"""

import argparse
import json
import pathlib
import ssl
import sys
import urllib.request

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.db import Base, SessionLocal, engine  # noqa: E402
from app.models import Game  # noqa: E402

DEFAULT_INDEX = "https://4gus71n.github.io/cartridge-games/index.json"


def load_index(source: str) -> dict:
    path = pathlib.Path(source).expanduser()
    if path.exists():
        return json.loads(path.read_text())
    # python.org macOS builds ship without CA certs; prefer certifi's bundle.
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = ssl.create_default_context()
    with urllib.request.urlopen(source, timeout=20, context=context) as response:
        return json.loads(response.read())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", default=DEFAULT_INDEX)
    args = parser.parse_args()

    index = load_index(args.index)
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        for g in index["games"]:
            game = db.query(Game).filter(Game.slug == g["slug"]).first()
            if game is None:
                game = Game(slug=g["slug"], initial_likes=0, initial_comments=0, stars=0)
                db.add(game)
            game.title = g["title"]
            game.description = g.get("description", "")
            game.author = g.get("author", "Cartridge Studio")
            game.license_spdx = g.get("license", "All rights reserved")
            game.source_url = ""  # empty = shown as a Cartridge original
            game.play_url = g["play_url"]
            game.package_url = g["package_url"]
            game.package_sha256 = g["package_sha256"]
            game.thumbnail_url = g.get("thumbnail_url", "")
            game.poster_style = g.get("poster_style", "TAP")
            game.accent_top = g.get("accent_top", "#0B0E18")
            game.accent_bottom = g.get("accent_bottom", "#1B2350")
            game.orientation = g.get("orientation", "any")
            game.tags = ",".join(g.get("tags", []))
            game.bundled = False
            game.status = "verified"
            game.review_note = f"cartridge original v{g.get('version', 1)}"
            print(f"upserted {g['slug']} ({g['package_sha256'][:12]}…)")
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    main()

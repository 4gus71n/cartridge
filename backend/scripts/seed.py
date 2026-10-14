"""Seed the verified catalog (the 20 launch games) into the database.

Run from backend/:  python scripts/seed.py
"""

import json
import pathlib
import sys

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.config import PUBLIC_BASE_URL  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app import models  # noqa: E402,F401
from app.db import Base, engine  # noqa: E402
from app.models import Game  # noqa: E402

DATA = BACKEND / "data"

# Games whose canvas reads better on a wide screen
ORIENTATIONS: dict[str, str] = {}

# slug, title, description, author, license, source_url, poster, top, bottom, likes, comments, bundled
GAMES = [
    ("2048", "2048", "Slide, merge, don't get stuck.", "Gabriele Cirulli", "MIT", "https://github.com/gabrielecirulli/2048", "TILES", "#3A2E27", "#8A715C", 48210, 986, True),
    ("black-hole-square", "Black Hole Square", "A puzzle that pulls you in.", "Quinten", "MIT", "https://github.com/Quinten/black-hole-square", "HOLE", "#12071F", "#4C1D95", 2895, 51, True),
    ("neon-flap", "Neon Flap", "One tap. Infinite skyline.", "Cartridge Studio", "MIT", "", "FLAP", "#0B1020", "#1B2350", 18234, 312, True),
    ("dot-dodge", "Dot Dodge", "Drag to survive the rain.", "Cartridge Studio", "MIT", "", "DODGE", "#12071F", "#3B0A54", 9312, 187, True),
    ("tap-rush", "Tap Rush", "15 seconds. How many can you hit?", "Cartridge Studio", "MIT", "", "TAP", "#031B1B", "#0C4A44", 4107, 96, True),
]


def main() -> None:
    games = [g for g in GAMES if g[1]]
    packages = {}
    packages_file = DATA / "packages.json"
    if packages_file.exists():
        packages = json.loads(packages_file.read_text())

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        for (slug, title, description, author, license_spdx, source_url,
             poster, top, bottom, likes, comments, bundled) in games:
            game = db.query(Game).filter(Game.slug == slug).first()
            if game is None:
                game = Game(slug=slug)
                db.add(game)
            game.title = title
            game.description = description
            game.author = author
            game.license_spdx = license_spdx
            game.source_url = source_url
            game.poster_style = poster
            game.accent_top = top
            game.accent_bottom = bottom
            # Real counts only: no synthetic baselines.
            game.initial_likes = 0
            game.initial_comments = 0
            game.bundled = bundled
            game.status = "verified"
            game.orientation = ORIENTATIONS.get(slug, "any")
            if slug in packages:
                game.package_url = f"{PUBLIC_BASE_URL}/static/packages/{slug}.zip"
                game.package_sha256 = packages[slug]["sha256"]
        db.commit()
        count = db.query(Game).filter(Game.status == "verified").count()
        print(f"seeded {count} verified games")
    finally:
        db.close()


if __name__ == "__main__":
    main()

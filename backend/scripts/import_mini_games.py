"""Import the 'mini-browser-games' collection (MIT) as cartridges.

The repo (wangzifan396-wzf/mini-browser-games) is a single-author MIT-licensed
collection of ~124 zero-dependency single-file HTML5 games with an explicit
quality audit (GAME_TIERS.json). Deprecated "E" tier games are skipped.

Each active game is packaged as its own cartridge zip (index.html + LICENSE)
and promoted to verified, ready to appear in the app.

Run from backend/:
  .venv/bin/python scripts/import_mini_games.py
"""

import hashlib
import json
import pathlib
import re
import subprocess
import sys
import zipfile

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.config import PUBLIC_BASE_URL  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import Game  # noqa: E402
from app.routers.admin import derive_poster  # noqa: E402

REPO_URL = "https://github.com/wangzifan396-wzf/mini-browser-games"
REPO_DIR = BACKEND / "data" / "mini-browser-games"
PACKAGES = BACKEND / "app" / "static" / "packages"


def ensure_repo() -> None:
    if REPO_DIR.exists():
        return
    REPO_DIR.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "clone", "--depth", "1", "--quiet", REPO_URL, str(REPO_DIR)],
        check=True,
    )


def main() -> None:
    ensure_repo()
    tiers = json.loads((REPO_DIR / "GAME_TIERS.json").read_text())["tiers"]
    license_path = REPO_DIR / "LICENSE"
    if not license_path.exists():
        raise SystemExit("LICENSE missing from collection repo")

    active = [
        (tier, filename)
        for tier, files in tiers.items()
        if tier.upper() != "E"
        for filename in files
    ]
    print(f"active games: {len(active)} "
          f"(tiers: {', '.join(sorted(t for t in tiers if t.upper() != 'E'))})\n")

    PACKAGES.mkdir(parents=True, exist_ok=True)
    db = SessionLocal()
    imported = skipped_missing = already_live = 0
    try:
        for tier, filename in active:
            source = REPO_DIR / filename
            if not source.is_file():
                print(f"  skip {filename}: file missing")
                skipped_missing += 1
                continue

            stem = pathlib.Path(filename).stem
            slug = "mmg-" + re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
            existing = db.query(Game).filter(Game.slug == slug).first()
            if existing is not None and existing.status == "verified":
                already_live += 1
                continue

            zip_path = PACKAGES / f"{slug}.zip"
            with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(source, "index.html")
                archive.write(license_path, "LICENSE")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()

            title = stem.replace("-", " ").replace("_", " ").title()
            game = existing if existing is not None else Game(slug=slug)
            style, top, bottom = derive_poster(slug)
            game.title = title
            game.description = ""
            game.author = "wangzifan396-wzf"
            game.license_spdx = "MIT"
            game.source_url = REPO_URL
            game.bundled = False
            game.status = "verified"
            game.package_url = f"{PUBLIC_BASE_URL}/static/packages/{slug}.zip"
            game.package_sha256 = digest
            game.poster_style = style
            game.accent_top = top
            game.accent_bottom = bottom
            game.orientation = "any"
            game.tags = f"mini-games,collection,tier-{tier.lower()}"
            game.review_note = (
                f"mini-browser-games collection by wangzifan396-wzf (tier {tier})"
            )
            game.stars = 55
            game.qa_status = ""
            game.qa_keys = ""
            game.qa_note = ""
            if existing is None:
                db.add(game)
            db.commit()
            imported += 1
            print(
                f"  OK {slug} (tier {tier}, {zip_path.stat().st_size // 1024} KB)"
            )

        live = db.query(Game).filter(Game.status == "verified").count()
        print(
            f"\nimported {imported}, already live {already_live}, "
            f"missing {skipped_missing}; verified total: {live}"
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()

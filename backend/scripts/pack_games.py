"""Package the bundled KMP game assets into downloadable zips.

Reads:  ../../composeApp/src/androidMain/assets/games/<slug>/
Writes: ../app/static/packages/<slug>.zip and ../data/packages.json

Run from the backend/ directory:  python scripts/pack_games.py
"""

import hashlib
import json
import pathlib
import zipfile

BACKEND = pathlib.Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
SOURCE = REPO / "composeApp/src/androidMain/assets/games"
OUT = BACKEND / "app/static/packages"
DATA = BACKEND / "data"

SKIP = {"CREDITS.txt"}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for game_dir in sorted(p for p in SOURCE.iterdir() if p.is_dir()):
        slug = game_dir.name
        zip_path = OUT / f"{slug}.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(game_dir.rglob("*")):
                if not file.is_file():
                    continue
                rel = file.relative_to(game_dir)
                if rel.as_posix() in SKIP:
                    continue
                archive.write(file, rel.as_posix())
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        manifest[slug] = {
            "bytes": zip_path.stat().st_size,
            "sha256": digest,
        }
        print(f"packed {slug}: {zip_path.stat().st_size / 1024:.0f} KB")
    (DATA / "packages.json").write_text(json.dumps(manifest, indent=2))
    print(f"\n{len(manifest)} packages -> {OUT}")


if __name__ == "__main__":
    main()

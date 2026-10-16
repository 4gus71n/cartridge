"""Build a Cartridge original (Godot) and publish it to the cartridge-games
GitHub Pages repo.

Usage (from anywhere):
  backend/.venv/bin/python tools/publish_game.py <slug> [--push] [--skip-tests]

Steps:
  1. run games/<slug>/tools/run_tests.sh (the game's gate) unless skipped
  2. godot --import + --export-release "Web" (no-threads, Compatibility)
  3. copy the export to ~/cartridge-games/<slug>/ (playable on Pages)
  4. build a deterministic zip at ~/cartridge-games/packages/<slug>.zip
     (same input -> same sha256) with the Godot license notices inside
  5. upsert the entry in ~/cartridge-games/index.json
  6. with --push: commit + push the hosting repo

Then load it into the catalog: backend/.venv/bin/python backend/scripts/import_hosted.py
"""

import argparse
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import zipfile

REPO = pathlib.Path(__file__).resolve().parents[1]
HOSTING = pathlib.Path.home() / "cartridge-games"
BASE_URL = "https://4gus71n.github.io/cartridge-games"
LICENSES = REPO / "games" / "_shared" / "licenses"
ZIP_EPOCH = (2020, 1, 1, 0, 0, 0)


def run(cmd: list[str], cwd: pathlib.Path) -> None:
    print("$", " ".join(cmd))
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        sys.exit(f"command failed ({result.returncode}): {' '.join(cmd)}")


def deterministic_zip(src: pathlib.Path, dest: pathlib.Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in sorted(p for p in src.rglob("*") if p.is_file()):
            info = zipfile.ZipInfo(file.relative_to(src).as_posix(), ZIP_EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, file.read_bytes(), compresslevel=9)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("slug")
    parser.add_argument("--push", action="store_true")
    parser.add_argument("--skip-tests", action="store_true")
    args = parser.parse_args()

    project = REPO / "games" / args.slug
    meta = json.loads((project / "cartridge.json").read_text())
    if not (HOSTING / ".git").exists():
        sys.exit(f"hosting repo not found at {HOSTING}")

    gate = project / "tools" / "run_tests.sh"
    if gate.exists() and not args.skip_tests:
        run([str(gate)], project)

    export_dir = project / "export" / "web"
    shutil.rmtree(export_dir, ignore_errors=True)
    export_dir.mkdir(parents=True)
    run(["godot", "--headless", "--path", ".", "--import"], project)
    run(["godot", "--headless", "--path", ".", "--export-release", "Web",
         "export/web/index.html"], project)
    if not (export_dir / "index.wasm").exists():
        sys.exit("export produced no index.wasm")
    for lic in LICENSES.glob("*.txt"):
        shutil.copy(lic, export_dir / lic.name)
    (export_dir / "cartridge.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))

    site = HOSTING / args.slug
    shutil.rmtree(site, ignore_errors=True)
    shutil.copytree(export_dir, site)
    package = HOSTING / "packages" / f"{args.slug}.zip"
    deterministic_zip(export_dir, package)
    data = package.read_bytes()
    sha = hashlib.sha256(data).hexdigest()

    index_path = HOSTING / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {"games": []}
    games = [g for g in index["games"] if g["slug"] != args.slug]
    previous = next((g for g in index["games"] if g["slug"] == args.slug), None)
    entry = {
        **meta,
        "play_url": f"{BASE_URL}/{args.slug}/index.html",
        "package_url": f"{BASE_URL}/packages/{args.slug}.zip",
        "package_sha256": sha,
        "package_bytes": len(data),
        "updated_at": (previous or {}).get("updated_at")
        if previous and previous.get("package_sha256") == sha
        else datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }
    games.append(entry)
    index["games"] = sorted(games, key=lambda g: g["slug"])
    index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    print(f"published {args.slug} v{meta['version']}: {len(data) / 1e6:.1f} MB, sha256 {sha[:12]}…")

    if args.push:
        run(["git", "add", "-A"], HOSTING)
        status = subprocess.run(["git", "status", "--porcelain"], cwd=HOSTING,
                                capture_output=True, text=True).stdout.strip()
        if status:
            run(["git", "commit", "-m", f"publish {args.slug} v{meta['version']}"], HOSTING)
            run(["git", "push"], HOSTING)
        else:
            print("hosting repo unchanged; nothing to push")


if __name__ == "__main__":
    main()

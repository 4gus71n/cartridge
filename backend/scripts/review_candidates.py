"""Review candidate games and promote the good ones to verified.

For each candidate (sorted by stars, highest first):
  1. find a playable HTML entry (any depth: index.html, *.html, nested dirs)
  2. verify a license file exists in the repo (evidence for our compliance trail)
  3. download the branch tarball, package the game directory into a zip
     (the chosen entry is renamed to index.html for the app loader)
  4. sanity-check the entry looks like a game (canvas/script/engine reference)
  5. promote: status=verified, package_url + sha256, derived poster/orientation

Uses raw.githubusercontent.com + codeload.github.com only, so no GitHub API
rate limits apply.

Run from backend/:
  python scripts/review_candidates.py --limit 60 --min-stars 10
Options:
  --dry-run      do everything except writing zips/DB
  --concurrency  parallel workers (default 4)
  --slug         review one specific slug
  --deep         skip the quick probe and always inspect the tarball
                 (the admin "Package & approve" button uses this mode)
"""

import argparse
import concurrent.futures
import hashlib
import io
import os
import pathlib
import re
import shutil
import sys
import tarfile
import tempfile
import zipfile
from datetime import date

import httpx

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.config import PUBLIC_BASE_URL  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import Game  # noqa: E402
from app.routers.admin import derive_poster  # noqa: E402

PACKAGES = BACKEND / "app" / "static" / "packages"

BRANCHES = ["main", "master", "gh-pages"]
PROBE_NAMES = ["index.html", "index.htm", "game.html", "play.html", "main.html"]
PROBE_DIRS = ["public", "dist", "build", "_site", "docs", "src"]
SKIP_NAME_WORDS = {
    "template", "boilerplate", "starter", "engine", "tutorial", "awesome",
    "portfolio", "example", "demo", "docs", "website", "sdk", "framework",
    "cli", "editor", "resume", "blog", "test", "drawing", "paint",
    "calculator", "notes", "chat", "loader", "manager", "generator",
    "littlejs", "pixijs", "kaboom", "melonjs",
}
ZIP_EXCLUDES = {".git", ".github", ".vscode", "node_modules", "__MACOSX"}
ENTRY_SKIP_NAMES = {"404.html", "error.html", "500.html"}
SOFT_ENGINE_WORDS = (
    "engine", "framework", "library", "toolkit", "sdk", "plugin",
    "component", "boilerplate", "template", "collection", "filters", "admin",
    "multiplayer", "mmorpg", "mmo", "socket.io", "multi-player", "online game",
    "neural", "machine learning", "reinforcement", "save manager", "map generator",
    "test framework", "manifest loader", "ai training",
)
GAME_WORDS = (
    "game", "play", "arcade", "puzzle", "adventure", "shooter", "runner",
    "frogger", "snake", "tetris", "chess", "pacman", "invader", "quiz",
    "solitaire", "platformer", "rogue", "froggy", "mario",
)
ENGINE_MARKERS = (
    "phaser", "pixi", "kaboom", "littlejs", "melonjs", "three.min.js",
    "godot", "unity",
)
LANDSCAPE_HINTS = ("racing", "runner", "running", "shooter", "invaders",
                   "platformer", "pinball")
MAX_TARBALL = 150 * 1024 * 1024
MAX_EXTRACTED = 250 * 1024 * 1024
MAX_ZIP = 80 * 1024 * 1024


class TooLarge(Exception):
    pass


REMOTE_HTML_REF = re.compile(r'(?i)(src|href)\s*=\s*["\'](https?://[^"\']+)["\']')
REMOTE_CSS_REF = re.compile(r'(?i)url\(\s*([\'"]?)(https?://[^\'")]+)\1\s*\)')
INTEGRITY_ATTR = re.compile(r'(?i)\s+integrity\s*=\s*["\'][^"\']*["\']')
CROSSORIGIN_ATTR = re.compile(r'(?i)\s+crossorigin(\s*=\s*["\'][^"\']*["\'])?')
VENDOR_BUDGET = 12 * 1024 * 1024


def vendor_remote_assets(client: httpx.Client, game_dir: pathlib.Path, entry: pathlib.Path) -> None:
    """Download CDN scripts/styles referenced by the game and rewrite them to
    local relative paths, so the packaged game works offline in the WebView."""
    vendor_dir = game_dir / "vendor"
    cache: dict[str, pathlib.Path | None] = {}
    remaining = VENDOR_BUDGET

    def store(url: str) -> pathlib.Path | None:
        nonlocal remaining
        if url in cache:
            return cache[url]
        cache[url] = None
        try:
            response = client.get(url, timeout=30, follow_redirects=True)
        except Exception:
            return None
        if response.status_code != 200 or not response.content:
            return None
        if len(response.content) > remaining:
            return None
        remaining -= len(response.content)
        base = re.sub(r"[^A-Za-z0-9._-]", "_", url.split("?")[0].rsplit("/", 1)[-1]) or "asset"
        name = f"{hashlib.sha1(url.encode()).hexdigest()[:10]}-{base}"
        path = vendor_dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(response.content)
        cache[url] = path
        return path

    text = entry.read_text(encoding="utf-8", errors="replace")
    vendored_any = False

    def html_replace(match: re.Match) -> str:
        nonlocal vendored_any
        attribute, url = match.group(1), match.group(2)
        path = store(url)
        if path is None:
            return match.group(0)
        vendored_any = True
        return f'{attribute}="{path.relative_to(game_dir).as_posix()}"'

    text = REMOTE_HTML_REF.sub(html_replace, text)
    if vendored_any:
        text = INTEGRITY_ATTR.sub("", text)
        text = CROSSORIGIN_ATTR.sub("", text)
    entry.write_text(text, encoding="utf-8")

    for css in list(game_dir.rglob("*.css")):
        try:
            css_text = css.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        def css_replace(match: re.Match) -> str:
            quote, url = match.group(1), match.group(2)
            path = store(url)
            if path is None:
                return match.group(0)
            relative = os.path.relpath(path, css.parent).replace(os.sep, "/")
            return f"url({quote}{relative}{quote})"

        new_text = REMOTE_CSS_REF.sub(css_replace, css_text)
        if new_text != css_text:
            css.write_text(new_text, encoding="utf-8")


def raw_url(owner: str, repo: str, branch: str, path: str) -> str:
    return f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}"


def tarball_url(owner: str, repo: str, branch: str) -> str:
    return f"https://codeload.github.com/{owner}/{repo}/tar.gz/{branch}"


def fetch_text(client: httpx.Client, url: str, limit: int = 4000) -> str | None:
    try:
        response = client.get(url, timeout=20, follow_redirects=True)
        if response.status_code != 200:
            return None
        return response.text[:limit]
    except Exception:
        return None


def looks_like_game(entry_html: str, title: str, description: str) -> bool:
    title_desc = f"{title} {description}".lower()
    entry_lower = entry_html.lower()
    match = re.search(r"<title[^>]*>(.*?)</title>", entry_lower, re.S)
    entry_title = match.group(1)[:200] if match else ""
    game_word = any(word in f"{title_desc} {entry_title}" for word in GAME_WORDS)
    uses_engine = any(marker in entry_lower for marker in ENGINE_MARKERS)
    if uses_engine and game_word:
        return True
    if any(word in title_desc for word in SOFT_ENGINE_WORDS):
        return False
    return game_word


def guess_orientation(description: str) -> str:
    lowered = (description or "").lower()
    return "landscape" if any(h in lowered for h in LANDSCAPE_HINTS) else "any"


def probe_entry(client: httpx.Client, owner: str, repo: str) -> tuple[str, str] | None:
    """Cheap pre-screen: probe common entry locations via raw URLs."""
    for branch in BRANCHES:
        for name in PROBE_NAMES:
            text = fetch_text(client, raw_url(owner, repo, branch, name), limit=1500)
            if text is not None and len(text) > 400:
                return branch, name
        for directory in PROBE_DIRS:
            path = f"{directory}/index.html"
            text = fetch_text(client, raw_url(owner, repo, branch, path), limit=1500)
            if text is not None and len(text) > 400:
                return branch, path
    return None


def download_tarball(
    client: httpx.Client, owner: str, repo: str, prefer: str | None
) -> tuple[str, bytes] | None:
    branches = ([prefer] if prefer else []) + [b for b in BRANCHES if b != prefer]
    for branch in branches:
        try:
            response = client.get(tarball_url(owner, repo, branch), timeout=180)
        except Exception:
            continue
        if response.status_code == 200 and len(response.content) > 0:
            if len(response.content) > MAX_TARBALL:
                raise TooLarge(f"{len(response.content) // (1024 * 1024)}MB archive")
            return branch, response.content
    return None


def extract_tree(data: bytes) -> tuple[pathlib.Path, pathlib.Path] | None:
    tmpdir = pathlib.Path(tempfile.mkdtemp(prefix="cartridge-review-"))
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            if sum(m.size for m in members) > MAX_EXTRACTED:
                return None
            for member in members:
                parts = pathlib.PurePosixPath(member.name).parts
                if any(part in ZIP_EXCLUDES for part in parts):
                    continue
                if member.name.startswith("/") or ".." in parts:
                    continue
                tar.extract(member, tmpdir)
    except Exception:
        return None
    roots = [p for p in tmpdir.iterdir() if p.is_dir()]
    if not roots:
        return None
    return tmpdir, roots[0]


def entry_score(path: pathlib.Path, root: pathlib.Path) -> int:
    relative = path.relative_to(root)
    parts = [p.lower() for p in relative.parts]
    depth = len(parts) - 1
    name = path.name.lower()
    score = 0
    if name in ("index.html", "index.htm"):
        score += 60
    elif "game" in name or "play" in name or "mario" in name:
        score += 40
    else:
        score += 10
    if depth == 0:
        score += 30
    elif parts[0] in ("public", "dist", "build", "_site", "docs", "src"):
        score += 20
    else:
        score -= depth * 5
    try:
        if path.stat().st_size > 3000:
            score += 10
    except OSError:
        pass
    return score


def find_entry_in_tree(
    root: pathlib.Path, title: str, description: str
) -> pathlib.Path | None:
    candidates = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        name = path.name.lower()
        if not (name.endswith(".html") or name.endswith(".htm")):
            continue
        if name in ENTRY_SKIP_NAMES:
            continue
        relative = path.relative_to(root)
        parts = [p.lower() for p in relative.parts]
        if any(part in ZIP_EXCLUDES or part in ("test", "tests", "__tests__", "spec")
               for part in parts[:-1]):
            continue
        if len(parts) > 4 or path.stat().st_size < 800:
            continue
        candidates.append(path)

    viable = []
    for path in candidates:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if looks_like_game(text, title, description):
            viable.append(path)
    if not viable:
        return None
    return max(viable, key=lambda p: entry_score(p, root))


def find_license_in_tree(root: pathlib.Path) -> pathlib.Path | None:
    best = None
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        upper = path.name.upper()
        if upper.startswith("LICENSE") or upper.startswith("COPYING") or upper.startswith("LICENCE"):
            depth = len(path.relative_to(root).parts)
            if depth <= 2 and (best is None or depth < len(best.relative_to(root).parts)):
                best = path
    return best


def package_tree(
    client: httpx.Client,
    root: pathlib.Path,
    game_dir: pathlib.Path,
    entry: pathlib.Path,
    license_file: pathlib.Path,
    slug: str,
) -> tuple[pathlib.Path, str] | None:
    entry_text = entry.read_text(encoding="utf-8", errors="replace")
    # SPA builds often use root-absolute asset paths; our WebView serves the
    # game from a subdirectory, so rewrite "/..." to "./...".
    patched = re.sub(r'(?i)(src|href)="/', r'\1="./', entry_text)
    if patched != entry_text:
        entry.write_text(patched, encoding="utf-8")

    # Vendor CDN scripts/styles so the game runs offline with no external calls.
    vendor_remote_assets(client, game_dir, entry)

    files: dict[str, pathlib.Path] = {}
    for file in sorted(game_dir.rglob("*")):
        if not file.is_file():
            continue
        relative = file.relative_to(game_dir)
        if any(part in ZIP_EXCLUDES for part in relative.parts):
            continue
        files[relative.as_posix()] = file

    entry_relative = entry.relative_to(game_dir).as_posix()
    if entry_relative not in ("index.html", "index.htm"):
        files.pop(entry_relative, None)
        files["index.html"] = entry

    PACKAGES.mkdir(parents=True, exist_ok=True)
    zip_path = PACKAGES / f"{slug}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for arcname, source in sorted(files.items()):
            archive.write(source, arcname)
        try:
            license_file.relative_to(game_dir)
            license_added = license_file.relative_to(game_dir).as_posix() in files
        except ValueError:
            license_added = False
        if not license_added and license_file.name not in {
            pathlib.PurePosixPath(name).name for name in files
        }:
            archive.write(license_file, f"LICENSE-{license_file.name}")

    if zip_path.stat().st_size > MAX_ZIP:
        zip_path.unlink()
        return None
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    return zip_path, digest


def apply_promotion(db, game, result: dict) -> None:
    style, top, bottom = derive_poster(game.slug)
    game.status = "verified"
    game.bundled = False
    game.package_url = f"{PUBLIC_BASE_URL}/static/packages/{game.slug}.zip"
    game.package_sha256 = result["sha256"]
    game.poster_style = style
    game.accent_top = top
    game.accent_bottom = bottom
    game.orientation = guess_orientation(game.description)
    game.tags = (game.tags + ",auto-reviewed").strip(",")
    game.review_note = (
        f"reviewed {date.today().isoformat()}; license file: {result['license_file']}; "
        f"entry: {result['entry']}; branch: {result['branch']}"
    )
    db.commit()


def review_one(record: dict, deep: bool = False) -> dict:
    slug = record["slug"]
    owner = record["owner"]
    repo = record["repo"]
    result = {"slug": slug, "status": "skipped", "note": ""}

    if not deep and set(slug.split("-")) & SKIP_NAME_WORDS:
        result["note"] = "name looks like a template/engine"
        return result

    with httpx.Client(headers={"User-Agent": "cartridge-review"}) as client:
        branch: str | None = None
        if not deep:
            probed = probe_entry(client, owner, repo)
            if probed is not None:
                branch = probed[0]
            else:
                # Probe missed; if the metadata still smells like a game,
                # fall through to a deep tarball inspection.
                haystack = (
                    f"{record.get('title', '')} {record.get('description', '')}".lower()
                )
                if not any(word in haystack for word in GAME_WORDS):
                    result["note"] = "no playable entry found by probe"
                    return result

        try:
            downloaded = download_tarball(client, owner, repo, branch)
        except TooLarge as error:
            result["note"] = f"repository archive too large ({error})"
            return result
        if downloaded is None:
            result["note"] = "could not download repository tarball"
            return result
        branch, data = downloaded

        extracted = extract_tree(data)
        if extracted is None:
            result["note"] = "repository too large or archive invalid"
            return result
        tmpdir, root = extracted
        try:
            title = record.get("title", "")
            description = record.get("description", "")
            entry = find_entry_in_tree(root, title, description)
            if entry is None:
                result["note"] = "no game-like html entry found in repository"
                return result
            license_file = find_license_in_tree(root)
            if license_file is None:
                result["note"] = "no license file found"
                return result
            game_dir = entry.parent
            packaged = package_tree(client, root, game_dir, entry, license_file, slug)
            if packaged is None:
                result["note"] = "packaging failed (too large or entry invalid)"
                return result
            zip_path, digest = packaged
            result.update(
                {
                    "status": "promoted",
                    "branch": branch,
                    "entry": entry.relative_to(root).as_posix(),
                    "license_file": license_file.name,
                    "zip_path": str(zip_path),
                    "sha256": digest,
                }
            )
            return result
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--min-stars", type=int, default=5)
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--deep", action="store_true")
    parser.add_argument("--slug", type=str, default="")
    parser.add_argument("--tag", type=str, default="")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        query = db.query(Game).filter(Game.status == "candidate", Game.review_note == "")
        if args.tag:
            query = query.filter(Game.tags.like(f"%{args.tag}%"))
        if args.slug:
            query = query.filter(Game.slug == args.slug)
        else:
            query = query.filter(Game.stars >= args.min_stars)
        candidates = (
            query.order_by(Game.stars.desc()).limit(args.limit).all()
            if not args.slug
            else query.all()
        )
        verified_urls = {
            (g.source_url or "").rstrip("/").lower().removesuffix(".git")
            for g in db.query(Game).filter(Game.status == "verified").all()
            if g.source_url
        }
        records = []
        for game in candidates:
            match = re.match(r"https?://github\.com/([^/]+)/([^/]+)", game.source_url or "")
            if not match:
                continue
            url = (game.source_url or "").rstrip("/").lower().removesuffix(".git")
            if url in verified_urls:
                print(f"  skip {game.slug}: duplicate of an existing verified game")
                continue
            records.append(
                {
                    "slug": game.slug,
                    "owner": match.group(1),
                    "repo": match.group(2).removesuffix(".git"),
                    "game_id": game.id,
                    "title": game.title,
                    "description": game.description,
                }
            )

        print(f"reviewing {len(records)} candidates (min-stars={args.min_stars})...\n")
        promoted = skipped = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futures = {
                pool.submit(review_one, record, args.deep): record for record in records
            }
            for future in concurrent.futures.as_completed(futures):
                record = futures[future]
                try:
                    result = future.result()
                except Exception as error:  # noqa: BLE001
                    print(f"  ERROR {record['slug']}: {error}")
                    continue
                mark = "OK  " if result["status"] == "promoted" else "skip"
                print(f"  {mark} {record['slug']}: {result.get('note') or 'promoted'}")
                if result["status"] == "promoted" and not args.dry_run:
                    game = db.get(Game, record["game_id"])
                    apply_promotion(db, game, result)
                    promoted += 1
                else:
                    if not args.dry_run:
                        game = db.get(Game, record["game_id"])
                        game.review_note = (
                            f"auto-review skipped {date.today().isoformat()}: "
                            f"{result.get('note') or 'not game-like'}"
                        )
                        db.commit()
                    skipped += 1

        total_verified = db.query(Game).filter(Game.status == "verified").count()
        print(f"\npromoted {promoted}, skipped {skipped}; "
              f"verified games in database: {total_verified}")
    finally:
        db.close()


if __name__ == "__main__":
    main()

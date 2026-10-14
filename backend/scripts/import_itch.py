"""Import open-source web games from itch.io.

Crawls https://itch.io/games/platform-web/tag-open-source with Playwright,
visits each game page, looks for a GitHub repository link, verifies the
repository license is one we can redistribute, and registers the repository
as a candidate game (same pipeline as the GitHub import).

We never download or re-host anything from itch.io itself: itch is used for
discovery only, and the game is packaged from its own repository.

Run from backend/:
  .venv/bin/python scripts/import_itch.py --limit 150
Options:
  --limit N   max number of game pages to visit (default 150)
  --headed    show the browser window (debugging)
"""

import argparse
import json
import pathlib
import re
import sys
import time

import httpx
from playwright.sync_api import sync_playwright

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app import models  # noqa: E402,F401
from app.db import Base, SessionLocal, engine  # noqa: E402
from app.models import Game  # noqa: E402

DATA = BACKEND / "data"
BROWSE_URL = "https://itch.io/games/platform-web/tag-open-source"
SEEN_FILE = DATA / "itch_seen.json"

ALLOWED_LICENSES = {
    "MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "ISC",
    "CC0-1.0", "CC-BY-4.0", "Unlicense", "MPL-2.0", "0BSD",
}

GITHUB_REPO_RE = re.compile(
    r"^https?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$"
)
RESERVED_OWNERS = {
    "features", "marketplace", "sponsors", "topics", "orgs", "about",
    "pricing", "enterprise", "login", "join", "settings", "notifications",
    "explore", "trending", "collections", "events", "apps", "contact",
    "security", "site", "readme", "solutions", "customer-stories",
}

LICENSE_FILES = [
    "LICENSE", "LICENSE.md", "LICENSE.txt", "license", "license.md",
    "license.txt", "COPYING", "COPYING.txt", "LICENSE-MIT", "LICENCE",
]

# Order matters: 3-clause BSD before 2-clause.
LICENSE_FINGERPRINTS = [
    ("BSD-3-Clause", ("redistribution and use in source and binary forms",
                      "neither the name")),
    ("BSD-2-Clause", ("redistribution and use in source and binary forms",)),
    ("MIT", ("permission is hereby granted, free of charge",)),
    ("ISC", ("permission to use, copy, modify, and/or distribute this software",)),
    ("Apache-2.0", ("apache license", "version 2.0")),
    ("MPL-2.0", ("mozilla public license",)),
    ("Unlicense", ("free and unencumbered software released into the public domain",)),
    ("CC0-1.0", ("cc0 1.0",)),
    ("CC-BY-4.0", ("creative commons attribution 4.0",)),
    ("0BSD", ("permission to use, copy, modify, and/or distribute this software",
              "zero-clause")),
]


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")[:120]


def classify_license(text: str) -> str | None:
    lowered = text.lower()[:8000]
    if "gnu general public license" in lowered or "gnu affero" in lowered:
        return "GPL"  # explicitly not usable
    for spdx, needles in LICENSE_FINGERPRINTS:
        if all(needle in lowered for needle in needles):
            return spdx
    return None


def fetch_license_spdx(client: httpx.Client, owner: str, repo: str) -> str | None:
    for branch in ("main", "master"):
        for name in LICENSE_FILES:
            url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{name}"
            try:
                response = client.get(url, timeout=15)
            except Exception:
                continue
            if response.status_code == 200 and response.text.strip():
                spdx = classify_license(response.text)
                if spdx:
                    return spdx
        try:
            response = client.get(
                f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/package.json",
                timeout=15,
            )
            if response.status_code == 200:
                match = re.search(r'"license"\s*:\s*"([^"]+)"', response.text)
                if match:
                    candidate = match.group(1)
                    if candidate in ALLOWED_LICENSES:
                        return candidate
        except Exception:
            pass
    return None


def fetch_stars(client: httpx.Client, owner: str, repo: str) -> int:
    try:
        response = client.get(f"https://github.com/{owner}/{repo}", timeout=20)
        if response.status_code == 200:
            match = re.search(
                r'id="repo-stars-counter-star"[^>]*title="([\d,]+)"', response.text
            )
            if match:
                return int(match.group(1).replace(",", ""))
    except Exception:
        pass
    return 0


def collect_game_urls(page, limit: int) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()
    for page_number in range(1, 60):
        target = BROWSE_URL if page_number == 1 else f"{BROWSE_URL}?page={page_number}"
        page.goto(target, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(2000)
        hrefs = page.eval_on_selector_all(
            ".game_cell a.title, a.game_link",
            "els => els.map(e => e.href).filter(Boolean)",
        )
        new = 0
        for href in hrefs:
            clean = href.split("?")[0]
            if clean not in seen:
                seen.add(clean)
                urls.append(clean)
                new += 1
                if len(urls) >= limit:
                    return urls[:limit]
        print(f"  browse page {page_number}: +{new} links (total {len(urls)})", flush=True)
        if new == 0:
            break
    return urls[:limit]


def extract_game(page, url: str) -> dict:
    page.goto(url, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(1200)

    def text_of(selector: str, limit: int = 600) -> str:
        element = page.query_selector(selector)
        if element is None:
            return ""
        return (element.inner_text() or "").strip()[:limit]

    github_links = page.eval_on_selector_all(
        "a[href*='github.com']", "els => els.map(e => e.href)"
    )
    return {
        "itch_url": url,
        "title": text_of("h1.game_title", 200),
        "author": text_of(".game_author a, a.user_link", 120),
        "description": text_of(".formatted_description", 600).replace("\n", " "),
        "github_links": github_links,
    }


def pick_repo(links: list[str]) -> str | None:
    for link in links:
        clean = link.split("?")[0].rstrip("/")
        match = GITHUB_REPO_RE.match(clean)
        if not match:
            continue
        owner = match.group(1)
        if owner.lower() in RESERVED_OWNERS:
            continue
        return f"https://github.com/{match.group(1)}/{match.group(2)}"
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=150)
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    if SEEN_FILE.exists():
        seen = set(json.loads(SEEN_FILE.read_text()))

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    stats = {"visited": 0, "no_github": 0, "bad_license": 0, "duplicate": 0,
             "imported": 0, "page_error": 0}
    imported_games = []
    outcomes: list[dict] = []

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=not args.headed)
            page = browser.new_page(
                viewport={"width": 1280, "height": 900},
                user_agent=(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
                ),
            )
            # Images/fonts/media are irrelevant for link extraction; skipping
            # them makes the crawl roughly twice as fast.
            page.route(
                "**/*",
                lambda route: route.abort()
                if route.request.resource_type in ("image", "media", "font")
                else route.continue_(),
            )

            print("collecting game links from itch.io browse page...", flush=True)
            urls = collect_game_urls(page, args.limit)
            print(f"visiting {len(urls)} game pages...\n", flush=True)

            client = httpx.Client(headers={"User-Agent": "cartridge-import"})
            for index, url in enumerate(urls, 1):
                if url in seen:
                    continue
                seen.add(url)
                try:
                    info = extract_game(page, url)
                except Exception as error:  # noqa: BLE001
                    stats["page_error"] += 1
                    outcomes.append({
                        "title": url, "itch_url": url, "outcome": "page_error",
                        "detail": str(error)[:160],
                    })
                    print(f"  [{index}] {url} -> page error: {error}", flush=True)
                    continue
                stats["visited"] += 1
                repo_url = pick_repo(info["github_links"])
                if repo_url is None:
                    stats["no_github"] += 1
                    outcomes.append({
                        "title": info["title"] or url, "itch_url": url,
                        "outcome": "no_github", "detail": "no GitHub link on the page",
                    })
                    print(f"  [{index}] {info['title'] or url} -> no GitHub link", flush=True)
                    continue

                owner, repo = repo_url.split("/")[-2:]
                spdx = fetch_license_spdx(client, owner, repo)
                if spdx is None or spdx not in ALLOWED_LICENSES:
                    stats["bad_license"] += 1
                    outcomes.append({
                        "title": info["title"] or url, "itch_url": url,
                        "outcome": "bad_license", "repo": repo_url,
                        "detail": spdx or "no license file found",
                    })
                    print(
                        f"  [{index}] {info['title'] or url} -> license not usable "
                        f"({spdx or 'not found'})",
                        flush=True,
                    )
                    continue

                slug = f"gh-{slugify(owner)}-{slugify(repo)}"
                existing = db.query(Game).filter(Game.slug == slug).first()
                if existing is not None and not existing.review_note.startswith("cleared"):
                    stats["duplicate"] += 1
                    outcomes.append({
                        "title": info["title"] or url, "itch_url": url,
                        "outcome": "duplicate", "repo": repo_url,
                        "detail": f"already in catalog as {existing.status}",
                    })
                    print(f"  [{index}] {info['title']} -> already known", flush=True)
                    continue

                stars = fetch_stars(client, owner, repo)
                game = existing if existing is not None else Game(slug=slug)
                game.title = info["title"] or repo
                game.description = info["description"] or ""
                game.author = info["author"] or owner
                game.license_spdx = spdx
                game.source_url = repo_url
                game.bundled = False
                game.status = "candidate"
                game.tags = "itch-import,open-source"
                game.stars = stars
                game.review_note = ""
                game.qa_status = ""
                game.qa_keys = ""
                game.qa_note = ""
                if existing is None:
                    db.add(game)
                db.commit()
                stats["imported"] += 1
                imported_games.append({"slug": slug, "itch_url": url, "repo": repo_url})
                outcomes.append({
                    "title": game.title, "itch_url": url, "outcome": "imported",
                    "repo": repo_url, "license": spdx, "stars": stars,
                })
                print(
                    f"  [{index}] {info['title']} -> {repo_url} "
                    f"({spdx}, {stars} stars) IMPORTED",
                    flush=True,
                )
                time.sleep(0.6)

            browser.close()

        (DATA / "itch_candidates.json").write_text(
            json.dumps(imported_games, indent=1)
        )
        SEEN_FILE.write_text(json.dumps(sorted(seen)))

        # Full per-game report.
        (DATA / "itch_report.json").write_text(
            json.dumps({"stats": stats, "games": outcomes}, indent=1)
        )
        groups = {
            "imported": [o for o in outcomes if o["outcome"] == "imported"],
            "bad_license": [o for o in outcomes if o["outcome"] == "bad_license"],
            "no_github": [o for o in outcomes if o["outcome"] == "no_github"],
            "duplicate": [o for o in outcomes if o["outcome"] == "duplicate"],
            "page_error": [o for o in outcomes if o["outcome"] == "page_error"],
        }
        lines = [f"# itch.io open-source web crawl report ({len(outcomes)} games)", ""]
        lines.append(f"Stats: {stats}")
        for name, items in groups.items():
            lines.append(f"\n## {name} ({len(items)})")
            for item in items:
                detail = item.get("detail", "")
                repo = item.get("repo", "")
                license_id = item.get("license", "")
                stars = item.get("stars", "")
                extras = " ".join(
                    str(x) for x in (repo, license_id, f"{stars} stars" if stars != "" else "") if x
                )
                lines.append(f"- {item['title']} — {extras} {('- ' + detail) if detail else ''}".rstrip())
        (DATA / "itch_report.md").write_text("\n".join(lines))
        print(f"\ndone: {stats}")
        print(f"report: {DATA / 'itch_report.md'}")
    finally:
        db.close()


if __name__ == "__main__":
    main()

"""Smoke-test packaged games in a headless browser.

For each verified game with a package zip:
  1. extract it and serve it over HTTP (same-origin like the app WebView)
  2. load it in Playwright at a mobile viewport (orientation-aware)
  3. record page errors, failed requests, and whether anything rendered
  4. detect which keys the game listens for (for the on-screen keyboard)
  5. save a screenshot and write qa_status / qa_keys / qa_note to the DB

Statuses: ok | issues (console/request errors) | broken (page errors / blank)

Run from backend/:
  .venv/bin/python scripts/qa_games.py --limit 50 --concurrency 3
Options:
  --slug SLUG     test one game
  --reported      only test games with open user reports
  --refresh       re-extract zips and re-test even if qa_status is set
"""

import argparse
import concurrent.futures
import http.server
import pathlib
import re
import shutil
import sys
import threading
import zipfile

from playwright.sync_api import sync_playwright

BACKEND = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.db import SessionLocal  # noqa: E402
from app.models import Game, Report  # noqa: E402

PACKAGES = BACKEND / "app" / "static" / "packages"
QA_ROOT = BACKEND / "data" / "qa_games"
SHOTS = BACKEND / "data" / "qa_shots"
PORT = 8907

CODE_KEYS = {
    "KeyW": "W", "KeyA": "A", "KeyS": "S", "KeyD": "D",
    "ArrowUp": "ArrowUp", "ArrowDown": "ArrowDown",
    "ArrowLeft": "ArrowLeft", "ArrowRight": "ArrowRight",
    "Space": "Space", "KeyZ": "Z", "KeyX": "X",
    "Enter": "Enter", "Shift": "Shift",
}
CODEKEY_NUMBERS = {
    "87": "W", "65": "A", "83": "S", "68": "D",
    "38": "ArrowUp", "40": "ArrowDown", "37": "ArrowLeft", "39": "ArrowRight",
    "32": "Space", "90": "Z", "88": "X", "13": "Enter", "16": "Shift",
}
KEY_ORDER = ["W", "A", "S", "D", "ArrowUp", "ArrowDown", "ArrowLeft",
             "ArrowRight", "Space", "Z", "X", "Enter", "Shift"]

_thread_state = threading.local()


def get_browser():
    if not hasattr(_thread_state, "browser"):
        _thread_state.playwright = sync_playwright().start()
        _thread_state.browser = _thread_state.playwright.chromium.launch(headless=True)
    return _thread_state.browser


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(QA_ROOT), **kwargs)

    def log_message(self, *args):
        pass


def detect_keys(game_dir: pathlib.Path) -> list[str]:
    found: set[str] = set()
    budget = 3 * 1024 * 1024
    for file in sorted(game_dir.rglob("*")):
        if budget <= 0:
            break
        if not file.is_file() or file.suffix.lower() not in (".js", ".html", ".htm", ".mjs"):
            continue
        try:
            text = file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        budget -= len(text)
        for token, name in CODE_KEYS.items():
            if token in text:
                found.add(name)
        for match in re.finditer(
            r"(?:keyCode|which)\s*[=!]==?\s*(\d{2,3})|case\s+(\d{2,3})\s*:", text
        ):
            number = match.group(1) or match.group(2)
            if number in CODEKEY_NUMBERS:
                found.add(CODEKEY_NUMBERS[number])
    return [key for key in KEY_ORDER if key in found]


def qa_one(slug: str, orientation: str) -> tuple[str, str, str, str]:
    """Returns (slug, status, keys, note)."""
    browser = get_browser()
    width, height = (844, 390) if orientation == "landscape" else (390, 844)
    context = browser.new_context(viewport={"width": width, "height": height})
    page = context.new_page()
    errors: list[str] = []
    failed: list[str] = []
    page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
    page.on(
        "console",
        lambda m: errors.append(f"console: {m.text}") if m.type == "error" else None,
    )
    page.on("requestfailed", lambda r: failed.append(r.url.rsplit("/", 1)[-1]))

    game_dir = QA_ROOT / slug
    keys = detect_keys(game_dir)
    key_note = f"keys: {','.join(keys)}" if keys else "keys: none detected"

    status, note = "ok", ""
    try:
        page.goto(
            f"http://127.0.0.1:{PORT}/{slug}/index.html",
            timeout=15000,
            wait_until="load",
        )
        page.wait_for_timeout(5000)
        canvas = page.evaluate(
            "() => { const c = document.querySelector('canvas'); "
            "return c ? c.width + 'x' + c.height : ''; }"
        )
        text_len = page.evaluate(
            "() => document.body ? document.body.innerText.trim().length : 0"
        )
        try:
            shot = page.screenshot()
            SHOTS.mkdir(parents=True, exist_ok=True)
            (SHOTS / f"{slug}.png").write_bytes(shot)
        except Exception:
            pass

        if any(e.startswith("pageerror") for e in errors):
            status = "broken"
        elif not canvas and text_len == 0:
            status = "broken"
            errors.append("blank page")
        elif errors or failed:
            status = "issues"

        details = errors[:3] + ([f"{len(failed)} failed requests"] if failed else [])
        content = f"canvas {canvas}" if canvas else f"dom {text_len} chars"
        note = f"{key_note}; {content}"
        if details:
            note += "; " + "; ".join(details)
    except Exception as error:  # noqa: BLE001
        status = "broken"
        note = f"load failed: {error}"
    finally:
        context.close()
    return slug, status, key_note, note[:280]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--concurrency", type=int, default=3)
    parser.add_argument("--slug", type=str, default="")
    parser.add_argument("--reported", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    QA_ROOT.mkdir(parents=True, exist_ok=True)
    SHOTS.mkdir(parents=True, exist_ok=True)

    db = SessionLocal()
    try:
        query = db.query(Game).filter(Game.status == "verified")
        if args.slug:
            query = query.filter(Game.slug == args.slug)
        elif args.reported:
            reported = db.query(Report.game_id).filter(Report.status == "open")
            query = query.filter(Game.id.in_(reported))
        elif not args.refresh:
            query = query.filter(Game.qa_status == "")
        candidates = query.limit(args.limit).all()

        targets = []
        skipped = 0
        for game in candidates:
            zip_path = PACKAGES / f"{game.slug}.zip"
            if not zip_path.exists():
                game.qa_status = "skipped"
                game.qa_note = "not packaged (remote url game)"
                skipped += 1
                continue
            target = QA_ROOT / game.slug
            if target.exists() and args.refresh:
                shutil.rmtree(target)
            if not target.exists():
                target.mkdir(parents=True)
                try:
                    with zipfile.ZipFile(zip_path) as archive:
                        archive.extractall(target)
                except Exception as error:  # noqa: BLE001
                    game.qa_status = "broken"
                    game.qa_note = f"bad zip: {error}"[:280]
                    game.status = "rejected"
                    game.review_note = f"QA unplayable: bad package ({error})"[:300]
                    skipped += 1
                    continue
            targets.append((game.slug, game.orientation))
        db.commit()

        print(f"QA: {len(targets)} games to test ({skipped} skipped)\n", flush=True)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), QuietHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        counts = {"ok": 0, "issues": 0, "broken": 0}
        rejected = 0
        try:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=args.concurrency
            ) as pool:
                futures = {
                    pool.submit(qa_one, slug, orientation): slug
                    for slug, orientation in targets
                }
                for future in concurrent.futures.as_completed(futures):
                    slug, status, key_note, note = future.result()
                    counts[status] = counts.get(status, 0) + 1
                    game = db.query(Game).filter(Game.slug == slug).first()
                    if game:
                        game.qa_status = status
                        game.qa_keys = key_note.removeprefix("keys: ")[:120]
                        game.qa_note = note
                        if status == "broken":
                            # Fully broken: mark unplayable and skip it entirely.
                            game.status = "rejected"
                            game.review_note = f"QA unplayable: {note}"[:300]
                            rejected += 1
                        db.commit()
                    print(f"  [{status:6s}] {slug}: {note}", flush=True)
        finally:
            server.shutdown()

        print(f"\ndone: {counts}; rejected as unplayable: {rejected}")
    finally:
        db.close()


if __name__ == "__main__":
    main()

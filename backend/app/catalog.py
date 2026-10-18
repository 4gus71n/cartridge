"""Public catalog published to GitHub Pages (catalog.json + config.json).

Players read `catalog.json` straight from Pages, so the feed works even when
this backend is offline. The API only adds social data on top.

Contract for other modules: anything that changes what players should see
(approving a version, a takedown, a sync of originals) calls `request_publish()`.
The catalog is built from `games` rows:
  status == "verified"   -> listed
  status == "taken_down" -> listed with taken_down=true so apps delete local copies

Configuration (env):
  CARTRIDGE_HOSTING_DIR   local checkout of the Pages repo (default ~/cartridge-games)
  CARTRIDGE_PAGES_URL     its public URL (default https://4gus71n.github.io/cartridge-games)
  CARTRIDGE_PUBLIC_API    API URL players should use (written to config.json; optional)
  CARTRIDGE_AUTOPUBLISH   "1" = git commit + push on publish (default: on if the
                          hosting dir is a git repo; tests set it to "0")
  CARTRIDGE_SYNC_MINUTES  originals sync interval (default 10; 0 disables periodic sync)
  CARTRIDGE_BACKGROUND    "0" disables the background thread (tests)
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import logging
import os
import pathlib
import shutil
import ssl
import subprocess
import threading
import time
import urllib.request

log = logging.getLogger("cartridge.catalog")

STATIC_PACKAGES = pathlib.Path(__file__).resolve().parent / "static" / "packages"
CATALOG_FORMAT = 1


def hosting_dir() -> pathlib.Path:
    return pathlib.Path(os.getenv("CARTRIDGE_HOSTING_DIR", str(pathlib.Path.home() / "cartridge-games")))


def pages_url() -> str:
    return os.getenv("CARTRIDGE_PAGES_URL", "https://4gus71n.github.io/cartridge-games").rstrip("/")


def _autopublish() -> bool:
    flag = os.getenv("CARTRIDGE_AUTOPUBLISH")
    if flag is not None:
        return flag == "1"
    return (hosting_dir() / ".git").exists()


# --- originals sync (Pages index.json -> games table) ----------------------

def load_index(source: str | None = None) -> dict:
    """Originals index: the local hosting checkout if present, else Pages."""
    local = hosting_dir() / "index.json"
    if source is None and local.exists():
        return json.loads(local.read_text())
    url = source or f"{pages_url()}/index.json"
    path = pathlib.Path(url).expanduser()
    if path.exists():
        return json.loads(path.read_text())
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = ssl.create_default_context()
    with urllib.request.urlopen(url, timeout=20, context=context) as response:
        return json.loads(response.read())


def sync_originals(db, index: dict) -> list[str]:
    """Upsert every game of the originals index. Returns slugs whose package changed."""
    from .models import Game

    changed = []
    for g in index.get("games", []):
        game = db.query(Game).filter(Game.slug == g["slug"]).first()
        if game is None:
            game = Game(slug=g["slug"], initial_likes=0, initial_comments=0, stars=0)
            db.add(game)
        if game.package_sha256 != g["package_sha256"] or game.status != "verified":
            changed.append(g["slug"])
        game.title = g["title"]
        game.title_es = g.get("title_es", "")
        game.description = g.get("description", "")
        game.description_es = g.get("description_es", "")
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
        game.version = int(g.get("version", 1))
        game.bundled = False
        game.status = "verified"
        game.review_note = f"cartridge original v{game.version}"
    db.commit()
    return changed


# --- catalog build ---------------------------------------------------------

def _entry(game, db) -> dict:
    from .routers.games import game_to_out

    out = game_to_out(game, db).model_dump()
    out.update(
        version=getattr(game, "version", 1) or 1,
        title_es=getattr(game, "title_es", "") or "",
        description_es=getattr(game, "description_es", "") or "",
        taken_down=game.status == "taken_down",
    )
    # Locally served legacy packages must also live on Pages so players can
    # download them while this machine is off.
    if "/static/packages/" in (out.get("package_url") or ""):
        out["package_url"] = f"{pages_url()}/packages/{game.slug}.zip"
    # Check screenshots used as posters live on the backend; mirror them to Pages.
    thumb = out.get("thumbnail_url") or ""
    if "/shots/" in thumb:
        name = thumb.rsplit("/shots/", 1)[1].split("?")[0]
        out["thumbnail_url"] = f"{pages_url()}/shots/{name}"
    # Social counts change constantly; the API serves them live. Keeping them out
    # of the published file avoids a Pages commit for every like.
    out.pop("likes", None)
    out.pop("comments", None)
    return out


def build_catalog(db) -> dict:
    from .models import Game

    games = (
        db.query(Game)
        .filter(Game.status.in_(["verified", "taken_down"]))
        .order_by(Game.id)
        .all()
    )
    return {"format": CATALOG_FORMAT, "games": [_entry(g, db) for g in games]}


def _legacy_packages(catalog: dict) -> list[pathlib.Path]:
    """Copy locally served zips into the Pages repo; returns the copied paths."""
    copied = []
    for g in catalog["games"]:
        if g["package_url"] != f"{pages_url()}/packages/{g['slug']}.zip":
            continue
        src = STATIC_PACKAGES / f"{g['slug']}.zip"
        dst = hosting_dir() / "packages" / f"{g['slug']}.zip"
        if src.exists() and (not dst.exists() or dst.read_bytes() != src.read_bytes()):
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(src, dst)
            copied.append(dst)
    return copied


def _shots(catalog: dict) -> list[pathlib.Path]:
    from . import config

    copied = []
    prefix = f"{pages_url()}/shots/"
    for g in catalog["games"]:
        thumb = g.get("thumbnail_url") or ""
        if not thumb.startswith(prefix):
            continue
        name = thumb[len(prefix):]
        src = config.CHECKS_DIR / "shots" / name
        dst = hosting_dir() / "shots" / name
        if src.exists() and (not dst.exists() or dst.read_bytes() != src.read_bytes()):
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(src, dst)
            copied.append(dst)
    return copied


def write_files(catalog: dict) -> bool:
    """Write catalog.json/config.json into the hosting dir. True if anything changed."""
    root = hosting_dir()
    root.mkdir(parents=True, exist_ok=True)
    changed = bool(_legacy_packages(catalog))
    changed = bool(_shots(catalog)) or changed
    body = json.dumps(catalog, indent=1, ensure_ascii=False, sort_keys=True)
    digest = hashlib.sha256(body.encode()).hexdigest()
    path = root / "catalog.json"
    previous = json.loads(path.read_text()) if path.exists() else {}
    if previous.get("sha256") != digest:
        stamped = dict(catalog, sha256=digest,
                       generated_at=dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"))
        path.write_text(json.dumps(stamped, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
        changed = True
    config_path = root / "config.json"
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    wanted = dict(config, catalog_url=f"{pages_url()}/catalog.json")
    public_api = os.getenv("CARTRIDGE_PUBLIC_API", "").rstrip("/")
    if public_api:
        wanted["api_base_url"] = public_api
    if wanted != config:
        config_path.write_text(json.dumps(wanted, indent=1, sort_keys=True) + "\n")
        changed = True
    return changed


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=hosting_dir(), capture_output=True, text=True)


def push(reason: str) -> bool:
    paths = [n for n in ("catalog.json", "config.json", "packages", "shots") if (hosting_dir() / n).exists()]
    _git("add", *paths)  # a missing pathspec would make git add nothing at all
    if not _git("status", "--porcelain").stdout.strip():
        return False
    _git("commit", "-m", f"catalog: {reason or 'update'}")
    result = _git("push")
    if result.returncode != 0:
        log.warning("catalog push failed: %s", result.stderr.strip()[:300])
        return False
    return True


def publish(db, reason: str = "") -> dict:
    """Build + write + (optionally) push. Returns a small status dict."""
    catalog = build_catalog(db)
    changed = write_files(catalog)
    pushed = push(reason) if changed and _autopublish() else False
    log.info("catalog %s: %d games, changed=%s pushed=%s", reason, len(catalog["games"]), changed, pushed)
    return {"games": len(catalog["games"]), "changed": changed, "pushed": pushed}


def sync_and_publish(reason: str = "sync") -> dict:
    from .db import SessionLocal

    db = SessionLocal()
    try:
        synced = sync_originals(db, load_index())
        result = publish(db, f"{reason}: {', '.join(synced)}" if synced else reason)
        return dict(result, synced=synced)
    finally:
        db.close()


# --- background worker -----------------------------------------------------

_lock = threading.Lock()
_pending = threading.Event()
_reasons: list[str] = []
_worker: threading.Thread | None = None
_stop = threading.Event()


def request_publish(reason: str = "") -> None:
    """Debounced, non-blocking publish (safe to call from request handlers)."""
    with _lock:
        _reasons.append(reason)
    _pending.set()


def _run_publish() -> None:
    from .db import SessionLocal

    with _lock:
        reasons = list(_reasons)
        _reasons.clear()
    db = SessionLocal()
    try:
        publish(db, "; ".join(r for r in reasons if r)[:200])
    except Exception:  # noqa: BLE001
        log.exception("catalog publish failed")
    finally:
        db.close()


def _loop(interval_s: float) -> None:
    next_sync = 0.0
    while not _stop.is_set():
        now = time.monotonic()
        if interval_s and now >= next_sync:
            try:
                sync_and_publish("periodic sync")
            except Exception:  # noqa: BLE001
                log.exception("originals sync failed")
            next_sync = now + interval_s
        if _pending.wait(timeout=5):
            _pending.clear()
            _stop.wait(2)  # debounce bursts (e.g. several approvals)
            _run_publish()


def start_background() -> None:
    global _worker
    if _worker is not None or os.getenv("CARTRIDGE_BACKGROUND", "1") == "0":
        return
    minutes = float(os.getenv("CARTRIDGE_SYNC_MINUTES", "10"))
    _worker = threading.Thread(target=_loop, args=(minutes * 60,), daemon=True, name="catalog")
    _worker.start()


def stop_background() -> None:
    _stop.set()

"""Game versions: state machine, serialisation, diffs and the approve/takedown actions.

States:  checking ──► failed_checks
                  └─► needs_review ──► approved ──► superseded
                                   ├─► rejected
                                   └─► superseded   (a newer version was submitted)
"""

import json
import re
import shutil
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from . import catalog, config
from .models import Creator, Game, GameVersion, Submission

CHECKING = "checking"
FAILED = "failed_checks"
NEEDS_REVIEW = "needs_review"
APPROVED = "approved"
REJECTED = "rejected"
SUPERSEDED = "superseded"
STATUSES = (CHECKING, FAILED, NEEDS_REVIEW, APPROVED, REJECTED, SUPERSEDED)
PENDING = (CHECKING, NEEDS_REVIEW)
MAX_PENDING_PER_CREATOR = 5

SHOT_NAME_RE = re.compile(r"^[a-z0-9-]+-v\d+\.png$")

POSTER_STYLES = [
    "TAP", "TILES", "FLAP", "BRICKS", "SNAKE", "MATCH",
    "INVADER", "TOWER", "DODGE", "SPACEPI", "HOLE", "MINE",
]
PALETTES = [
    ("#0B1020", "#1B2350"),
    ("#12071F", "#4C1D95"),
    ("#031B1B", "#0C4A44"),
    ("#1C1917", "#78350F"),
    ("#0F172A", "#312E81"),
    ("#0A1F12", "#1B5E20"),
    ("#1F1147", "#7C2D8A"),
    ("#042F2E", "#155E75"),
]


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")[:80] or "game"


def derive_poster(seed: str) -> tuple[str, str, str]:
    import hashlib

    digest = int(hashlib.sha256(seed.encode()).hexdigest(), 16)
    style = POSTER_STYLES[digest % len(POSTER_STYLES)]
    top, bottom = PALETTES[(digest // 7) % len(PALETTES)]
    return style, top, bottom


def unique_slug(db: Session, title: str) -> str:
    """A slug free in both `games` and `game_versions` (v1 reserves the name)."""
    base = slugify(title)
    slug, counter = base, 2
    while (
        db.query(Game.id).filter(Game.slug == slug).first()
        or db.query(GameVersion.id).filter(GameVersion.slug == slug).first()
    ):
        slug = f"{base}-{counter}"
        counter += 1
    return slug


def version_from_submission(db: Session, submission: Submission) -> GameVersion:
    """Legacy /submissions row -> v1 GameVersion awaiting review (no checks ran)."""
    version = GameVersion(
        slug=unique_slug(db, submission.title),
        creator_id=None,
        version=1,
        title=submission.title,
        description=submission.description,
        play_url=submission.url,
        source_url=submission.url,
        license_spdx=submission.license_spdx,
        poster_url=submission.image_url,
        status=NEEDS_REVIEW if submission.status == "pending" else REJECTED,
        report="[]",
        legacy_submission_id=submission.id,
    )
    db.add(version)
    return version


def load_json(text: str, fallback):
    try:
        return json.loads(text or "")
    except ValueError:
        return fallback


def version_out(v: GameVersion) -> dict:
    return {
        "id": v.id,
        "slug": v.slug,
        "version": v.version,
        "status": v.status,
        "title": v.title,
        "title_es": v.title_es,
        "description": v.description,
        "description_es": v.description_es,
        "play_url": v.play_url,
        "package_url": v.package_url,
        "source_url": v.source_url,
        "license_spdx": v.license_spdx,
        "orientation": v.orientation,
        "poster_url": v.poster_url,
        "sha256": v.sha256,
        "size_bytes": v.size_bytes,
        "file_count": v.file_count,
        "report": load_json(v.report, []),
        "has_screenshot": bool(v.screenshot_path),
        "reviewer_note": v.reviewer_note,
        "legacy": v.legacy_submission_id is not None,
        "created_at": v.created_at.isoformat() if v.created_at else "",
        "checked_at": v.checked_at.isoformat() if v.checked_at else "",
        "reviewed_at": v.reviewed_at.isoformat() if v.reviewed_at else "",
    }


def approved_version(db: Session, slug: str, exclude_id: int | None = None) -> GameVersion | None:
    query = db.query(GameVersion).filter(GameVersion.slug == slug, GameVersion.status == APPROVED)
    if exclude_id is not None:
        query = query.filter(GameVersion.id != exclude_id)
    return query.order_by(GameVersion.version.desc()).first()


def manifest_diff(previous: GameVersion | None, current: GameVersion) -> dict | None:
    """Size / file-count deltas and added, removed and changed files (by CRC)."""
    if previous is None:
        return None
    old = load_json(previous.manifest, {})
    new = load_json(current.manifest, {})
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(p for p in set(old) & set(new) if old[p] != new[p])
    cap = 50
    return {
        "previous_version": previous.version,
        "previous_id": previous.id,
        "size_before": previous.size_bytes,
        "size_after": current.size_bytes,
        "size_delta": current.size_bytes - previous.size_bytes,
        "files_before": previous.file_count,
        "files_after": current.file_count,
        "added": added[:cap],
        "removed": removed[:cap],
        "changed": changed[:cap],
        "added_count": len(added),
        "removed_count": len(removed),
        "changed_count": len(changed),
    }


def _publish_screenshot(v: GameVersion) -> str:
    """Copy the checker screenshot to the public shots dir; returns its URL or ''."""
    if not v.screenshot_path:
        return ""
    src = config.CHECKS_DIR / v.screenshot_path
    if not src.is_file():
        return ""
    name = f"{v.slug}-v{v.version}.png"
    shots = config.CHECKS_DIR / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, shots / name)
    return f"{config.PUBLIC_BASE_URL}/shots/{name}"


def approve(db: Session, v: GameVersion, note: str = "", force: bool = False) -> Game:
    if v.status != NEEDS_REVIEW and not (force and v.status == FAILED):
        raise HTTPException(status_code=400, detail=f"Version is {v.status}, not needs_review")

    creator = db.get(Creator, v.creator_id) if v.creator_id else None
    game = db.query(Game).filter(Game.slug == v.slug).first()
    if game is not None and (
        game.creator_id != v.creator_id or (game.creator_id is None and v.game_id != game.id)
    ):
        raise HTTPException(status_code=409, detail="Slug belongs to another game")
    if game is None:
        style, top, bottom = derive_poster(v.slug)
        game = Game(
            slug=v.slug,
            title=v.title,
            poster_style=style,
            accent_top=top,
            accent_bottom=bottom,
            bundled=False,
        )
        db.add(game)

    if creator is not None:
        author = creator.display_name
    elif v.legacy_submission_id:
        sub = db.get(Submission, v.legacy_submission_id)
        author = (sub.email.split("@")[0] if sub and sub.email else "") or "community"
    else:
        author = "community"

    tags = [t for t in (game.tags or "").split(",") if t.strip()]
    if "community" not in tags:
        tags.append("community")

    game.title = v.title
    game.title_es = v.title_es
    game.description = v.description
    game.description_es = v.description_es
    game.author = author
    game.license_spdx = v.license_spdx
    game.source_url = v.source_url or v.play_url
    game.play_url = v.play_url
    game.package_url = v.package_url
    game.package_sha256 = v.sha256
    game.orientation = v.orientation or "any"
    game.version = v.version
    game.thumbnail_url = v.poster_url or _publish_screenshot(v) or game.thumbnail_url
    game.tags = ",".join(tags)
    game.creator_id = v.creator_id
    game.status = "verified"
    db.flush()

    for old in db.query(GameVersion).filter(
        GameVersion.slug == v.slug, GameVersion.status == APPROVED, GameVersion.id != v.id
    ):
        old.status = SUPERSEDED
    v.status = APPROVED
    v.game_id = game.id
    v.reviewer_note = note
    v.reviewed_at = datetime.utcnow()
    if v.legacy_submission_id:
        sub = db.get(Submission, v.legacy_submission_id)
        if sub is not None:
            sub.status = "approved"
    db.commit()
    catalog.request_publish(f"approved {v.slug} v{v.version}")
    return game


def reject(db: Session, v: GameVersion, note: str = "") -> None:
    if v.status not in (NEEDS_REVIEW, FAILED, CHECKING):
        raise HTTPException(status_code=400, detail=f"Version is {v.status}")
    v.status = REJECTED
    v.reviewer_note = note
    v.reviewed_at = datetime.utcnow()
    if v.legacy_submission_id:
        sub = db.get(Submission, v.legacy_submission_id)
        if sub is not None:
            sub.status = "rejected"
    db.commit()


def take_down(db: Session, game: Game, note: str = "") -> None:
    game.status = "taken_down"
    game.review_note = (f"taken down: {note}" if note else "taken down")[:300]
    db.commit()
    catalog.request_publish(f"takedown {game.slug}")

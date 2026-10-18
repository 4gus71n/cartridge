"""Creator portal: web pages + JWT API for creators to submit games and updates."""

from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from .. import checks, config
from ..creator_terms import CREATOR_TERMS, CURRENT_TERMS_VERSION
from ..db import get_db
from ..models import Creator, Game, GameVersion, User
from ..schemas import CreatorTermsIn, VersionIn
from ..security import get_current_user
from ..versions import (
    CHECKING,
    MAX_PENDING_PER_CREATOR,
    PENDING,
    SHOT_NAME_RE,
    SUPERSEDED,
    unique_slug,
    version_out,
)

router = APIRouter(tags=["creator"])

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"


@router.get("/portal", include_in_schema=False)
def portal_page():
    return FileResponse(STATIC_DIR / "portal.html")


@router.get("/portal/guide", include_in_schema=False)
def guide_page():
    return FileResponse(STATIC_DIR / "guide.html")


@router.get("/shots/{name}", include_in_schema=False)
def public_shot(name: str):
    """Screenshots of approved versions (used as thumbnails when no poster is given)."""
    path = config.CHECKS_DIR / "shots" / name
    if not SHOT_NAME_RE.match(name) or not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, media_type="image/png")


def _creator_for(user: User, db: Session) -> Creator | None:
    return db.query(Creator).filter(Creator.user_id == user.id).first()


def _creator_out(user: User, creator: Creator | None) -> dict:
    return {
        "email": user.email,
        "is_admin": user.is_admin,
        "is_creator": creator is not None,
        "display_name": creator.display_name if creator else "",
        "terms_version_accepted": creator.terms_version_accepted if creator else "",
        "terms_current_version": CURRENT_TERMS_VERSION,
        "needs_terms": creator is None or creator.terms_version_accepted != CURRENT_TERMS_VERSION,
    }


def get_creator(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> Creator:
    creator = _creator_for(user, db)
    if creator is None or creator.terms_version_accepted != CURRENT_TERMS_VERSION:
        raise HTTPException(status_code=403, detail="Accept the current creator terms first")
    return creator


@router.get("/creator/terms")
def creator_terms():
    return {"version": CURRENT_TERMS_VERSION, "text": CREATOR_TERMS}


@router.post("/creator/terms")
def accept_terms(
    payload: CreatorTermsIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if payload.terms_version != CURRENT_TERMS_VERSION:
        raise HTTPException(
            status_code=400, detail=f"Current terms version is {CURRENT_TERMS_VERSION}"
        )
    creator = _creator_for(user, db)
    if creator is None:
        creator = Creator(user_id=user.id, display_name=payload.display_name)
        db.add(creator)
    creator.display_name = payload.display_name
    creator.terms_version_accepted = CURRENT_TERMS_VERSION
    creator.accepted_at = datetime.utcnow()
    db.commit()
    return _creator_out(user, creator)


@router.get("/creator/me")
def creator_me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return _creator_out(user, _creator_for(user, db))


def _new_version(
    db: Session, creator: Creator, slug: str, payload: VersionIn, game: Game | None
) -> GameVersion:
    pending_elsewhere = (
        db.query(GameVersion)
        .filter(
            GameVersion.creator_id == creator.id,
            GameVersion.status.in_(PENDING),
            GameVersion.slug != slug,
        )
        .count()
    )
    if pending_elsewhere >= MAX_PENDING_PER_CREATOR:
        raise HTTPException(
            status_code=429,
            detail=f"You already have {MAX_PENDING_PER_CREATOR} versions waiting; "
            "wait for a review before submitting more",
        )
    last = (
        db.query(GameVersion.version)
        .filter(GameVersion.slug == slug)
        .order_by(GameVersion.version.desc())
        .first()
    )
    number = max(last[0] if last else 0, game.version if game is not None else 0) + 1
    for old in db.query(GameVersion).filter(
        GameVersion.slug == slug, GameVersion.status.in_(PENDING)
    ):
        old.status = SUPERSEDED
    version = GameVersion(
        slug=slug,
        game_id=game.id if game is not None else None,
        creator_id=creator.id,
        version=number,
        status=CHECKING,
        report="[]",
        **payload.model_dump(),
    )
    db.add(version)
    db.commit()
    db.refresh(version)
    checks.wake()
    return version


@router.post("/creator/games")
def create_game(
    payload: VersionIn,
    creator: Creator = Depends(get_creator),
    db: Session = Depends(get_db),
):
    slug = unique_slug(db, payload.title)
    return version_out(_new_version(db, creator, slug, payload, None))


@router.post("/creator/games/{slug}/versions")
def submit_update(
    slug: str,
    payload: VersionIn,
    creator: Creator = Depends(get_creator),
    db: Session = Depends(get_db),
):
    game = db.query(Game).filter(Game.slug == slug).first()
    if game is not None:
        owner = game.creator_id
    else:
        first = db.query(GameVersion).filter(GameVersion.slug == slug).first()
        if first is None:
            raise HTTPException(status_code=404, detail="Game not found")
        owner = first.creator_id
    if owner != creator.id:
        raise HTTPException(status_code=403, detail="You don't own this game")
    if game is not None and game.status == "taken_down":
        raise HTTPException(status_code=409, detail="This game was taken down; contact us")
    return version_out(_new_version(db, creator, slug, payload, game))


@router.get("/creator/games")
def my_games(creator: Creator = Depends(get_creator), db: Session = Depends(get_db)):
    rows = (
        db.query(GameVersion)
        .filter(GameVersion.creator_id == creator.id)
        .order_by(GameVersion.version.desc())
        .all()
    )
    games: dict[str, dict] = {}
    for v in rows:
        entry = games.setdefault(v.slug, {"slug": v.slug, "versions": []})
        entry["versions"].append(version_out(v))
    for slug, entry in games.items():
        game = db.query(Game).filter(Game.slug == slug).first()
        live = next((x for x in entry["versions"] if x["status"] == "approved"), None)
        entry["title"] = entry["versions"][0]["title"]
        entry["game_status"] = game.status if game is not None else ""
        entry["live_version"] = live["version"] if live else None
    return sorted(
        games.values(), key=lambda g: g["versions"][0]["created_at"], reverse=True
    )


@router.get("/creator/versions/{version_id}/screenshot", include_in_schema=False)
def my_screenshot(
    version_id: int,
    creator: Creator = Depends(get_creator),
    db: Session = Depends(get_db),
):
    v = db.get(GameVersion, version_id)
    if v is None or v.creator_id != creator.id or not v.screenshot_path:
        raise HTTPException(status_code=404, detail="Not found")
    path = config.CHECKS_DIR / v.screenshot_path
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, media_type="image/png")

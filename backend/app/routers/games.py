from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Comment, Game, Like, Report, User
from ..schemas import CommentIn, CommentOut, GameOut, ReportIn, ReportOut
from ..security import get_current_user, get_optional_user

router = APIRouter(tags=["games"])


def get_game_or_404(db: Session, slug: str) -> Game:
    game = db.query(Game).filter(Game.slug == slug).first()
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")
    return game


def game_to_out(game: Game, db: Session, base_url: str | None = None) -> GameOut:
    likes = db.query(Like).filter(Like.game_id == game.id).count()
    comments = db.query(Comment).filter(Comment.game_id == game.id).count()
    package_url = game.package_url
    if package_url and base_url:
        # Serve the package from whichever host the client actually reached us on
        # (LAN IP, 127.0.0.1 via adb reverse, emulator alias, ...).
        package_url = f"{base_url.rstrip('/')}/static/packages/{game.slug}.zip"
    return GameOut(
        slug=game.slug,
        title=game.title,
        description=game.description,
        author=game.author,
        license_spdx=game.license_spdx,
        source_url=game.source_url,
        play_url=game.play_url,
        package_url=package_url,
        package_sha256=game.package_sha256,
        thumbnail_url=game.thumbnail_url,
        poster_style=game.poster_style,
        accent_top=game.accent_top,
        accent_bottom=game.accent_bottom,
        bundled=game.bundled,
        status=game.status,
        orientation=game.orientation,
        tags=game.tags,
        likes=game.initial_likes + likes,
        comments=game.initial_comments + comments,
        updated_at=game.updated_at.isoformat() if game.updated_at else "",
    )


@router.get("/games", response_model=list[GameOut])
def list_games(
    request: Request,
    status: str = "verified",
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    query = db.query(Game).filter(Game.status == status)
    if user is not None:
        # Games the user reported are hidden from them.
        reported = db.query(Report.game_id).filter(Report.user_id == user.id)
        query = query.filter(~Game.id.in_(reported))
    games = query.order_by(Game.id.asc()).all()
    base = str(request.base_url)
    return [game_to_out(g, db, base) for g in games]


@router.get("/games/{slug}", response_model=GameOut)
def get_game(slug: str, request: Request, db: Session = Depends(get_db)):
    return game_to_out(get_game_or_404(db, slug), db, str(request.base_url))


REPORT_REASONS = {
    "broken", "graphics", "quality", "desktop", "keyboard", "unplayable",
    "adult", "other", "remove",
}


@router.post("/games/{slug}/report", response_model=ReportOut)
def report_game(
    slug: str,
    payload: ReportIn,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    reason = payload.reason.strip().lower()
    if reason not in REPORT_REASONS:
        raise HTTPException(status_code=422, detail="Unknown report reason")
    details = payload.details.strip()
    if reason == "other" and len(details) < 3:
        raise HTTPException(status_code=422, detail="Please describe the problem")
    report = Report(
        user_id=user.id if user else None,
        game_id=game.id,
        reason=reason,
        details=details[:2000],
    )
    db.add(report)
    if reason in ("unplayable", "remove") and game.status == "verified":
        # Pull it from the catalog immediately. "unplayable" is a quality
        # signal; "remove" is a curation action from the report dialog.
        game.status = "rejected"
        reporter = user.email if user else "guest"
        if reason == "unplayable":
            game.review_note = f"user-reported utterly broken by {reporter}"[:300]
            game.qa_status = "broken"
        else:
            game.review_note = f"removed from catalog by {reporter} (curation)"[:300]
    db.commit()
    db.refresh(report)
    return ReportOut(
        id=report.id,
        game_slug=game.slug,
        reason=report.reason,
        details=report.details,
        status=report.status,
        reporter=user.email if user else "guest",
        created_at=report.created_at.isoformat(),
    )


@router.get("/games/{slug}/comments", response_model=list[CommentOut])
def list_comments(slug: str, db: Session = Depends(get_db)):
    game = get_game_or_404(db, slug)
    rows = (
        db.query(Comment)
        .filter(Comment.game_id == game.id)
        .order_by(Comment.created_at.asc())
        .limit(200)
        .all()
    )
    return [
        CommentOut(
            id=c.id,
            author=(c.user.email.split("@")[0] if c.user else "player"),
            body=c.body,
            created_at=c.created_at.isoformat(),
        )
        for c in rows
    ]


@router.post("/games/{slug}/comments", response_model=CommentOut)
def add_comment(
    slug: str,
    payload: CommentIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    comment = Comment(user_id=user.id, game_id=game.id, body=payload.body.strip())
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return CommentOut(
        id=comment.id,
        author=user.email.split("@")[0],
        body=comment.body,
        created_at=comment.created_at.isoformat(),
    )

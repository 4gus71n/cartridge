import hashlib
import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Game, Report, Submission, User
from ..schemas import CandidateOut, ReportOut, SubmissionOut
from ..security import get_admin_user

router = APIRouter(tags=["admin"])

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

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
    digest = int(hashlib.sha256(seed.encode()).hexdigest(), 16)
    style = POSTER_STYLES[digest % len(POSTER_STYLES)]
    top, bottom = PALETTES[(digest // 7) % len(PALETTES)]
    return style, top, bottom


def submission_out(s: Submission) -> SubmissionOut:
    return SubmissionOut(
        id=s.id,
        title=s.title,
        description=s.description,
        url=s.url,
        license_spdx=s.license_spdx,
        image_url=s.image_url,
        email=s.email,
        status=s.status,
        created_at=s.created_at.isoformat(),
    )


@router.get("/admin", include_in_schema=False)
def admin_page():
    return FileResponse(STATIC_DIR / "admin.html")


@router.get("/admin/submissions", response_model=list[SubmissionOut])
def list_submissions(
    status: str = "pending",
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(Submission)
        .filter(Submission.status == status)
        .order_by(Submission.created_at.asc())
        .all()
    )
    return [submission_out(s) for s in rows]


@router.post("/admin/submissions/{submission_id}/approve")
def approve_submission(
    submission_id: int,
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    submission = db.get(Submission, submission_id)
    if submission is None:
        raise HTTPException(status_code=404, detail="Submission not found")
    if submission.status != "pending":
        raise HTTPException(status_code=400, detail=f"Already {submission.status}")

    base_slug = slugify(submission.title)
    slug = base_slug
    counter = 2
    while db.query(Game).filter(Game.slug == slug).first():
        slug = f"{base_slug}-{counter}"
        counter += 1

    style, top, bottom = derive_poster(slug)
    game = Game(
        slug=slug,
        title=submission.title,
        description=submission.description,
        author=submission.email.split("@")[0] if submission.email else "community",
        license_spdx=submission.license_spdx,
        source_url=submission.url,
        play_url=submission.url,
        thumbnail_url=submission.image_url,
        poster_style=style,
        accent_top=top,
        accent_bottom=bottom,
        bundled=False,
        status="verified",
        tags="community",
    )
    submission.status = "approved"
    db.add(game)
    db.commit()
    return {"approved": True, "game_slug": slug}


@router.get("/admin/candidates")
def list_candidates(
    q: str = "",
    status: str = "candidate",
    include_skipped: bool = False,
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    query = db.query(Game).filter(Game.status == status)
    if not include_skipped:
        query = query.filter(~Game.review_note.like("auto-review skipped%"))
    if q.strip():
        like = f"%{q.strip().lower()}%"
        query = query.filter(
            func.lower(Game.title).like(like) | func.lower(Game.slug).like(like)
        )
    total = query.count()
    rows = (
        query.order_by(Game.stars.desc(), Game.id.asc()).offset(offset).limit(limit).all()
    )
    items = [
        CandidateOut(
            slug=g.slug,
            title=g.title,
            description=g.description,
            author=g.author,
            license_spdx=g.license_spdx,
            source_url=g.source_url,
            stars=g.stars,
            review_note=g.review_note,
            status=g.status,
        )
        for g in rows
    ]
    return {"total": total, "items": items}


@router.post("/admin/candidates/{slug}/reject")
def reject_candidate(
    slug: str,
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    game = db.query(Game).filter(Game.slug == slug, Game.status == "candidate").first()
    if game is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    game.status = "rejected"
    game.review_note = "rejected by admin"
    db.commit()
    return {"rejected": True}


@router.post("/admin/candidates/{slug}/approve")
def approve_candidate(
    slug: str,
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    game = db.query(Game).filter(Game.slug == slug, Game.status == "candidate").first()
    if game is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    match = re.match(r"https?://github\.com/([^/]+)/([^/]+)", game.source_url or "")
    if not match:
        raise HTTPException(status_code=400, detail="Candidate has no GitHub source")

    from scripts.review_candidates import apply_promotion, review_one

    record = {
        "slug": game.slug,
        "owner": match.group(1),
        "repo": match.group(2).removesuffix(".git"),
        "game_id": game.id,
        "title": game.title,
        "description": game.description,
    }
    result = review_one(record, deep=True)
    if result["status"] != "promoted":
        game.review_note = f"manual review: {result.get('note') or 'not packageable'}"
        db.commit()
        return {"approved": False, "reason": result.get("note") or "not packageable"}
    apply_promotion(db, game, result)
    return {
        "approved": True,
        "orientation": game.orientation,
        "package_url": game.package_url,
    }


@router.get("/admin/reports", response_model=list[ReportOut])
def list_reports(
    status: str = "open",
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(Report)
        .filter(Report.status == status)
        .order_by(Report.created_at.asc())
        .all()
    )
    return [
        ReportOut(
            id=r.id,
            game_slug=r.game.slug if r.game else "unknown",
            reason=r.reason,
            details=r.details,
            status=r.status,
            reporter=r.user.email if r.user else "guest",
            created_at=r.created_at.isoformat(),
        )
        for r in rows
    ]


@router.post("/admin/reports/{report_id}/resolve")
def resolve_report(
    report_id: int,
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    report = db.get(Report, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found")
    report.status = "resolved"
    db.commit()
    return {"resolved": True}


@router.post("/admin/submissions/{submission_id}/reject")
def reject_submission(
    submission_id: int,
    _: User = Depends(get_admin_user),
    db: Session = Depends(get_db),
):
    submission = db.get(Submission, submission_id)
    if submission is None:
        raise HTTPException(status_code=404, detail="Submission not found")
    submission.status = "rejected"
    db.commit()
    return {"rejected": True}

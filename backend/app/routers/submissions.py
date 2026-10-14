from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Submission
from ..schemas import SubmissionIn, SubmissionOut

router = APIRouter(tags=["submissions"])

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"


@router.get("/submit", include_in_schema=False)
def submit_page():
    return FileResponse(STATIC_DIR / "submit.html")


@router.post("/submissions", response_model=SubmissionOut)
def create_submission(payload: SubmissionIn, db: Session = Depends(get_db)):
    submission = Submission(
        title=payload.title.strip(),
        description=payload.description.strip(),
        url=payload.url.strip(),
        license_spdx=payload.license_spdx.strip(),
        image_url=payload.image_url.strip(),
        email=payload.email.strip().lower(),
    )
    db.add(submission)
    db.commit()
    db.refresh(submission)
    return SubmissionOut(
        id=submission.id,
        title=submission.title,
        description=submission.description,
        url=submission.url,
        license_spdx=submission.license_spdx,
        image_url=submission.image_url,
        email=submission.email,
        status=submission.status,
        created_at=submission.created_at.isoformat(),
    )

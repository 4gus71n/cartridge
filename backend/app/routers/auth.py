from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..config import ADMIN_EMAILS
from ..db import get_db
from ..models import (
    Collection,
    CollectionItem,
    Comment,
    Creator,
    Game,
    GameVersion,
    Like,
    Report,
    Save,
    User,
)
from ..schemas import AuthOut, DeleteAccountIn, LoginIn, SignupIn, UserOut
from ..security import create_token, get_current_user, hash_password, verify_password

router = APIRouter(tags=["auth"])


def _user_out(user: User) -> UserOut:
    return UserOut(id=user.id, email=user.email, is_admin=user.is_admin)


@router.post("/auth/signup", response_model=AuthOut)
def signup(payload: SignupIn, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(
        email=email,
        password_hash=hash_password(payload.password),
        is_admin=email in ADMIN_EMAILS,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return AuthOut(token=create_token(user.id), user=_user_out(user))


@router.post("/auth/login", response_model=AuthOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == email).first()
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return AuthOut(token=create_token(user.id), user=_user_out(user))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return _user_out(user)


@router.post("/auth/delete")
def delete_account(
    payload: DeleteAccountIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Permanently delete the caller's account and personal data (password required).

    Removed: email, password hash, likes, saves, collections, comments, creator
    profile. Reports stay (anonymised) so moderation history isn't lost.
    Published games stay up under the license they were submitted with, but are
    detached from the account; versions still waiting for review are rejected.
    """
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Wrong password")
    uid = user.id
    collection_ids = [c.id for c in db.query(Collection.id).filter(Collection.user_id == uid)]
    if collection_ids:
        db.query(CollectionItem).filter(CollectionItem.collection_id.in_(collection_ids)).delete(
            synchronize_session=False
        )
    for model in (Collection, Like, Save, Comment):
        db.query(model).filter(model.user_id == uid).delete(synchronize_session=False)
    db.query(Report).filter(Report.user_id == uid).update({Report.user_id: None}, synchronize_session=False)
    creator = db.query(Creator).filter(Creator.user_id == uid).first()
    if creator is not None:
        db.query(GameVersion).filter(
            GameVersion.creator_id == creator.id,
            GameVersion.status.in_(["checking", "needs_review", "failed_checks"]),
        ).update(
            {GameVersion.status: "rejected", GameVersion.reviewer_note: "creator deleted their account"},
            synchronize_session=False,
        )
        db.query(GameVersion).filter(GameVersion.creator_id == creator.id).update(
            {GameVersion.creator_id: None}, synchronize_session=False
        )
        db.query(Game).filter(Game.creator_id == creator.id).update(
            {Game.creator_id: None}, synchronize_session=False
        )
        db.delete(creator)
    db.delete(user)
    db.commit()
    return {"deleted": True}

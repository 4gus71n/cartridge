from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..config import ADMIN_EMAILS
from ..db import get_db
from ..models import User
from ..schemas import AuthOut, LoginIn, SignupIn, UserOut
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

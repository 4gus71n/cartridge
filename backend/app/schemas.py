from typing import Optional

from pydantic import BaseModel, Field, field_validator


def _check_email(value: str) -> str:
    value = value.strip().lower()
    if "@" not in value or len(value) < 5:
        raise ValueError("Invalid email")
    return value


class SignupIn(BaseModel):
    email: str
    password: str = Field(min_length=6, max_length=128)

    _validate_email = field_validator("email")(_check_email)


class LoginIn(BaseModel):
    email: str
    password: str

    _validate_email = field_validator("email")(_check_email)


class UserOut(BaseModel):
    id: int
    email: str
    is_admin: bool


class AuthOut(BaseModel):
    token: str
    user: UserOut


class GameOut(BaseModel):
    slug: str
    title: str
    description: str
    author: str
    license_spdx: str
    source_url: str
    play_url: str
    package_url: str
    package_sha256: str
    thumbnail_url: str
    poster_style: str
    accent_top: str
    accent_bottom: str
    bundled: bool
    status: str
    orientation: str = "any"
    tags: str
    likes: int
    comments: int
    updated_at: str = ""
    version: int = 1
    title_es: str = ""
    description_es: str = ""


class LikeOut(BaseModel):
    liked: bool
    likes: int


class SaveIn(BaseModel):
    collection_id: Optional[int] = None


class SaveOut(BaseModel):
    saved: bool


class CollectionIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class CollectionOut(BaseModel):
    id: int
    name: str
    count: int
    game_slugs: list[str]


class CollectionItemIn(BaseModel):
    slug: str


class CommentIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class CommentOut(BaseModel):
    id: int
    author: str
    body: str
    created_at: str


class CandidateOut(BaseModel):
    slug: str
    title: str
    description: str = ""
    author: str = ""
    license_spdx: str = ""
    source_url: str = ""
    stars: int = 0
    review_note: str = ""
    status: str = ""


class ReportIn(BaseModel):
    reason: str = Field(min_length=3, max_length=30)
    details: str = Field(default="", max_length=2000)


class ReportOut(BaseModel):
    id: int
    game_slug: str
    reason: str
    details: str
    status: str
    reporter: str
    created_at: str


class SubmissionIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)
    url: str = Field(min_length=4, max_length=500)
    license_spdx: str = Field(min_length=2, max_length=50)
    image_url: str = Field(default="", max_length=500)
    email: str = Field(default="", max_length=255)


class SubmissionOut(BaseModel):
    id: int
    title: str
    description: str
    url: str
    license_spdx: str
    image_url: str
    email: str
    status: str
    created_at: str

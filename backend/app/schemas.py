from typing import Optional

from urllib.parse import urlparse

from pydantic import BaseModel, Field, field_validator

from . import config
from .licensing import ALLOWED_LICENSES, canonical_spdx


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


def _https_url(value: str, required: bool) -> str:
    value = (value or "").strip()
    if not value:
        if required:
            raise ValueError("Required")
        return ""
    parsed = urlparse(value)
    if parsed.scheme == "https" and parsed.hostname:
        return value
    if (
        config.ALLOW_LOCAL_URLS
        and parsed.scheme == "http"
        and parsed.hostname in ("127.0.0.1", "localhost")
    ):
        return value
    raise ValueError("Must be an https:// URL")


class CreatorTermsIn(BaseModel):
    display_name: str = Field(min_length=2, max_length=60)
    terms_version: str

    @field_validator("display_name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if len(value) < 2:
            raise ValueError("Display name is too short")
        return value


class VersionIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)
    title_es: str = Field(default="", max_length=200)
    description_es: str = Field(default="", max_length=4000)
    play_url: str = Field(max_length=500)
    package_url: str = Field(max_length=500)
    source_url: str = Field(default="", max_length=500)
    poster_url: str = Field(default="", max_length=500)
    license_spdx: str = Field(max_length=50)
    orientation: str = "any"

    @field_validator("title", "description", "title_es", "description_es")
    @classmethod
    def _strip(cls, value: str) -> str:
        return value.strip()

    @field_validator("play_url", "package_url")
    @classmethod
    def _required_url(cls, value: str) -> str:
        return _https_url(value, required=True)

    @field_validator("source_url", "poster_url")
    @classmethod
    def _optional_url(cls, value: str) -> str:
        return _https_url(value, required=False)

    @field_validator("license_spdx")
    @classmethod
    def _license(cls, value: str) -> str:
        spdx = canonical_spdx(value)
        if spdx not in ALLOWED_LICENSES:
            raise ValueError(f"License must be one of: {', '.join(ALLOWED_LICENSES)}")
        return spdx

    @field_validator("orientation")
    @classmethod
    def _orientation(cls, value: str) -> str:
        if value not in ("any", "portrait", "landscape"):
            raise ValueError("orientation must be any, portrait or landscape")
        return value


class ReviewIn(BaseModel):
    note: str = Field(default="", max_length=500)
    force: bool = False  # approve a failed_checks version anyway (false positive)

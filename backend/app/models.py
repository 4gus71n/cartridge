from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from .db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    is_admin = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Game(Base):
    __tablename__ = "games"

    id = Column(Integer, primary_key=True)
    slug = Column(String(200), unique=True, nullable=False, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False, default="")
    author = Column(String(200), nullable=False, default="")
    license_spdx = Column(String(50), nullable=False, default="MIT")
    source_url = Column(String(500), nullable=False, default="")
    play_url = Column(String(500), nullable=False, default="")
    package_url = Column(String(500), nullable=False, default="")
    package_sha256 = Column(String(64), nullable=False, default="")
    thumbnail_url = Column(String(500), nullable=False, default="")
    poster_style = Column(String(40), nullable=False, default="TAP")
    accent_top = Column(String(20), nullable=False, default="#0B1020")
    accent_bottom = Column(String(20), nullable=False, default="#1B2350")
    bundled = Column(Boolean, nullable=False, default=False)
    status = Column(String(20), nullable=False, default="candidate", index=True)
    orientation = Column(String(20), nullable=False, default="any")
    review_note = Column(String(300), nullable=False, default="")
    qa_status = Column(String(20), nullable=False, default="")
    qa_keys = Column(String(120), nullable=False, default="")
    qa_note = Column(String(300), nullable=False, default="")
    tags = Column(String(300), nullable=False, default="")
    initial_likes = Column(Integer, nullable=False, default=0)
    initial_comments = Column(Integer, nullable=False, default=0)
    stars = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)


class Like(Base):
    __tablename__ = "likes"
    __table_args__ = (UniqueConstraint("user_id", "game_id"),)

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    game_id = Column(Integer, ForeignKey("games.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Save(Base):
    __tablename__ = "saves"
    __table_args__ = (UniqueConstraint("user_id", "game_id"),)

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    game_id = Column(Integer, ForeignKey("games.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Collection(Base):
    __tablename__ = "collections"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(120), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    items = relationship("CollectionItem", cascade="all, delete-orphan", backref="collection")


class CollectionItem(Base):
    __tablename__ = "collection_items"
    __table_args__ = (UniqueConstraint("collection_id", "game_id"),)

    id = Column(Integer, primary_key=True)
    collection_id = Column(
        Integer, ForeignKey("collections.id", ondelete="CASCADE"), nullable=False
    )
    game_id = Column(Integer, ForeignKey("games.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Comment(Base):
    __tablename__ = "comments"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    game_id = Column(Integer, ForeignKey("games.id", ondelete="CASCADE"), nullable=False)
    body = Column(Text, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    user = relationship("User")


class Report(Base):
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    game_id = Column(Integer, ForeignKey("games.id", ondelete="CASCADE"), nullable=False)
    reason = Column(String(30), nullable=False)  # broken | graphics | other
    details = Column(Text, nullable=False, default="")
    status = Column(String(20), nullable=False, default="open", index=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    game = relationship("Game")
    user = relationship("User")


class Submission(Base):
    __tablename__ = "submissions"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False, default="")
    url = Column(String(500), nullable=False)
    license_spdx = Column(String(50), nullable=False)
    image_url = Column(String(500), nullable=False, default="")
    email = Column(String(255), nullable=False, default="")
    status = Column(String(20), nullable=False, default="pending", index=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

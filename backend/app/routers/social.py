from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Collection, CollectionItem, Game, Like, Save, User
from ..schemas import (
    CollectionIn,
    CollectionItemIn,
    CollectionOut,
    GameOut,
    LikeOut,
    SaveIn,
    SaveOut,
)
from ..security import get_current_user
from .games import game_to_out, get_game_or_404

router = APIRouter(tags=["social"])


def _like_count(db: Session, game: Game) -> int:
    return game.initial_likes + db.query(Like).filter(Like.game_id == game.id).count()


@router.post("/games/{slug}/like", response_model=LikeOut)
def like_game(
    slug: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    if not db.query(Like).filter(Like.user_id == user.id, Like.game_id == game.id).first():
        db.add(Like(user_id=user.id, game_id=game.id))
        db.commit()
    return LikeOut(liked=True, likes=_like_count(db, game))


@router.delete("/games/{slug}/like", response_model=LikeOut)
def unlike_game(
    slug: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    row = db.query(Like).filter(Like.user_id == user.id, Like.game_id == game.id).first()
    if row:
        db.delete(row)
        db.commit()
    return LikeOut(liked=False, likes=_like_count(db, game))


@router.get("/me/likes", response_model=list[GameOut])
def my_likes(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    games = (
        db.query(Game)
        .join(Like, Like.game_id == Game.id)
        .filter(Like.user_id == user.id)
        .order_by(Like.created_at.desc())
        .all()
    )
    base = str(request.base_url)
    return [game_to_out(g, db, base) for g in games]


def _get_owned_collection(db: Session, user: User, collection_id: int) -> Collection:
    collection = db.get(Collection, collection_id)
    if collection is None or collection.user_id != user.id:
        raise HTTPException(status_code=404, detail="Collection not found")
    return collection


@router.post("/games/{slug}/save", response_model=SaveOut)
def save_game(
    slug: str,
    payload: SaveIn | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    if not db.query(Save).filter(Save.user_id == user.id, Save.game_id == game.id).first():
        db.add(Save(user_id=user.id, game_id=game.id))
        db.commit()
    if payload and payload.collection_id is not None:
        collection = _get_owned_collection(db, user, payload.collection_id)
        exists = (
            db.query(CollectionItem)
            .filter(
                CollectionItem.collection_id == collection.id,
                CollectionItem.game_id == game.id,
            )
            .first()
        )
        if not exists:
            db.add(CollectionItem(collection_id=collection.id, game_id=game.id))
            db.commit()
    return SaveOut(saved=True)


@router.delete("/games/{slug}/save", response_model=SaveOut)
def unsave_game(
    slug: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    game = get_game_or_404(db, slug)
    row = db.query(Save).filter(Save.user_id == user.id, Save.game_id == game.id).first()
    if row:
        db.delete(row)
    db.query(CollectionItem).filter(
        CollectionItem.game_id == game.id,
        CollectionItem.collection_id.in_(
            db.query(Collection.id).filter(Collection.user_id == user.id)
        ),
    ).delete(synchronize_session=False)
    db.commit()
    return SaveOut(saved=False)


@router.get("/me/saves", response_model=list[GameOut])
def my_saves(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    games = (
        db.query(Game)
        .join(Save, Save.game_id == Game.id)
        .filter(Save.user_id == user.id)
        .order_by(Save.created_at.desc())
        .all()
    )
    base = str(request.base_url)
    return [game_to_out(g, db, base) for g in games]


@router.post("/collections", response_model=CollectionOut)
def create_collection(
    payload: CollectionIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    collection = Collection(user_id=user.id, name=payload.name.strip())
    db.add(collection)
    db.commit()
    db.refresh(collection)
    return CollectionOut(id=collection.id, name=collection.name, count=0, game_slugs=[])


@router.get("/collections", response_model=list[CollectionOut])
def list_collections(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    out = []
    for collection in (
        db.query(Collection)
        .filter(Collection.user_id == user.id)
        .order_by(Collection.created_at.asc())
        .all()
    ):
        slugs = [
            row[0]
            for row in db.query(Game.slug)
            .join(CollectionItem, CollectionItem.game_id == Game.id)
            .filter(CollectionItem.collection_id == collection.id)
            .all()
        ]
        out.append(
            CollectionOut(
                id=collection.id, name=collection.name, count=len(slugs), game_slugs=slugs
            )
        )
    return out


@router.delete("/collections/{collection_id}")
def delete_collection(
    collection_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    collection = _get_owned_collection(db, user, collection_id)
    db.delete(collection)
    db.commit()
    return {"deleted": True}


@router.post("/collections/{collection_id}/items", response_model=CollectionOut)
def add_collection_item(
    collection_id: int,
    payload: CollectionItemIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    collection = _get_owned_collection(db, user, collection_id)
    game = get_game_or_404(db, payload.slug)
    if not db.query(Save).filter(Save.user_id == user.id, Save.game_id == game.id).first():
        db.add(Save(user_id=user.id, game_id=game.id))
    exists = (
        db.query(CollectionItem)
        .filter(
            CollectionItem.collection_id == collection.id,
            CollectionItem.game_id == game.id,
        )
        .first()
    )
    if not exists:
        db.add(CollectionItem(collection_id=collection.id, game_id=game.id))
    db.commit()
    slugs = [
        row[0]
        for row in db.query(Game.slug)
        .join(CollectionItem, CollectionItem.game_id == Game.id)
        .filter(CollectionItem.collection_id == collection.id)
        .all()
    ]
    return CollectionOut(
        id=collection.id, name=collection.name, count=len(slugs), game_slugs=slugs
    )


@router.delete("/collections/{collection_id}/items/{slug}", response_model=CollectionOut)
def remove_collection_item(
    collection_id: int,
    slug: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    collection = _get_owned_collection(db, user, collection_id)
    game = get_game_or_404(db, slug)
    db.query(CollectionItem).filter(
        CollectionItem.collection_id == collection.id,
        CollectionItem.game_id == game.id,
    ).delete()
    db.commit()
    slugs = [
        row[0]
        for row in db.query(Game.slug)
        .join(CollectionItem, CollectionItem.game_id == Game.id)
        .filter(CollectionItem.collection_id == collection.id)
        .all()
    ]
    return CollectionOut(
        id=collection.id, name=collection.name, count=len(slugs), game_slugs=slugs
    )

from app.db import SessionLocal
from app.models import Report, User


def test_delete_account_removes_personal_data(client, auth_headers, game_slug):
    client.post(f"/games/{game_slug}/like", headers=auth_headers)
    client.post(f"/games/{game_slug}/save", headers=auth_headers)
    col = client.post("/collections", json={"name": "Mine"}, headers=auth_headers).json()
    client.post(f"/collections/{col['id']}/items", json={"slug": game_slug}, headers=auth_headers)
    client.post(f"/games/{game_slug}/comments", json={"body": "hi"}, headers=auth_headers)
    client.post(f"/games/{game_slug}/report", json={"reason": "broken", "details": ""}, headers=auth_headers)

    assert client.post("/auth/delete", json={"password": "nope"}, headers=auth_headers).status_code == 401
    assert client.post("/auth/delete", json={"password": "secret123"}).status_code == 401
    assert client.post("/auth/delete", json={"password": "secret123"}, headers=auth_headers).json() == {
        "deleted": True
    }

    db = SessionLocal()
    try:
        assert db.query(User).filter_by(email="player@test.local").first() is None
        assert [r.user_id for r in db.query(Report).all()] == [None]  # moderation history kept, anonymised
    finally:
        db.close()
    assert client.get(f"/games/{game_slug}/comments").json() == []
    assert client.get("/me", headers=auth_headers).status_code == 401  # token is dead
    # the email can sign up again from scratch
    again = client.post("/auth/signup", json={"email": "player@test.local", "password": "secret123"})
    assert again.status_code == 200
    headers = {"Authorization": f"Bearer {again.json()['token']}"}
    assert client.get("/me/likes", headers=headers).json() == []


def test_delete_creator_keeps_published_games(client, creator_headers):
    from app.models import Creator, Game

    db = SessionLocal()
    try:
        creator = db.query(Creator).one()
        db.add(Game(slug="kept", title="Kept", status="verified", creator_id=creator.id))
        db.commit()
    finally:
        db.close()
    assert client.post("/auth/delete", json={"password": "secret123"}, headers=creator_headers).status_code == 200
    db = SessionLocal()
    try:
        assert db.query(Creator).count() == 0
        game = db.query(Game).filter_by(slug="kept").one()
        assert (game.status, game.creator_id) == ("verified", None)
    finally:
        db.close()

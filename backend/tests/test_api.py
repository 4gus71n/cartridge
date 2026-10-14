def test_signup_login_me(client):
    response = client.post(
        "/auth/signup", json={"email": "a@test.local", "password": "secret123"}
    )
    assert response.status_code == 200
    token = response.json()["token"]

    duplicate = client.post(
        "/auth/signup", json={"email": "a@test.local", "password": "secret123"}
    )
    assert duplicate.status_code == 400

    bad_login = client.post(
        "/auth/login", json={"email": "a@test.local", "password": "wrong"}
    )
    assert bad_login.status_code == 401

    login = client.post(
        "/auth/login", json={"email": "a@test.local", "password": "secret123"}
    )
    assert login.status_code == 200

    me = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "a@test.local"


def test_submission_and_admin_approval(client, admin_headers):
    response = client.post(
        "/submissions",
        json={
            "title": "Neon Runner",
            "description": "One tap. Infinite skyline.",
            "url": "https://example.com/neon-runner/",
            "license_spdx": "MIT",
            "image_url": "https://example.com/thumb.png",
            "email": "dev@example.com",
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] == "pending"

    pending = client.get("/admin/submissions?status=pending", headers=admin_headers)
    assert len(pending.json()) == 1

    approved = client.post(
        f"/admin/submissions/{pending.json()[0]['id']}/approve", headers=admin_headers
    )
    assert approved.status_code == 200
    slug = approved.json()["game_slug"]

    games = client.get("/games?status=verified").json()
    assert any(g["slug"] == slug for g in games)
    game = next(g for g in games if g["slug"] == slug)
    assert game["play_url"] == "https://example.com/neon-runner/"
    assert game["license_spdx"] == "MIT"


def test_admin_requires_admin(client, auth_headers):
    response = client.get("/admin/submissions", headers=auth_headers)
    assert response.status_code == 403


def test_like_unlike(client, auth_headers, game_slug):
    unauthenticated = client.post(f"/games/{game_slug}/like")
    assert unauthenticated.status_code == 401

    liked = client.post(f"/games/{game_slug}/like", headers=auth_headers)
    assert liked.status_code == 200
    assert liked.json() == {"liked": True, "likes": 1}

    again = client.post(f"/games/{game_slug}/like", headers=auth_headers)
    assert again.json()["likes"] == 1

    mine = client.get("/me/likes", headers=auth_headers)
    assert [g["slug"] for g in mine.json()] == [game_slug]

    unliked = client.delete(f"/games/{game_slug}/like", headers=auth_headers)
    assert unliked.json() == {"liked": False, "likes": 0}
    assert client.get("/me/likes", headers=auth_headers).json() == []


def test_save_and_collections(client, auth_headers, game_slug):
    saved = client.post(f"/games/{game_slug}/save", json={}, headers=auth_headers)
    assert saved.json() == {"saved": True}
    assert [g["slug"] for g in client.get("/me/saves", headers=auth_headers).json()] == [
        game_slug
    ]

    collection = client.post(
        "/collections", json={"name": "Arcade"}, headers=auth_headers
    ).json()
    assert collection["count"] == 0

    added = client.post(
        f"/collections/{collection['id']}/items",
        json={"slug": game_slug},
        headers=auth_headers,
    )
    assert added.json()["count"] == 1
    assert added.json()["game_slugs"] == [game_slug]

    collections = client.get("/collections", headers=auth_headers).json()
    assert collections[0]["name"] == "Arcade"

    removed = client.delete(
        f"/collections/{collection['id']}/items/{game_slug}", headers=auth_headers
    )
    assert removed.json()["count"] == 0


def test_reports(client, auth_headers, admin_headers, game_slug):
    anonymous = client.post(
        f"/games/{game_slug}/report", json={"reason": "broken", "details": ""}
    )
    assert anonymous.status_code == 200
    assert anonymous.json()["reason"] == "broken"
    assert anonymous.json()["reporter"] == "guest"

    signed = client.post(
        f"/games/{game_slug}/report",
        json={"reason": "graphics", "details": "sprites are corrupted"},
        headers=auth_headers,
    )
    assert signed.json()["reporter"] == "player@test.local"

    needs_details = client.post(
        f"/games/{game_slug}/report", json={"reason": "other", "details": ""}
    )
    assert needs_details.status_code == 422

    invalid = client.post(
        f"/games/{game_slug}/report", json={"reason": "nonsense", "details": ""}
    )
    assert invalid.status_code == 422

    reports = client.get("/admin/reports?status=open", headers=admin_headers)
    assert len(reports.json()) == 2

    resolved = client.post(
        f"/admin/reports/{reports.json()[0]['id']}/resolve", headers=admin_headers
    )
    assert resolved.json() == {"resolved": True}
    assert len(client.get("/admin/reports?status=open", headers=admin_headers).json()) == 1


def test_admin_candidates(client, admin_headers, auth_headers):
    from app.db import SessionLocal
    from app.models import Game

    db = SessionLocal()
    db.add(
        Game(
            slug="gh-test-candidate",
            title="Test Candidate",
            description="a game",
            status="candidate",
            stars=5,
            source_url="https://github.com/example/game",
        )
    )
    db.commit()
    db.close()

    forbidden = client.get("/admin/candidates", headers=auth_headers)
    assert forbidden.status_code == 403

    listing = client.get("/admin/candidates?status=candidate", headers=admin_headers)
    assert listing.status_code == 200
    assert listing.json()["total"] == 1
    assert listing.json()["items"][0]["slug"] == "gh-test-candidate"

    filtered = client.get("/admin/candidates?q=zzz", headers=admin_headers)
    assert filtered.json()["total"] == 0

    rejected = client.post("/admin/candidates/gh-test-candidate/reject", headers=admin_headers)
    assert rejected.json() == {"rejected": True}
    assert client.get("/admin/candidates", headers=admin_headers).json()["total"] == 0


def test_reported_games_hidden_for_reporter(client, auth_headers, game_slug):
    for reason in ("desktop", "adult", "keyboard"):
        response = client.post(
            f"/games/{game_slug}/report",
            json={"reason": reason, "details": ""},
            headers=auth_headers,
        )
        assert response.status_code == 200

    visible_for_reporter = client.get("/games?status=verified", headers=auth_headers)
    assert all(g["slug"] != game_slug for g in visible_for_reporter.json())

    visible_anonymously = client.get("/games?status=verified")
    assert any(g["slug"] == game_slug for g in visible_anonymously.json())

    # "Utterly broken" pulls the game from the catalog for everyone.
    unplayable = client.post(
        f"/games/{game_slug}/report",
        json={"reason": "unplayable", "details": ""},
        headers=auth_headers,
    )
    assert unplayable.status_code == 200
    anonymous_after = client.get("/games?status=verified")
    assert all(g["slug"] != game_slug for g in anonymous_after.json())


def test_remove_report_rejects_globally(client, auth_headers, game_slug):
    response = client.post(
        f"/games/{game_slug}/report",
        json={"reason": "remove", "details": ""},
        headers=auth_headers,
    )
    assert response.status_code == 200
    visible = client.get("/games?status=verified")
    assert all(g["slug"] != game_slug for g in visible.json())


def test_comments(client, auth_headers, game_slug):
    posted = client.post(
        f"/games/{game_slug}/comments",
        json={"body": "So addictive!"},
        headers=auth_headers,
    )
    assert posted.status_code == 200
    assert posted.json()["author"] == "player"
    assert posted.json()["body"] == "So addictive!"

    comments = client.get(f"/games/{game_slug}/comments")
    assert len(comments.json()) == 1

    unauthenticated = client.post(
        f"/games/{game_slug}/comments", json={"body": "nope"}
    )
    assert unauthenticated.status_code == 401

"""Creator portal API: gates, ownership, version state machine, admin review, takedown."""

from app import checks
from app.creator_terms import CURRENT_TERMS_VERSION
from gamekit import ERROR_JS, good_files, write_zip


def payload(base, zip_name, **overrides):
    data = {
        "title": "Neon Tapper",
        "description": "Tap to glow.",
        "title_es": "Tapper Neón",
        "description_es": "Toca para brillar.",
        "play_url": f"{base}/",
        "package_url": f"{base}/{zip_name}",
        "source_url": "https://github.com/maker/neon-tapper",
        "license_spdx": "MIT",
        "orientation": "portrait",
    }
    data.update(overrides)
    return data


def signup(client, email):
    r = client.post("/auth/signup", json={"email": email, "password": "secret123"})
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_pages_and_submit_redirect(client):
    assert "Creator" in client.get("/portal").text
    assert "GitHub Pages" in client.get("/portal/guide").text
    redirect = client.get("/submit", follow_redirects=False)
    assert redirect.status_code in (302, 307) and redirect.headers["location"] == "/portal"
    terms = client.get("/creator/terms").json()
    assert terms["version"] == CURRENT_TERMS_VERSION
    assert "MIT" in terms["text"] and "takedown" in terms["text"].lower()


def test_auth_and_terms_gates(client):
    body = payload("https://example.com", "g.zip")
    assert client.get("/creator/me").status_code == 401
    assert client.post("/creator/games", json=body).status_code == 401
    assert client.get("/creator/games").status_code == 401

    headers = signup(client, "new@test.local")
    me = client.get("/creator/me", headers=headers).json()
    assert me["needs_terms"] is True and me["is_creator"] is False
    assert client.post("/creator/games", json=body, headers=headers).status_code == 403
    assert client.get("/creator/games", headers=headers).status_code == 403

    stale = client.post(
        "/creator/terms", json={"display_name": "New", "terms_version": "1999-01-01"}, headers=headers
    )
    assert stale.status_code == 400
    ok = client.post(
        "/creator/terms",
        json={"display_name": "  New   Maker ", "terms_version": CURRENT_TERMS_VERSION},
        headers=headers,
    )
    assert ok.status_code == 200
    me = client.get("/creator/me", headers=headers).json()
    assert me["needs_terms"] is False and me["display_name"] == "New Maker"
    created = client.post("/creator/games", json=body, headers=headers)
    assert created.status_code == 200
    assert created.json()["status"] == "checking" and created.json()["version"] == 1


def test_validation(client, creator_headers):
    base = "https://example.com"
    for bad in (
        {"play_url": "http://example.com/"},
        {"package_url": "ftp://example.com/g.zip"},
        {"package_url": ""},
        {"source_url": "javascript:alert(1)"},
        {"license_spdx": "GPL-3.0"},
        {"license_spdx": "Other / not sure"},
        {"orientation": "sideways"},
        {"title": ""},
    ):
        r = client.post("/creator/games", json=payload(base, "g.zip", **bad), headers=creator_headers)
        assert r.status_code == 422, bad
    ok = client.post(
        "/creator/games", json=payload(base, "g.zip", license_spdx="cc0-1.0"), headers=creator_headers
    )
    assert ok.json()["license_spdx"] == "CC0-1.0"


def test_ownership_versions_and_rate_limit(client, creator_headers):
    base = "https://example.com"
    v1 = client.post("/creator/games", json=payload(base, "a.zip"), headers=creator_headers).json()
    slug = v1["slug"]
    assert slug == "neon-tapper"
    # same title again gets its own slug
    other = client.post("/creator/games", json=payload(base, "b.zip"), headers=creator_headers).json()
    assert other["slug"] == "neon-tapper-2"

    stranger = signup(client, "stranger@test.local")
    client.post(
        "/creator/terms",
        json={"display_name": "Stranger", "terms_version": CURRENT_TERMS_VERSION},
        headers=stranger,
    )
    hijack = client.post(f"/creator/games/{slug}/versions", json=payload(base, "x.zip"), headers=stranger)
    assert hijack.status_code == 403
    assert client.post("/creator/games/nope/versions", json=payload(base, "x.zip"), headers=stranger).status_code == 404
    assert client.get("/creator/games", headers=stranger).json() == []

    v2 = client.post(f"/creator/games/{slug}/versions", json=payload(base, "a2.zip"), headers=creator_headers)
    assert v2.status_code == 200 and v2.json()["version"] == 2
    mine = {g["slug"]: g for g in client.get("/creator/games", headers=creator_headers).json()}
    assert [(v["version"], v["status"]) for v in mine[slug]["versions"]] == [
        (2, "checking"),
        (1, "superseded"),
    ]
    assert mine[slug]["game_status"] == "" and mine[slug]["live_version"] is None

    # 2 pending so far (neon-tapper v2, neon-tapper-2 v1); 3 more new games fit, the 6th doesn't
    for i in range(3):
        r = client.post("/creator/games", json=payload(base, "c.zip", title=f"Game {i}"), headers=creator_headers)
        assert r.status_code == 200
    blocked = client.post("/creator/games", json=payload(base, "c.zip", title="One too many"), headers=creator_headers)
    assert blocked.status_code == 429
    # an update to a game with a pending version replaces it, so it's still allowed
    again = client.post(f"/creator/games/{slug}/versions", json=payload(base, "a3.zip"), headers=creator_headers)
    assert again.status_code == 200 and again.json()["version"] == 3


def test_full_review_flow(client, creator_headers, admin_headers, auth_headers, file_server, publish_calls):
    base, root = file_server
    write_zip(root / "flow-v1.zip", good_files())
    v1 = client.post("/creator/games", json=payload(base, "flow-v1.zip"), headers=creator_headers).json()
    slug = v1["slug"]

    assert checks.process_pending() == 1
    mine = client.get("/creator/games", headers=creator_headers).json()[0]
    latest = mine["versions"][0]
    assert latest["status"] == "needs_review", latest["report"]
    assert {r["check"] for r in latest["report"]} >= {"download", "zip_safety", "license_file", "boot", "play_url"}
    assert latest["has_screenshot"] and len(latest["sha256"]) == 64
    assert client.get(f"/creator/versions/{latest['id']}/screenshot", headers=creator_headers).status_code == 200

    # admin queue
    assert client.get("/admin/versions", headers=auth_headers).status_code == 403
    queue = client.get("/admin/versions", headers=admin_headers).json()
    assert [q["id"] for q in queue] == [v1["id"]]
    assert queue[0]["diff"] is None and queue[0]["creator"] == "Maker Studio"
    assert queue[0]["contact"] == "maker@test.local"
    shot = client.get(f"/admin/versions/{v1['id']}/screenshot", headers=admin_headers)
    assert shot.status_code == 200 and shot.content[:4] == b"\x89PNG"

    assert client.post(f"/admin/versions/{v1['id']}/approve", headers=auth_headers).status_code == 403
    approved = client.post(f"/admin/versions/{v1['id']}/approve", json={"note": "nice"}, headers=admin_headers)
    assert approved.status_code == 200
    assert publish_calls == [f"approved {slug} v1"]

    from app.db import SessionLocal
    from app.models import Creator, Game

    db = SessionLocal()
    game = db.query(Game).filter(Game.slug == slug).one()
    creator = db.query(Creator).one()
    assert game.status == "verified" and game.creator_id == creator.id
    assert game.package_url == f"{base}/flow-v1.zip"
    assert game.package_sha256 == latest["sha256"]
    assert (game.title_es, game.description_es) == ("Tapper Neón", "Toca para brillar.")
    assert game.author == "Maker Studio" and game.tags == "community"
    assert game.license_spdx == "MIT" and game.orientation == "portrait" and game.version == 1
    assert game.thumbnail_url == f"http://testserver/shots/{slug}-v1.png"
    db.close()
    assert client.get(f"/shots/{slug}-v1.png").status_code == 200
    listed = client.get("/games?status=verified").json()
    assert any(g["slug"] == slug for g in listed)
    # approving twice is not allowed
    assert client.post(f"/admin/versions/{v1['id']}/approve", headers=admin_headers).status_code == 400

    # update: v2 adds a level and changes the game script
    write_zip(root / "flow-v2.zip", good_files(**{"level2.json": "{}", "game.js": "/* v2 */"}))
    v2 = client.post(
        f"/creator/games/{slug}/versions",
        json=payload(base, "flow-v2.zip", poster_url="https://example.com/poster.png"),
        headers=creator_headers,
    ).json()
    checks.process_pending()
    queue = client.get("/admin/versions", headers=admin_headers).json()
    assert [q["id"] for q in queue] == [v2["id"]]
    diff = queue[0]["diff"]
    assert diff["previous_version"] == 1 and diff["files_before"] == 3 and diff["files_after"] == 4
    assert diff["added"] == ["level2.json"] and diff["removed"] == [] and diff["changed"] == ["game.js"]
    client.post(f"/admin/versions/{v2['id']}/approve", headers=admin_headers)
    assert publish_calls[-1] == f"approved {slug} v2"
    versions = client.get("/creator/games", headers=creator_headers).json()[0]["versions"]
    assert [(v["version"], v["status"]) for v in versions] == [(2, "approved"), (1, "superseded")]
    db = SessionLocal()
    game = db.query(Game).filter(Game.slug == slug).one()
    assert game.version == 2 and game.thumbnail_url == "https://example.com/poster.png"
    db.close()

    # v3 gets rejected with a note the creator can read
    v3 = client.post(f"/creator/games/{slug}/versions", json=payload(base, "flow-v2.zip"), headers=creator_headers).json()
    checks.process_pending()
    client.post(f"/admin/versions/{v3['id']}/reject", json={"note": "same as v2"}, headers=admin_headers)
    latest = client.get("/creator/games", headers=creator_headers).json()[0]["versions"][0]
    assert latest["status"] == "rejected" and latest["reviewer_note"] == "same as v2"

    # takedown
    assert client.post(f"/admin/games/{slug}/takedown", headers=auth_headers).status_code == 403
    down = client.post(f"/admin/games/{slug}/takedown", json={"note": "DMCA"}, headers=admin_headers)
    assert down.status_code == 200 and publish_calls[-1] == f"takedown {slug}"
    assert all(g["slug"] != slug for g in client.get("/games?status=verified").json())
    assert client.get("/admin/versions", headers=admin_headers).json() == []
    blocked = client.post(f"/creator/games/{slug}/versions", json=payload(base, "flow-v2.zip"), headers=creator_headers)
    assert blocked.status_code == 409
    assert client.post("/admin/games/nope/takedown", headers=admin_headers).status_code == 404


def test_failed_checks_and_recheck(client, creator_headers, admin_headers, file_server, publish_calls):
    base, root = file_server
    write_zip(root / "crash.zip", good_files(**{"game.js": ERROR_JS}))
    v = client.post("/creator/games", json=payload(base, "crash.zip"), headers=creator_headers).json()
    checks.process_pending()
    mine = client.get("/creator/games", headers=creator_headers).json()[0]["versions"][0]
    assert mine["status"] == "failed_checks"
    assert any(r["check"] == "boot" and r["status"] == "fail" for r in mine["report"])
    assert client.get("/admin/versions", headers=admin_headers).json() == []
    failed = client.get("/admin/versions?status=failed_checks", headers=admin_headers).json()
    assert [f["id"] for f in failed] == [v["id"]]
    assert client.post(f"/admin/versions/{v['id']}/approve", headers=admin_headers).status_code == 400

    # creator fixes the file behind the same URL; admin re-runs the checks
    write_zip(root / "crash.zip", good_files())
    assert client.post(f"/admin/versions/{v['id']}/recheck", headers=admin_headers).json() == {"status": "checking"}
    checks.process_pending()
    assert client.get(f"/admin/versions/{v['id']}", headers=admin_headers).json()["status"] == "needs_review"

    # a version superseded while being checked keeps its superseded status
    v2 = client.post(f"/creator/games/{v['slug']}/versions", json=payload(base, "crash.zip"), headers=creator_headers).json()
    from app.db import SessionLocal
    from app.models import GameVersion

    db = SessionLocal()
    db.get(GameVersion, v2["id"]).status = "superseded"
    db.commit()
    db.close()
    assert checks.run_version(v2["id"]) == "superseded"
    assert publish_calls == []


def test_checker_crash_is_recorded(client, creator_headers, monkeypatch):
    def boom(**_):
        raise RuntimeError("boom")

    monkeypatch.setattr(checks, "check_package", boom)
    v = client.post("/creator/games", json=payload("https://example.com", "g.zip"), headers=creator_headers).json()
    assert checks.process_pending() == 1
    mine = client.get("/creator/games", headers=creator_headers).json()[0]["versions"][0]
    assert mine["id"] == v["id"] and mine["status"] == "failed_checks"
    assert mine["report"][0]["check"] == "internal"


def test_legacy_submission_migration(client, admin_headers, publish_calls):
    from app import migrate
    from app.db import SessionLocal, engine
    from app.models import Game, GameVersion, Submission

    db = SessionLocal()
    for title, status in (("Old Pending", "pending"), ("Old Rejected", "rejected"), ("Old Approved", "approved")):
        db.add(Submission(title=title, description="d", url="https://example.com/old/",
                          license_spdx="MIT", image_url="https://example.com/i.png",
                          email="olddev@test.local", status=status))
    db.commit()
    db.close()

    assert migrate.migrate_legacy_submissions(engine) == 2
    assert migrate.migrate_legacy_submissions(engine) == 0  # idempotent

    queue = client.get("/admin/versions", headers=admin_headers).json()
    assert len(queue) == 1
    legacy = queue[0]
    assert legacy["slug"] == "old-pending" and legacy["legacy"] and legacy["report"] == []
    assert legacy["contact"] == "olddev@test.local"
    rejected = client.get("/admin/versions?status=rejected", headers=admin_headers).json()
    assert [r["slug"] for r in rejected] == ["old-rejected"]

    client.post(f"/admin/versions/{legacy['id']}/approve", headers=admin_headers)
    db = SessionLocal()
    game = db.query(Game).filter(Game.slug == "old-pending").one()
    assert game.status == "verified" and game.play_url == "https://example.com/old/"
    assert game.thumbnail_url == "https://example.com/i.png" and game.author == "olddev"
    assert db.query(Submission).filter(Submission.title == "Old Pending").one().status == "approved"
    assert db.query(GameVersion).count() == 2
    db.close()
    assert publish_calls == ["approved old-pending v1"]


def test_legacy_routes_keep_versions_in_sync(client, admin_headers, game_slug):
    # game_slug fixture: POST /submissions + legacy approve route
    from app.db import SessionLocal
    from app.models import Game, GameVersion

    db = SessionLocal()
    v = db.query(GameVersion).one()
    game = db.query(Game).filter(Game.slug == game_slug).one()
    assert v.status == "approved" and v.game_id == game.id and v.slug == game_slug
    db.close()
    assert client.get("/admin/versions", headers=admin_headers).json() == []

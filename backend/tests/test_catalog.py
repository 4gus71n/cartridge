import json

from app import catalog
from app.db import SessionLocal
from app.models import Game

INDEX = {
    "games": [
        {
            "slug": "minefield", "version": 2, "title": "Minefield", "title_es": "Buscaminas",
            "description": "No-guess minesweeper.", "description_es": "Buscaminas sin adivinar.",
            "author": "Cartridge Studio", "license": "All rights reserved", "orientation": "portrait",
            "tags": ["puzzle"], "poster_style": "MINE", "accent_top": "#0B0E18", "accent_bottom": "#3A1424",
            "play_url": "https://pages.test/minefield/index.html",
            "package_url": "https://pages.test/packages/minefield.zip",
            "package_sha256": "a" * 64, "thumbnail_url": "https://pages.test/minefield/poster.png",
        }
    ]
}


def _catalog(tmp_path):
    return json.loads((tmp_path / "catalog.json").read_text())


def test_sync_upserts_and_reports_changes(client, tmp_path, monkeypatch):
    monkeypatch.setenv("CARTRIDGE_HOSTING_DIR", str(tmp_path))
    db = SessionLocal()
    try:
        assert catalog.sync_originals(db, INDEX) == ["minefield"]
        assert catalog.sync_originals(db, INDEX) == []  # unchanged → no update signal
        game = db.query(Game).filter_by(slug="minefield").one()
        assert (game.version, game.title_es, game.status) == (2, "Buscaminas", "verified")
        bumped = json.loads(json.dumps(INDEX))
        bumped["games"][0]["package_sha256"] = "b" * 64
        assert catalog.sync_originals(db, bumped) == ["minefield"]
    finally:
        db.close()


def test_publish_writes_catalog_and_config(client, tmp_path, monkeypatch):
    monkeypatch.setenv("CARTRIDGE_HOSTING_DIR", str(tmp_path))
    monkeypatch.setenv("CARTRIDGE_PAGES_URL", "https://pages.test")
    monkeypatch.setenv("CARTRIDGE_PUBLIC_API", "https://api.test")
    db = SessionLocal()
    try:
        catalog.sync_originals(db, INDEX)
        db.add(Game(slug="hidden", title="Hidden", status="candidate"))
        db.add(Game(slug="gone", title="Gone", status="taken_down", package_url="https://x.test/g.zip"))
        db.add(Game(slug="legacy", title="Legacy", status="verified",
                    package_url="http://localhost:8123/static/packages/legacy.zip"))
        db.commit()
        first = catalog.publish(db, "test")
        assert first["changed"] and not first["pushed"]
        data = _catalog(tmp_path)
        by_slug = {g["slug"]: g for g in data["games"]}
        assert set(by_slug) == {"minefield", "gone", "legacy"}  # candidates never published
        assert by_slug["gone"]["taken_down"] is True
        assert by_slug["minefield"]["taken_down"] is False
        assert by_slug["minefield"]["package_sha256"] == "a" * 64
        assert by_slug["minefield"]["title_es"] == "Buscaminas"
        # local legacy packages are rewritten to their Pages mirror
        assert by_slug["legacy"]["package_url"] == "https://pages.test/packages/legacy.zip"
        assert "likes" not in by_slug["minefield"]  # social counts stay on the API
        config = json.loads((tmp_path / "config.json").read_text())
        assert config == {"api_base_url": "https://api.test", "catalog_url": "https://pages.test/catalog.json"}
        # republishing the same state is a no-op (no Pages commit spam)
        stamp = data["generated_at"]
        assert catalog.publish(db, "again")["changed"] is False
        assert _catalog(tmp_path)["generated_at"] == stamp
    finally:
        db.close()


def test_api_exposes_version_and_spanish_text(client, tmp_path, monkeypatch):
    monkeypatch.setenv("CARTRIDGE_HOSTING_DIR", str(tmp_path))
    db = SessionLocal()
    try:
        catalog.sync_originals(db, INDEX)
    finally:
        db.close()
    game = next(g for g in client.get("/games?status=verified").json() if g["slug"] == "minefield")
    assert (game["version"], game["title_es"]) == (2, "Buscaminas")
    # hosted packages keep their absolute URL
    assert game["package_url"] == "https://pages.test/packages/minefield.zip"


def test_admin_sync_requires_admin(client, auth_headers):
    assert client.post("/admin/catalog/sync", headers=auth_headers).status_code == 403


def test_check_screenshot_posters_are_mirrored(client, tmp_path, monkeypatch):
    from app import config

    monkeypatch.setenv("CARTRIDGE_HOSTING_DIR", str(tmp_path / "hosting"))
    monkeypatch.setenv("CARTRIDGE_PAGES_URL", "https://pages.test")
    shots = config.CHECKS_DIR / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    (shots / "cool-v1.png").write_bytes(b"png")
    db = SessionLocal()
    try:
        db.add(Game(slug="cool", title="Cool", status="verified",
                    thumbnail_url="http://127.0.0.1:8123/shots/cool-v1.png"))
        db.commit()
        catalog.publish(db, "shots")
    finally:
        db.close()
    entry = next(g for g in json.loads((tmp_path / "hosting" / "catalog.json").read_text())["games"]
                 if g["slug"] == "cool")
    assert entry["thumbnail_url"] == "https://pages.test/shots/cool-v1.png"
    assert (tmp_path / "hosting" / "shots" / "cool-v1.png").read_bytes() == b"png"


def test_tunnel_url_from_cloudflared_metrics(monkeypatch, tmp_path):
    import http.server
    import threading

    class Metrics(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            body = b'{"hostname":"abc-def.trycloudflare.com"}' if self.path == "/quicktunnel" else b"{}"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Metrics)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        monkeypatch.setenv("CARTRIDGE_TUNNEL_METRICS", f"http://127.0.0.1:{server.server_port}")
        monkeypatch.delenv("CARTRIDGE_PUBLIC_API", raising=False)
        monkeypatch.setenv("CARTRIDGE_HOSTING_DIR", str(tmp_path))
        assert catalog.tunnel_url() == "https://abc-def.trycloudflare.com"
        catalog.write_files({"format": 1, "games": []})
        assert json.loads((tmp_path / "config.json").read_text())["api_base_url"] == "https://abc-def.trycloudflare.com"
    finally:
        server.shutdown()
    monkeypatch.setenv("CARTRIDGE_TUNNEL_METRICS", "http://127.0.0.1:9")  # nothing listening
    assert catalog.tunnel_url() == ""

import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="cartridge-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"
os.environ["JWT_SECRET"] = "test-secret"
os.environ["ADMIN_EMAILS"] = "admin@test.local"
os.environ["PUBLIC_BASE_URL"] = "http://testserver"
os.environ["CHECKS_DIR"] = f"{_TMP}/checks"
os.environ["CHECKS_WORKER"] = "0"  # tests drive app.checks synchronously
os.environ["CHECKS_SETTLE_MS"] = "200"
os.environ["ALLOW_LOCAL_URLS"] = "1"  # fixtures are served from 127.0.0.1

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture()
def client():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(client):
    response = client.post(
        "/auth/signup", json={"email": "player@test.local", "password": "secret123"}
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


@pytest.fixture()
def admin_headers(client):
    response = client.post(
        "/auth/signup", json={"email": "admin@test.local", "password": "secret123"}
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


@pytest.fixture()
def game_slug(client, admin_headers):
    client.post(
        "/submissions",
        json={
            "title": "Test Runner",
            "description": "A test game",
            "url": "https://example.com/test-runner/",
            "license_spdx": "MIT",
            "image_url": "https://example.com/thumb.png",
            "email": "dev@test.local",
        },
    )
    pending = client.get("/admin/submissions?status=pending", headers=admin_headers).json()
    submission_id = pending[0]["id"]
    response = client.post(
        f"/admin/submissions/{submission_id}/approve", headers=admin_headers
    )
    assert response.status_code == 200
    return response.json()["game_slug"]


@pytest.fixture(scope="session")
def file_server(tmp_path_factory):
    """Local static server for fixture packages: yields (base_url, root_dir)."""
    from app.checks import serve_dir

    root = tmp_path_factory.mktemp("served")
    server = serve_dir(root)
    yield f"http://127.0.0.1:{server.server_address[1]}", root
    server.shutdown()
    server.server_close()


def _signup(client, email):
    response = client.post("/auth/signup", json={"email": email, "password": "secret123"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


@pytest.fixture()
def creator_headers(client):
    from app.creator_terms import CURRENT_TERMS_VERSION

    headers = _signup(client, "maker@test.local")
    accepted = client.post(
        "/creator/terms",
        json={"display_name": "Maker Studio", "terms_version": CURRENT_TERMS_VERSION},
        headers=headers,
    )
    assert accepted.status_code == 200
    return headers


@pytest.fixture()
def publish_calls(monkeypatch):
    from app import catalog

    calls = []
    monkeypatch.setattr(catalog, "request_publish", lambda reason="": calls.append(reason))
    return calls

import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="cartridge-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"
os.environ["JWT_SECRET"] = "test-secret"
os.environ["ADMIN_EMAILS"] = "admin@test.local"
os.environ["PUBLIC_BASE_URL"] = "http://testserver"

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

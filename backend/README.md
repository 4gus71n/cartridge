# Cartridge backend

FastAPI + SQLAlchemy (SQLite by default). The Android app uses `/auth/*`, `/games`,
the social routes and `/reports`. Admins use `/admin`, creators use `/portal`.

```bash
cd backend
python -m venv .venv && .venv/bin/pip install -r requirements.txt playwright
.venv/bin/playwright install chromium          # for the boot check
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
.venv/bin/python -m pytest -q                  # hermetic, no internet needed
```

Settings come from the environment or `backend/.env`: `DATABASE_URL`, `JWT_SECRET`,
`ADMIN_EMAILS` (comma-separated; these accounts are admins on signup),
`PUBLIC_BASE_URL`, and the portal settings below.

## Creator portal (v2)

- `/portal`: log in or sign up (existing JWT auth, token in `localStorage`), accept
  the creator terms (`app/creator_terms.py`; bump `CURRENT_TERMS_VERSION` to make
  everyone re-accept), submit a new game or an update, and see each version's
  status and check report.
- `/portal/guide`: how to host on GitHub Pages (play URL) and attach a zip to a
  GitHub Release (package URL). `/submit` redirects to `/portal`.
- API (JWT; everything except `/creator/me` and `/creator/terms` needs accepted terms):
  `GET|POST /creator/terms`, `GET /creator/me`, `GET /creator/games`,
  `POST /creator/games` (v1 of a new game), `POST /creator/games/{slug}/versions`
  (an update; you must own the game), `GET /creator/versions/{id}/screenshot`.
  URLs must be https. You can have at most 5 versions waiting (checking or in review).
- Version states: `checking` → `failed_checks` | `needs_review` → `approved` |
  `rejected`. A new submission supersedes the pending versions of the same game, and
  an approval supersedes the previously approved one.
- Admin (`/admin`): `GET /admin/versions?status=needs_review|failed_checks|…|all`
  (report, screenshot, diff against the live version), `POST /admin/versions/{id}/approve`
  (`{"note", "force"}`; `force` approves a `failed_checks` version),
  `POST /admin/versions/{id}/reject`, `POST /admin/versions/{id}/recheck`, and
  `POST /admin/games/{slug}/takedown`. Approving creates or updates the `games` row
  (status `verified`, pinned `package_sha256`) and calls
  `app.catalog.request_publish()`. So does a takedown.
- Legacy `submissions` rows are copied into `game_versions` at startup (`pending` →
  `needs_review`, `rejected` → `rejected`). The old table and routes still work.

### Checks worker

`app/checks.py` downloads the package (50 MB cap, 30 s, redirects followed, public
https hosts only) and records its sha256. It then checks:

- zip safety: no traversal, absolute paths or symlinks; at most 100 MB unpacked and
  5,000 files; `index.html` at the root or in one top folder.
- license: a LICENSE/COPYING file whose detected SPDX matches the declared one, and
  that SPDX is on the allow-list.
- external hosts in html/js/css (warning only).
- a headless Chromium boot at 412×915 with touch and every non-local request
  blocked. Uncaught errors fail; console errors warn. A screenshot is saved.
- that the play URL is reachable (warning only).

Any `fail` → `failed_checks`; otherwise `needs_review`.

- **In the API**: started as a background thread at startup and woken on every
  submission. It also polls every 5 s. Disable it with `CHECKS_WORKER=0`, for
  example when you run a separate worker.
- **Standalone**: `.venv/bin/python -m app.checks --worker` runs the loop forever,
  and `--pending` drains the queue once.
- **One version**: `.venv/bin/python -m app.checks <version_id>` re-checks it and prints
  the report.

Env: `CHECKS_DIR` (screenshots and scratch space, default `backend/data/checks`,
gitignored; approved screenshots are served at `/shots/<slug>-v<n>.png`),
`CHECKS_SETTLE_MS` (wait after load, default 3000), `ALLOW_LOCAL_URLS=1` (dev and
tests only: accept and fetch `http://127.0.0.1` URLs), `TAKEDOWN_CONTACT` (shown in
the creator terms).

Run a single worker. Two API processes with the worker enabled can check the same
version twice. That's harmless, but it wastes work.

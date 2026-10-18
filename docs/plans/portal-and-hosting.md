# Plan: free hosting, catalog sync and the creator portal

Status: **in progress** (started 2026-10-18). Owner decisions, 2026-10-18:

| Question | Decision |
|---|---|
| Where the backend runs | **Cheapest possible**: free, or a few cents, or local. |
| Where community games live | **Creators host their own games** and give us URLs. Recommend GitHub Pages for play and GitHub Releases for the package. |
| Publishing policy | **Automated checks, then an admin approves every new game and every update.** |
| Who can submit | **Logged-in Cartridge accounts only.** They accept creator terms and declare a license. |

## Architecture after this plan

```
            ┌──────────── GitHub Pages: 4gus71n/cartridge-games (free, always on) ───────────┐
            │  <slug>/ playable builds + packages/*.zip   (our originals)                    │
            │  catalog.json  ← FULL feed: originals + approved community games (pinned sha)  │
            │  config.json   ← { api_base_url } (stable pointer to wherever the API runs)    │
            └────────────────────────────────────────────────────────────────────────────────┘
                 ▲ git push (publish_catalog)                    ▲ read on app start (no backend needed)
                 │                                               │
  Backend (FastAPI + SQLite) on the Mac ── Cloudflare Tunnel ──► app: social (likes, comments, saves,
  checks worker (Playwright) + admin review                           reports), login, creator portal
                 │
                 ▼ downloads/validates
  Creator-hosted games: play URL (e.g. GitHub Pages) + package zip URL (e.g. GitHub Release asset)
```

Key ideas:
- **The feed doesn't depend on the backend being up.** The app reads `catalog.json`
  from Pages first, and gets social data from the API when it can reach it. If the
  Mac is off, people can still browse, download and play. Likes and comments come
  back when the API returns.
- **Every update needs approval, without us hosting creator files.** On approval we
  pin the package URL plus its sha256 into the catalog. The app checks the sha
  before installing. If a creator swaps the file behind the same URL, the download
  fails the check and the app keeps the approved copy. New content only reaches
  players when the creator submits a new version and an admin approves it.
- **Updates reach players automatically.** A new approved version changes the sha
  in `catalog.json`. The app already re-downloads a game when its sha changes (it
  keeps the old copy when offline). Phase 1 adds a background check for installed
  games.
- **The API location can change for free.** A Cloudflare quick tunnel gets a
  random URL on each restart. `config.json` on Pages always points at the current
  one, and the backend republishes it when the tunnel URL changes. A fixed domain
  (about $10 a year) or a free Oracle Cloud VM can replace it later without an app
  update.

## Phases

### Phase 1: catalog on Pages + automatic sync (host-agnostic) — DONE 2026-10-18
Verified on the emulator: with the backend stopped and app data cleared, the feed
loads from Pages and a game downloads and boots. A stale sha marker on an installed
game triggers a background re-download, without the game being opened.
- [x] `backend/app/catalog.py`: build the full catalog (Pages `index.json` originals,
      plus locally packaged legacy games, plus approved community versions) and write
      `~/cartridge-games/catalog.json` and `config.json`. `publish_catalog` commits and
      pushes only when something changed.
- [x] Backend background sync. On startup and every 10 minutes it pulls the Pages
      `index.json` and upserts originals, which replaces running `import_hosted.py` by
      hand. There's also an admin "Sync now" button.
- [x] App catalog source: Pages `catalog.json` first, then the API `/games` to merge
      social counts and per-user hiding, then the cached copy. The API base comes
      from `config.json`, with the built-in list as fallback.
- [x] App update check: on every catalog refresh, any installed game whose sha
      changed is re-downloaded in the background (on unmetered networks) or the next
      time it's opened.
- [x] Tests (pytest for catalog build and sync; a unit check of the app-side merge
      logic) plus a run on the emulator.

### Phase 2: creator portal v2 (worktree `~/cartridge-wt/portal`)
- [x] Data: `creators`, with terms accepted at a terms version and a display name.
      `game_versions` holds game, version number, play_url, package_url, declared
      SPDX, sha256, size, status (`checking`→`needs_review`→`approved`/`rejected`/`failed_checks`),
      check report JSON, screenshot path, reviewer note and timestamps.
      Submissions become versions; the old `submissions` table is migrated.
- [x] Web portal pages: login/signup (existing JWT auth), creator terms, "New game",
      "My games" (versions, status, check report, "Submit update"), and a guide
      "Host your game on GitHub Pages + Releases".
- [x] Automated checks worker, which runs in the background:
      - Download the package with size caps (50 MB zip, 100 MB unpacked) and a timeout.
      - Zip safety: no path traversal, no symlinks, `index.html` at the root.
      - License: a `LICENSE*` file is present, the text matches the declared SPDX, and
        the SPDX is on the allow-list in roadmap §3.
      - Scan for external `http(s)://` references to other hosts. Offline-unfriendly
        games get a warning.
      - Headless Chromium boot at phone size with the network blocked, served from the
        unpacked zip: no page errors, a screenshot, and boot time.
      - Check that the play URL is reachable.
      - Record a pass/warn/fail line per check.
- [x] Admin review: queue of `needs_review` versions with the report, screenshot,
      diff against the previous version (size, files) and approve/reject with a note.
      Approve triggers `publish_catalog`.
- [x] Takedown: the admin can delete a game, which sets `takenDown` in the catalog and
      makes the app delete local copies. (Backend: `POST /admin/games/{slug}/takedown`
      → `status=taken_down` + `request_publish`; the catalog/app side is Phase 1.)
- [x] Tests: pytest for each check against fixture zips (good, traversal, no license,
      GPL, external CDN, huge), the version state machine, and the auth and terms gates.
- Done 2026-10-18 on `portal/v2`: `app/checks.py` (worker thread + `python -m app.checks`),
  `app/versions.py` (state machine, approve/takedown), `routers/creator.py`, `/portal`,
  `/portal/guide`, admin queue in `static/admin.html`. How to run: `backend/README.md`.
  Open product questions: takedown contact (`TAKEDOWN_CONTACT`, defaults to the
  cartridge-games issues page), whether creators may update a taken-down game (now: 409).

### Phase 3: free hosting
- [ ] `backend/Dockerfile`, plus `docker-compose.yml` for the API, the checks worker
      and Cloudflare `cloudflared`. SQLite lives on a volume with a nightly backup to a
      second folder.
- [x] `tools/run_server.sh` starts the API and a quick tunnel (the checks worker runs inside the API process). Live since 2026-10-18,, and updates
      `config.json` on Pages when the tunnel URL changes.
- [ ] Production app config: HTTPS only (drop `usesCleartextTraffic` for release
      builds).
- [ ] Doc: moving to a free Oracle Cloud ARM VM or a cheap VPS uses the same compose
      file.

### Phase 4: release polish
- [ ] Terms of use, creator terms, privacy and DMCA/takedown pages, served from
      Pages.
- [ ] Signed release APK and version bump. Optional: Play internal testing.

## Out of scope for now
iOS runtime (roadmap M6), payments and monetisation, a recommendation feed.

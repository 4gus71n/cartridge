# Cartridge — Product & Engineering Roadmap

A TikTok-style feed where every reel is a playable HTML5/JS game.

**Status:** Draft v0.1 · **Last updated:** 2026-10-04
**Android prototype:** running — vertical feed, play/close WebView flow, **20 bundled games** (3 original + 17 sourced from GitHub under MIT/Apache-2.0/BSD-3-Clause/CC0, each with a `CREDITS.txt` evidence file and tappable credits sheet).
**v0.2 (offline-first + social):** Python/FastAPI backend (`backend/`) with JWT auth, likes, saves, collections, comments, submissions and an admin review page; Supabase-ready (schema + `DATABASE_URL` swap). App has email/password signup + login, profile screen (liked/saved/collections, logout), save-to-collection flow, API-backed comments, and offline-first behavior: state cached locally (SharedPreferences JSON) with best-effort sync, and liked/saved games are downloaded (zip or same-origin mirror) into app storage and served offline from the WebView asset loader. Verified end-to-end on emulator and device.
**Content pipeline:** GitHub license-filtered import populated **1,636 games in the database** — 20 verified/live + 1,616 candidates (status=`candidate`) awaiting license verification and packaging before they appear in the feed.
**v0.3 (reports, rotation, review pipeline):** in-app **report flow** on every reel (doesn't work / broken graphics / other with free-text) saved for admins and surfaced in the admin page's review queue. **Per-game screen orientation** — the feed stays portrait, games with wide canvases (pool, pacman, invaders, etc.) force landscape, everything else follows the sensor. **Candidate review pipeline** (`backend/scripts/review_candidates.py`) verifies license files, finds playable entries, packages tarballs into downloadable zips, and promotes them — 44 games verified and playable so far, with server-side demotions for engines/multiplayer/dev-build repos. Needs a GitHub token-free run; see script options for further batches.
**v0.4 (real data + robustness):** API client now resolves across multiple base URLs (adb-reverse localhost → Mac LAN IP → emulator alias) with per-request failover, so the app works over Wi-Fi without USB. Synthetic like/comment baselines removed — counts are real and update from server responses. Collections are local-first: creating one and saving into it works offline and syncs by name. Profile tabs fixed (Saved/Collections were rendering off-screen), profile refresh pulls newly approved games. Report reasons extended with "The game quality isn't good"; reports render in the admin queue. Admin dashboard gained the **Candidate games** queue (search, pagination, Package & approve / Reject) wired to the review pipeline — approvals package the zip and go live in the app on next catalog refresh. Review filters hardened (engine/tool/AI-demo/multiplayer/dev-entry guards) and prior bad promotions demoted: 67 verified games, 1,573 candidates, 21 rejected.
**v0.5 (report hardening + itch.io discovery):** reported games are hidden from the reporter — server-side via an authenticated `/games` filter and instantly on-device (persisted); report options now include "This is a desktop game" and "Improper or adult content" alongside broken/graphics/quality/other. New itch.io discovery crawler (`backend/scripts/import_itch.py`, Playwright): scrolls `itch.io/games/platform-web/tag-open-source`, finds GitHub repos, fingerprints licenses (GPL rejected, MIT/Apache/BSD/ISC/CC0/etc. accepted), and imports them as candidates for the same packaging pipeline — 93 imported in the first pass. Packaging now also vendors CDN scripts/styles into game zips so games that load libraries from CDNs run offline.
**v0.6 (pivot to original games, 2026-10-14):** third-party scraping abandoned (glitchy, limited). Catalog purged to 2048 + Black Hole Square + the 3 Cartridge originals. New games are built in Godot 4.7 (web export, no-threads, Compatibility renderer) and hosted on GitHub Pages; backlog in `games/BACKLOG.md`.
**Still pending:** SQLDelight migration for local state, iOS runtime (M6), scaled automated review (hundreds more candidates), submission portal hardening, pruning user-reported games in bulk.

---

## 1. Vision

Cartridge is a vertical, immersive feed of playable web games. Every "reel" is a **cartridge**: a full-screen game card with a preview image, a play button, and the familiar social rail on the right (like, comment, share, save). Tap play and the game runs full-screen in a WebView; a close (✕) button in the top-left exits back to the feed. Saved cartridges download to local storage and play with zero connectivity.

**Core loop**

1. Scroll a full-screen vertical feed of cartridges.
2. Tap **Play** → game boots in a WebView; the pager locks so swipes don't interfere with gameplay.
3. React with the right rail: **like**, **comment**, **share**, **save**.
4. Saved games are stored on-device and playable offline, forever.

**Non-goals for v1:** accounts, real social graph, recommendation ML, creator tools, monetization.

---

## 2. Locked decisions

| Area | Decision |
|---|---|
| Game licensing | **Permissive licenses only** — MIT, ISC, BSD-2/3, Apache-2.0, MPL-2.0, Unlicense, CC0, CC-BY-4.0. GPL family and CC-BY-SA excluded in v1. Credit shown where required. |
| Social scope | **Local-first MVP** — likes, comments, saves live on-device (SQLDelight). No accounts. Repositories abstracted so a backend drops in later without UI changes. |
| Platforms | **Android first, iOS immediately after**, on one KMP + Compose Multiplatform codebase. |
| Game delivery | **Hybrid** — ~10–15 game starter pack bundled in the app + new games streamed from CDN. Everything saved is unzipped locally and playable offline. |
| Curation | **Automated discovery + human review**. A creator **submission portal** is planned for v2. |

---

## 3. Licensing & compliance (non-negotiable)

This is the existential risk of the product. Policy: **if we can't prove the license, it doesn't ship.**

### 3.1 Principles

- **Free to play ≠ free to copy.** Redistribution requires an explicit license grant, even for free games.
- **itch.io is not a free-for-all.** Its default is *All Rights Reserved*. A game is eligible **only** if the page, repo, or bundled license file explicitly grants one of the accepted licenses below. Never scrape or re-host itch.io builds otherwise.
- **No license file / no license statement = All Rights Reserved.** This includes public GitHub repos without a license.
- **Assets count too.** An MIT-licensed game using ripped sprites/audio is not shippable. The review checklist includes an asset provenance check.
- **Excluded:** GPL/LGPL/AGPL, CC-BY-SA (revisit later case-by-case), "freeware" with no terms, anything with trademarks (Mario/Disney/etc.) regardless of code license.

### 3.2 Accepted licenses and their obligations

| License (SPDX) | Redistribute | Commercial | Obligations in the app |
|---|---|---|---|
| MIT, ISC, BSD-2-Clause | Yes | Yes | Ship copyright + license text |
| BSD-3-Clause | Yes | Yes | Above + no-endorsement notice |
| Apache-2.0 | Yes | Yes | License text, NOTICE contents, note modifications |
| MPL-2.0 | Yes | Yes | Ship license + source of MPL-covered files (unmodified games satisfy this) |
| Unlicense, CC0-1.0 | Yes | Yes | None (credit as courtesy) |
| CC-BY-4.0 | Yes | Yes | Visible credit, license name/link, note if modified |

**Every accepted license above permits commercial use**, so monetization later (ads/subscriptions) does not invalidate the catalog.

### 3.3 Per-game compliance artifacts (stored in the content repo)

- SPDX license ID + link
- Copy of the original license file(s), including licenses of bundled libraries (Phaser, Pixi, etc.)
- Source URL + **pinned commit hash**
- Attribution string, e.g. `Neon Runner by Jane Doe — MIT License`
- Asset provenance note (all assets original or permissively licensed)
- `sha256` of the published package

### 3.4 In-app compliance requirements

- **Credit chip** on every reel: `by @author · MIT` (tap → credits detail screen with source link).
- **Licenses screen** (Settings → Licenses) listing every cartridge with full license text and source links.
- Each downloaded game folder contains the original `LICENSE*` file alongside `index.html`.
- **Kill switch / takedown:** the catalog manifest carries a `takenDown` flag. When set, the app removes any cached copy on next sync. Public legal contact (e.g. `legal@…`) and a documented DMCA process before launch.
- CI lint: the content repo does not build unless every cartridge validates against the metadata schema **and** has license evidence.

---

## 4. Architecture

### 4.1 Stack

| Concern | Choice |
|---|---|
| Language / UI | Kotlin 2.x + Compose Multiplatform (shared UI for Android + iOS) |
| DI | Koin |
| Local DB | SQLDelight (catalog cache, likes, comments, saves, downloads) |
| Networking | Ktor Client (catalog + package downloads, resumable) |
| Images | Coil 3 (multiplatform) |
| Serialization | kotlinx.serialization (manifest/metadata JSON) |
| Zip handling | Okio `ZipFileSystem` (multiplatform unzip, avoids per-platform code) |
| Feed | Compose `VerticalPager` + `LazyColumn` details |
| Background work | WorkManager (Android) / BGTaskScheduler (iOS, later milestone) |
| Game runtime | Android `WebView` + `WebViewAssetLoader`; iOS `WKWebView` + `WKURLSchemeHandler`/`loadFileURL` |

### 4.2 Module layout

```
cartridge/
├─ composeApp/
│  ├─ commonMain/        # feed, reels, social, offline, domain, navigation
│  ├─ androidMain/       # WebView host, asset loader, WorkManager, share sheet
│  └─ iosMain/           # WKWebView host, file coordinator, share sheet
├─ iosApp/               # Xcode wrapper
├─ content/              # catalog: metadata/*.json, licenses/, thumbnails/, starter pack
├─ tools/                # discovery + verification CLI (Playwright + Kotlin/Node)
└─ roadmap.md
```

### 4.3 Game contract

A cartridge package is a ZIP with:

```
<game>/
├─ index.html            # required entry point at root
├─ …game files…
├─ LICENSE-<spdx>.txt    # injected at packaging time
└─ cartridge.json        # copy of catalog metadata (generated)
```

At runtime the native side:

1. Unzips to `filesDir/games/{id}/` (or plays from bundled assets for the starter pack).
2. Serves it from a **stable pseudo-origin** so `fetch`/`XHR`/`localStorage` behave like a real website:
   - **Android:** `WebViewAssetLoader` → `https://appassets.androidplatform.net/games/{id}/…` (`InternalStoragePathHandler` for downloaded games; assets handler for bundled ones). Avoids `file://` CORS/CSP breakage.
   - **iOS:** `loadFileURL(_:allowingReadAccessTo:)` as the v1 baseline; if a game needs `fetch`/`XHR`, fall back to a `WKURLSchemeHandler` with a custom origin, and only if strictly necessary a localhost server.
3. Injects `cartridge-bridge.js` (runtime-injected, never modifying distributed files):

```js
window.Cartridge = {
  ready(),                  // game finished loading → hides spinner
  error(message),           // surfaces error state to native
  haptic(),                 // optional feedback
  orientation('portrait'|'landscape'|'any')
}
// native → JS: pause(), resume(), mute()
```

### 4.4 Play mode & inputs

- Feed is **portrait**. Per-game orientation from metadata (`portrait`/`landscape`/`any`); Android locks the activity, iOS overrides supported orientations.
- While playing: **pager scroll disabled**, right rail hidden, ✕ close button top-left, system back = exit. Optionally a mute toggle.
- Audio: Android `mediaPlaybackRequiresUserGesture`, audio focus handling; iOS `AVAudioSession` played-back category (silent-switch caveat documented).
- **WebView lifecycle:** destroy on exit (`stopLoading()` + `destroy()`, drop references) to avoid leaks. No WebView pooling in v1. Preload only the thumbnail row.
- **Keyboard-only games:** review checklist requires touch-only playability (`needsKeyboard: false`). A virtual gamepad overlay is a v1.5 candidate, not v1.

### 4.5 Offline & delivery

- **Save** → download ZIP (progress on the save button, resumable) → verify `sha256` → unzip → mark saved in DB.
- **Catalog sync:** `GET /catalog/v1/manifest.json` with ETag; diff into SQLDelight; honor `takenDown`.
- **Feed sources:** bundled starter pack ∪ synced catalog ∪ saved games.
- **Storage screen:** per-game size, delete, total usage; LRU eviction for cached-but-not-saved cartridges.
- **Error states:** download failed, unzip failed, game boot error → retry UI, never a dead end.
- Starter pack capped at ~40 MB bundled.

### 4.6 Data model (catalog entry)

```json
{
  "id": "neon-runner",
  "title": "Neon Runner",
  "author": { "name": "Jane Doe", "url": "https://github.com/janedoe" },
  "license": {
    "spdx": "MIT",
    "url": "https://opensource.org/license/mit",
    "textPath": "licenses/neon-runner/LICENSE.txt",
    "attribution": "Neon Runner by Jane Doe — MIT License"
  },
  "source": { "repo": "https://github.com/janedoe/neon-runner", "commit": "abc123" },
  "media": { "thumbnail": "media/neon-runner.webp", "previewClip": null },
  "package": {
    "url": "https://cdn.cartridge.gg/games/neon-runner.zip",
    "sha256": "…", "bytes": 480211, "version": 3
  },
  "runtime": { "entry": "index.html", "orientation": "portrait", "needsKeyboard": false },
  "tags": ["arcade", "runner"],
  "takenDown": false
}
```

Engagement tables (local): `likes`, `comments`, `saves`, `plays`, `downloads`.

---

## 5. Content pipeline

```
Discover → Verify (automated) → Human review → Package → Publish (CDN manifest)
```

**Sources for discovery (permissive licenses only):**
`js13kGames` entries (tiny, mobile-friendly, many MIT — best fit), GitHub search with `license:mit|apache-2.0|cc0-1.0` + topics (`html5-game`, `javascript-game`, `phaser`, `pixijs`, `kaplay`), permissively licensed demos in Phaser/Pixi showcase repos, Kenney templates. itch.io only when explicitly licensed.

**Discovery CLI (`tools/`):**

1. Query GitHub API: license filter + topics + activity signals.
2. Fetch candidate → detect entry point, engine, license file → SPDX; reject no-license.
3. Headless smoke test (Playwright, 390×844, network disabled): boots without errors, touch-usable, **self-contained (no external calls)**, screenshot → thumbnail, measure package size.
4. Emit draft `metadata.json` + attribution string + evidence bundle.

**Human review checklist (definition of done for a cartridge):**

- [ ] License file present, matches declared SPDX, covers code *and* assets
- [ ] No trademarks / ripped assets / unclear provenance
- [ ] Playable with touch only; no keyboard required
- [ ] Works offline after first load; no analytics/ads/external calls
- [ ] Acceptable perf on a mid-range Android device; < ~10 MB package (exceptions reviewed)
- [ ] Content is safe for a general audience (store policy)
- [ ] Evidence bundle stored in `content/`

**Publish:** inject license file + `cartridge.json`, zip, content-address, upload to CDN (S3+CloudFront or Cloudflare R2), bump catalog manifest version.

**v2 — Submission portal:** dev signup → upload ZIP + declare license (license file required) → automated checks reuse the CLI → human review queue → publish. Same manifest.

---

## 6. Milestones

Estimates assume 1–2 engineers; weeks are relative, not calendar dates.

### M0 — Foundations (~1 week)
KMP + Compose Multiplatform skeleton, CI (build + tests + ktlint/detekt), Koin, SQLDelight schema v1, theme/design tokens, `cartridge` branding placeholder.
**Exit:** app builds and runs on Android with an empty feed.

### M1 — Feed UI (~1–2 weeks)
Vertical pager, cartridge reel card (thumbnail, center play button, right rail, credit chip, title), mock data, saved tab shell, navigation.
**Exit:** smooth 60fps scroll over 50 mock cartridges.

### M2 — Game runtime (~2–3 weeks)
Packaging convention, starter pack plumbing, Android WebView + `WebViewAssetLoader`, bridge injection, play/close flow, pager lock, orientation lock, error/loading states, WebView teardown.
**Exit:** a bundled game runs fullscreen, exits cleanly, no leaks across 20 open/close cycles.

### M3 — Offline & delivery (~2 weeks)
Catalog client (Ktor + ETag), download with progress/resume + sha256 verify, Okio unzip, save button, offline mode, storage management screen, starter pack bundled.
**Exit:** save a game from the CDN, enable airplane mode, play it.

### M4 — Social (local) (~1–2 weeks)
Likes, comment bottom sheet, share sheet (deep link + store link), saved list, play counts, optimistic updates in SQLDelight.
**Exit:** all social state persists across restarts; repositories ready for a backend swap.

### M5 — Content pipeline v1 (~2–3 weeks, parallel with M3/M4)
Discovery CLI, review checklist, evidence bundle format, CDN manifest, **first 25 license-verified cartridges** published (10–15 shipped in starter pack).
**Exit:** 25 playable games, every one passing the license CI lint.

### M6 — iOS bring-up (~3 weeks)
`iosApp` wrapper, `WKWebView` host + file serving, unzip/storage, downloads, share sheet, orientation handling, TestFlight build.
**Exit:** feature parity with Android for feed, play, save/offline, social.

### M7 — Beta hardening (~2–3 weeks)
Lifecycle/audio/rotation edge cases, memory profiling, crash reporting (privacy-friendly), Licenses + takedown screens, store listings, Play internal → closed beta, TestFlight beta.
**Exit:** public beta on both stores with 50+ cartridges.

### v2 backlog
Backend + accounts, real comments/moderation, submission portal, short looping preview clips (WebM), recommendation feed, creator profiles, virtual gamepad overlay, Wi-Fi-only downloads, landing pages for shared links, monetization.

---

## 7. Testing & QA

- **Content CI:** schema validation + license-evidence lint + Playwright smoke test per cartridge (also re-run before catalog publishes).
- **Unit tests:** catalog diffing, license validation, download/unzip, repository logic (shared, run on both platforms).
- **UI tests:** Compose UI tests for feed, play/close flow, social actions.
- **Manual matrix:** low-end + mid + flagship Android (including heavy OEM WebView skins), iPhone with/without silent switch, airplane-mode runs, thermal/battery spot checks, 30+ min session memory.
- **Legal regression:** kill-switch propagation test, cached copy removal, attribution rendering for CC-BY.

---

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Shipping a game without valid license | Store bans, DMCA, legal exposure | Per-game evidence bundle, CI lint, asset audit, kill switch, takedown process |
| Mislabeled GitHub licenses / contaminated assets | Same as above | Human review checklist; reject on any doubt; pinned commits for audit trail |
| Games break on mobile WebViews (OEM variance, iOS quirks) | Core experience failures | Bridge + smoke tests on device matrix; review gate; curated catalog only |
| Games needing network (CDNs, APIs) | Offline requirement breaks | Playwright test with network disabled; reject non-self-contained games |
| Keyboard-only games | Unplayable on mobile | Touch-only requirement in checklist; virtual gamepad is v1.5 scope |
| WebView memory/leaks | Crashes, battery drain | Strict teardown, no pooling, memory profiling in M7 |
| App size from starter pack | Install friction | 40 MB cap; everything else streamed |
| Catalog starvation (too few good permissive games) | Weak feed | js13kGames + GitHub topics as primary sources; submission portal in v2 |
| Backend added later conflicts with local data | Migration pain | Repository interfaces from day one; data model mirrors future API shape |

---

## 9. Open questions

- App/package ID and final naming trademark check (`com.cartridge.app` placeholder).
- Min SDK (proposal: Android 26 / iOS 16) — depends on WebView feature needs.
- CDN choice (S3+CloudFront vs Cloudflare R2) and content repo hosting.
- Do we ever want accounts? (Supabase/Firebase vs custom Ktor backend when the time comes.)
- Monetization plans — all accepted licenses are commercial-safe, but ads affect review criteria.
- Preview media in v1: static thumbnails only, or short looping clips from day one?
- Design language/Figma source of truth for the reel template and play-mode chrome.
- Share-link strategy: landing page site (web) for shared cartridges — v1 deep link + store link only?

---

## 10. Appendix — accepted-license quick reference

| SPDX | Ship license text | Credit required | Notes |
|---|---|---|---|
| MIT / ISC / BSD-2 / BSD-3 | Yes | No | Simplest tier |
| Apache-2.0 | Yes + NOTICE | No | State changes if modified |
| MPL-2.0 | Yes | No | Unmodified games are fine |
| Unlicense / CC0-1.0 | No | No | Credit is a courtesy |
| CC-BY-4.0 | Yes | **Yes** | Credit + license link + changes noted |

Excluded in v1: GPL-2.0/3.0, LGPL, AGPL, CC-BY-SA, no-license/ARR, unverified assets.

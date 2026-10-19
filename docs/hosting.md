# Hosting the Cartridge backend

Players never need the backend to browse or play: the feed (`catalog.json`), the
games and the packages are static files on GitHub Pages
(`4gus71n/cartridge-games`). The backend adds accounts, likes, comments,
reports, the creator portal, the checks worker and the admin queue. When it's
down, those features pause and nothing else breaks.

| Option | Cost | Uptime | URL |
|---|---|---|---|
| This Mac + quick tunnel (`tools/run_server.sh`) | $0 | while the Mac is awake | random `*.trycloudflare.com`, re-published on restart |
| Docker on this Mac (`docker compose up -d`) | $0 | same, survives reboots if Docker auto-starts | same |
| Oracle Cloud Always Free ARM VM + compose | $0 | 24/7 | quick tunnel, or named tunnel with a domain |
| Any small VPS (Hetzner CX22 ≈ €4/mo) + compose | low | 24/7 | same |

The app finds the API through `config.json` on Pages (`api_base_url`), so moving
the backend never needs an app update.

## Option A: this Mac, no Docker
```
tools/run_server.sh
```
Starts uvicorn on :8123 (reusing it if it's already running), opens a Cloudflare
quick tunnel, and pushes the tunnel URL to `config.json`.

## Option B: Docker Compose (any machine)
```
git clone git@github.com:4gus71n/cartridge.git && cd cartridge
git clone https://github.com/4gus71n/cartridge-games ../cartridge-games
cp backend/.env.example backend/.env    # set JWT_SECRET, ADMIN_EMAILS, GITHUB_TOKEN
docker compose up -d --build
docker compose logs -f api              # "catalog ... pushed=True" once the tunnel is up
```
Services:
- `api`: FastAPI, the checks worker (Playwright Chromium) and the catalog
  publisher. It reads the tunnel URL from `tunnel:2000/quicktunnel` and
  republishes `config.json` whenever that URL changes (checked every minute).
- `tunnel`: `cloudflared` quick tunnel, free with no account.
- `backup`: SQLite snapshot every 24 h into `backend/backups/`, keeping 14.
  Copy that folder off the machine now and then (it is git-ignored).

`GITHUB_TOKEN`: a fine-grained personal access token limited to
`4gus71n/cartridge-games` with **Contents: read and write**. The container uses it
to push `catalog.json`. Without it, everything works except auto-publishing.

Only run **one** API container: two checks workers would test the same
submission twice.

Moving an existing install: stop the old one, then copy `backend/cartridge.db` to
`backend/data/cartridge.db` and `backend/app/static/packages/` across.

## Oracle Cloud Always Free (24/7, $0)
1. Create an account at cloud.oracle.com (it needs a card for identity checks, but Always
   Free resources are never charged). Pick a home region with ARM capacity.
2. Compute → Instances → Create: Ubuntu 24.04, shape **VM.Standard.A1.Flex**
   (up to 4 OCPU / 24 GB free; 1 OCPU / 6 GB is plenty).
3. No inbound ports are needed: the tunnel connects outbound. Keep only SSH open.
4. On the VM: `sudo apt install -y docker.io docker-compose-v2 git`, then follow
   Option B. The image is multi-arch (the Playwright base image ships arm64).
5. Stop the Mac's `run_server.sh`, or the two will fight over `config.json`.

## Fixed URL (optional, about $10 a year)
Quick-tunnel URLs change on every restart, and the app copes with that through
`config.json`. For a stable URL, buy a cheap domain, add it to Cloudflare (free plan),
create a named tunnel (`cloudflared tunnel create cartridge`), route
`api.<domain>` to it, replace the `tunnel` command with
`tunnel run --token <TOKEN>`, and set `CARTRIDGE_PUBLIC_API=https://api.<domain>`.

#!/bin/bash
# Run the Cartridge backend on this Mac and expose it publicly for free.
#
#   tools/run_server.sh            # API on :8123 + Cloudflare quick tunnel + config.json update
#   tools/run_server.sh --no-tunnel
#
# A Cloudflare *quick tunnel* (no account, no domain, $0) gives a random
# https://<words>.trycloudflare.com URL that changes on every restart. This
# script publishes the current URL to GitHub Pages (config.json →
# api_base_url), and the app reads it on start, so no app update is needed when
# it changes. Quick tunnels have no uptime guarantee. For a fixed URL, use a
# named tunnel on a cheap domain (docs/plans/portal-and-hosting.md, Phase 3).
#
# Logs: $TMPDIR/cartridge-server/{api,tunnel}.log. Ctrl-C stops everything.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOSTING="${CARTRIDGE_HOSTING_DIR:-$HOME/cartridge-games}"
LOGS="${TMPDIR:-/tmp}/cartridge-server"; mkdir -p "$LOGS"
PORT=8123
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT INT TERM

if lsof -iTCP:$PORT -sTCP:LISTEN -P >/dev/null 2>&1; then
  echo "API already listening on :$PORT (reusing it)"
else
  (cd "$ROOT/backend" && exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $PORT) >"$LOGS/api.log" 2>&1 &
  pids+=($!)
  for _ in $(seq 1 30); do curl -sf "localhost:$PORT/health" >/dev/null && break; sleep 1; done
  echo "API up on :$PORT (log $LOGS/api.log)"
fi

[ "${1:-}" = "--no-tunnel" ] && { echo "no tunnel; Ctrl-C to stop"; wait; exit 0; }

cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >"$LOGS/tunnel.log" 2>&1 &
pids+=($!)
URL=""
for _ in $(seq 1 60); do
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOGS/tunnel.log" | head -1)
  [ -n "$URL" ] && break; sleep 1
done
[ -z "$URL" ] && { echo "tunnel failed, see $LOGS/tunnel.log"; exit 1; }
for _ in $(seq 1 30); do curl -sf "$URL/health" >/dev/null && break; sleep 2; done
echo "public API: $URL"

python3 - "$HOSTING/config.json" "$URL" <<'EOF'
import json, pathlib, sys
path, url = pathlib.Path(sys.argv[1]), sys.argv[2]
cfg = json.loads(path.read_text()) if path.exists() else {}
cfg["api_base_url"] = url
path.write_text(json.dumps(cfg, indent=1, sort_keys=True) + "\n")
EOF
(cd "$HOSTING" && git add config.json && git commit -qm "config: api_base_url → $URL" && git push -q) \
  && echo "config.json published (Pages refreshes in ~1 min)" || echo "config.json unchanged / push failed"
echo "running; Ctrl-C to stop"
wait

"""Game-local screenshot helper for Trajectory (QA + poster).

Usage:
  ~/cartridge/backend/.venv/bin/python tools/capture.py <export_dir> <out_dir> <shots.json>

shots.json: [{"name": "poster", "query": "?poster=21&x=1.5", "w": 360, "h": 640, "dpr": 2,
              "locale": "en-US", "wait": 2500,
              "steps": [{"tap": [0.5, 0.6], "wait": 500, "shot": "after"}]}, ...]
Each entry boots the build with its query string (the game reads ?poster=N&x=X
to stage level N with the rocket frozen at world x = X; ?level=N opens level N;
?screen=levels opens level select) and saves <name>.png after `wait` ms, then
runs optional tap steps. Exit 1 on page/console errors.
"""

import functools
import http.server
import json
import pathlib
import sys
import threading

from playwright.sync_api import sync_playwright

export_dir = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
shots = json.loads(pathlib.Path(sys.argv[3]).read_text())


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream"}

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(export_dir)))
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}/index.html"

errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                                      "--ignore-gpu-blocklist"])
    for s in shots:
        w, h = s.get("w", 412), s.get("h", 915)
        ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=s.get("dpr", 2),
                                  has_touch=True, is_mobile=True, locale=s.get("locale", "en-US"))
        page = ctx.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: m.type == "error" and errors.append(m.text))
        page.goto(base + s.get("query", ""))
        page.wait_for_function(
            "() => { const s = document.getElementById('status'); return !s || s.style.display === 'none' || s.style.visibility === 'hidden' }",
            timeout=60000)
        page.wait_for_timeout(s.get("wait", 1500))
        page.screenshot(path=str(out / f"{s['name']}.png"))
        for step in s.get("steps", []):
            if "tap" in step:
                page.touchscreen.tap(step["tap"][0] * w, step["tap"][1] * h)
            page.wait_for_timeout(step.get("wait", 600))
            if "shot" in step:
                page.screenshot(path=str(out / f"{s['name']}-{step['shot']}.png"))
        ctx.close()
        print("shot", s["name"])
    browser.close()
server.shutdown()
print("errors:", errors or "none")
sys.exit(1 if errors else 0)

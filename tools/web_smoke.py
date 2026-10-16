"""Smoke-test a Cartridge web build in headless Chromium at a phone viewport.

Usage: python web_smoke.py <export_dir | url> <out_dir> [steps.json]

Serves the export, boots it with touch enabled, runs the tap script and saves
screenshots. Fails (exit 1) on page errors / console errors.

steps.json (optional; defaults to games/<slug>/smoke.json when <export_dir>
is games/<slug>/export/web, else just a boot screenshot):
  {
    "landscape": false,                       # optional: swap the viewport
    "boot_wait_ms": 1500,                     # optional: extra wait after boot
    "steps": [
      {"tap": [0.5, 0.40], "wait": 800, "shot": "2-board"},  # fractions of viewport
      {"swipe": [0.5, 0.7, 0.5, 0.3], "wait": 500},
      {"hold": [0.5, 0.5], "ms": 600, "wait": 300},
      {"text": "go north", "wait": 300},       # types into the focused element
      {"wait": 1000, "shot": "4-later"}
    ]
  }
"""

import functools
import http.server
import json
import pathlib
import sys
import threading
import time

from playwright.sync_api import sync_playwright

target = sys.argv[1]
is_url = target.startswith("http")
export_dir = None if is_url else pathlib.Path(target).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)

steps_path = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None
if steps_path is None and export_dir is not None:
    guess = export_dir.parent.parent / "smoke.json"  # games/<slug>/export/web -> games/<slug>
    if guess.exists():
        steps_path = guess
spec = json.loads(steps_path.read_text()) if steps_path else {"steps": []}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream"}

    def log_message(self, *args):
        pass


server = None
if is_url:
    url = target
else:
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", 0), functools.partial(Handler, directory=str(export_dir)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/index.html"

W, H = (915, 412) if spec.get("landscape") else (412, 915)


def xy(frac):
    return frac[0] * W, frac[1] * H


errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                                      "--ignore-gpu-blocklist"])
    page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=2,
                            has_touch=True, is_mobile=True, locale=spec.get("locale", "en-US"))
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))
    t0 = time.time()
    page.goto(url)
    # Godot builds: wait until the status overlay is gone (engine booted).
    page.wait_for_function(
        "() => { const s = document.getElementById('status'); return !s || s.style.display === 'none' || s.style.visibility === 'hidden' }",
        timeout=60000)
    page.wait_for_timeout(spec.get("boot_wait_ms", 1500))
    print(f"boot: {time.time() - t0:.1f}s")
    page.screenshot(path=str(out / "1-boot.png"))
    for step in spec.get("steps", []):
        if "tap" in step:
            page.touchscreen.tap(*xy(step["tap"]))
        elif "swipe" in step:
            x0, y0 = xy(step["swipe"][:2])
            x1, y1 = xy(step["swipe"][2:])
            page.mouse.move(x0, y0)
            page.mouse.down()
            for i in range(1, 11):
                page.mouse.move(x0 + (x1 - x0) * i / 10, y0 + (y1 - y0) * i / 10)
                page.wait_for_timeout(15)
            page.mouse.up()
        elif "hold" in step:
            page.mouse.move(*xy(step["hold"]))
            page.mouse.down()
            page.wait_for_timeout(step.get("ms", 600))
            page.mouse.up()
        elif "text" in step:
            page.keyboard.type(step["text"])
        page.wait_for_timeout(step.get("wait", 600))
        if "shot" in step:
            page.screenshot(path=str(out / f"{step['shot']}.png"))
    browser.close()

if server:
    server.shutdown()
print("errors:", errors or "none")
sys.exit(1 if any("Error" in e or "error" in e for e in errors) else 0)

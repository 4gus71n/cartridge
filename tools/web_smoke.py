"""Smoke-test a Godot web export in headless Chromium at a phone viewport.

Usage: python web_smoke.py <export_dir | url> <out_dir>
Serves the export, loads it with touch enabled, taps through menu -> easy
board -> first dig, and saves screenshots. Fails on page errors.
"""

import functools
import http.server
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

errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                                      "--ignore-gpu-blocklist"])
    page = browser.new_page(viewport={"width": 412, "height": 915}, device_scale_factor=2,
                            has_touch=True, is_mobile=True, locale="en-US")
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))
    t0 = time.time()
    page.goto(url)
    # Wait until the Godot status overlay is gone (engine booted).
    page.wait_for_function(
        "() => { const s = document.getElementById('status'); return !s || s.style.display === 'none' || s.style.visibility === 'hidden' }",
        timeout=60000)
    page.wait_for_timeout(1500)
    print(f"boot: {time.time() - t0:.1f}s")
    page.screenshot(path=str(out / "1-menu.png"))
    # Menu buttons: easy is the first big button, roughly 40% down the screen.
    page.touchscreen.tap(206, 915 * 0.40)
    page.wait_for_timeout(800)
    page.screenshot(path=str(out / "2-board.png"))
    page.touchscreen.tap(206, 915 * 0.50)
    page.wait_for_timeout(1200)
    page.screenshot(path=str(out / "3-dug.png"))
    browser.close()

if server:
    server.shutdown()
print("errors:", errors or "none")
sys.exit(1 if any("Error" in e or "error" in e for e in errors) else 0)

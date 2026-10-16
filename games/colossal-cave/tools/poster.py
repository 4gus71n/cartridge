"""Capture poster.png (720x1280) from the real web build, mid-game.

Usage: python tools/poster.py <export_dir> <out.png>

Plays an opening route through the shell's own send() (same path as the
buttons), then screenshots the transcript at 360x640 CSS px, DPR 2.
"""
import functools
import http.server
import pathlib
import sys
import threading

from playwright.sync_api import sync_playwright

export_dir = pathlib.Path(sys.argv[1]).resolve()
dest = pathlib.Path(sys.argv[2]).resolve()

ROUTE = ["no", "in", "take lamp", "take keys", "out", "s", "s", "s", "unlock grate", "d", "w",
         "take cage", "light lamp", "w", "w", "w", "take bird", "w", "d"]


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(H, directory=str(export_dir)))
threading.Thread(target=srv.serve_forever, daemon=True).start()
with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 360, "height": 640}, device_scale_factor=2, has_touch=True,
                      is_mobile=True, locale="en-US")
    page.goto(f"http://127.0.0.1:{srv.server_port}/index.html")

    def idle():
        page.wait_for_function("() => window.cave && !window.cave.state().busy", timeout=15000)

    idle()
    for c in ROUTE:
        page.evaluate("c => window.cave.send(c)", c)
        page.wait_for_timeout(60)
        idle()
    page.wait_for_timeout(500)
    # frame the last command at the top of the transcript
    page.evaluate("""() => { const log = document.getElementById('log');
        const cmds = log.querySelectorAll('p.cmd'); const c = cmds[cmds.length - 1];
        log.style.scrollBehavior = 'auto'; log.scrollTop = c.offsetTop - log.offsetTop - 12; }""")
    page.wait_for_timeout(300)
    page.screenshot(path=str(dest))
    b.close()
srv.shutdown()
print("wrote", dest)

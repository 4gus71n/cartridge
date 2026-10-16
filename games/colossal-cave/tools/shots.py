"""Game-local browser checks for Colossal Cave (not the smoke gate).

Usage: python tools/shots.py <export_dir> <out_dir> [es]

Boots the web build in headless Chromium at 412x915 (DPR 2), prints the
positions of the pad buttons (as viewport fractions, for smoke.json), plays a
short scripted game through real taps, reloads to verify the localStorage
autosave/resume, checks tap-a-word, and saves screenshots of every state.
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
locale = "es-ES" if len(sys.argv) > 3 and sys.argv[3] == "es" else "en-US"


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(H, directory=str(export_dir)))
threading.Thread(target=srv.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{srv.server_port}/index.html"
W, H_ = 412, 915
errors = []
fails = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        fails.append(msg)


with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": W, "height": H_}, device_scale_factor=2, has_touch=True,
                        is_mobile=True, locale=locale)
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))

    def idle():
        page.wait_for_function("() => window.cave && !window.cave.state().busy", timeout=15000)
        page.wait_for_timeout(150)

    def tap_word(word):
        el = page.locator(f'.k[data-word="{word}"]').first
        bb = el.bounding_box()
        page.touchscreen.tap(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2)
        page.wait_for_timeout(100)

    def text():
        return page.evaluate("document.getElementById('log').innerText")

    page.goto(url)
    idle()
    page.screenshot(path=str(out / "a-boot.png"))
    rects = page.evaluate("""() => [...document.querySelectorAll('#pad .k, #chips .k, #cmd, #histBtn, #menuBtn, #sendBtn')]
        .map(e => { const r = e.getBoundingClientRect(); return [e.dataset.word || e.id,
          +((r.x + r.width / 2) / innerWidth).toFixed(3), +((r.y + r.height / 2) / innerHeight).toFixed(3),
          Math.round(r.width), Math.round(r.height)] })""")
    print(json.dumps(rects))

    check("Would you like instructions?" in text(), "intro question shown")
    check(page.locator('#chips .k[data-word="NO"]').count() == 1, "NO chip offered for yes/no question")
    tap_word("NO")
    idle()
    check("end of a road" in text(), "NO chip answered the question")
    tap_word("IN")
    idle()
    check("well house" in text(), "IN key entered the building")
    # verb + tap a word in the transcript
    tap_word("TAKE")
    check(page.input_value("#cmd") == "take ", "TAKE armed the input")
    page.screenshot(path=str(out / "b-armed.png"))
    loc = page.evaluate("""() => {
        const ps = [...document.querySelectorAll('#log p.out')];
        for (const p of ps.reverse()) {
          const i = p.textContent.indexOf('lamp'); if (i < 0) continue;
          const r = document.createRange(); r.setStart(p.firstChild, i + 1); r.setEnd(p.firstChild, i + 3);
          const b = r.getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2];
        } return null }""")
    page.touchscreen.tap(*loc)
    idle()
    check("> take lamp" in text() or "take lamp" in text(), "tap on 'lamp' sent 'take lamp'")
    tap_word("INVENTORY")
    idle()
    check("Brass lantern" in text(), "INVENTORY shows the lamp")
    # typed command through the native input
    page.tap("#cmd")
    page.keyboard.type("take keys\n")
    idle()
    check(page.locator("#log p.cmd", has_text="take keys").count() == 1, "typed command sent with Enter")
    for w in ["OUT", "S", "S", "S"]:
        tap_word(w)
        idle()
    page.tap("#cmd")
    page.keyboard.type("unlock grate\n")
    idle()
    tap_word("DOWN")
    idle()
    tap_word("W")
    idle()
    tap_word("LIGHT")  # sent at once: "light" lights the carried lamp
    idle()
    check("lamp is now on" in text(), "LIGHT turned on the lamp")
    tap_word("W")
    idle()
    page.screenshot(path=str(out / "c-midgame.png"))
    saved = page.evaluate("() => !!localStorage.getItem('cave.save.v1')")
    check(saved, "autosave in localStorage")

    # resume after reload
    n_before = page.evaluate("() => document.querySelectorAll('#log p').length")
    page.reload()
    idle()
    t = text()
    after = page.evaluate("""() => { const ps = [...document.querySelectorAll('#log p')];
        let i = ps.length - 1; while (i >= 0 && !ps[i].classList.contains('sep')) i--;
        return ps.slice(i).map(p => p.textContent).join('\\n') }""")
    check("debris room" in after and "points" in after, "resume shows score + current location")
    check(page.evaluate("() => document.querySelectorAll('#log p').length") >= n_before, "transcript restored")
    tap_word("INVENTORY")
    idle()
    check("Brass lantern" in text().split("INVENTORY")[-1] or text().count("Brass lantern") >= 2,
          "inventory survives reload")
    page.screenshot(path=str(out / "d-resumed.png"))

    # history sheet
    page.tap("#histBtn")
    page.wait_for_timeout(300)
    check(page.locator("#histList .hist").count() >= 5, "history sheet lists commands")
    page.screenshot(path=str(out / "e-history.png"))
    page.locator("#histList .hist").first.tap()
    page.wait_for_timeout(200)
    check(page.input_value("#cmd") == "inventory", "history item fills the input")

    # menu + credits
    page.tap("#menuBtn")
    page.wait_for_timeout(300)
    page.screenshot(path=str(out / "f-menu.png"))
    page.tap("#creditsBtn")
    page.wait_for_timeout(300)
    page.screenshot(path=str(out / "g-credits.png"))
    page.tap("#closeCredits")

    # quit -> end card -> play again
    page.fill("#cmd", "quit")
    page.tap("#sendBtn")
    idle()
    tap_word("YES")
    page.wait_for_function("() => window.cave.state().ended", timeout=10000)
    page.wait_for_timeout(300)
    check(page.is_visible("#endcard"), "end card after quitting")
    check(not page.evaluate("() => !!localStorage.getItem('cave.save.v1')"), "save cleared at game end")
    page.screenshot(path=str(out / "h-ended.png"))
    page.reload()
    page.wait_for_timeout(800)
    check(page.is_visible("#endcard"), "end card persists after reload")
    page.tap("#againBtn")
    idle()
    check("Would you like instructions?" in text() and "quit" not in text(), "Play again starts fresh")

    # new game from the menu mid-game
    tap_word("NO")
    idle()
    page.tap("#menuBtn")
    page.tap("#newBtn")
    page.wait_for_timeout(200)
    page.screenshot(path=str(out / "i-confirm.png"))
    page.tap("#confirmYes")
    idle()
    check("end of a road" not in text(), "New game resets the transcript")
    b.close()

srv.shutdown()
print("errors:", errors or "none")
print("FAILED: %d" % len(fails) if fails else "ALL OK")
sys.exit(1 if fails or errors else 0)

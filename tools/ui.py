"""Tiny adb UI driver: tap elements by visible text / content-desc via uiautomator dumps."""
import re
import subprocess
import sys
import time

DEV = "emulator-5554"


def adb(*args, out=False):
    r = subprocess.run(["adb", "-s", DEV, *args], capture_output=True, text=True)
    return r.stdout if out else r.returncode


def nodes():
    for _ in range(4):
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        xml = adb("shell", "cat", "/sdcard/ui.xml", out=True)
        if "<node" in xml:
            break
        time.sleep(1)
    res = []
    for m in re.finditer(r"<node ([^>]*)>", xml):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
        b = re.findall(r"\d+", a.get("bounds", ""))
        if len(b) == 4:
            x1, y1, x2, y2 = map(int, b)
            res.append((a.get("text", ""), a.get("content-desc", ""), a.get("class", ""), (x1 + x2) // 2, (y1 + y2) // 2))
    return res


def find(label, exact=True, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        for t, d, c, x, y in nodes():
            if (label in (t, d)) if exact else (label in t or label in d):
                return x, y
        time.sleep(1)
    raise SystemExit(f"not found: {label}\n" + "\n".join(f"{t!r} {d!r}" for t, d, *_ in nodes() if t or d))


def tap(label, **kw):
    x, y = find(label, **kw)
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(1.2)


def type_into(label, text, **kw):
    tap(label, **kw)
    adb("shell", "input", "text", text.replace(" ", "%s"))
    time.sleep(0.6)


def shot(path):
    with open(path, "wb") as f:
        f.write(subprocess.run(["adb", "-s", DEV, "exec-out", "screencap", "-p"], capture_output=True).stdout)


if __name__ == "__main__":
    cmd, *rest = sys.argv[1:]
    {"tap": lambda: tap(rest[0]), "type": lambda: type_into(rest[0], rest[1]), "shot": lambda: shot(rest[0]),
     "dump": lambda: print("\n".join(f"{t!r} {d!r} {c.split('.')[-1]} {x},{y}" for t, d, c, x, y in nodes() if t or d))}[cmd]()

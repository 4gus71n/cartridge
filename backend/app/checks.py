"""Automated checks for creator-submitted game versions.

Runs as a background thread inside the API (started at startup unless
CHECKS_WORKER=0) and as a CLI:

    python -m app.checks <version_id>   # (re)check one version, print the report
    python -m app.checks --pending      # drain every version in `checking`
    python -m app.checks --worker       # standalone worker loop

A report is a list of {check, status: pass|warn|fail, detail}. Any fail moves the
version to failed_checks, otherwise to needs_review (an admin approves every
version either way).
"""

import argparse
import functools
import hashlib
import ipaddress
import json
import logging
import re
import shutil
import socket
import threading
import time
import zipfile
from contextlib import contextmanager
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import urljoin, urlparse

import httpx

from . import config
from .licensing import ALLOWED_LICENSES, canonical_spdx, detect_spdx, is_allowed

log = logging.getLogger("cartridge.checks")

MAX_PACKAGE_BYTES = 50 * 1024 * 1024
MAX_UNPACKED_BYTES = 100 * 1024 * 1024
MAX_FILES = 5000
DOWNLOAD_TIMEOUT_S = 30
PLAY_URL_TIMEOUT_S = 10
BOOT_TIMEOUT_MS = 30_000
MAX_REDIRECTS = 5
VIEWPORT = {"width": 412, "height": 915}
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36 CartridgeChecks/1.0"
)
POLL_INTERVAL_S = 5

SCANNED_SUFFIXES = {".html", ".htm", ".js", ".mjs", ".css"}
URL_HOST_RE = re.compile(r"https?://([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
SCRIPT_SRC_RE = re.compile(
    r"""<script[^>]*\ssrc\s*=\s*["']?(?:https?:)?//([A-Za-z0-9.-]+)""", re.IGNORECASE
)
LINK_HREF_RE = re.compile(
    r"""<link[^>]*\shref\s*=\s*["']?(?:https?:)?//([A-Za-z0-9.-]+)""", re.IGNORECASE
)
# Namespaces and license/doc links that never load anything.
IGNORED_HOSTS = {
    "www.w3.org", "w3.org", "xmlns.com", "purl.org", "ns.adobe.com",
    "opensource.org", "www.opensource.org", "www.apache.org", "apache.org",
    "www.gnu.org", "gnu.org", "creativecommons.org", "mozilla.org", "www.mozilla.org",
    "example.com", "www.example.com", "localhost",
}
LICENSE_FILE_RE = re.compile(r"^(licen[cs]e|copying|unlicense)", re.IGNORECASE)


class CheckError(Exception):
    pass


def line(check: str, status: str, detail: str) -> dict:
    return {"check": check, "status": status, "detail": detail}


def _mb(n: int) -> str:
    if n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n / 1024 / 1024:.1f} MB"


# --------------------------------------------------------------------------- network


def guard_url(url: str) -> None:
    """Only public https hosts (plus loopback http when ALLOW_LOCAL_URLS is on)."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise CheckError("not an http(s) URL")
    host = parsed.hostname
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror:
        raise CheckError(f"cannot resolve {host}") from None
    ips = {ipaddress.ip_address(str(info[4][0]).split("%")[0]) for info in infos}
    if config.ALLOW_LOCAL_URLS and ips and all(ip.is_loopback for ip in ips):
        return
    if parsed.scheme != "https":
        raise CheckError("URL must use https")
    if any(not ip.is_global for ip in ips):
        raise CheckError(f"{host} resolves to a non-public address")


@contextmanager
def safe_stream(client: httpx.Client, url: str):
    """GET with redirects followed by hand so every hop passes guard_url."""
    for _ in range(MAX_REDIRECTS + 1):
        guard_url(url)
        with client.stream("GET", url) as response:
            if response.is_redirect and response.headers.get("location"):
                url = urljoin(str(response.url), response.headers["location"])
                continue
            yield response
            return
    raise CheckError("too many redirects")


def download(url: str, dest: Path) -> tuple[str, int]:
    deadline = time.monotonic() + DOWNLOAD_TIMEOUT_S
    digest = hashlib.sha256()
    size = 0
    try:
        with httpx.Client(
            timeout=DOWNLOAD_TIMEOUT_S, headers={"User-Agent": MOBILE_UA}
        ) as client, safe_stream(client, url) as response:
            if response.status_code >= 400:
                raise CheckError(f"HTTP {response.status_code}")
            length = response.headers.get("content-length", "")
            if length.isdigit() and int(length) > MAX_PACKAGE_BYTES:
                raise CheckError(f"package is {_mb(int(length))}, the limit is {_mb(MAX_PACKAGE_BYTES)}")
            with open(dest, "wb") as fh:
                for chunk in response.iter_bytes(65536):
                    size += len(chunk)
                    if size > MAX_PACKAGE_BYTES:
                        raise CheckError(f"package is larger than {_mb(MAX_PACKAGE_BYTES)}")
                    if time.monotonic() > deadline:
                        raise CheckError(f"download took longer than {DOWNLOAD_TIMEOUT_S} s")
                    digest.update(chunk)
                    fh.write(chunk)
    except httpx.TimeoutException:
        raise CheckError(f"download timed out after {DOWNLOAD_TIMEOUT_S} s") from None
    except httpx.HTTPError as exc:
        raise CheckError(f"download failed: {type(exc).__name__}") from None
    return digest.hexdigest(), size


def check_play_url(url: str) -> dict:
    if not url:
        return line("play_url", "warn", "no play URL given")
    try:
        with httpx.Client(
            timeout=PLAY_URL_TIMEOUT_S, headers={"User-Agent": MOBILE_UA}
        ) as client, safe_stream(client, url) as response:
            code = response.status_code
    except CheckError as exc:
        return line("play_url", "warn", f"not reachable: {exc}")
    except httpx.HTTPError as exc:
        return line("play_url", "warn", f"not reachable: {type(exc).__name__}")
    if code >= 400:
        return line("play_url", "warn", f"returned HTTP {code}")
    return line("play_url", "pass", f"reachable (HTTP {code})")


# --------------------------------------------------------------------------- package


def unpack(zip_path: Path, dest: Path) -> tuple[dict, str]:
    """Validate and extract a game zip. Returns (manifest {path: [size, crc]}, detail)."""
    try:
        zf = zipfile.ZipFile(zip_path)
    except (zipfile.BadZipFile, OSError):
        raise CheckError("not a valid zip file") from None
    with zf:
        files = []
        declared_total = 0
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
                raise CheckError(f"absolute path in zip: {name}")
            parts = PurePosixPath(name).parts
            if ".." in parts:
                raise CheckError(f"path traversal in zip: {name}")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise CheckError(f"symlink in zip: {name}")
            if info.is_dir() or not parts:
                continue
            if parts[0] == "__MACOSX" or parts[-1] == ".DS_Store":
                continue
            files.append((name, info))
            declared_total += info.file_size
        if not files:
            raise CheckError("zip is empty")
        if len(files) > MAX_FILES:
            raise CheckError(f"{len(files)} files, the limit is {MAX_FILES}")
        if declared_total > MAX_UNPACKED_BYTES:
            raise CheckError(
                f"unpacks to {_mb(declared_total)}, the limit is {_mb(MAX_UNPACKED_BYTES)}"
            )

        names = {name for name, _ in files}
        note = "index.html at the root"
        if "index.html" in names:
            prefix = ""
        else:
            tops = {name.split("/", 1)[0] for name in names}
            top = next(iter(tops))
            if len(tops) == 1 and all("/" in n for n in names) and f"{top}/index.html" in names:
                prefix = f"{top}/"
                note = f"index.html inside '{top}/' (normalised to root)"
            else:
                raise CheckError(
                    "index.html must be at the root of the zip (or inside one top-level folder)"
                )

        dest.mkdir(parents=True, exist_ok=True)
        root = dest.resolve()
        written = 0
        manifest = {}
        for name, info in files:
            rel = name[len(prefix):]
            target = (dest / rel).resolve()
            if root not in target.parents:
                raise CheckError(f"path escapes the package: {name}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as out:
                while chunk := src.read(65536):
                    written += len(chunk)
                    if written > MAX_UNPACKED_BYTES:
                        raise CheckError(f"unpacks to more than {_mb(MAX_UNPACKED_BYTES)}")
                    out.write(chunk)
            manifest[rel] = [info.file_size, info.CRC]
    return manifest, f"{len(manifest)} files, {_mb(written)} unpacked, {note}"


def check_declared_license(declared: str) -> dict:
    spdx = canonical_spdx(declared)
    if is_allowed(spdx):
        return line("license_declared", "pass", f"{spdx} is on the allow-list")
    return line(
        "license_declared",
        "fail",
        f"'{declared or 'none'}' is not allowed (allowed: {', '.join(ALLOWED_LICENSES)})",
    )


def check_license_file(site: Path, declared: str) -> dict:
    declared = canonical_spdx(declared)
    found = sorted(p for p in site.iterdir() if p.is_file() and LICENSE_FILE_RE.match(p.name))
    if not found:
        return line("license_file", "fail", "no LICENSE or COPYING file at the root of the package")
    detected = {p.name: detect_spdx(p.read_text(errors="ignore")[:200_000]) for p in found}
    for name, spdx in detected.items():
        if spdx and not is_allowed(spdx):
            return line("license_file", "fail", f"{name} looks like {spdx}, which is not allowed")
    for name, spdx in detected.items():
        if spdx == declared:
            return line("license_file", "pass", f"{name} matches {declared}")
    known = {name: spdx for name, spdx in detected.items() if spdx}
    if known:
        name, spdx = next(iter(known.items()))
        return line("license_file", "fail", f"{name} looks like {spdx} but {declared} was declared")
    names = ", ".join(detected)
    return line("license_file", "warn", f"could not recognise the license text in {names}")


def check_external_refs(site: Path) -> dict:
    hosts: set[str] = set()
    script_hosts: set[str] = set()
    for path in site.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SCANNED_SUFFIXES:
            continue
        text = path.read_text(errors="ignore")[:5_000_000]
        hosts.update(h.lower() for h in URL_HOST_RE.findall(text))
        if path.suffix.lower() in (".html", ".htm"):
            script_hosts.update(h.lower() for h in SCRIPT_SRC_RE.findall(text))
            script_hosts.update(h.lower() for h in LINK_HREF_RE.findall(text))
    hosts = {h for h in hosts | script_hosts if h not in IGNORED_HOSTS}
    script_hosts = {h for h in script_hosts if h not in IGNORED_HOSTS}
    if not hosts:
        return line("external_refs", "pass", "no external hosts referenced")
    detail = (
        f"references {len(hosts)} external host(s): {', '.join(sorted(hosts)[:10])}"
        " — the game may not work offline"
    )
    if script_hosts:
        detail = f"loads scripts/styles from {', '.join(sorted(script_hosts)[:10])}; " + detail
    return line("external_refs", "warn", detail)


# --------------------------------------------------------------------------- boot


class _QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass


def serve_dir(directory: Path) -> ThreadingHTTPServer:
    handler = functools.partial(_QuietHandler, directory=str(directory))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def boot_check(site: Path, screenshot: Path) -> list[dict]:
    """Open index.html in headless Chromium at phone size, offline except our server."""
    try:
        from playwright.sync_api import TimeoutError as PlaywrightTimeout
        from playwright.sync_api import sync_playwright
    except ImportError:
        return [line("boot", "warn", "playwright is not installed; boot check skipped")]

    server = serve_dir(site)
    origin = f"http://127.0.0.1:{server.server_address[1]}"
    page_errors: list[str] = []
    console_errors: list[str] = []
    blocked: set[str] = set()
    lines: list[dict] = []
    load_ms = None
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                args=["--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"]
            )
            try:
                context = browser.new_context(
                    viewport=VIEWPORT,
                    is_mobile=True,
                    has_touch=True,
                    device_scale_factor=2,
                    user_agent=MOBILE_UA,
                    service_workers="block",
                )

                def route(r):
                    if r.request.url.startswith(origin + "/"):
                        r.continue_()
                    else:
                        blocked.add(urlparse(r.request.url).hostname or r.request.url[:60])
                        r.abort("blockedbyclient")

                context.route("**/*", route)
                page = context.new_page()
                page.on("pageerror", lambda exc: page_errors.append(str(exc)[:300]))
                page.on(
                    "console",
                    lambda msg: console_errors.append(msg.text[:300]) if msg.type == "error" else None,
                )
                page.on("dialog", lambda dialog: dialog.dismiss())
                started = time.monotonic()
                try:
                    page.goto(f"{origin}/index.html", wait_until="load", timeout=BOOT_TIMEOUT_MS)
                    load_ms = int((time.monotonic() - started) * 1000)
                except PlaywrightTimeout:
                    lines.append(
                        line("boot", "fail", f"did not finish loading within {BOOT_TIMEOUT_MS // 1000} s")
                    )
                page.wait_for_timeout(config.CHECKS_SETTLE_MS)
                screenshot.parent.mkdir(parents=True, exist_ok=True)
                page.screenshot(path=str(screenshot))
            finally:
                browser.close()
    except Exception as exc:  # browser missing / crashed: let a human look
        log.exception("boot check crashed")
        return [line("boot", "warn", f"headless browser unavailable: {type(exc).__name__}: {exc}"[:300])]
    finally:
        server.shutdown()
        server.server_close()

    if page_errors:
        lines.append(
            line("boot", "fail", f"{len(page_errors)} uncaught error(s): " + " | ".join(page_errors[:3]))
        )
    elif load_ms is not None:
        lines.append(line("boot", "pass", f"loaded in {load_ms} ms at 412x915 (touch), no uncaught errors"))
    if console_errors or blocked:
        parts = []
        if console_errors:
            parts.append(f"{len(console_errors)} console error(s): " + " | ".join(console_errors[:3]))
        if blocked:
            parts.append("blocked network requests to " + ", ".join(sorted(blocked)[:10]))
        lines.append(line("console", "warn", "; ".join(parts)))
    else:
        lines.append(line("console", "pass", "no console errors, no external requests"))
    return lines


# --------------------------------------------------------------------------- orchestration


def check_package(
    *, package_url: str, play_url: str, license_spdx: str, workdir: Path
) -> dict:
    """Run every check (no DB). Returns report, status and package facts."""
    workdir.mkdir(parents=True, exist_ok=True)
    zip_path = workdir / "package.zip"
    site = workdir / "site"
    shot = workdir / "screenshot.png"
    shutil.rmtree(site, ignore_errors=True)
    shot.unlink(missing_ok=True)
    facts = {"sha256": "", "size_bytes": 0, "manifest": {}, "screenshot": ""}
    report = [check_declared_license(license_spdx)]
    unpacked = False
    try:
        if not package_url:
            report.append(line("download", "fail", "no package URL"))
        else:
            try:
                sha, size = download(package_url, zip_path)
                facts.update(sha256=sha, size_bytes=size)
                report.append(line("download", "pass", f"{_mb(size)}, sha256 {sha[:12]}…"))
            except CheckError as exc:
                report.append(line("download", "fail", str(exc)))
            else:
                try:
                    manifest, detail = unpack(zip_path, site)
                    facts["manifest"] = manifest
                    report.append(line("zip_safety", "pass", detail))
                    unpacked = True
                except CheckError as exc:
                    report.append(line("zip_safety", "fail", str(exc)))
        if unpacked:
            report.append(check_license_file(site, license_spdx))
            report.append(check_external_refs(site))
            report.extend(boot_check(site, shot))
            if shot.is_file():
                facts["screenshot"] = str(shot)
        report.append(check_play_url(play_url))
    finally:
        shutil.rmtree(site, ignore_errors=True)
        zip_path.unlink(missing_ok=True)
    status = "failed_checks" if any(r["status"] == "fail" for r in report) else "needs_review"
    return {"report": report, "status": status, **facts}


def run_version(version_id: int) -> str:
    """Check one version and store the result. Always leaves `checking`."""
    from .db import SessionLocal
    from .models import GameVersion

    db = SessionLocal()
    try:
        v = db.get(GameVersion, version_id)
        if v is None:
            raise ValueError(f"version {version_id} not found")
        try:
            result = check_package(
                package_url=v.package_url,
                play_url=v.play_url,
                license_spdx=v.license_spdx,
                workdir=config.CHECKS_DIR / f"v{v.id}",
            )
        except Exception as exc:
            log.exception("checks crashed for version %s", version_id)
            result = {
                "report": [
                    line("internal", "fail", f"checker error ({type(exc).__name__}); an admin will re-run the checks")
                ],
                "status": "failed_checks",
                "sha256": "",
                "size_bytes": 0,
                "manifest": {},
                "screenshot": "",
            }
        db.refresh(v)
        v.report = json.dumps(result["report"])
        v.sha256 = result["sha256"]
        v.size_bytes = result["size_bytes"]
        v.manifest = json.dumps(result["manifest"])
        v.file_count = len(result["manifest"])
        v.screenshot_path = f"v{v.id}/screenshot.png" if result["screenshot"] else ""
        v.checked_at = datetime.utcnow()
        if v.status == "checking":  # may have been superseded meanwhile
            v.status = result["status"]
        db.commit()
        return v.status
    finally:
        db.close()


def process_pending(limit: int | None = None) -> int:
    from .db import SessionLocal
    from .models import GameVersion

    done = 0
    while limit is None or done < limit:
        db = SessionLocal()
        try:
            row = (
                db.query(GameVersion.id)
                .filter(GameVersion.status == "checking")
                .order_by(GameVersion.id.asc())
                .first()
            )
        finally:
            db.close()
        if row is None:
            break
        run_version(row[0])
        done += 1
    return done


_wake = threading.Event()
_stop = threading.Event()
_thread: threading.Thread | None = None


def wake() -> None:
    """Called after a submission so the worker doesn't wait for the next poll."""
    _wake.set()


def _loop() -> None:
    log.info("checks worker started")
    while not _stop.is_set():
        try:
            process_pending()
        except Exception:
            log.exception("checks worker iteration failed")
        _wake.wait(POLL_INTERVAL_S)
        _wake.clear()


def start_worker() -> None:
    global _thread
    if not config.CHECKS_WORKER or (_thread is not None and _thread.is_alive()):
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name="checks-worker", daemon=True)
    _thread.start()


def stop_worker() -> None:
    _stop.set()
    _wake.set()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.checks", description=__doc__.split("\n")[0])
    parser.add_argument("version_id", nargs="?", type=int, help="version to (re)check")
    parser.add_argument("--pending", action="store_true", help="check every version in `checking`")
    parser.add_argument("--worker", action="store_true", help="run the worker loop forever")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO)

    from . import migrate, models  # noqa: F401
    from .db import Base, SessionLocal, engine

    Base.metadata.create_all(bind=engine)
    migrate.run(engine)
    if args.worker:
        config.CHECKS_WORKER = True
        _loop()
        return 0
    if args.pending:
        print(f"checked {process_pending()} version(s)")
        return 0
    if args.version_id is None:
        parser.error("give a version id, --pending or --worker")
    db = SessionLocal()
    v = db.get(models.GameVersion, args.version_id)
    if v is None:
        print(f"version {args.version_id} not found")
        return 1
    v.status = "checking"
    db.commit()
    db.close()
    status = run_version(args.version_id)
    db = SessionLocal()
    report = json.loads(db.get(models.GameVersion, args.version_id).report)
    db.close()
    for r in report:
        print(f"{r['status']:>4}  {r['check']:<17} {r['detail']}")
    print(f"=> {status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

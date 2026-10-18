"""Each automated check against fixture packages served from 127.0.0.1 (no internet)."""

import pytest

from app import checks, config
from app.licensing import detect_spdx
from gamekit import APACHE, CDN_INDEX, ERROR_JS, GPL3, INDEX, MIT, MPL, good_files, write_zip


def run(file_server, tmp_path, name, files=None, *, symlinks=None, license_spdx="MIT", raw=None, play=None):
    base, root = file_server
    if raw is not None:
        (root / name).write_bytes(raw)
    elif files is not None:
        write_zip(root / name, files, symlinks)
    result = checks.check_package(
        package_url=f"{base}/{name}",
        play_url=play if play is not None else f"{base}/",
        license_spdx=license_spdx,
        workdir=tmp_path / "work",
    )
    by_check = {}
    for entry in result["report"]:
        by_check.setdefault(entry["check"], entry)
    return result, by_check


def statuses(by_check):
    return {k: v["status"] for k, v in by_check.items()}


def test_good_game_passes_everything(file_server, tmp_path):
    result, by = run(file_server, tmp_path, "good.zip", good_files())
    assert result["status"] == "needs_review", result["report"]
    assert set(statuses(by).values()) == {"pass"}, result["report"]
    assert len(result["sha256"]) == 64 and result["size_bytes"] > 0
    assert set(result["manifest"]) == {"index.html", "game.js", "LICENSE"}
    assert result["screenshot"].endswith("screenshot.png")
    assert "loaded in" in by["boot"]["detail"]
    # temporary files are cleaned, the screenshot stays
    assert not (tmp_path / "work" / "site").exists()
    assert (tmp_path / "work" / "screenshot.png").is_file()


def test_single_top_folder_is_normalised(file_server, tmp_path, monkeypatch):
    monkeypatch.setattr(checks, "boot_check", lambda site, shot: [])
    files = {f"my-game/{k}": v for k, v in good_files().items()}
    files["__MACOSX/._index.html"] = "junk"
    result, by = run(file_server, tmp_path, "nested.zip", files)
    assert by["zip_safety"]["status"] == "pass"
    assert "normalised" in by["zip_safety"]["detail"]
    assert "index.html" in result["manifest"]
    assert by["license_file"]["status"] == "pass"


@pytest.mark.parametrize(
    "files,symlinks,needle",
    [
        ({"index.html": INDEX, "LICENSE": MIT, "../evil.js": "x"}, None, "traversal"),
        ({"index.html": INDEX, "LICENSE": MIT, "a/../../evil.js": "x"}, None, "traversal"),
        ({"index.html": INDEX, "LICENSE": MIT, "/etc/evil": "x"}, None, "absolute"),
        ({"index.html": INDEX, "LICENSE": MIT}, {"link": "/etc/passwd"}, "symlink"),
        ({"game.html": INDEX, "LICENSE": MIT}, None, "index.html"),
        ({"a/index.html": INDEX, "b/LICENSE": MIT}, None, "index.html"),
    ],
)
def test_unsafe_zips_fail(file_server, tmp_path, files, symlinks, needle):
    result, by = run(file_server, tmp_path, "bad.zip", files, symlinks=symlinks)
    assert result["status"] == "failed_checks"
    assert by["zip_safety"]["status"] == "fail"
    assert needle in by["zip_safety"]["detail"]
    assert "boot" not in by  # nothing ran on an unsafe package


def test_not_a_zip_and_missing_package(file_server, tmp_path):
    result, by = run(file_server, tmp_path, "junk.zip", raw=b"this is not a zip")
    assert by["zip_safety"]["status"] == "fail" and "valid zip" in by["zip_safety"]["detail"]
    result, by = run(file_server, tmp_path, "missing.zip")
    assert by["download"]["status"] == "fail" and "404" in by["download"]["detail"]
    assert result["status"] == "failed_checks"


def test_oversized_download(file_server, tmp_path, monkeypatch):
    monkeypatch.setattr(checks, "MAX_PACKAGE_BYTES", 1000)
    files = good_files(**{"big.bin": __import__("os").urandom(5000)})
    result, by = run(file_server, tmp_path, "huge.zip", files)
    assert by["download"]["status"] == "fail"
    assert "limit" in by["download"]["detail"] or "larger" in by["download"]["detail"]
    assert result["status"] == "failed_checks"


def test_unpacked_size_and_file_count_caps(file_server, tmp_path, monkeypatch):
    monkeypatch.setattr(checks, "MAX_UNPACKED_BYTES", 100_000)
    bomb = good_files(**{"zeros.bin": b"\0" * 200_000})  # compresses to a few hundred bytes
    _, by = run(file_server, tmp_path, "bomb.zip", bomb)
    assert by["zip_safety"]["status"] == "fail" and "unpacks to" in by["zip_safety"]["detail"]

    monkeypatch.setattr(checks, "MAX_UNPACKED_BYTES", 100 * 1024 * 1024)
    monkeypatch.setattr(checks, "MAX_FILES", 3)
    many = good_files(**{f"f{i}.txt": "x" for i in range(5)})
    _, by = run(file_server, tmp_path, "many.zip", many)
    assert by["zip_safety"]["status"] == "fail" and "files" in by["zip_safety"]["detail"]


def test_license_checks(file_server, tmp_path, monkeypatch):
    monkeypatch.setattr(checks, "boot_check", lambda site, shot: [])
    no_license = {"index.html": INDEX, "game.js": "1"}
    result, by = run(file_server, tmp_path, "nolicense.zip", no_license)
    assert by["license_file"]["status"] == "fail" and result["status"] == "failed_checks"

    result, by = run(file_server, tmp_path, "gpl.zip", good_files(LICENSE=GPL3))
    assert by["license_file"]["status"] == "fail" and "GPL-3.0" in by["license_file"]["detail"]

    _, by = run(file_server, tmp_path, "gpl-declared.zip", good_files(LICENSE=GPL3), license_spdx="GPL-3.0")
    assert by["license_declared"]["status"] == "fail"

    _, by = run(file_server, tmp_path, "mismatch.zip", good_files(LICENSE=APACHE))
    assert by["license_file"]["status"] == "fail" and "Apache-2.0" in by["license_file"]["detail"]

    _, by = run(file_server, tmp_path, "apache.zip", good_files(LICENSE=APACHE), license_spdx="apache-2.0")
    assert by["license_file"]["status"] == "pass"

    custom = good_files(LICENSE="All rights reserved, do whatever you like.")
    result, by = run(file_server, tmp_path, "custom.zip", custom)
    assert by["license_file"]["status"] == "warn" and result["status"] == "needs_review"

    files = good_files()
    files["COPYING.md"] = files.pop("LICENSE")
    _, by = run(file_server, tmp_path, "copying.zip", files)
    assert by["license_file"]["status"] == "pass"


def test_detect_spdx():
    assert detect_spdx(MIT) == "MIT"
    assert detect_spdx(GPL3) == "GPL-3.0"
    assert detect_spdx(APACHE) == "Apache-2.0"
    assert detect_spdx(MPL) == "MPL-2.0"  # mentions the GNU licenses, still MPL
    assert detect_spdx("GNU LESSER GENERAL PUBLIC LICENSE Version 3 ... GNU General Public License") == "LGPL-3.0"
    assert detect_spdx("This is free and unencumbered software released into the public domain.") == "Unlicense"
    assert detect_spdx("Creative Commons Legal Code\n\nCC0 1.0 Universal") == "CC0-1.0"
    assert detect_spdx("Attribution-ShareAlike 4.0 International") == "CC-BY-SA-4.0"
    assert detect_spdx("Creative Commons Attribution 4.0 International Public License") == "CC-BY-4.0"
    isc = "Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee"
    assert detect_spdx(isc) == "ISC"
    bsd = "Redistribution and use in source and binary forms, with or without modification"
    assert detect_spdx(bsd) == "BSD-2-Clause"
    assert detect_spdx(bsd + " Neither the name of the copyright holder") == "BSD-3-Clause"
    assert detect_spdx("hello") is None


def test_external_cdn_warns_and_is_blocked(file_server, tmp_path):
    files = good_files(**{"index.html": CDN_INDEX})
    result, by = run(file_server, tmp_path, "cdn.zip", files)
    assert result["status"] == "needs_review", result["report"]
    assert by["external_refs"]["status"] == "warn"
    assert "cdn.jsdelivr.net" in by["external_refs"]["detail"]
    assert "loads scripts" in by["external_refs"]["detail"]
    assert by["console"]["status"] == "warn"
    assert "cdn.jsdelivr.net" in by["console"]["detail"]  # request was blocked, not fetched


def test_uncaught_error_fails_boot(file_server, tmp_path):
    result, by = run(file_server, tmp_path, "crash.zip", good_files(**{"game.js": ERROR_JS}))
    assert by["boot"]["status"] == "fail"
    assert "undefinedFunctionCall" in by["boot"]["detail"]
    assert result["status"] == "failed_checks"


def test_play_url_reachability(file_server, tmp_path, monkeypatch):
    monkeypatch.setattr(checks, "boot_check", lambda site, shot: [])
    base, root = file_server
    (root / "play").mkdir(exist_ok=True)
    (root / "play" / "index.html").write_text("<p>play</p>")
    _, by = run(file_server, tmp_path, "p.zip", good_files(), play=f"{base}/play")  # 301 -> /play/
    assert by["play_url"]["status"] == "pass"
    _, by = run(file_server, tmp_path, "p.zip", good_files(), play=f"{base}/nope/")
    assert by["play_url"]["status"] == "warn" and "404" in by["play_url"]["detail"]
    _, by = run(file_server, tmp_path, "p.zip", good_files(), play="http://127.0.0.1:9/")
    assert by["play_url"]["status"] == "warn"


def test_guard_url_blocks_private_and_plain_http(monkeypatch):
    monkeypatch.setattr(config, "ALLOW_LOCAL_URLS", False)
    with pytest.raises(checks.CheckError, match="https"):
        checks.guard_url("http://127.0.0.1/x.zip")
    with pytest.raises(checks.CheckError, match="non-public"):
        checks.guard_url("https://127.0.0.1/x.zip")
    with pytest.raises(checks.CheckError, match="non-public"):
        checks.guard_url("https://10.0.0.8/x.zip")
    with pytest.raises(checks.CheckError):
        checks.guard_url("ftp://example.com/x.zip")

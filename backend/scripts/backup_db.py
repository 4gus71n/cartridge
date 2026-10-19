"""Consistent SQLite snapshot of the Cartridge DB (safe while the API is writing).

    python -m scripts.backup_db            # one snapshot into $BACKUP_DIR
    python -m scripts.backup_db --loop     # every BACKUP_HOURS (default 24), forever

Keeps the newest BACKUP_KEEP (default 14) snapshots. The DB path comes from
DATABASE_URL (sqlite only).
"""

from __future__ import annotations

import datetime as dt
import os
import pathlib
import sqlite3
import sys
import time


def db_path() -> pathlib.Path:
    url = os.getenv("DATABASE_URL", "sqlite:///./cartridge.db")
    if not url.startswith("sqlite:///"):
        raise SystemExit(f"backup_db only supports sqlite, got {url}")
    return pathlib.Path(url[len("sqlite:///"):])


def snapshot() -> pathlib.Path:
    src = db_path()
    out_dir = pathlib.Path(os.getenv("BACKUP_DIR", str(src.parent / "backups")))
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / f"cartridge-{dt.datetime.now(dt.timezone.utc):%Y%m%d-%H%M%S}.db"
    with sqlite3.connect(src) as source, sqlite3.connect(dst) as target:
        source.backup(target)
    keep = int(os.getenv("BACKUP_KEEP", "14"))
    for old in sorted(out_dir.glob("cartridge-*.db"))[:-keep]:
        old.unlink()
    print(f"backup: {dst} ({dst.stat().st_size // 1024} KB)", flush=True)
    return dst


if __name__ == "__main__":
    if "--loop" in sys.argv:
        hours = float(os.getenv("BACKUP_HOURS", "24"))
        while True:
            snapshot()
            time.sleep(hours * 3600)
    else:
        snapshot()

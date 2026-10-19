import sqlite3

from scripts import backup_db


def test_snapshot_and_rotation(tmp_path, monkeypatch):
    db = tmp_path / "live.db"
    with sqlite3.connect(db) as c:
        c.execute("create table t (x)")
        c.execute("insert into t values (42)")
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{db}")
    monkeypatch.setenv("BACKUP_DIR", str(tmp_path / "b"))
    monkeypatch.setenv("BACKUP_KEEP", "2")
    for i in range(3):
        (tmp_path / "b").mkdir(exist_ok=True)
        (tmp_path / "b" / f"cartridge-2000010{i}-000000.db").write_bytes(b"old")
    dst = backup_db.snapshot()
    with sqlite3.connect(dst) as c:
        assert c.execute("select x from t").fetchone() == (42,)
    assert sorted(p.name for p in (tmp_path / "b").iterdir()) == ["cartridge-20000102-000000.db", dst.name]

"""Tiny additive migrations for SQLite/Postgres (create_all never alters tables).

Add a column here when a model gains one; `run()` is idempotent and runs at startup.
"""

from sqlalchemy import inspect, text

# table -> {column: DDL type + default}
ADDED_COLUMNS: dict[str, dict[str, str]] = {
    "games": {
        "orientation": "VARCHAR(20) NOT NULL DEFAULT 'any'",
        "review_note": "VARCHAR(300) NOT NULL DEFAULT ''",
        "qa_status": "VARCHAR(20) NOT NULL DEFAULT ''",
        "qa_keys": "VARCHAR(120) NOT NULL DEFAULT ''",
        "qa_note": "VARCHAR(300) NOT NULL DEFAULT ''",
        "version": "INTEGER NOT NULL DEFAULT 1",
        "title_es": "VARCHAR(200) NOT NULL DEFAULT ''",
        "description_es": "TEXT NOT NULL DEFAULT ''",
        "creator_id": "INTEGER",
    },
}


def run(engine) -> list[str]:
    insp = inspect(engine)
    done = []
    with engine.begin() as conn:
        for table, cols in ADDED_COLUMNS.items():
            if not insp.has_table(table):
                continue  # create_all will build it with every column
            have = {c["name"] for c in insp.get_columns(table)}
            for name, ddl in cols.items():
                if name not in have:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
                    done.append(f"{table}.{name}")
    return done



def migrate_legacy_submissions(engine) -> int:
    """Copy v1 `submissions` rows into `game_versions` (idempotent; old table kept).

    pending -> needs_review (empty report, no creator), rejected -> rejected.
    Approved submissions already produced a `games` row and are skipped.
    """
    from sqlalchemy.orm import Session

    from .models import GameVersion, Submission
    from .versions import version_from_submission

    insp = inspect(engine)
    if not (insp.has_table("submissions") and insp.has_table("game_versions")):
        return 0
    count = 0
    with Session(engine) as db:
        done = {
            sid
            for (sid,) in db.query(GameVersion.legacy_submission_id).filter(
                GameVersion.legacy_submission_id.isnot(None)
            )
        }
        rows = (
            db.query(Submission)
            .filter(Submission.status.in_(("pending", "rejected")))
            .order_by(Submission.id)
            .all()
        )
        for submission in rows:
            if submission.id in done:
                continue
            version_from_submission(db, submission)
            db.flush()
            count += 1
        db.commit()
    return count

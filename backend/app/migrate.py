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

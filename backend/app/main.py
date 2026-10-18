from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import models  # noqa: F401  (register models before create_all)
from . import catalog, migrate
from .db import Base, engine
from .routers import admin, auth, catalog_admin, games, social, submissions

STATIC_DIR = Path(__file__).resolve().parent / "static"
(STATIC_DIR / "packages").mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Cartridge API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)
migrate.run(engine)

app.include_router(auth.router)
app.include_router(games.router)
app.include_router(social.router)
app.include_router(submissions.router)
app.include_router(admin.router)
app.include_router(catalog_admin.router)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.on_event("startup")
def _start_catalog_worker() -> None:
    catalog.start_background()


@app.get("/health")
def health():
    return {"status": "ok"}

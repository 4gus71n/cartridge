from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import models  # noqa: F401  (register models before create_all)
from . import catalog, checks, migrate
from .db import Base, engine
from .routers import admin, auth, catalog_admin, creator, games, social, submissions

STATIC_DIR = Path(__file__).resolve().parent / "static"
(STATIC_DIR / "packages").mkdir(parents=True, exist_ok=True)



@asynccontextmanager
async def lifespan(_app: FastAPI):
    checks.start_worker()  # no-op when CHECKS_WORKER=0
    catalog.start_background()  # no-op when CARTRIDGE_BACKGROUND=0
    yield
    checks.stop_worker()


app = FastAPI(title="Cartridge API", version="0.3.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)
migrate.run(engine)
migrate.migrate_legacy_submissions(engine)

app.include_router(auth.router)
app.include_router(games.router)
app.include_router(social.router)
app.include_router(submissions.router)
app.include_router(admin.router)
app.include_router(catalog_admin.router)
app.include_router(creator.router)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/health")
def health():
    return {"status": "ok"}

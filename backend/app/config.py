import os
import pathlib

from dotenv import load_dotenv

BACKEND_DIR = pathlib.Path(__file__).resolve().parents[1]
load_dotenv(BACKEND_DIR / ".env")

# Absolute default so scripts run from any cwd hit the same DB (a relative
# sqlite path once created a stray ./cartridge.db at the repo root).
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{BACKEND_DIR / 'cartridge.db'}")
if DATABASE_URL.startswith("sqlite:///./"):
    DATABASE_URL = f"sqlite:///{BACKEND_DIR / DATABASE_URL.removeprefix('sqlite:///./')}"
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-me")
JWT_TTL_DAYS = int(os.getenv("JWT_TTL_DAYS", "30"))
ADMIN_EMAILS = [e.strip().lower() for e in os.getenv("ADMIN_EMAILS", "").split(",") if e.strip()]
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000").rstrip("/")

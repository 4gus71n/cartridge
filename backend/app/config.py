import os

from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./cartridge.db")
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-me")
JWT_TTL_DAYS = int(os.getenv("JWT_TTL_DAYS", "30"))
ADMIN_EMAILS = [e.strip().lower() for e in os.getenv("ADMIN_EMAILS", "").split(",") if e.strip()]
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000").rstrip("/")

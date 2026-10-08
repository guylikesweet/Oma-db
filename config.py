import os
from dotenv import load_dotenv

load_dotenv()

basedir = os.path.abspath(os.path.dirname(__file__))


class Config:
    _secret_key = os.environ.get("SECRET_KEY")
    _production_database = bool(os.environ.get("DATABASE_URL"))
    _public_base_url = os.environ.get("OMA_PUBLIC_BASE_URL", "").strip().rstrip("/")

    # Never allow the production deployment to silently fall back to a
    # predictable signing key. Local development may still use the explicit
    # development fallback when DATABASE_URL is not configured.
    if _production_database and not _secret_key:
        raise RuntimeError(
            "SECRET_KEY must be configured when DATABASE_URL is set."
        )

    SECRET_KEY = _secret_key or "dev-key-change-me"

    _admin_username = os.environ.get("ADMIN_USERNAME")
    _admin_password = os.environ.get("ADMIN_PASSWORD")
    if _production_database and not _admin_username:
        raise RuntimeError(
            "ADMIN_USERNAME must be configured when DATABASE_URL is set."
        )
    if _production_database and not _admin_password:
        raise RuntimeError(
            "ADMIN_PASSWORD must be configured when DATABASE_URL is set."
        )

    if _production_database and not _public_base_url.startswith(("https://", "http://")):
        raise RuntimeError(
            "OMA_PUBLIC_BASE_URL must be configured as an http(s) URL when DATABASE_URL is set."
        )

    # Render/Supabase provide DATABASE_URL as postgres://... -> SQLAlchemy needs postgresql://
    _raw_db_url = os.environ.get("DATABASE_URL", "")
    if _raw_db_url.startswith("postgres://"):
        _raw_db_url = _raw_db_url.replace("postgres://", "postgresql://", 1)

    SQLALCHEMY_DATABASE_URI = _raw_db_url or "sqlite:///" + os.path.join(basedir, "dev.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # A 12 MB raw chat photo becomes roughly 16 MB when base64 encoded in JSON.
    # Leave a little protocol overhead while still preventing unexpectedly large
    # request bodies from reaching Flask/Pillow.
    MAX_CONTENT_LENGTH = 18 * 1024 * 1024

    # The legacy /classic interface uses Flask's signed session cookie.
    # Harden it automatically for the production deployment.
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = _production_database

    # Neon (and most serverless/free-tier Postgres) suspends its compute after a few
    # minutes idle. A connection sitting in SQLAlchemy's pool at that point goes stale,
    # so without these settings the next request fails with
    # "SSL connection has been closed unexpectedly". pool_pre_ping tests each connection
    # with a cheap SELECT 1 before using it and transparently reconnects if it's dead.
    # pool_recycle forces connections older than 5 minutes to be replaced proactively.
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    ADMIN_USERNAME = _admin_username or "admin"
    ADMIN_PASSWORD = _admin_password or "change-me"
    OMA_PUBLIC_BASE_URL = _public_base_url

    # Default courier rate per CBM (Naira), used when seeding courier_rates
    DEFAULT_RATE_PER_CBM = 600000.00

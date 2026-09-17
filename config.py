import os
from dotenv import load_dotenv

load_dotenv()

basedir = os.path.abspath(os.path.dirname(__file__))


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-key-change-me")

    # Render/Supabase provide DATABASE_URL as postgres://... -> SQLAlchemy needs postgresql://
    _raw_db_url = os.environ.get("DATABASE_URL", "")
    if _raw_db_url.startswith("postgres://"):
        _raw_db_url = _raw_db_url.replace("postgres://", "postgresql://", 1)

    SQLALCHEMY_DATABASE_URI = _raw_db_url or "sqlite:///" + os.path.join(basedir, "dev.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False

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

    ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
    ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "change-me")

    # Default courier rate per CBM (Naira), used when seeding courier_rates
    DEFAULT_RATE_PER_CBM = 600000.00

import os
from pydantic import BaseModel


class Settings(BaseModel):
    jwks_url: str = os.getenv("JWKS_URL", "http://localhost/.well-known/jwks.json")
    jwt_audience: str = os.getenv("JWT_AUDIENCE", "secure-device-clients")
    jwt_issuer: str = os.getenv("JWT_ISSUER", "secure-device-control-system")
    heartbeat_interval_seconds: int = int(os.getenv("HEARTBEAT_INTERVAL_SECONDS", "30"))
    telemetry_interval_seconds: int = int(os.getenv("TELEMETRY_INTERVAL_SECONDS", "60"))
    policy_hash: str = os.getenv("POLICY_HASH", "sha256:policy_placeholder")
    controller_id: str = os.getenv("CONTROLLER_ID", "controller")
    laravel_webhook_base: str = os.getenv("LARAVEL_WEBHOOK_BASE", "http://localhost/api/v1/webhook")

    # Security / signing / replay protection
    redis_url: str | None = os.getenv("REDIS_URL")
    max_clock_skew_seconds: int = int(os.getenv("MAX_CLOCK_SKEW_SECONDS", "5"))
    require_ed25519: bool = os.getenv("REQUIRE_ED25519", "true").lower() in ("1", "true", "yes")
    allow_dev_sig_fallback: bool = os.getenv("ALLOW_DEV_SIG_FALLBACK", "false").lower() in ("1", "true", "yes")
    require_agent_seq: bool = os.getenv("REQUIRE_AGENT_SEQ", "true").lower() in ("1", "true", "yes")

    # Device key registry (SQLite + optional seeding JSON)
    device_registry_db_path: str = os.getenv("DEVICE_REGISTRY_DB_PATH", "./data/device_registry.db")
    device_pubkeys_seed_path: str | None = os.getenv("DEVICE_PUBKEYS_PATH")


settings = Settings()

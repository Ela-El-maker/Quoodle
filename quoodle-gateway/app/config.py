import os
from pydantic import BaseModel


class Settings(BaseModel):
    jwks_url: str = os.getenv("JWKS_URL", "http://localhost:8000/.well-known/jwks.json")
    jwt_audience: str = os.getenv("JWT_AUDIENCE", "secure-device-clients")
    jwt_issuer: str = os.getenv("JWT_ISSUER", "secure-device-control-system")
    heartbeat_interval_seconds: int = int(os.getenv("HEARTBEAT_INTERVAL_SECONDS", "30"))
    telemetry_interval_seconds: int = int(os.getenv("TELEMETRY_INTERVAL_SECONDS", "60"))
    policy_hash: str | None = os.getenv("POLICY_HASH")
    controller_id: str = os.getenv("CONTROLLER_ID", "controller")
    policy_version: str | None = os.getenv("POLICY_VERSION")
    laravel_webhook_base: str = os.getenv("LARAVEL_WEBHOOK_BASE", "http://localhost:8000/api/v1/webhook")

    # Redis configuration
    redis_url: str | None = os.getenv("REDIS_URL")
    redis_max_connections: int = int(os.getenv("REDIS_MAX_CONNECTIONS", "10"))
    redis_socket_timeout: float = float(os.getenv("REDIS_SOCKET_TIMEOUT", "5.0"))
    redis_key_prefix: str = os.getenv("REDIS_KEY_PREFIX", "quoodle:")

    # Security / signing / replay protection
    max_clock_skew_seconds: int = int(os.getenv("MAX_CLOCK_SKEW_SECONDS", "5"))
    require_ed25519: bool = os.getenv("REQUIRE_ED25519", "true").lower() in ("1", "true", "yes")
    allow_dev_sig_fallback: bool = os.getenv("ALLOW_DEV_SIG_FALLBACK", "false").lower() in ("1", "true", "yes")
    require_agent_seq: bool = os.getenv("REQUIRE_AGENT_SEQ", "true").lower() in ("1", "true", "yes")

    # Device key registry (SQLite + optional seeding JSON)
    device_registry_db_path: str = os.getenv("DEVICE_REGISTRY_DB_PATH", "./data/device_registry.db")
    device_pubkeys_seed_path: str | None = os.getenv("DEVICE_PUBKEYS_PATH")

    # Laravel ↔ FastAPI (server-to-server) request signing
    require_laravel_signature: bool = os.getenv("REQUIRE_LARAVEL_SIGNATURE", "false").lower() in ("1", "true", "yes")
    laravel_service_pubkey_b64: str | None = os.getenv("LARAVEL_SERVICE_PUBKEY_B64")
    require_laravel_seq: bool = os.getenv("REQUIRE_LARAVEL_SEQ", "false").lower() in ("1", "true", "yes")

    # FastAPI → Laravel webhook signing
    sign_laravel_webhooks: bool = os.getenv("SIGN_LARAVEL_WEBHOOKS", "false").lower() in ("1", "true", "yes")
    fastapi_service_private_key_b64: str | None = os.getenv("FASTAPI_SERVICE_PRIVATE_KEY_B64")

    # Webhook outbox (durable retries)
    webhook_outbox_db_path: str = os.getenv("WEBHOOK_OUTBOX_DB_PATH", "./data/webhook_outbox.db")
    webhook_outbox_max_attempts: int = int(os.getenv("WEBHOOK_OUTBOX_MAX_ATTEMPTS", "6"))
    webhook_outbox_base_delay_seconds: int = int(os.getenv("WEBHOOK_OUTBOX_BASE_DELAY_SECONDS", "1"))
    webhook_outbox_max_delay_seconds: int = int(os.getenv("WEBHOOK_OUTBOX_MAX_DELAY_SECONDS", "60"))
    webhook_outbox_worker_interval_seconds: float = float(os.getenv("WEBHOOK_OUTBOX_WORKER_INTERVAL_SECONDS", "1"))

    # Test-only fault injection
    webhook_fault_mode: str = os.getenv("WEBHOOK_FAULT_MODE", "")
    enable_test_endpoints: bool = os.getenv("ENABLE_TEST_ENDPOINTS", "false").lower() in ("1", "true", "yes")


settings = Settings()

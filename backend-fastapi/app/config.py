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


settings = Settings()

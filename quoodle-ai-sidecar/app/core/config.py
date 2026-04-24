from __future__ import annotations

import os
from pydantic import BaseModel


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


class Settings(BaseModel):
    service_token: str = os.getenv("AI_SIDECAR_SERVICE_TOKEN", "")
    request_timeout_seconds: float = float(os.getenv("AI_REQUEST_TIMEOUT_SECONDS", "15"))

    ai_global_enabled: bool = _bool_env("AI_GLOBAL_ENABLED", True)
    ai_device_copilot_enabled: bool = _bool_env("AI_DEVICE_COPILOT_ENABLED", True)
    ai_provider_qwen_enabled: bool = _bool_env("AI_PROVIDER_QWEN_ENABLED", True)

    qwen_base_url: str = os.getenv(
        "AI_QWEN_BASE_URL",
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
    )
    qwen_api_key: str = os.getenv("AI_QWEN_API_KEY", "")
    qwen_api_mode: str = os.getenv("AI_QWEN_API_MODE", "responses")
    qwen_model: str = os.getenv("AI_QWEN_MODEL", "qwen3.6-plus")
    qwen_timeout_seconds: float = float(os.getenv("AI_QWEN_TIMEOUT_SECONDS", "45"))
    qwen_max_output_tokens: int = int(os.getenv("AI_QWEN_MAX_OUTPUT_TOKENS", "1024"))

    prompt_templates_dir: str = os.getenv("AI_PROMPT_TEMPLATES_DIR", "prompts")
    prompt_profile: str = os.getenv("AI_PROMPT_PROFILE", "device_health")
    prompt_version: str = os.getenv("AI_PROMPT_VERSION", "v1")


settings = Settings()

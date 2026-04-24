from __future__ import annotations

from fastapi import APIRouter

from app.core.config import settings
from app.observability.metrics import metrics
from app.prompts import PromptTemplateManager

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, object]:
    dependency = "ok"
    if settings.ai_provider_qwen_enabled and settings.qwen_api_key.strip() == "":
        dependency = "warning"

    prompt_manager = PromptTemplateManager(
        templates_dir=settings.prompt_templates_dir,
        prompt_id=settings.prompt_profile,
        prompt_version=settings.prompt_version,
    )

    return {
        "status": "ok",
        "service": "quoodle-ai-sidecar",
        "dependencies": {
            "qwen_provider": dependency,
        },
        "prompt_templates": prompt_manager.status(),
        "metrics": metrics.snapshot(),
    }

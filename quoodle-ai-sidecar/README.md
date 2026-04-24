# quoodle-ai-sidecar

Internal read-mostly AI sidecar for Quoodle Phase 1 Device Health Copilot.

## Scope (Phase 1)

- Internal endpoint: `POST /internal/ai/chat/ask`
- Health endpoint: `GET /health`
- Read-only tool routing and guardrails
- Qwen Responses API driver (with mock fallback)
- No draft execution and no direct device/gateway control

## Local run

```powershell
cd quoodle-ai-sidecar
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Environment

- `AI_GLOBAL_ENABLED`
- `AI_DEVICE_COPILOT_ENABLED`
- `AI_PROVIDER_QWEN_ENABLED`
- `AI_SIDECAR_SERVICE_TOKEN`
- `AI_QWEN_BASE_URL`
- `AI_QWEN_API_KEY`
- `AI_QWEN_API_MODE` (`responses` or `chat_completions`)
- `AI_QWEN_MODEL`
- `AI_QWEN_TIMEOUT_SECONDS`
- `AI_QWEN_MAX_OUTPUT_TOKENS`
- `AI_PROMPT_TEMPLATES_DIR` (default: `prompts`)
- `AI_PROMPT_PROFILE` (default: `device_health`)
- `AI_PROMPT_VERSION` (default: `v1`)

## Prompt templates (phase-ready)

The sidecar supports file-backed prompt templates with safe fallback:

- `prompts/<profile>/<version>/system.md`
- `prompts/<profile>/<version>/user.md`

If either file is missing, the sidecar falls back to built-in prompts so Phase 1 remains stable.

from __future__ import annotations

from fastapi import FastAPI

from app.api.chat import router as chat_router
from app.api.health import router as health_router

app = FastAPI(title="Quoodle AI Copilot")
app.include_router(chat_router)
app.include_router(health_router)


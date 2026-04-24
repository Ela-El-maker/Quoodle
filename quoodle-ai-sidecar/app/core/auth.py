from __future__ import annotations

from fastapi import HTTPException, Request

from app.core.config import settings


def verify_service_auth(request: Request) -> None:
    expected = settings.service_token.strip()
    if expected == "":
        return

    auth = (request.headers.get("authorization") or "").strip()
    if not auth.lower().startswith("bearer "):
        raise HTTPException(
            status_code=401,
            detail={"code": "unauthorized", "message": "Missing bearer service token"},
        )

    token = auth[7:].strip()
    if token != expected:
        raise HTTPException(
            status_code=401,
            detail={"code": "unauthorized", "message": "Invalid service token"},
        )


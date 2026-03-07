"""Compatibility shim for `app.api`.

This repo contains both:
- a directory `app/api/` (schemas/routes)
- and a module file `app/api.py`

Python treats `app.api` as a module (this file), which would normally prevent
imports like `app.api.schemas`. To keep existing imports working, we expose the
submodules by defining `__path__` to point at the `app/api/` directory.

The actual REST router builders live in `app/api_controller.py`.
"""

from __future__ import annotations

import os

# Allow `import app.api.schemas` even though `app.api` is a module.
__path__ = [os.path.join(os.path.dirname(__file__), "api")]

def create_router(manager):
    from app.api_controller import create_router as _create_router

    return _create_router(manager)


def build_command_delivery(payload, session_id):
    from app.api_controller import build_command_delivery as _build_command_delivery

    return _build_command_delivery(payload, session_id)


def build_dispatch_response(status, device_id, command_id, reason=None):
    from app.api_controller import build_dispatch_response as _build_dispatch_response

    return _build_dispatch_response(status, device_id, command_id, reason)


__all__ = ["create_router", "build_command_delivery", "build_dispatch_response"]

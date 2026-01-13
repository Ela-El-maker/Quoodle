from __future__ import annotations

import json
from typing import Any


def _normalize(value: Any) -> Any:
    # Canonical JSON rules (pragmatic subset):
    # - Objects: sort keys lexicographically
    # - No insignificant whitespace
    # - UTF-8
    # - Disallow NaN/Infinity
    # - Keep list order
    # Note: "normalized floats" is handled by Python's JSON encoder
    # with allow_nan=False and compact separators; current message schema
    # is mostly strings/ints.
    if isinstance(value, dict):
        # Force string keys and stable ordering
        return {str(k): _normalize(v) for k, v in sorted(value.items(), key=lambda kv: str(kv[0]))}
    if isinstance(value, list):
        return [_normalize(v) for v in value]
    return value


def canonicalize_json(value: Any) -> bytes:
    normalized = _normalize(value)
    text = json.dumps(
        normalized,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )
    return text.encode("utf-8")


def strip_sig(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: strip_sig(v) for k, v in value.items() if k != "sig"}
    if isinstance(value, list):
        return [strip_sig(v) for v in value]
    return value

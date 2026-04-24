from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_endpoint() -> None:
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"


def test_scope_guardrail_blocks_unauthorized_device() -> None:
    payload = {
        "query": "Why is this device unhealthy?",
        "actor_context": {
            "tenant_id": "default",
            "actor_id": "usr_test",
            "role": "operator",
        },
        "scope_context": {
            "allowed_device_ids": ["dev_allowed"],
            "allowed_actions": ["read_device_state"],
        },
        "selected_refs": {"device_id": "dev_forbidden"},
        "correlation_id": "corr_test",
        "context": {
            "device_summary": {"device_id": "dev_forbidden"},
            "latest_telemetry": {},
            "command_failures": [],
            "audit_events": [],
            "system_health": {},
        },
    }
    res = client.post("/internal/ai/chat/ask", json=payload)
    assert res.status_code == 403
    assert res.json()["detail"]["code"] == "scope_unresolved"


def test_read_only_answer_returns_artifact() -> None:
    payload = {
        "query": "Why is this device unhealthy?",
        "actor_context": {
            "tenant_id": "default",
            "actor_id": "usr_test",
            "role": "operator",
        },
        "scope_context": {
            "allowed_device_ids": ["dev_abc"],
            "allowed_actions": ["read_device_state"],
        },
        "selected_refs": {"device_id": "dev_abc"},
        "correlation_id": "corr_test",
        "context": {
            "device_summary": {
                "device_id": "dev_abc",
                "lifecycle_state": "degraded",
                "risk_score": 44,
                "last_seen": "2026-04-23T10:00:00Z",
            },
            "latest_telemetry": {
                "timestamp": "2026-04-23T10:00:10Z",
                "metrics": {"cpu": 82.1, "ram": 73.2},
            },
            "command_failures": [
                {
                    "command_id": "cmd_1",
                    "method": "collect_system_info",
                    "state": "failed",
                    "error_code": "gateway_timeout",
                    "error_message": "delivery timeout",
                    "completed_at": "2026-04-23T09:59:00Z",
                }
            ],
            "audit_events": [
                {
                    "id": "aud_1",
                    "event_type": "command.failed",
                    "timestamp": "2026-04-23T09:59:00Z",
                    "actor": "operator",
                }
            ],
            "system_health": {"overall_status": "degraded", "component_counts": {"healthy": 2, "degraded": 1, "offline": 0}},
        },
    }
    res = client.post("/internal/ai/chat/ask", json=payload)
    assert res.status_code == 200
    body = res.json()
    assert body["artifact"]["artifact_type"] == "answer"
    assert body["artifact"]["draft_only"] is False
    assert "missing_information" in body["artifact"]
    assert "next_safe_questions" in body["artifact"]
    assert len(body["evidence_refs"]) >= 1


def test_incomplete_when_required_context_is_missing() -> None:
    payload = {
        "query": "What changed in the last hour?",
        "actor_context": {
            "tenant_id": "default",
            "actor_id": "usr_test",
            "role": "operator",
        },
        "scope_context": {
            "allowed_device_ids": ["dev_abc"],
            "allowed_actions": ["read_device_state"],
        },
        "selected_refs": {"device_id": "dev_abc"},
        "correlation_id": "corr_test_incomplete",
        "context": {
            "device_summary": {
                "device_id": "dev_abc",
                "lifecycle_state": "active",
                "risk_score": None,
                "last_seen": "2026-04-23T10:00:00Z",
            },
            "latest_telemetry": {
                "timestamp": None,
                "metrics": {"cpu": None, "ram": None, "disk_usage": None},
            },
            "command_failures": [],
            "audit_events": [],
            "system_health": {"overall_status": "ok"},
        },
    }
    res = client.post("/internal/ai/chat/ask", json=payload)
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "incomplete"
    assert body["artifact"]["state"] == "incomplete"
    assert len(body["artifact"]["missing_information"]) > 0

from app.config import settings
from app.state import webhook_outbox


async def forward_command_result(payload: dict) -> None:
    """
    Forward COMMAND_RESULT to Laravel webhook as per FastAPI_Laravel_Interface POST_/command/result.
    """
    target = f"{settings.laravel_webhook_base}/command/result"

    body = payload.get("body", {})
    trace_id = body.get("trace_id") or body.get("command_message_id")
    data = {
        "command_id": body.get("command_message_id"),
        "device_id": payload.get("device_id"),
        "trace_id": trace_id,
        "execution_state": body.get("execution_state"),
        "result": body.get("result", {}),
        "error_code": body.get("error_code"),
        "error_message": body.get("error_message"),
        "timestamp": payload.get("timestamp"),
    }
    await webhook_outbox.enqueue_and_send("command_result", target, data)

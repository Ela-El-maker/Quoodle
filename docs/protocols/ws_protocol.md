# WS Protocol Summary

Common envelope fields: ype, from, device_id, session_id, timestamp, message_id, body, sig per WindowsAgent + FastAPI (WSS control channel).json.
Message types implemented: AUTH, AUTH_ACK, AUTH_ERROR, HEARTBEAT, TELEMETRY, COMMAND_DELIVERY, COMMAND_ACK, COMMAND_RESULT, UPDATE_ANNOUNCE, UPDATE_STATUS, POLICY_UPDATE, ALERT, ERROR.
Validation logic lives in ackend-fastapi/app/ws/protocol.py; agent builders in quoodle-agent-windows/src/ws/ws_protocol.cpp keep fields and ordering canonical.

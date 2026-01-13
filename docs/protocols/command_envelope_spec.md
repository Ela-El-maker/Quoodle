# Command Envelope Spec

Outer WSS envelope uses CommonEnvelope. Inner command_envelope fields: message_id, trace_id, seq, header{version,timestamp,ttl_seconds,priority,requires_ack,long_running}, body{method,params,sensitive}, meta{device_id,origin_user_id,enc,enc_key_id,policy_version}, sig.
Delivery is signed by FastAPI; Agent verifies before ACK and execution.

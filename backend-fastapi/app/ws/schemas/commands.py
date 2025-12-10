from pydantic import BaseModel
from typing import Optional, Dict

class CommandHeader(BaseModel):
    version: str
    timestamp: str
    ttl_seconds: int
    priority: str
    requires_ack: bool
    long_running: bool

class CommandMeta(BaseModel):
    device_id: str
    origin_user_id: str
    enc: str
    enc_key_id: Optional[str]
    policy_version: str

class CommandEnvelope(BaseModel):
    header: CommandHeader
    body: Dict[str, object]
    meta: CommandMeta
    message_id: str
    trace_id: str
    seq: int
    sig: str

from pydantic import BaseModel
from typing import Optional

class CommonEnvelope(BaseModel):
    message_id: str
    timestamp: str
    type: str
    from_: str
    device_id: str
    session_id: Optional[str]
    body: dict
    sig: str

    class Config:
        fields = {"from_": "from"}

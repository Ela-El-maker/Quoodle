from pydantic import BaseModel
from typing import Optional

class AuthBody(BaseModel):
    jwt: str
    nonce: str

class AgentInfo(BaseModel):
    agent_version: str
    os_build: str
    hwid_hash: str
    attestation_hash: Optional[str]

class AuthMessage(BaseModel):
    body: dict

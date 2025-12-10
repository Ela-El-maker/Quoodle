from pydantic import BaseModel
from typing import Optional

class UpdateAnnounce(BaseModel):
    release_id: str
    version: str
    manifest_url: str
    signature_url: str
    sha256: str
    min_os_build: str
    policy: dict

class UpdateStatus(BaseModel):
    release_id: str
    version: str
    phase: str
    progress: dict
    error_code: Optional[int]
    error_message: Optional[str]
    rollback_snapshot_id: Optional[str]

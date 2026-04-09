from pydantic import BaseModel
from typing import Dict, Any

class TelemetryMetrics(BaseModel):
    cpu: str
    ram: str
    disk_usage: str
    network_tx: str
    network_rx: str

class TelemetryBody(BaseModel):
    timestamp: str
    metrics: Dict[str, Any]
    telemetry_scope: str

class TelemetryPipeline:
    async def ingest(self, device_id: str, metrics: dict) -> dict:
        return {"device_id": device_id, "ingested": True, "metrics": metrics}

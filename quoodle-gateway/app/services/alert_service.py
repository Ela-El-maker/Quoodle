class AlertService:
    async def send_alert(self, device_id: str, alert: dict) -> dict:
        return {"device_id": device_id, "alert": alert, "status": "sent"}

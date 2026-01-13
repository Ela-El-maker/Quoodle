class PresenceTracker:
    def __init__(self) -> None:
        self._online: set[str] = set()

    async def online(self, device_id: str) -> None:
        self._online.add(device_id)

    async def offline(self, device_id: str) -> None:
        self._online.discard(device_id)

    async def is_online(self, device_id: str) -> bool:
        return device_id in self._online

from collections import defaultdict, deque
from typing import Any, Deque, Dict, List


class OfflineQueue:
    def __init__(self, max_per_device: int = 200) -> None:
        self._queues: Dict[str, Deque[Dict[str, Any]]] = defaultdict(deque)
        self._max = max_per_device

    def enqueue(self, device_id: str, message: Dict[str, Any]) -> None:
        queue = self._queues[device_id]
        if len(queue) >= self._max:
            queue.popleft()
        queue.append(message)

    def drain(self, device_id: str) -> List[Dict[str, Any]]:
        queue = self._queues.get(device_id)
        if not queue:
            return []
        items = list(queue)
        queue.clear()
        return items

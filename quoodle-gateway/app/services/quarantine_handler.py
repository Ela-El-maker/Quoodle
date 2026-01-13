from typing import Dict, List


class QuarantineHandler:
    def __init__(self) -> None:
        self._quarantined: Dict[str, str] = {}
        self._allowlist: List[str] = ["time_sync", "fetch_revocations", "reauth", "collect_diagnostics"]

    def set_quarantine(self, device_id: str, reason: str) -> None:
        self._quarantined[device_id] = reason

    def lift_quarantine(self, device_id: str) -> None:
        self._quarantined.pop(device_id, None)

    def status(self, device_id: str) -> dict:
        if device_id in self._quarantined:
            return {"state": "quarantined", "reason": self._quarantined[device_id]}
        return {"state": "active", "reason": None}

    def is_blocked(self, device_id: str, method: str) -> bool:
        if device_id not in self._quarantined:
            return False
        return method not in self._allowlist

    def allowlist(self) -> List[str]:
        return list(self._allowlist)

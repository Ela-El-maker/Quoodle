from typing import Dict, List


class QuarantineHandler:
    def __init__(self) -> None:
        self._quarantined: Dict[str, str] = {}
        self._allowlist: List[str] = [
            "time_sync",
            "fetch_revocations",
            "reauth",
            "collect_diagnostics",
            "ping",
            "health_check",
            "collect_system_info",
            "lock_screen",
            "enable_input",
            "show_message",
            "reconnect_network",
            "allow_outbound",
            "force_repair",
            "re_attest",
            "attest_device",
            "fail_attestation",
            "enter_quarantine",
            "exit_quarantine",
            "policy_probe",
            "get_command_log",
            "get_audit_trail",
            "export_artifacts",
            "verify_signature",
            "replay_request",
            "panic_disable_agent",
            "revoke_all_keys",
            "restore_defaults",
            "unlock_all",
        ]

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

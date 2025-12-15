from typing import Dict, Any


class RiskScorer:
    """
    Lightweight risk scoring based on telemetry metrics.
    """

    def score(self, metrics: Dict[str, Any]) -> float:
        cpu = self._to_float(metrics.get("cpu"))
        ram = self._to_float(metrics.get("ram"))
        disk = self._to_float(metrics.get("disk_usage"))

        score = 0.0
        for val in (cpu, ram, disk):
            if val is None:
                continue
            if val > 90:
                score += 30
            elif val > 75:
                score += 20
            elif val > 50:
                score += 10

        return min(score, 100.0)

    def _to_float(self, value: Any) -> float | None:
        if value is None:
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            try:
                stripped = value.replace("%", "")
                return float(stripped)
            except ValueError:
                return None
        return None

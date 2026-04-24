from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app.core.hashing import sha256_json, stable_json_dumps


DEFAULT_SYSTEM_PROMPT = (
    "You are Quoodle Copilot. You explain device health using only provided evidence. "
    "Never claim execution authority, never imply commands were run by AI, and keep responses concise."
)

DEFAULT_USER_PROMPT_TEMPLATE = (
    "User query:\n"
    "{{QUERY}}\n\n"
    "Evidence bundle (JSON SHA256):\n"
    "{{EVIDENCE_BUNDLE_HASH}}\n\n"
    "Tool outputs (JSON):\n"
    "{{TOOL_OUTPUTS_JSON}}\n\n"
    "Return a short explanation with likely causes, confidence cues, and missing data."
)


@dataclass
class PromptBundle:
    prompt_id: str
    prompt_version: str
    prompt_source: str
    system_prompt: str
    user_prompt: str
    prompt_hash: str


class PromptTemplateManager:
    def __init__(self, templates_dir: str, prompt_id: str, prompt_version: str) -> None:
        self.prompt_id = prompt_id.strip() or "device_health"
        self.prompt_version = prompt_version.strip() or "v1"
        self.templates_root = Path(templates_dir)
        if not self.templates_root.is_absolute():
            self.templates_root = (Path(__file__).resolve().parents[2] / self.templates_root).resolve()

    def status(self) -> dict[str, Any]:
        system_path = self._path("system.md")
        user_path = self._path("user.md")
        return {
            "prompt_id": self.prompt_id,
            "prompt_version": self.prompt_version,
            "templates_root": str(self.templates_root),
            "system_template_exists": system_path.exists(),
            "user_template_exists": user_path.exists(),
        }

    def build(self, query: str, context: dict[str, Any], tool_outputs: dict[str, dict[str, Any]]) -> PromptBundle:
        system_text = self._read_template("system.md") or DEFAULT_SYSTEM_PROMPT
        user_template = self._read_template("user.md") or DEFAULT_USER_PROMPT_TEMPLATE
        source = "file" if self._has_required_files() else "fallback"

        evidence_bundle_hash = sha256_json({"context": context, "tools": tool_outputs})
        rendered_user = (
            user_template.replace("{{QUERY}}", query.strip())
            .replace("{{EVIDENCE_BUNDLE_HASH}}", evidence_bundle_hash)
            .replace("{{TOOL_OUTPUTS_JSON}}", stable_json_dumps(tool_outputs))
        )
        prompt_hash = sha256_json(
            {
                "prompt_id": self.prompt_id,
                "prompt_version": self.prompt_version,
                "system_prompt": system_text,
                "user_prompt": rendered_user,
            }
        )
        return PromptBundle(
            prompt_id=self.prompt_id,
            prompt_version=self.prompt_version,
            prompt_source=source,
            system_prompt=system_text,
            user_prompt=rendered_user,
            prompt_hash=prompt_hash,
        )

    def _has_required_files(self) -> bool:
        return self._path("system.md").exists() and self._path("user.md").exists()

    def _path(self, filename: str) -> Path:
        return self.templates_root / self.prompt_id / self.prompt_version / filename

    def _read_template(self, filename: str) -> str | None:
        path = self._path(filename)
        if not path.exists():
            return None
        try:
            return path.read_text(encoding="utf-8").strip()
        except Exception:
            return None

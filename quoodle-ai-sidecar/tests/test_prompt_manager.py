from pathlib import Path

from app.prompts import PromptTemplateManager


def test_prompt_manager_uses_fallback_when_templates_missing(tmp_path: Path) -> None:
    manager = PromptTemplateManager(
        templates_dir=str(tmp_path),
        prompt_id="device_health",
        prompt_version="v1",
    )

    bundle = manager.build(
        query="Why is this device unhealthy?",
        context={"device_summary": {"device_id": "dev_1"}},
        tool_outputs={"get_device_summary": {"device_id": "dev_1"}},
    )

    assert bundle.prompt_source == "fallback"
    assert bundle.prompt_id == "device_health"
    assert bundle.prompt_version == "v1"
    assert bundle.prompt_hash.startswith("sha256:")
    assert "Why is this device unhealthy?" in bundle.user_prompt


def test_prompt_manager_reads_files_when_present(tmp_path: Path) -> None:
    prompt_dir = tmp_path / "device_health" / "v1"
    prompt_dir.mkdir(parents=True, exist_ok=True)
    (prompt_dir / "system.md").write_text("SYSTEM TEMPLATE", encoding="utf-8")
    (prompt_dir / "user.md").write_text("Q={{QUERY}}", encoding="utf-8")

    manager = PromptTemplateManager(
        templates_dir=str(tmp_path),
        prompt_id="device_health",
        prompt_version="v1",
    )
    bundle = manager.build(
        query="hello",
        context={},
        tool_outputs={},
    )

    assert bundle.prompt_source == "file"
    assert bundle.system_prompt == "SYSTEM TEMPLATE"
    assert bundle.user_prompt == "Q=hello"

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "quoodle-control-plane/app/Services/CommandRegistry/Registry.php"
AGENT_MAP_PATH = ROOT / "quoodle-agent-linux/agent/src/privileged_client.cpp"
EXECUTOR_PATH = ROOT / "quoodle-agent-linux/privileged/src/executor.c"


def parse_registry_commands(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return re.findall(r"'([a-z_]+)'\s*=>\s*new CommandDefinition", text)


def parse_agent_map(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return {
        method: capability
        for method, capability in re.findall(r'\{"([a-z_]+)",\s*"([A-Z_]+)"\}', text)
    }


def parse_executor_caps(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    implemented = set(
        re.findall(r'strcmp\(cap->valuestring,\s*"([A-Z_]+)"\)\s*==\s*0', text)
    )
    implemented.discard("CAP_DISCOVERY")
    return implemented


def parse_discovery_caps(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    supported = set(
        re.findall(r'cJSON_CreateString\("([A-Z_]+)"\)', text)
    )
    supported.discard("CAP_DISCOVERY")
    return supported


def build_report() -> dict[str, object]:
    registry_commands = parse_registry_commands(REGISTRY_PATH)
    agent_map = parse_agent_map(AGENT_MAP_PATH)
    executor_caps = parse_executor_caps(EXECUTOR_PATH)
    discovery_caps = parse_discovery_caps(EXECUTOR_PATH)

    missing_agent_mappings = sorted(
        command for command in registry_commands if command not in agent_map
    )

    commands_by_capability: dict[str, list[str]] = defaultdict(list)
    for command in registry_commands:
        capability = agent_map.get(command)
        if capability:
            commands_by_capability[capability].append(command)

    missing_executor_caps = sorted(
        capability for capability in commands_by_capability if capability not in executor_caps
    )

    commands_missing_executor = {
        capability: sorted(commands_by_capability[capability])
        for capability in missing_executor_caps
    }

    discovery_missing_caps = sorted(executor_caps - discovery_caps)
    discovery_extra_caps = sorted(discovery_caps - executor_caps)

    fully_supported_commands = sorted(
        command
        for command, capability in agent_map.items()
        if command in registry_commands and capability in executor_caps
    )

    partially_supported_commands = sorted(
        command
        for command, capability in agent_map.items()
        if command in registry_commands and capability not in executor_caps
    )

    return {
        "counts": {
            "registry_commands": len(registry_commands),
            "agent_mappings": len(agent_map),
            "executor_capabilities": len(executor_caps),
            "discovery_capabilities": len(discovery_caps),
            "fully_supported_commands": len(fully_supported_commands),
            "partially_supported_commands": len(partially_supported_commands),
            "missing_agent_mappings": len(missing_agent_mappings),
            "missing_executor_capabilities": len(missing_executor_caps),
        },
        "fully_supported_commands": fully_supported_commands,
        "missing_agent_mappings": missing_agent_mappings,
        "missing_executor_capabilities": missing_executor_caps,
        "commands_missing_executor": commands_missing_executor,
        "discovery_missing_capabilities": discovery_missing_caps,
        "discovery_extra_capabilities": discovery_extra_caps,
    }


def print_report(report: dict[str, object]) -> None:
    counts = report["counts"]
    print("Command parity report")
    print(f"Registry commands: {counts['registry_commands']}")
    print(f"Agent mappings: {counts['agent_mappings']}")
    print(f"Executor capabilities: {counts['executor_capabilities']}")
    print(f"Discovery capabilities: {counts['discovery_capabilities']}")
    print(f"Fully supported commands: {counts['fully_supported_commands']}")
    print(f"Partially supported commands: {counts['partially_supported_commands']}")
    print()

    fully_supported = report["fully_supported_commands"]
    print("Fully supported commands:")
    print("  " + ", ".join(fully_supported) if fully_supported else "  none")
    print()

    missing_agent = report["missing_agent_mappings"]
    print("Registry commands missing an agent mapping:")
    print("  " + ", ".join(missing_agent) if missing_agent else "  none")
    print()

    missing_executor = report["commands_missing_executor"]
    print("Commands mapped by the agent but not implemented by the executor:")
    if missing_executor:
        for capability, commands in missing_executor.items():
            print(f"  {capability}: {', '.join(commands)}")
    else:
        print("  none")
    print()

    discovery_missing = report["discovery_missing_capabilities"]
    print("Executor capabilities missing from discovery:")
    print("  " + ", ".join(discovery_missing) if discovery_missing else "  none")
    print()

    discovery_extra = report["discovery_extra_capabilities"]
    print("Discovery capabilities missing executor handlers:")
    print("  " + ", ".join(discovery_extra) if discovery_extra else "  none")


def has_issues(report: dict[str, object]) -> bool:
    return any(
        report[key]
        for key in (
            "missing_agent_mappings",
            "missing_executor_capabilities",
            "discovery_missing_capabilities",
            "discovery_extra_capabilities",
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate parity between control-plane commands, Linux agent capability "
            "mappings, and the privileged executor implementation."
        )
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero when parity gaps are found.",
    )
    args = parser.parse_args()

    report = build_report()
    print_report(report)

    if args.strict and has_issues(report):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

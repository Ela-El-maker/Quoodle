#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_jsonl(fp, record: dict) -> None:
    fp.write(json.dumps(record, ensure_ascii=False) + "\n")
    fp.flush()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run E2E harness and collect full-system trace logs.")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--laravel-base-url", default=os.getenv("LARAVEL_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--fastapi-base-url", default=os.getenv("FASTAPI_BASE_URL", "http://localhost:8000"))
    parser.add_argument("--user-email", default=os.getenv("TEST_USER_EMAIL", "test@example.com"))
    parser.add_argument("--user-password", default=os.getenv("TEST_USER_PASSWORD", "password"))
    return parser.parse_args()


def run_harness(env: dict, trace_fp, e2e_log_path: Path) -> dict:
    command_ids = set()
    device_ids = set()
    run_summary = None
    raw_lines = []

    with e2e_log_path.open("w", encoding="utf-8") as e2e_fp:
        proc = subprocess.Popen(
            [sys.executable, str(ROOT / "e2e_quoodle_harness.py")],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.rstrip("\n")
            if not line:
                continue
            e2e_fp.write(line + "\n")
            raw_lines.append(line)
            try:
                record = json.loads(line)
            except Exception:
                write_jsonl(
                    trace_fp,
                    {
                        "timestamp": iso_now(),
                        "source": "e2e_harness",
                        "event_type": "stdout",
                        "message": line,
                    },
                )
                continue
            record["source"] = "e2e_harness"
            write_jsonl(trace_fp, record)
            cmd = record.get("command_id(optional)") or record.get("command_id")
            dev = record.get("device_id(optional)") or record.get("device_id")
            if cmd:
                command_ids.add(cmd)
            if dev:
                device_ids.add(dev)
        proc.wait()
        if proc.returncode != 0:
            raise RuntimeError(f"E2E harness failed with exit code {proc.returncode}")

    # The harness prints a JSON summary object at the end (pretty JSON, multi-line).
    try:
        full_text = e2e_log_path.read_text(encoding="utf-8")
        idx = full_text.rfind("\n{")
        if idx == -1:
            idx = full_text.rfind("{")
        while idx != -1:
            try:
                parsed = json.loads(full_text[idx:])
            except Exception:
                idx = full_text.rfind("\n{", 0, idx)
                continue
            if isinstance(parsed, dict) and "runs" in parsed:
                run_summary = parsed
                break
            idx = full_text.rfind("\n{", 0, idx)
    except Exception:
        run_summary = None

    return {
        "command_ids": sorted(command_ids),
        "device_ids": sorted(device_ids),
        "summary": run_summary or {},
    }


def capture_docker_logs(trace_fp, since_iso: str, container: str) -> None:
    cmd = ["docker", "logs", "--since", since_iso, "--timestamps", container]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        write_jsonl(
            trace_fp,
            {
                "timestamp": iso_now(),
                "source": f"docker:{container}",
                "event_type": "log.error",
                "message": result.stderr.strip(),
            },
        )
        return

    for line in result.stdout.splitlines():
        ts = None
        msg = line
        if " " in line:
            possible_ts, rest = line.split(" ", 1)
            if possible_ts.endswith("Z"):
                ts = possible_ts
                msg = rest
        write_jsonl(
            trace_fp,
            {
                "timestamp": ts or iso_now(),
                "source": f"docker:{container}",
                "event_type": "log",
                "message": msg,
            },
        )


def fetch_outbox_events(command_ids: list[str]) -> list[dict]:
    if not command_ids:
        return []
    script = """
import json
import sqlite3
import sys

ids = set(json.loads(sys.argv[1]))
conn = sqlite3.connect('/app/data/webhook_outbox.db')
rows = conn.execute(
    'SELECT event_type,status,payload_json,attempts,last_error,created_at,updated_at FROM webhook_outbox ORDER BY created_at ASC'
).fetchall()
events = []
for event_type, status, payload_json, attempts, last_error, created_at, updated_at in rows:
    try:
        payload = json.loads(payload_json)
    except Exception:
        continue
    if payload.get('command_id') not in ids:
        continue
    events.append({
        'event_type': event_type,
        'status': status,
        'attempts': attempts,
        'last_error': last_error,
        'created_at': created_at,
        'updated_at': updated_at,
        'payload': payload,
    })
print(json.dumps(events))
"""
    result = subprocess.run(
        ["docker", "exec", "-i", "quoodle-gateway", "python", "-", json.dumps(command_ids)],
        input=script,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return []
    try:
        return json.loads(result.stdout.strip() or "[]")
    except Exception:
        return []


def fetch_command_states(command_ids: list[str]) -> list[dict]:
    if not command_ids:
        return []
    ids = ",".join(f"'{cid}'" for cid in command_ids)
    query = (
        "SELECT id,state,status,execution_state,reason,updated_at,completed_at "
        f"FROM commands WHERE id IN ({ids})"
    )
    result = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            "quoodle-db",
            "mysql",
            "-u",
            "quoodle",
            "-p" + os.getenv("MYSQL_PASSWORD", "quoodle_pass"),
            "-D",
            "secure_device",
            "-N",
            "-B",
            "-e",
            query,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    rows = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 7:
            continue
        rows.append(
            {
                "command_id": parts[0],
                "state": parts[1],
                "status": parts[2],
                "execution_state": parts[3],
                "reason": parts[4],
                "updated_at": parts[5],
                "completed_at": parts[6],
            }
        )
    return rows


def main() -> int:
    args = parse_args()
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_dir = ROOT / "logs" / "full_trace"
    log_dir.mkdir(parents=True, exist_ok=True)
    trace_log_path = log_dir / f"full_trace_{ts}.jsonl"
    summary_path = log_dir / f"full_trace_{ts}_summary.json"
    e2e_log_path = ROOT / "logs" / "e2e" / f"e2e_{ts}.jsonl"
    e2e_log_path.parent.mkdir(parents=True, exist_ok=True)

    start_iso = iso_now()
    env = os.environ.copy()
    env.update(
        {
            "LARAVEL_BASE_URL": args.laravel_base_url,
            "FASTAPI_BASE_URL": args.fastapi_base_url,
            "TEST_USER_EMAIL": args.user_email,
            "TEST_USER_PASSWORD": args.user_password,
            "RUNS": str(args.runs),
            "SEED": str(args.seed),
            "RUN_NONCE": ts,
        }
    )

    with trace_log_path.open("w", encoding="utf-8") as trace_fp:
        write_jsonl(
            trace_fp,
            {
                "timestamp": start_iso,
                "source": "runner",
                "event_type": "run.start",
                "message": "Starting full trace run",
                "runs": args.runs,
                "seed": args.seed,
                "laravel_base_url": args.laravel_base_url,
                "fastapi_base_url": args.fastapi_base_url,
            },
        )

        harness_result = run_harness(env, trace_fp, e2e_log_path)

        write_jsonl(
            trace_fp,
            {
                "timestamp": iso_now(),
                "source": "runner",
                "event_type": "run.harness.complete",
                "message": "E2E harness complete",
                "summary": harness_result.get("summary", {}),
            },
        )

        for container in ("quoodle-control-plane", "quoodle-gateway"):
            capture_docker_logs(trace_fp, start_iso, container)

        command_ids = harness_result.get("command_ids", [])
        outbox_events = fetch_outbox_events(command_ids)
        for event in outbox_events:
            write_jsonl(
                trace_fp,
                {
                    "timestamp": event.get("created_at") or iso_now(),
                    "source": "gateway.outbox",
                    "event_type": event.get("event_type"),
                    "status": event.get("status"),
                    "attempts": event.get("attempts"),
                    "last_error": event.get("last_error"),
                    "payload": event.get("payload"),
                },
            )

        states = fetch_command_states(command_ids)
        for row in states:
            write_jsonl(
                trace_fp,
                {
                    "timestamp": iso_now(),
                    "source": "control_plane.db",
                    "event_type": "command.state",
                    **row,
                },
            )

    summary = {
        "runs": args.runs,
        "command_ids": harness_result.get("command_ids", []),
        "devices": harness_result.get("device_ids", []),
        "harness_summary": harness_result.get("summary", {}),
        "trace_log": str(trace_log_path),
        "e2e_log": str(e2e_log_path),
    }
    with summary_path.open("w", encoding="utf-8") as fp:
        json.dump(summary, fp, ensure_ascii=False, indent=2)

    print(f"Full trace log: {trace_log_path}")
    print(f"Summary: {summary_path}")
    print(f"E2E log: {e2e_log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

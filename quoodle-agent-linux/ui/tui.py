#!/usr/bin/env python3
import curses
import os
import time
from typing import List

from common import (
    DEFAULT_SECRETS,
    attestation_hash,
    export_diagnostics,
    journal_tail,
    load_capabilities,
    capabilities_with_meta,
    send_notification,
    load_processed_commands,
    merged_env,
    state_snapshot,
)


TABS = ["Overview", "Trust", "Capabilities", "Logs", "Pairing", "Diagnostics"]


def draw_header(stdscr, title: str) -> None:
    stdscr.attron(curses.A_REVERSE)
    stdscr.addstr(0, 0, f" {title} ".ljust(curses.COLS - 1))
    stdscr.attroff(curses.A_REVERSE)


def draw_tabs(stdscr, active: int) -> None:
    y = 1
    x = 1
    for idx, tab in enumerate(TABS):
        label = f" {idx+1}:{tab} "
        if idx == active:
            stdscr.attron(curses.A_STANDOUT)
            stdscr.addstr(y, x, label)
            stdscr.attroff(curses.A_STANDOUT)
        else:
            stdscr.addstr(y, x, label)
        x += len(label) + 1


def draw_kv(stdscr, y: int, x: int, key: str, value: str) -> None:
    stdscr.addstr(y, x, f"{key:18} {value}")


def draw_overview(stdscr, snap: dict) -> None:
    y = 3
    draw_kv(stdscr, y, 2, "Device ID", snap["device_id"]); y += 1
    draw_kv(stdscr, y, 2, "WSS URL", snap["ws_url"]); y += 1
    draw_kv(stdscr, y, 2, "Agent JWT", (snap["agent_jwt"][:10] + "...") if snap["agent_jwt"] else "-"); y += 1
    draw_kv(stdscr, y, 2, "Agent Service", snap["agent_status"]); y += 1
    draw_kv(stdscr, y, 2, "Priv Service", snap["priv_status"]); y += 1
    draw_kv(stdscr, y, 2, "Policy Hash", snap["policy_hash"]); y += 1
    draw_kv(stdscr, y, 2, "Sequence", snap["sequence"]); y += 1
    draw_kv(stdscr, y, 2, "Last Delivery", snap["last_delivery"]); y += 1
    draw_kv(stdscr, y, 2, "Processed Cmds", snap["processed_count"]); y += 1
    draw_kv(stdscr, y, 2, "Outbox Items", snap["outbox_count"]); y += 1
    draw_kv(stdscr, y, 2, "Last State", snap["last_state_update"]); y += 1
    draw_kv(stdscr, y, 2, "Quarantine", snap["quarantine"]); y += 1


def draw_trust(stdscr, snap: dict) -> None:
    y = 3
    draw_kv(stdscr, y, 2, "Controller Key", snap["controller_pubkey"]); y += 1
    draw_kv(stdscr, y, 2, "Agent PrivKey", snap["agent_privkey"]); y += 1
    draw_kv(stdscr, y, 2, "Agent PubKey", snap["agent_pubkey"]); y += 1
    draw_kv(stdscr, y, 2, "Daemon PubKey", snap["daemon_pubkey"]); y += 1
    draw_kv(stdscr, y, 2, "Priv Socket", snap["priv_socket"]); y += 2
    mid, att = attestation_hash()
    draw_kv(stdscr, y, 2, "Machine ID", mid or "-"); y += 1
    draw_kv(stdscr, y, 2, "Attest Hash", att or "-"); y += 1


def draw_capabilities(stdscr, caps: List[str]) -> None:
    y = 3
    stdscr.addstr(y, 2, "Capability".ljust(28) + "Risk".ljust(10) + "Description")
    y += 1
    for cap, risk, desc in capabilities_with_meta(caps):
        if y >= curses.LINES - 2:
            break
        stdscr.addstr(y, 2, cap.ljust(28) + risk.ljust(10) + desc[: (curses.COLS - 42)])
        y += 1


def draw_logs(stdscr) -> None:
    log = journal_tail(["quoodle-agent", "quoodle-privileged"], 120)
    lines = log.splitlines()[-(curses.LINES - 4):]
    y = 3
    for line in lines:
        stdscr.addstr(y, 2, line[: curses.COLS - 4])
        y += 1


def draw_pairing(stdscr) -> None:
    y = 3
    stdscr.addstr(y, 2, "Pairing (headless):"); y += 2
    stdscr.addstr(y, 2, "Set QUOODLE_API_BASE and QUOODLE_USER_JWT then run:"); y += 1
    stdscr.addstr(y, 2, "  ./ui/quoodle-agent-ui --pair"); y += 2
    stdscr.addstr(y, 2, "Tip: QUOODLE_AGENT_PUBKEY_B64 must be set in secrets.env"); y += 1


def draw_diagnostics(stdscr) -> None:
    y = 3
    stdscr.addstr(y, 2, "Export diagnostics bundle:"); y += 2
    stdscr.addstr(y, 2, "Press 'e' to export to /tmp/quoodle-agent-diag-*"); y += 1


def run_pairing(stdscr) -> None:
    env = merged_env(DEFAULT_SECRETS)
    api_base = env.get("QUOODLE_API_BASE") or env.get("QUOODLE_CONTROL_PLANE")
    user_jwt = env.get("QUOODLE_USER_JWT")
    if not api_base or not user_jwt:
        stdscr.addstr(curses.LINES - 2, 2, "Missing QUOODLE_API_BASE or QUOODLE_USER_JWT.")
        return
    import subprocess
    cli_path = os.path.join(os.path.dirname(__file__), "..", "cli", "quoodle-agent")
    subprocess.run(
        [cli_path, "pair", "--api-base", api_base, "--user-jwt", user_jwt,
         "--update-secrets"],
        check=False
    )


def main(stdscr) -> None:
    curses.curs_set(0)
    active = 0
    caps = load_capabilities()
    msg = ""
    last_quarantine = None
    seen_commands = set()

    while True:
        stdscr.erase()
        draw_header(stdscr, "Quoodle Agent UI (Linux - TUI)")
        draw_tabs(stdscr, active)

        snap = state_snapshot(DEFAULT_SECRETS)
        processed = load_processed_commands(DEFAULT_SECRETS)
        for entry in processed:
            cmd_id = entry.get("command_id")
            if not cmd_id or cmd_id in seen_commands:
                continue
            seen_commands.add(cmd_id)
            result = entry.get("result", {})
            status = result.get("status", "unknown")
            exec_state = result.get("execution_state", "")
            notify = f"{cmd_id} • {status}"
            if exec_state:
                notify += f" ({exec_state})"
            urgency = "critical" if status in ("failed", "error") else "normal"
            send_notification("Command Result", notify, urgency)
        if last_quarantine is None:
            last_quarantine = snap.get("quarantine")
        elif snap.get("quarantine") != last_quarantine:
            state = snap.get("quarantine")
            if state == "yes":
                send_notification("Quoodle Agent", "Device entered quarantine", "critical")
                msg = "Quarantine ON"
            else:
                send_notification("Quoodle Agent", "Device released from quarantine", "normal")
                msg = "Quarantine OFF"
            last_quarantine = state
        if active == 0:
            draw_overview(stdscr, snap)
        elif active == 1:
            draw_trust(stdscr, snap)
        elif active == 2:
            draw_capabilities(stdscr, caps)
        elif active == 3:
            draw_logs(stdscr)
        elif active == 4:
            draw_pairing(stdscr)
        elif active == 5:
            draw_diagnostics(stdscr)

        stdscr.addstr(curses.LINES - 2, 2, "q=quit  r=refresh  e=export  p=pair")
        if msg:
            stdscr.addstr(curses.LINES - 1, 2, msg[: curses.COLS - 4])
        stdscr.refresh()

        stdscr.timeout(1000)
        ch = stdscr.getch()
        if ch == -1:
            continue
        if ch in (ord("q"), 27):
            break
        if ch in (ord("1"), ord("2"), ord("3"), ord("4"), ord("5"), ord("6")):
            active = int(chr(ch)) - 1
        if ch == ord("r"):
            msg = "Refreshed."
        if ch == ord("e"):
            path = export_diagnostics("/tmp", DEFAULT_SECRETS)
            msg = f"Diagnostics exported: {path}"
        if ch == ord("p"):
            run_pairing(stdscr)
            msg = "Pairing attempted (check CLI output)."


if __name__ == "__main__":
    curses.wrapper(main)

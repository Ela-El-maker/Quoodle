#!/usr/bin/env python3
import sys
import threading
import time

try:
    import pystray  # type: ignore
    from PIL import Image, ImageDraw  # type: ignore
except Exception:
    pystray = None

from desktop_app import AgentDesktopApp
from common import (
    state_snapshot,
    load_processed_commands,
    send_notification,
    DEFAULT_SECRETS,
)


def build_icon(color: str) -> "Image.Image":
    image = Image.new("RGB", (64, 64), color)
    dc = ImageDraw.Draw(image)
    dc.ellipse((12, 12, 52, 52), fill=color, outline="white")
    return image


def tray_main() -> int:
    if pystray is None:
        print("pystray not available. Install with: pip install pystray pillow", file=sys.stderr)
        return 1

    app = AgentDesktopApp()
    app.withdraw()

    icon = pystray.Icon("quoodle")

    seen_commands = set()
    last_quarantine = None

    def refresh_icon():
        nonlocal last_quarantine
        while True:
            snap = state_snapshot(DEFAULT_SECRETS)
            status = snap.get("agent_status", "unknown")
            color = "#16a34a" if status == "active" else "#f59e0b"
            icon.icon = build_icon(color)
            icon.title = f"Quoodle Agent ({status})"

            processed = load_processed_commands(DEFAULT_SECRETS)
            for entry in processed:
                cmd_id = entry.get("command_id")
                if not cmd_id or cmd_id in seen_commands:
                    continue
                seen_commands.add(cmd_id)
                result = entry.get("result", {})
                status = result.get("status", "unknown")
                exec_state = result.get("execution_state", "")
                msg = f"{cmd_id} • {status}"
                if exec_state:
                    msg += f" ({exec_state})"
                urgency = "critical" if status in ("failed", "error") else "normal"
                send_notification("Command Result", msg, urgency)

            current_quarantine = snap.get("quarantine")
            if last_quarantine is None:
                last_quarantine = current_quarantine
            elif current_quarantine != last_quarantine:
                if current_quarantine == "yes":
                    send_notification("Quoodle Agent", "Device entered quarantine", "critical")
                else:
                    send_notification("Quoodle Agent", "Device released from quarantine", "normal")
                last_quarantine = current_quarantine
            time.sleep(5)

    def open_window():
        app.deiconify()
        app.lift()

    def quit_app():
        icon.stop()
        app.destroy()

    icon.menu = pystray.Menu(
        pystray.MenuItem("Open", lambda: open_window()),
        pystray.MenuItem("Quit", lambda: quit_app()),
    )

    threading.Thread(target=refresh_icon, daemon=True).start()
    icon.run()
    return 0


if __name__ == "__main__":
    sys.exit(tray_main())

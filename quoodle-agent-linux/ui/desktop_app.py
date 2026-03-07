#!/usr/bin/env python3
import os
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

from common import (
    DEFAULT_SECRETS,
    attestation_hash,
    capabilities_with_meta,
    export_diagnostics,
    journal_tail,
    load_capabilities,
    load_processed_commands,
    merged_env,
    send_notification,
    state_snapshot,
)


class AgentDesktopApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Quoodle Agent (Linux)")
        self.geometry("920x640")
        self.resizable(True, True)

        self.env = merged_env(DEFAULT_SECRETS)
        self.capabilities = load_capabilities()

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        self.status_tab = ttk.Frame(self.notebook)
        self.trust_tab = ttk.Frame(self.notebook)
        self.cap_tab = ttk.Frame(self.notebook)
        self.logs_tab = ttk.Frame(self.notebook)
        self.pair_tab = ttk.Frame(self.notebook)
        self.diag_tab = ttk.Frame(self.notebook)

        self.notebook.add(self.status_tab, text="Status")
        self.notebook.add(self.trust_tab, text="Trust")
        self.notebook.add(self.cap_tab, text="Capabilities")
        self.notebook.add(self.logs_tab, text="Logs")
        self.notebook.add(self.pair_tab, text="Pairing")
        self.notebook.add(self.diag_tab, text="Diagnostics")

        self._build_status()
        self._build_trust()
        self._build_caps()
        self._build_logs()
        self._build_pairing()
        self._build_diag()

        self.after(1000, self.refresh)
        self._seen_commands = set()
        self._last_quarantine = None

    def _build_status(self) -> None:
        self.status_labels = {}
        fields = [
            "Device ID",
            "WSS URL",
            "Agent Service",
            "Priv Service",
            "Policy Hash",
            "Sequence",
            "Last Delivery",
            "Processed Cmds",
            "Outbox Items",
            "Last State",
        ]
        for idx, name in enumerate(fields):
            ttk.Label(self.status_tab, text=name).grid(row=idx, column=0, sticky="w", padx=12, pady=4)
            lbl = ttk.Label(self.status_tab, text="-")
            lbl.grid(row=idx, column=1, sticky="w", padx=12, pady=4)
            self.status_labels[name] = lbl

        self.jwt_label = ttk.Label(self.status_tab, text="JWT: -")
        self.jwt_label.grid(row=len(fields), column=0, columnspan=2, sticky="w", padx=12, pady=8)

    def _build_trust(self) -> None:
        self.trust_labels = {}
        fields = [
            "Controller Key",
            "Agent PrivKey",
            "Agent PubKey",
            "Daemon PubKey",
            "Priv Socket",
            "Machine ID",
            "Attestation Hash",
        ]
        for idx, name in enumerate(fields):
            ttk.Label(self.trust_tab, text=name).grid(row=idx, column=0, sticky="w", padx=12, pady=4)
            lbl = ttk.Label(self.trust_tab, text="-")
            lbl.grid(row=idx, column=1, sticky="w", padx=12, pady=4)
            self.trust_labels[name] = lbl

        ttk.Button(self.trust_tab, text="Run Attestation", command=self._run_attest).grid(
            row=len(fields), column=0, padx=12, pady=8, sticky="w"
        )

    def _build_caps(self) -> None:
        self.cap_tree = ttk.Treeview(self.cap_tab, columns=("cap", "risk", "desc"), show="headings")
        self.cap_tree.heading("cap", text="Capability")
        self.cap_tree.heading("risk", text="Risk")
        self.cap_tree.heading("desc", text="Description")
        self.cap_tree.column("cap", width=260, anchor="w")
        self.cap_tree.column("risk", width=120, anchor="w")
        self.cap_tree.column("desc", width=420, anchor="w")
        self.cap_tree.pack(fill=tk.BOTH, expand=True, padx=12, pady=12)

        for cap, risk, desc in capabilities_with_meta(self.capabilities):
            self.cap_tree.insert("", tk.END, values=(cap, risk, desc))

    def _build_logs(self) -> None:
        self.logs_text = tk.Text(self.logs_tab, height=30)
        self.logs_text.pack(fill=tk.BOTH, expand=True, padx=12, pady=12)
        ttk.Button(self.logs_tab, text="Refresh Logs", command=self._refresh_logs).pack(pady=4)

    def _build_pairing(self) -> None:
        ttk.Label(self.pair_tab, text="Control Plane API Base").grid(row=0, column=0, sticky="w", padx=12, pady=6)
        self.api_base = tk.Entry(self.pair_tab, width=60)
        self.api_base.grid(row=0, column=1, padx=12, pady=6)
        self.api_base.insert(0, self.env.get("QUOODLE_API_BASE", "http://localhost:8080"))

        ttk.Label(self.pair_tab, text="User JWT").grid(row=1, column=0, sticky="w", padx=12, pady=6)
        self.user_jwt = tk.Entry(self.pair_tab, width=60, show="*")
        self.user_jwt.grid(row=1, column=1, padx=12, pady=6)

        ttk.Label(self.pair_tab, text="Device Name").grid(row=2, column=0, sticky="w", padx=12, pady=6)
        self.device_name = tk.Entry(self.pair_tab, width=60)
        self.device_name.grid(row=2, column=1, padx=12, pady=6)
        self.device_name.insert(0, os.uname().nodename)

        ttk.Button(self.pair_tab, text="Pair Device", command=self._pair).grid(
            row=3, column=0, padx=12, pady=12, sticky="w"
        )
        ttk.Label(
            self.pair_tab,
            text="Requires QUOODLE_AGENT_PUBKEY_B64 in secrets.env",
        ).grid(row=4, column=0, columnspan=2, sticky="w", padx=12)

    def _build_diag(self) -> None:
        ttk.Button(self.diag_tab, text="Export Diagnostics", command=self._export_diag).pack(padx=12, pady=12)
        self.diag_label = ttk.Label(self.diag_tab, text="-")
        self.diag_label.pack(padx=12, pady=6)

    def _run_attest(self) -> None:
        mid, digest = attestation_hash()
        self.trust_labels["Machine ID"].configure(text=mid or "-")
        self.trust_labels["Attestation Hash"].configure(text=digest or "-")

    def _refresh_logs(self) -> None:
        logs = journal_tail(["quoodle-agent", "quoodle-privileged"], 200)
        self.logs_text.configure(state=tk.NORMAL)
        self.logs_text.delete("1.0", tk.END)
        self.logs_text.insert("1.0", logs)
        self.logs_text.configure(state=tk.DISABLED)

    def _pair(self) -> None:
        api_base = self.api_base.get().strip()
        user_jwt = self.user_jwt.get().strip()
        device_name = self.device_name.get().strip()
        if not api_base or not user_jwt:
            messagebox.showerror("Pairing", "Missing API base or user JWT.")
            return
        import subprocess
        cli_path = os.path.join(os.path.dirname(__file__), "..", "cli", "quoodle-agent")
        result = subprocess.run(
            [cli_path, "pair", "--api-base", api_base, "--user-jwt", user_jwt,
             "--update-secrets", "--device-name", device_name],
            capture_output=True, text=True
        )
        rc = result.returncode
        if rc != 0:
            messagebox.showerror("Pairing", "Pairing failed. Check terminal output.")
        else:
            messagebox.showinfo("Pairing", "Pairing completed. Agent JWT updated.")

    def _export_diag(self) -> None:
        path = export_diagnostics("/tmp", DEFAULT_SECRETS)
        self.diag_label.configure(text=path)

    def refresh(self) -> None:
        snap = state_snapshot(DEFAULT_SECRETS)
        self.status_labels["Device ID"].configure(text=snap["device_id"])
        self.status_labels["WSS URL"].configure(text=snap["ws_url"])
        self.status_labels["Agent Service"].configure(text=snap["agent_status"])
        self.status_labels["Priv Service"].configure(text=snap["priv_status"])
        self.status_labels["Policy Hash"].configure(text=snap["policy_hash"])
        self.status_labels["Sequence"].configure(text=snap["sequence"])
        self.status_labels["Last Delivery"].configure(text=snap["last_delivery"])
        self.status_labels["Processed Cmds"].configure(text=snap["processed_count"])
        self.status_labels["Outbox Items"].configure(text=snap["outbox_count"])
        self.status_labels["Last State"].configure(text=snap["last_state_update"])
        self.jwt_label.configure(text=f"JWT: {snap['agent_jwt'][:10]}..." if snap["agent_jwt"] else "JWT: -")

        self.trust_labels["Controller Key"].configure(text=snap["controller_pubkey"])
        self.trust_labels["Agent PrivKey"].configure(text=snap["agent_privkey"])
        self.trust_labels["Agent PubKey"].configure(text=snap["agent_pubkey"])
        self.trust_labels["Daemon PubKey"].configure(text=snap["daemon_pubkey"])
        self.trust_labels["Priv Socket"].configure(text=snap["priv_socket"])

        processed = load_processed_commands(DEFAULT_SECRETS)
        for entry in processed:
            cmd_id = entry.get("command_id")
            if not cmd_id or cmd_id in self._seen_commands:
                continue
            self._seen_commands.add(cmd_id)
            result = entry.get("result", {})
            status = result.get("status", "unknown")
            exec_state = result.get("execution_state", "")
            msg = f"{cmd_id} • {status}"
            if exec_state:
                msg += f" ({exec_state})"
            urgency = "critical" if status in ("failed", "error") else "normal"
            send_notification("Command Result", msg, urgency)

        if self._last_quarantine is None:
            self._last_quarantine = snap.get("quarantine")
        elif snap.get("quarantine") != self._last_quarantine:
            state = snap.get("quarantine")
            if state == "yes":
                send_notification("Quoodle Agent", "Device entered quarantine", "critical")
            else:
                send_notification("Quoodle Agent", "Device released from quarantine", "normal")
            self._last_quarantine = state

        self.after(3000, self.refresh)


def main() -> None:
    app = AgentDesktopApp()
    app.mainloop()


if __name__ == "__main__":
    main()

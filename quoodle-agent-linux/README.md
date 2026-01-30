# Quoodle Linux Agent (C++/C Implementation)

This is the **production-ready Linux endpoint agent** implementing the secure device control protocol, with full audit logging and parity with the Windows agent.
It follows the canonical contracts in:

- `docs/specs/WindowsAgent → FastAPI (WSS control channel).json`
- `docs/specs/LinuxAgent → PrivilegedExecutor Interface.json`

Status: **✅ Fully Implemented & Tested** - Supports WSS connectivity, command execution, privileged IPC, and audit-by-default.

## Components

- `agent/`: C++ WSS agent with Ed25519 signing, command execution, telemetry, and audit logging.
- `privileged/`: C privileged executor daemon (root-owned) with UDS IPC and policy enforcement.
- `systemd/`: Production systemd unit files for agent and daemon.
- `tests/`: Integration tests and E2E validation.

## Build (dev)

```bash
cmake -S . -B build
cmake --build build
```

Dependencies:

- `libsodium` (Ed25519 + base64)
- `pkg-config`
- `cJSON` is vendored for the privileged daemon
- `nlohmann/json` is vendored for the agent (JCS canonicalization)

## Run (dev)

```bash
./build/quoodle-agent-linux
```

```bash
sudo ./build/quoodle-privileged-daemon
```

## Linux Agent CLI (Headless UI)

Use the bundled CLI for status, diagnostics, logs, pairing, and attestation:

```bash
./cli/quoodle-agent status
./cli/quoodle-agent doctor
./cli/quoodle-agent logs --tail 200
./cli/quoodle-agent logs --follow
./cli/quoodle-agent attest
```

Pairing without QR (requires a user JWT):

```bash
./cli/quoodle-agent pair --api-base http://localhost:8080 --user-jwt "$USER_JWT" --update-secrets
```

Notes:
- Reads `/etc/quoodle/secrets.env` by default (override with `--secrets-file`).
- Uses `/etc/machine-id` for HWID if not provided.

## Linux Agent UI (Desktop + TUI + Tray)

Launch the desktop UI (Tkinter):

```bash
./ui/quoodle-agent-ui --desktop
```

Launch the terminal UI (curses):

```bash
./ui/quoodle-agent-ui --tui
```

Launch tray icon (requires `pystray` + `pillow`):

```bash
./ui/quoodle-agent-ui --tray
```

Notes:
- Tray mode is optional and will print instructions if dependencies are missing.
- Pairing can be invoked from the UI tabs or via `--pair` (CLI-based).

## Systemd User Auto-Start

Install user services that auto-start the desktop or tray UI:

```bash
./ui/install_user_service.sh
systemctl --user enable --now quoodle-agent-ui.service
# or:
systemctl --user enable --now quoodle-agent-tray.service
```

## Environment

Agent:

- `QUOODLE_WS_URL` (e.g., `wss://gateway.example.com/agent`)
- `QUOODLE_DEVICE_ID`
- `QUOODLE_AGENT_JWT`
- `QUOODLE_AGENT_PRIVKEY_B64`
- `QUOODLE_AGENT_KID`
- `QUOODLE_AGENT_STATE_DIR` (default: `/var/lib/quoodle/agent`)
- `QUOODLE_DAEMON_PUBKEY_B64` (verify daemon responses)
- `QUOODLE_CONTROLLER_PUBKEY_B64` (verify WSS signatures)
- `QUOODLE_ALLOW_UNVERIFIED_WSS` (dev-only; default false)
- `QUOODLE_MAX_CLOCK_SKEW` (seconds; default 120)
- `QUOODLE_TLS_INSECURE` (true to skip TLS verification; dev-only)
- `QUOODLE_TLS_CA_FILE` / `QUOODLE_TLS_CA_PATH` (optional CA overrides)

Daemon:

- `QUOODLE_PRIV_SOCKET` (default: `/run/quoodle/privileged.sock`)
- `QUOODLE_DAEMON_PRIVKEY_B64`
- `QUOODLE_DAEMON_KID`
- `QUOODLE_AGENT_PUBKEY_B64` (verify agent requests)
- `QUOODLE_PRIV_STATE_DIR` (default: `/var/lib/quoodle`)
- `QUOODLE_PRIV_ALLOWED_UID` / `QUOODLE_PRIV_ALLOWED_GID` (optional peer-cred allowlist)

## Notes

- Canonicalization must use JCS (RFC 8785).
- The daemon must persist `agent_sequence` and `request_id` dedupe state.
- Unsupported methods must fail closed with `ERR_CAPABILITY_NOT_SUPPORTED`.
- TLS is supported for `wss://` when OpenSSL is available.

## Linux Endpoint Agent Architecture (User-Space Authority Gate)

The Linux Agent is the last unprivileged authority in the system.
It cannot execute power, but it decides whether power is requested correctly.

If this layer is compromised, the kernel must still hold the line.

┌──────────────────────────────────────────────────────────────┐
│ Linux Endpoint Agent (User Space) │
│ │
│ Runs as unprivileged service user │
│ (e.g., quoodle-agent) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [1] Transport Layer (WSS Client) │ │
│ │ - Persistent WebSocket to Gateway │ │
│ │ - AUTH / ACK / RESULT frames │ │
│ │ - Heartbeats + reconnect │ │
│ └────────────────────────────────────────────────────────┘ │
│ │ Signed Envelopes │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [2] Cryptographic Verification Gate │ │
│ │ - Verify Gateway signature │ │
│ │ - Verify canonical JSON │ │
│ │ - Reject unsigned / malformed commands │ │
│ └────────────────────────────────────────────────────────┘ │
│ │ Verified Intent │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [3] Command State Machine │ │
│ │ - queued → acked → executing → completed │ │
│ │ - TTL enforcement │ │
│ │ - Idempotent replay handling │ │
│ └────────────────────────────────────────────────────────┘ │
│ │ Authorized Command │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [4] Local Policy & Capability Mapper │ │
│ │ - policy_hash comparison │ │
│ │ - method → capability mapping │ │
│ │ - deny unsupported / unsafe requests │ │
│ └────────────────────────────────────────────────────────┘ │
│ │ Capability Request │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [5] Privileged Boundary Client │ │
│ │ - Unix Domain Socket client │ │
│ │ - Signs request to kernel service │ │
│ │ - Maintains monotonic sequence │ │
│ └────────────────────────────────────────────────────────┘ │
│ │ Signed Capability Invocation │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ [6] Telemetry & Result Collector │ │
│ │ - Collect execution receipts │ │
│ │ - Attach metadata + timing │ │
│ │ - Send RESULT to Gateway │ │
│ └────────────────────────────────────────────────────────┘ │
│ │
└──────────────────────────────────────────────────────────────┘

Responsibilities (Strictly Defined)
What the Linux Agent CAN do

Authenticate itself cryptographically

Verify command authenticity

Enforce time, sequence, and replay rules

Translate abstract commands into capabilities

Request privileged execution

Report results and telemetry

What the Linux Agent CANNOT do

Execute privileged OS actions directly

Bypass kernel checks

Invent commands

Modify policies

Elevate its own privileges

This is intentional.

## Linux Kernel Service Architecture (Kernel Only)

Provide a trusted privileged boundary that:

authenticates who is asking,

blocks replays,

enforces capability allowlists,

produces tamper-resistant audit,

and only triggers a small set of privileged actions (often via a broker).

Kernel should not parse JSON, do networking, or implement “apps.”

1. Core Components (in-kernel)
   A) Control Plane Interface (northbound entry)

Pick one:

Option 1: Netlink (recommended)

Structured messages, async notifications, good fit for “requests + results”

Easy to include multicast events (audit/telemetry)

Option 2: Char device + ioctl

Simpler but easier to misuse (buffer mistakes, blocking semantics)

Option 3: eBPF hooks

Great for observability/telemetry, not a primary command channel

✅ Recommendation: Netlink for commands + ring buffer/tracepoints for telemetry

B) Caller Identity Gate

Kernel verifies the requestor is “the broker service” you trust.

Checks you can use:

Creds: pid, uid, gid, capabilities

Binary identity (best effort):

check the process executable inode/label,

verify it runs under a dedicated service account,

LSM label binding:

AppArmor profile or SELinux context must match

cgroup binding:

only allow callers in a dedicated cgroup slice (systemd makes this clean)

This is the “only this door key works” layer 🔑

C) Anti-replay + Monotonic Sequence Guard

Kernel keeps a small state per device/broker identity:

last_seq (monotonic)

cmd_id_cache (LRU or bloom-ish set for recent IDs)

time_window (TTL enforcement)

Reject if:

seq <= last_seq

cmd_id already seen

now > timestamp + ttl

This prevents “record once, replay forever.”

D) Capability Router

Define a capability ID table in kernel:

Example:

CAP_LOCK_SESSION

CAP_READONLY_SYSINFO

CAP_NET_QUARANTINE (high risk)

CAP_FILE_ENUM (often should stay user-space)

Each capability has:

risk tier (low/med/high)

required caller attributes (uid, LSM label, caps)

allowed parameters (strict fixed-size structs)

Kernel routes to a handler or rejects.

E) Execution Engine (tiny, bounded)

Two patterns:

Pattern 1: Kernel executes (rare)
Only for things that are truly kernel-native and safe:

read-only system metrics

controlled network filtering toggles (still high risk)

Pattern 2: Kernel triggers broker action (common)
Kernel validates → emits “approved event” → user-space broker performs action:

lock screen (via login/session services)

screenshot (typically compositor/user-space)

file operations (definitely user-space)

Kernel here is a gatekeeper + receipt writer.

F) Result Receipt + Audit Trail

Kernel returns a receipt:

cmd_id, seq, status, reason

timings

minimal digests (optional)

“who called” metadata

Audit/telemetry emission:

tracepoints (best)

ring buffer readable by a privileged telemetry collector

optional netlink notifications (for high-level events)

This is the “tamper-resistant diary” 📓

2. Data Plane: Message Types (Kernel-facing)

Keep kernel messages fixed-size, no JSON.

Request struct (conceptual)

version

cmd_id (uuid bytes)

seq (u64)

timestamp_ns (u64)

ttl_ms (u32)

cap_id (u16)

params_len + params (bounded)

params_digest (optional)

Response struct

cmd_id

seq

status

error_code

details_len + details (bounded)

3. “Kernel + Broker” Boundary (how it fits your Quoodle flow)

Even though you asked “kernel only”, in real system design you need to show where the kernel stops.

Kernel Service (trust boundary)
⬇ approves/denies
Root Broker Daemon (does OS work)
⬇ talks to DE/system services
Desktop/session/kernel APIs

                 (User-space boundary)

┌──────────────────────────────────────────────────────┐
│ Root Broker │
│ │
│ - Runs as root, minimal attack surface │
│ - Only component allowed to call kernel interface │
│ - Executes OS actions (loginctl, qdbus, nft, etc.) │
│ │
└───────────────▲───────────────────────────────────────┘
│ netlink / char-dev ioctl
│ fixed-size structs only
┌───────────────┴───────────────────────────────────────┐
│ KERNEL SERVICE (Ring 0) │
│ │
│ [1] Control Interface │
│ - Netlink family OR /dev/quoodle + ioctl │
│ │
│ [2] Caller Identity Gate │
│ - uid / gid / Linux capabilities │
│ - LSM label check (AppArmor / SELinux) │
│ - cgroup membership enforcement │
│ │
│ [3] Replay / TTL Guard │
│ - last_seq per caller │
│ - cmd_id LRU cache │
│ - TTL / time-window enforcement │
│ │
│ [4] Capability Router │
│ - cap_id allowlist (deny-by-default) │
│ - risk tiers per capability │
│ - strict parameter bounds validation │
│ │
│ [5] Execution Hooks │
│ - kernel-native micro-handlers (rare) │
│ - OR “approve event” → broker executes │
│ │
│ [6] Audit & Telemetry │
│ - tracepoints / ring buffer │
│ - immutable execution receipts │
│ │
└───────────────────────────────────────────────────────┘
(Kernel primitives)

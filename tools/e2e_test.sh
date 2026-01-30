#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080/api}"
GATEWAY_WS_URL="${GATEWAY_WS_URL:-ws://localhost:8000/agent}"
SECRETS_FILE="${SECRETS_FILE:-}"
ALLOW_SUDO="${ALLOW_SUDO:-0}"
DEVICE_NAME="${DEVICE_NAME:-$(hostname)}"
HWID="${HWID:-$(cat /etc/machine-id 2>/dev/null || echo unknown)}"
ALT_HWID_PREFIX="${ALT_HWID_PREFIX:-e2e}"
VERBOSE="${VERBOSE:-1}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

log() {
  if [ "$VERBOSE" -gt 0 ]; then
    echo "$@"
  fi
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

pick_secrets_file() {
  if [ -n "$SECRETS_FILE" ]; then
    echo "$SECRETS_FILE"
    return
  fi
  if [ -r "/etc/quoodle/secrets.env" ]; then
    echo "/etc/quoodle/secrets.env"
    return
  fi
  if [ -r "$HOME/.config/quoodle/secrets.env" ]; then
    echo "$HOME/.config/quoodle/secrets.env"
    return
  fi
  if [ -r "./quoodle-agent-linux/systemd/secrets.env" ]; then
    echo "./quoodle-agent-linux/systemd/secrets.env"
    return
  fi
  echo ""
}

SECRETS_FILE="$(pick_secrets_file)"
if [ -z "$SECRETS_FILE" ]; then
    fail "No readable secrets.env found. Set SECRETS_FILE to a readable/writable file."
fi

if [ ! -w "$SECRETS_FILE" ]; then
  fail "Secrets file is not writable: $SECRETS_FILE. Use a writable copy (e.g., ~/.config/quoodle/secrets.env)."
fi

read -rp "Control plane email: " EMAIL
read -rsp "Password: " PASSWORD
printf "\n"

log "Waiting for gateway health..."
GATEWAY_HEALTH="${GATEWAY_HEALTH:-http://localhost:8000/health}"
for i in {1..20}; do
  if curl -s "$GATEWAY_HEALTH" >/dev/null 2>&1; then
    log "Gateway healthy."
    break
  fi
  sleep 1
  if [ "$i" -eq 20 ]; then
    fail "Gateway not healthy at $GATEWAY_HEALTH"
  fi
done

sudo -v >/dev/null 2>&1 || { echo "sudo failed" >&2; exit 1; }

LOGIN_RESP=$(curl -s "$BASE_URL/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"device_fingerprint\":\"linux-e2e\"}")

JWT=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("jwt",""))' <<<"$LOGIN_RESP")

if [ -z "$JWT" ]; then
  fail "Login failed: $LOGIN_RESP"
fi

USER_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("user_id",""))' <<<"$LOGIN_RESP")
USER_ROLE=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("user_role",""))' <<<"$LOGIN_RESP")

PUBKEY=$(grep -E '^QUOODLE_AGENT_PUBKEY_B64=' "$SECRETS_FILE" | cut -d= -f2)
if [ -z "$PUBKEY" ]; then
  fail "Missing QUOODLE_AGENT_PUBKEY_B64 in $SECRETS_FILE"
fi

do_pair() {
  local req_hwid="$1"
  PAIR_RESP=$(curl -s "$BASE_URL/pair/request" \
  -H 'Content-Type: application/json' \
  -d "{\"device_name\":\"$DEVICE_NAME\",\"hwid\":\"$req_hwid\",\"pubkey\":\"$PUBKEY\"}")

  PAIR_STATUS=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$PAIR_RESP")
  PAIR_REASON=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("reason",""))' <<<"$PAIR_RESP")
  PAIR_TOKEN=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("pair_token",""))' <<<"$PAIR_RESP")
}

do_pair "$HWID"

if [ -z "$PAIR_TOKEN" ]; then
  if [ "$PAIR_STATUS" = "conflict" ] || [ "$PAIR_REASON" = "already_claimed" ]; then
    log "Pair request conflict (already claimed). Using existing secrets.env values."
    DEVICE_ID=$(grep -E '^QUOODLE_DEVICE_ID=' "$SECRETS_FILE" | cut -d= -f2)
    AGENT_JWT=$(grep -E '^QUOODLE_AGENT_JWT=' "$SECRETS_FILE" | cut -d= -f2)
    if [ -z "$DEVICE_ID" ] || [ -z "$AGENT_JWT" ]; then
      fail "Missing QUOODLE_DEVICE_ID or QUOODLE_AGENT_JWT in $SECRETS_FILE"
    fi
    log "Using device_id: $DEVICE_ID"
  else
    fail "Pair request failed: $PAIR_RESP"
  fi
fi

if [ -n "${PAIR_TOKEN:-}" ]; then
  CONFIRM_RESP=$(curl -s "$BASE_URL/pair/confirm" \
    -H "Authorization: Bearer $JWT" \
    -H 'Content-Type: application/json' \
    -d "{\"pair_token\":\"$PAIR_TOKEN\"}")

  DEVICE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("device_id",""))' <<<"$CONFIRM_RESP")
  AGENT_JWT=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_jwt",""))' <<<"$CONFIRM_RESP")

  if [ -z "$DEVICE_ID" ] || [ -z "$AGENT_JWT" ]; then
    fail "Pair confirm failed: $CONFIRM_RESP"
  fi

  log "Paired device_id: $DEVICE_ID"

  sed -i "s|^QUOODLE_DEVICE_ID=.*|QUOODLE_DEVICE_ID=$DEVICE_ID|" "$SECRETS_FILE"
  sed -i "s|^QUOODLE_AGENT_JWT=.*|QUOODLE_AGENT_JWT=$AGENT_JWT|" "$SECRETS_FILE"
fi

if [ -f /etc/systemd/system/quoodle-agent.service ]; then
  CURRENT_WS=$(grep -E '^Environment=QUOODLE_WS_URL=' /etc/systemd/system/quoodle-agent.service | tail -n1 | cut -d= -f2-)
  if [ "$CURRENT_WS" != "$GATEWAY_WS_URL" ]; then
  log "QUOODLE_WS_URL should be set to $GATEWAY_WS_URL in your systemd unit."
fi
fi

sleep 2
if [ "$ALLOW_SUDO" = "1" ] && command -v sudo >/dev/null 2>&1; then
  sudo -v || true
fi

if [ "$ALLOW_SUDO" = "1" ] && sudo -v >/dev/null 2>&1; then
  # Sync secrets to system service env file so the running agent uses the new device_id/JWT.
  if [ -f "/etc/quoodle/secrets.env" ]; then
    sudo cp "$SECRETS_FILE" /etc/quoodle/secrets.env
  fi
  if [ -f /etc/systemd/system/quoodle-agent.service ]; then
    sudo sed -i "s|Environment=QUOODLE_WS_URL=.*|Environment=QUOODLE_WS_URL=$GATEWAY_WS_URL|" /etc/systemd/system/quoodle-agent.service || true
    sudo systemctl daemon-reload || true
    sudo systemctl reset-failed quoodle-agent || true
    sudo systemctl restart quoodle-agent || true
  fi
fi

AGENT_LOG=$(journalctl -u quoodle-agent -n 15 --no-pager 2>/dev/null || true)
if [ -n "$AGENT_LOG" ]; then
  echo "$AGENT_LOG"
else
  log "No agent logs available (service may not be running)."
fi

if echo "$AGENT_LOG" | grep -q "AUTH_UNKNOWN_DEVICE"; then
  echo "Gateway reports AUTH_UNKNOWN_DEVICE. Re-pairing with a fresh device id..."
  NEW_HWID="${ALT_HWID_PREFIX}-$(python3 -c 'import uuid; print(uuid.uuid4())')"
  do_pair "$NEW_HWID"
  if [ -z "$PAIR_TOKEN" ]; then
    fail "Re-pair request failed: $PAIR_RESP"
  fi
  CONFIRM_RESP=$(curl -s "$BASE_URL/pair/confirm" \
    -H "Authorization: Bearer $JWT" \
    -H 'Content-Type: application/json' \
    -d "{\"pair_token\":\"$PAIR_TOKEN\"}")

  DEVICE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("device_id",""))' <<<"$CONFIRM_RESP")
  AGENT_JWT=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_jwt",""))' <<<"$CONFIRM_RESP")
  if [ -z "$DEVICE_ID" ] || [ -z "$AGENT_JWT" ]; then
    fail "Re-pair confirm failed: $CONFIRM_RESP"
  fi
  sed -i "s|^QUOODLE_DEVICE_ID=.*|QUOODLE_DEVICE_ID=$DEVICE_ID|" "$SECRETS_FILE"
  sed -i "s|^QUOODLE_AGENT_JWT=.*|QUOODLE_AGENT_JWT=$AGENT_JWT|" "$SECRETS_FILE"
  log "Updated secrets for device_id: $DEVICE_ID"
  log "Restart the agent service, then re-run this script."
  log "Tip: run with ALLOW_SUDO=1 to auto-sync secrets to /etc and restart."
  exit 0
fi

CLIENT_MSG_ID=$(python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
)

CMD_RESP=$(curl -s "$BASE_URL/commands" \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d "{\"device_id\":\"$DEVICE_ID\",\"method\":\"ping\",\"params\":{},\"sensitive\":false,\"client_message_id\":\"$CLIENT_MSG_ID\",\"user_id\":\"$USER_ID\",\"user_role\":\"$USER_ROLE\"}")

echo "Command response: $CMD_RESP"
CMD_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("command_id",""))' <<<"$CMD_RESP")

if [ -n "$CMD_ID" ]; then
  sleep 2
  STATUS=$(curl -s "$BASE_URL/commands/$CMD_ID" -H "Authorization: Bearer $JWT")
  echo "Command status: $STATUS"
fi

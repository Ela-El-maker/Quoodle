#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.do-mini}"
COMPOSE_FILE="${2:-docker-compose.do-mini.yml}"
AUTO_FIX="${3:-}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed."
  exit 1
fi

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

echo "== Quoodle Dispatch Diagnostics =="
echo "ENV_FILE=$ENV_FILE"
echo "COMPOSE_FILE=$COMPOSE_FILE"
echo

echo "-- Services"
compose ps
echo

echo "-- Gateway health"
if compose exec -T gateway sh -lc "curl -fsS http://127.0.0.1:8000/health >/tmp/gw-health.json"; then
  compose exec -T gateway sh -lc "cat /tmp/gw-health.json"
else
  echo "gateway health check failed"
fi
echo

echo "-- Online devices seen by gateway"
if compose exec -T gateway sh -lc "curl -fsS http://127.0.0.1:8000/api/v1/devices/online >/tmp/gw-online.json"; then
  compose exec -T gateway sh -lc "cat /tmp/gw-online.json"
else
  echo "gateway devices/online check failed"
fi
echo

echo "-- Queue workers"
queue_proc_probe='found=0; for f in /proc/*/cmdline; do [ -r "$f" ] || continue; if grep -a -q "queue:work" "$f"; then found=1; tr "\000" " " < "$f"; echo; fi; done; exit $([ "$found" -eq 1 ] && echo 0 || echo 1)'

echo "control-plane embedded worker:"
if compose exec -T control-plane sh -lc "$queue_proc_probe"; then
  true
else
  echo "not running inside control-plane container"
fi
echo

if compose ps --services | grep -q "^control-plane-worker$"; then
  echo "control-plane-worker container process:"
  if compose exec -T control-plane-worker sh -lc "$queue_proc_probe"; then
    true
  else
    echo "no queue:work process in control-plane-worker"
  fi
else
  echo "control-plane-worker service not enabled (profile 'worker' not active)"
fi
echo

echo "-- Command queue summary (MySQL)"
DB_SERVICE="db"
if ! compose ps --services | grep -q "^db$"; then
  if compose ps --services | grep -q "^mysql$"; then
    DB_SERVICE="mysql"
  fi
fi

compose exec -T "$DB_SERVICE" sh -lc '
mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -D "$MYSQL_DATABASE" -e "
SELECT state, COUNT(*) AS c
FROM commands
GROUP BY state
ORDER BY c DESC;

SELECT id, device_id, method, state, execution_state, COALESCE(reason, \"\") AS reason, queued_at, dispatched_at, completed_at
FROM commands
ORDER BY queued_at DESC
LIMIT 15;

SELECT COUNT(*) AS queued_jobs FROM jobs;
"
'
echo

echo "-- Interpretation hints"
cat <<'EOF'
1) If commands remain state=queued and queued_jobs keeps increasing:
   queue worker is not consuming jobs.

2) If reason shows "device not connected":
   gateway has no active websocket session for that device.

3) If gateway /api/v1/devices/online is empty:
   agent is not connected/authenticated to droplet gateway.
EOF
echo

if [[ "$AUTO_FIX" == "--fix" ]]; then
  echo "== Applying safe auto-fix =="
  echo "1) restart control-plane to relaunch embedded queue worker"
  compose restart control-plane

  echo "2) enable dedicated worker profile (recommended on droplet)"
  compose --profile worker up -d control-plane-worker

  echo "3) show worker logs"
  compose logs --tail=80 control-plane control-plane-worker || true
fi

echo "Diagnostics complete."

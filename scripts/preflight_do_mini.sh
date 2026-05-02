#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.do-mini}"
COMPOSE_FILE="${2:-docker-compose.do-mini.yml}"

ok() {
  printf '[OK]  %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
}

if [[ ! -f "$ENV_FILE" ]]; then
  fail "Missing env file: $ENV_FILE"
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  fail "Missing compose file: $COMPOSE_FILE"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  fail "docker is not installed."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose plugin is not available."
  exit 1
fi

declare -A env_map
while IFS='=' read -r raw_key raw_val; do
  line="${raw_key}${raw_val:+=$raw_val}"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue
  [[ "$line" != *"="* ]] && continue

  key="${line%%=*}"
  val="${line#*=}"
  key="$(printf '%s' "$key" | xargs)"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  env_map["$key"]="$val"
done < "$ENV_FILE"

required_keys=(
  APP_ENV APP_DEBUG APP_KEY
  DB_HOST DB_DATABASE DB_USERNAME DB_PASSWORD MYSQL_ROOT_PASSWORD
  REDIS_HOST REDIS_URL
  POLICY_HASH POLICY_VERSION CONTROLLER_ID
  LARAVEL_SERVICE_PRIVATE_KEY_B64 LARAVEL_SERVICE_PUBKEY_B64
  FASTAPI_SERVICE_PRIVATE_KEY_B64 FASTAPI_SERVICE_PUBLIC_KEY_B64
  ED25519_PRIVATE_KEY_B64
  MAIL_HOST MAIL_USERNAME MAIL_PASSWORD MAIL_FROM_ADDRESS
  CONTROL_PLANE_APP_URL CONTROL_PLANE_UI_URL
  NEXT_PUBLIC_CONTROL_PLANE_BASE_URL NEXT_PUBLIC_CONTROL_PLANE_API_URL NEXT_PUBLIC_CONTROL_PLANE_UI_URL
  FASTAPI_BASE_URL LARAVEL_WEBHOOK_BASE JWKS_URL CONTROL_PLANE_API_BASE
)

missing=()
placeholders=()

for key in "${required_keys[@]}"; do
  val="${env_map[$key]:-}"
  if [[ -z "$val" ]]; then
    missing+=("$key")
    continue
  fi
  if [[ "$val" == "<"*">" ]] || [[ "$val" == "replace_me" ]] || [[ "$val" == "change_me" ]]; then
    placeholders+=("$key")
  fi
done

if (( ${#missing[@]} > 0 )); then
  fail "Missing required keys: ${missing[*]}"
fi

if (( ${#placeholders[@]} > 0 )); then
  fail "Placeholder values detected: ${placeholders[*]}"
fi

if (( ${#missing[@]} > 0 || ${#placeholders[@]} > 0 )); then
  exit 1
fi

ok "Required keys are present."

app_env="${env_map[APP_ENV]:-}"
app_debug="${env_map[APP_DEBUG]:-}"
allow_dev="${env_map[ALLOW_DEV_SIG_FALLBACK]:-}"
enable_tests="${env_map[ENABLE_TEST_ENDPOINTS]:-}"
run_migrations="${env_map[RUN_MIGRATIONS_ON_BOOT]:-}"
embedded_worker="${env_map[RUN_QUEUE_WORKER_IN_WEB]:-}"

if [[ "$app_env" != "production" ]]; then
  warn "APP_ENV is '$app_env' (recommended: production)"
fi
if [[ "$app_debug" != "false" ]]; then
  warn "APP_DEBUG is '$app_debug' (recommended: false)"
fi
if [[ "$allow_dev" == "true" ]]; then
  fail "ALLOW_DEV_SIG_FALLBACK must be false in production"
  exit 1
fi
if [[ "$enable_tests" == "true" ]]; then
  fail "ENABLE_TEST_ENDPOINTS must be false in production"
  exit 1
fi
if [[ "$run_migrations" == "true" ]]; then
  warn "RUN_MIGRATIONS_ON_BOOT=true. Prefer manual migration during release."
fi
if [[ "$embedded_worker" == "true" ]]; then
  warn "RUN_QUEUE_WORKER_IN_WEB=true. This is memory-friendly for mini droplets, but less isolated than a dedicated worker."
fi

printf 'Validating compose rendering...\n'
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null
ok "docker compose config validation passed."
ok "Mini droplet preflight passed for $ENV_FILE using $COMPOSE_FILE."

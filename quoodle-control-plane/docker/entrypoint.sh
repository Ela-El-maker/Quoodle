#!/bin/bash
set -e

WAIT_FOR_DB_SECONDS=${WAIT_FOR_DB_SECONDS:-5}
RUN_MIGRATIONS_ON_BOOT=${RUN_MIGRATIONS_ON_BOOT:-true}
SEED_LOCAL_ADMIN_ON_BOOT=${SEED_LOCAL_ADMIN_ON_BOOT:-auto}
CACHE_CONFIG_ON_BOOT=${CACHE_CONFIG_ON_BOOT:-true}
RUN_QUEUE_WORKER_IN_WEB=${RUN_QUEUE_WORKER_IN_WEB:-true}
QUEUE_WORKER_SLEEP_SECONDS=${QUEUE_WORKER_SLEEP_SECONDS:-1}
QUEUE_WORKER_TRIES=${QUEUE_WORKER_TRIES:-3}
QUEUE_WORKER_TIMEOUT_SECONDS=${QUEUE_WORKER_TIMEOUT_SECONDS:-60}
QUEUE_WORKER_QUEUES=${QUEUE_WORKER_QUEUES:-fastapi,default}

if [[ "${WAIT_FOR_DB_SECONDS}" =~ ^[0-9]+$ ]] && [ "${WAIT_FOR_DB_SECONDS}" -gt 0 ]; then
    echo "Waiting for database connection..."
    sleep "${WAIT_FOR_DB_SECONDS}"
fi

# Ensure JWT keypair exists before booting auth flows.
JWT_PRIVATE_KEY_PATH=${JWT_PRIVATE_KEY_PATH:-/var/www/storage/app/private/jwt_private.pem}
JWT_PUBLIC_KEY_PATH=${JWT_PUBLIC_KEY_PATH:-/var/www/storage/app/private/jwt_public.pem}

if [ ! -s "$JWT_PRIVATE_KEY_PATH" ] || [ ! -s "$JWT_PUBLIC_KEY_PATH" ]; then
    echo "JWT keys missing; generating RSA keypair..."
    mkdir -p "$(dirname "$JWT_PRIVATE_KEY_PATH")"
    openssl genpkey -algorithm RSA -out "$JWT_PRIVATE_KEY_PATH" -pkeyopt rsa_keygen_bits:2048
    openssl rsa -in "$JWT_PRIVATE_KEY_PATH" -pubout -out "$JWT_PUBLIC_KEY_PATH"
    chmod 600 "$JWT_PRIVATE_KEY_PATH" || true
    chmod 644 "$JWT_PUBLIC_KEY_PATH" || true
    chown www-data:www-data "$JWT_PRIVATE_KEY_PATH" "$JWT_PUBLIC_KEY_PATH" || true
fi

if [ "${RUN_MIGRATIONS_ON_BOOT}" = "true" ]; then
    echo "Running migrations..."
    php artisan migrate --force
else
    echo "Skipping migrations (RUN_MIGRATIONS_ON_BOOT=${RUN_MIGRATIONS_ON_BOOT})"
fi

if [ "${SEED_LOCAL_ADMIN_ON_BOOT}" = "true" ] || \
   { [ "${SEED_LOCAL_ADMIN_ON_BOOT}" = "auto" ] && [ "${APP_ENV:-local}" = "local" ]; }; then
    echo "Seeding local admin account..."
    php artisan db:seed --class=Database\\Seeders\\LocalDevAdminSeeder --force
fi

if [ "${CACHE_CONFIG_ON_BOOT}" = "true" ]; then
    # Clear old config and cache fresh (picks up runtime env from docker-compose)
    echo "Caching configuration..."
    php artisan config:clear
    php artisan config:cache
    php artisan route:cache
fi

# Start Nginx in background
echo "Starting Nginx..."
service nginx start

if [ "${RUN_QUEUE_WORKER_IN_WEB}" = "true" ]; then
    # Start Laravel queue worker in background (process fastapi queue too)
    echo "Starting Laravel queue worker..."
    php artisan queue:work \
        --sleep="${QUEUE_WORKER_SLEEP_SECONDS}" \
        --tries="${QUEUE_WORKER_TRIES}" \
        --timeout="${QUEUE_WORKER_TIMEOUT_SECONDS}" \
        --queue="${QUEUE_WORKER_QUEUES}" &
else
    echo "Skipping embedded queue worker (RUN_QUEUE_WORKER_IN_WEB=${RUN_QUEUE_WORKER_IN_WEB})"
fi

# Start PHP-FPM in foreground
echo "Starting PHP-FPM..."
php-fpm

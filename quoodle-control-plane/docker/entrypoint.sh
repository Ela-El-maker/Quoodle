#!/bin/bash
set -e

# Wait for DB? (Optional, handled by compose 'depends_on' healthcheck usually, but sleep helps)
echo "Waiting for database connection..."
sleep 5

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

# Run migrations
echo "Running migrations..."
php artisan migrate --force

if [ "${APP_ENV:-local}" = "local" ]; then
    echo "Seeding local admin account..."
    php artisan db:seed --class=Database\\Seeders\\LocalDevAdminSeeder --force
fi

# Clear old config and cache fresh (picks up runtime env from docker-compose)
echo "Caching configuration..."
php artisan config:clear
php artisan config:cache
php artisan route:cache

# Start Nginx in background
echo "Starting Nginx..."
service nginx start

# Start Laravel queue worker in background (process fastapi queue too)
echo "Starting Laravel queue worker..."
php artisan queue:work --sleep=1 --tries=3 --timeout=60 --queue=fastapi,default &

# Start PHP-FPM in foreground
echo "Starting PHP-FPM..."
php-fpm

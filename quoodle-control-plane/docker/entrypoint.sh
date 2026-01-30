#!/bin/bash
set -e

# Wait for DB? (Optional, handled by compose 'depends_on' healthcheck usually, but sleep helps)
echo "Waiting for database connection..."
sleep 5

# Run migrations
echo "Running migrations..."
php artisan migrate --force

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

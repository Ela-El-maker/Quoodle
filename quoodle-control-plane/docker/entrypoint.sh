#!/bin/bash
set -e

# Wait for DB? (Optional, handled by compose 'depends_on' healthcheck usually, but sleep helps)
echo "Waiting for database connection..."
sleep 5

# Run migrations
echo "Running migrations..."
php artisan migrate --force

# Cache config
echo "Caching configuration..."
php artisan config:cache
php artisan route:cache

# Start Nginx in background
echo "Starting Nginx..."
service nginx start

# Start PHP-FPM in foreground
echo "Starting PHP-FPM..."
php-fpm

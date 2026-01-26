#!/bin/bash
set -e

# Debug: Show APP_KEY (first 10 chars only for security)
if [ -n "$APP_KEY" ]; then
    echo "APP_KEY: ${APP_KEY:0:10}..." >&2
fi

# Wait for database to be ready (only if DB_HOST is set)
if [ -n "$DB_HOST" ]; then
    echo "Waiting for database connection..." >&2
    until php artisan migrate:status > /dev/null 2>&1; do
        echo "Database not ready, waiting 2 seconds..." >&2
        sleep 2
    done
    echo "Database connection established!" >&2
fi

# Ensure bootstrap/cache directory exists and is writable
mkdir -p /var/www/bootstrap/cache
chmod -R 775 /var/www/bootstrap/cache
chown -R www-data:www-data /var/www/bootstrap/cache || true

# Remove stale cache files that might cause bootstrap errors
rm -f /var/www/bootstrap/cache/config.php
rm -f /var/www/bootstrap/cache/routes-*.php
rm -f /var/www/bootstrap/cache/services.php
rm -rf /var/www/storage/framework/views/*

# Clear old cache before regenerating
php artisan config:clear || true
php artisan route:clear || true
php artisan view:clear || true

# Cache configurations after environment variables are loaded
# Only cache if not in testing environment
if [ "$APP_ENV" != "testing" ]; then
    php artisan config:cache || true
    php artisan route:cache || true
    php artisan view:cache || true
fi

# Run migrations (only if DB_HOST is set and not in test mode)
if [ -n "$DB_HOST" ] && [ "$APP_ENV" != "testing" ]; then
    echo "Running database migrations..." >&2
    php artisan migrate --force || echo "Migration failed or already up to date" >&2
fi

# Execute the main command (from CMD or docker-compose)
exec "$@"

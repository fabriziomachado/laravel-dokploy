#!/bin/bash
set -e

# Debug: Show APP_KEY (first 10 chars only for security)
if [ -n "$APP_KEY" ]; then
    echo "APP_KEY: ${APP_KEY:0:10}..." >&2
fi

# Note: Laravel works with environment variables directly (from docker-compose, Dokploy, etc.)
# No .env file is needed at runtime - all config comes from environment variables

# Ensure bootstrap/cache directory exists and is writable FIRST
# This must be done before any artisan command to prevent cache loading errors
mkdir -p /var/www/bootstrap/cache
chmod -R 775 /var/www/bootstrap/cache
chown -R www-data:www-data /var/www/bootstrap/cache || true

# Remove stale cache files that might cause bootstrap errors
# Do this before any artisan commands to prevent Laravel from trying to load non-existent cache
rm -f /var/www/bootstrap/cache/config.php
rm -f /var/www/bootstrap/cache/routes-*.php
rm -f /var/www/bootstrap/cache/services.php
rm -f /var/www/bootstrap/cache/packages.php
rm -rf /var/www/storage/framework/views/*

# Clear old cache before regenerating
# Use --no-interaction to prevent any prompts
php artisan config:clear --no-interaction || true
php artisan route:clear --no-interaction || true
php artisan view:clear --no-interaction || true
php artisan optimize:clear --no-interaction || true

# Rediscover packages to ensure all service providers are registered
# This is critical for Debugbar and other packages that use auto-discovery
php artisan package:discover --ansi --no-interaction || true

# Wait for database to be ready (only if DB_HOST is set)
# Do this AFTER clearing cache to avoid cache loading issues
if [ -n "$DB_HOST" ]; then
    echo "Waiting for database connection..." >&2
    # Use a simple connection test instead of migrate:status to avoid loading routes cache
    until php -r "try { \$pdo = new PDO('mysql:host='.getenv('DB_HOST').';port='.getenv('DB_PORT').';dbname='.getenv('DB_DATABASE'), getenv('DB_USERNAME'), getenv('DB_PASSWORD')); \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION); exit(0); } catch (Exception \$e) { exit(1); }" > /dev/null 2>&1; do
        echo "Database not ready, waiting 2 seconds..." >&2
        sleep 2
    done
    echo "Database connection established!" >&2
fi

# Cache configurations after environment variables are loaded and database is ready
# Only cache if not in testing or local environment (to allow Debugbar to work)
# Also skip cache if APP_DEBUG is true
if [ "$APP_ENV" != "testing" ] && [ "$APP_ENV" != "local" ] && [ "$APP_DEBUG" != "true" ]; then
    # Generate cache files one by one to ensure they exist before Laravel tries to load them
    php artisan config:cache --no-interaction || true
    
    # Generate route cache - if it fails, clear it to prevent Laravel from trying to load non-existent cache
    if php artisan route:cache --no-interaction 2>&1; then
        echo "Route cache generated successfully" >&2
    else
        echo "Route cache generation failed, clearing route cache to prevent errors" >&2
        php artisan route:clear --no-interaction || true
    fi
    
    php artisan view:cache --no-interaction || true
else
    echo "Skipping config cache (APP_ENV=$APP_ENV, APP_DEBUG=$APP_DEBUG) to allow Debugbar" >&2
fi

# Run migrations (only if DB_HOST is set and not in test mode)
if [ -n "$DB_HOST" ] && [ "$APP_ENV" != "testing" ]; then
    echo "Running database migrations..." >&2
    php artisan migrate --force || echo "Migration failed or already up to date" >&2
fi

# Execute the main command (from CMD or docker-compose)
exec "$@"

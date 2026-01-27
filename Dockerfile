# PHP application
FROM php:8.4-cli AS base

# System packages, PHP extensions, and Node.js
RUN apt-get update && apt-get install -y \
    git unzip curl libpng-dev libonig-dev libxml2-dev \
    libzip-dev libpq-dev libcurl4-openssl-dev libssl-dev \
    zlib1g-dev libicu-dev g++ libevent-dev procps \
    pkg-config libhiredis-dev \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql mbstring zip exif pcntl bcmath sockets intl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Redis extension via PECL
RUN pecl install redis \
    && docker-php-ext-enable redis

# Configure PHP to send error_log to stderr (for Docker logs)
RUN echo "log_errors = On" >> /usr/local/etc/php/conf.d/docker-php-log.ini \
    && echo "error_log = /proc/self/fd/2" >> /usr/local/etc/php/conf.d/docker-php-log.ini

# Swoole is installed from GitHub (PHP 8.4 compatible version)
RUN curl -L -o swoole.tar.gz https://github.com/swoole/swoole-src/archive/refs/tags/v6.0.0.tar.gz \
    && tar -xf swoole.tar.gz \
    && cd swoole-src-6.0.0 \
    && phpize \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable swoole \
    && cd / \
    && rm -rf swoole-src-6.0.0 swoole.tar.gz

# Composer installation
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Copy composer files and artisan file
COPY composer.json composer.lock artisan ./

# Create Laravel's basic directory structure
RUN mkdir -p bootstrap/cache storage/app storage/framework/cache/data \
    storage/framework/sessions storage/framework/views storage/logs

# Install Composer dependencies (without post-scripts)
# If composer.lock is out of sync, Composer will handle it gracefully
# The --ignore-platform-reqs helps if lock was generated on different platform
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts --ignore-platform-reqs || \
    (echo "⚠️ composer.lock out of sync, updating..." && \
     composer update --no-dev --lock --no-interaction --ignore-platform-reqs && \
     composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts)

# Copy the rest of the project files
COPY . .

# Create temporary .env for build only (Laravel needs basic config for artisan commands)
# This .env will be removed after build - real values come from runtime environment
RUN if [ ! -f .env ]; then \
        cp .env.example .env 2>/dev/null || \
        (echo "APP_NAME=Laravel" > .env && \
         echo "APP_ENV=production" >> .env && \
         echo "APP_KEY=" >> .env && \
         echo "APP_DEBUG=false" >> .env && \
         echo "APP_URL=http://localhost" >> .env); \
    fi

# Clear package discovery cache (ensures fresh package discovery)
RUN rm -f bootstrap/cache/packages.php bootstrap/cache/services.php || true

# Generate temporary APP_KEY for build (only needed to run artisan commands)
# Real APP_KEY will come from environment variables in runtime
RUN php artisan key:generate --ansi || php artisan key:generate --force || true

# Generate Wayfinder files before Vite build
# (Wayfinder plugin needs Laravel/PHP to be available and configured)
RUN php artisan wayfinder:generate --with-form 2>&1 || (echo "❌ Wayfinder generation failed. Error details above." && exit 1)

# Install Node.js dependencies and build frontend assets
# If package-lock.json is out of sync, update it first, then install
RUN (npm ci --prefer-offline --no-audit --ignore-scripts || \
     (echo "⚠️ package-lock.json out of sync, updating..." && \
      npm install --package-lock-only --no-audit && \
      npm ci --prefer-offline --no-audit --ignore-scripts)) \
    && npm run build \
    && rm -rf node_modules

# Remove temporary .env file - real values will come from environment variables at runtime
# (docker-compose, Dokploy, or other orchestration tools will provide the real .env)
RUN rm -f .env

# Run Composer post-scripts
RUN composer dump-autoload --optimize

# Laravel config cache (to be done at runtime, not during build)
RUN php artisan config:clear \
 && php artisan route:clear \
 && php artisan view:clear

# File permissions
RUN chown -R www-data:www-data /var/www \
 && chmod -R 775 /var/www/storage /var/www/bootstrap/cache

EXPOSE 9000

# Entrypoint script (pode ser sobrescrito no docker-compose)
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Default command (pode ser sobrescrito no docker-compose)
CMD ["php", "artisan", "octane:start", "--server=swoole", "--host=0.0.0.0", "--port=9000"]
ENTRYPOINT ["docker-entrypoint.sh"]

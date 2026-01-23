FROM php:8.4-cli AS base

# System packages and PHP extensions
RUN apt-get update && apt-get install -y \
    git unzip curl libpng-dev libonig-dev libxml2-dev \
    libzip-dev libpq-dev libcurl4-openssl-dev libssl-dev \
    zlib1g-dev libicu-dev g++ libevent-dev procps \
    pkg-config libhiredis-dev \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql mbstring zip exif pcntl bcmath sockets intl \
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

# Node.js 18 (Vite compatible)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Composer installation
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Copy composer files and artisan file
COPY composer.json composer.lock artisan ./

# Create Laravel's basic directory structure
RUN mkdir -p bootstrap/cache storage/app storage/framework/cache/data \
    storage/framework/sessions storage/framework/views storage/logs

# Install Composer dependencies (without post-scripts)
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts

# Node files (cache for Vite build)
COPY package.json package-lock.json ./
RUN npm ci

# Copy the rest of the project files
COPY . .

# Run Composer post-scripts
RUN composer dump-autoload --optimize

# Vite build
RUN npm run build

# Laravel config cache (to be done at runtime, not during build)
RUN php artisan config:clear \
 && php artisan route:clear \
 && php artisan view:clear

# File permissions
RUN chown -R www-data:www-data /var/www \
 && chmod -R 775 /var/www/storage /var/www/bootstrap/cache

EXPOSE 9000

# Startup script
RUN echo '#!/bin/bash\n\
set -e\n\
# Debug: Show APP_KEY (first 10 chars only for security)\n\
echo "APP_KEY: ${APP_KEY:0:10}..." >&2\n\
# Clear old cache before regenerating\n\
php artisan config:clear\n\
php artisan route:clear\n\
php artisan view:clear\n\
# Cache configurations after environment variables are loaded\n\
php artisan config:cache\n\
php artisan route:cache\n\
php artisan view:cache\n\
# Test logging to stderr\n\
php artisan tinker --execute="Log::info(\"Laravel logging test - logs should appear in Dokploy\")" 2>&1 || true\n\
# Start the server\n\
exec php artisan octane:start --server=swoole --host=0.0.0.0 --port=9000\n\
' > /start.sh && chmod +x /start.sh

CMD ["/start.sh"]

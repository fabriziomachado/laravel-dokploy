#!/bin/bash
# Script para aplicar correções do Debugbar no container em execução

echo "🔧 Aplicando correções do Debugbar..."

# 1. Publicar configuração do Debugbar (se não existir)
if [ ! -f /var/www/config/debugbar.php ]; then
    echo "📝 Publicando configuração do Debugbar..."
    php artisan vendor:publish --provider="Fruitcake\LaravelDebugbar\ServiceProvider" --tag=config --force
fi

# 2. Adicionar Debugbar ao flush do Octane
echo "📝 Atualizando config/octane.php..."
if ! grep -q "LaravelDebugbar" /var/www/config/octane.php; then
    # Backup
    cp /var/www/config/octane.php /var/www/config/octane.php.bak
    
    # Adicionar ao flush
    sed -i "s/'flush' => \[/'flush' => [\n        \\\\Fruitcake\\\\LaravelDebugbar\\\\LaravelDebugbar::class,/" /var/www/config/octane.php
    echo "✅ Debugbar adicionado ao flush do Octane"
else
    echo "ℹ️  Debugbar já está no flush do Octane"
fi

# 3. Limpar todos os caches
echo "🧹 Limpando caches..."
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear

echo "✅ Correções aplicadas!"
echo ""
echo "⚠️  IMPORTANTE: Você precisa reiniciar o Octane para as mudanças terem efeito:"
echo "   docker-compose -f docker-compose.stack.local.yml restart app"

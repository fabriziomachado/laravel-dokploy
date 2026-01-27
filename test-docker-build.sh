#!/bin/bash

set -e

echo "🐳 Testando build do Dockerfile..."
echo ""

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Nome da imagem de teste
IMAGE_NAME="laravel-dokploy:test-build"
CONTAINER_NAME="test-build-container"

# Limpar builds anteriores (opcional)
echo -e "${YELLOW}📦 Limpando builds anteriores...${NC}"
docker rmi -f "$IMAGE_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Build da imagem
echo -e "${YELLOW}🔨 Fazendo build da imagem Docker...${NC}"
if docker build -t "$IMAGE_NAME" .; then
    echo -e "${GREEN}✅ Build concluído com sucesso!${NC}"
else
    echo -e "${RED}❌ Build falhou!${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}🔍 Verificando se os assets foram gerados...${NC}"

# Criar container temporário para verificar arquivos
if docker run --rm --entrypoint="" --name "$CONTAINER_NAME" "$IMAGE_NAME" ls -la /var/www/public/build/ 2>/dev/null; then
    echo -e "${GREEN}✅ Diretório /var/www/public/build/ existe${NC}"
else
    echo -e "${RED}❌ Diretório /var/www/public/build/ não encontrado!${NC}"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    exit 1
fi

# Verificar se há arquivos de build (ignorar diretórios, contar apenas arquivos)
# Usar --entrypoint para evitar que o docker-entrypoint.sh rode
BUILD_FILES=$(docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "find /var/www/public/build -type f 2>/dev/null | wc -l" 2>/dev/null | tr -d '[:space:]' || echo "0")
if [ -n "$BUILD_FILES" ] && [ "$BUILD_FILES" -gt "0" ] 2>/dev/null; then
    echo -e "${GREEN}✅ Arquivos de build encontrados: $BUILD_FILES arquivo(s)${NC}"
    # Listar alguns arquivos como exemplo
    echo -e "${YELLOW}   Exemplos de arquivos gerados:${NC}"
    docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "ls -1 /var/www/public/build/assets/*.js 2>/dev/null | head -3 | sed 's|.*/|     - |'" 2>/dev/null || true
    docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "ls -1 /var/www/public/build/assets/*.css 2>/dev/null | head -1 | sed 's|.*/|     - |'" 2>/dev/null || true
else
    echo -e "${RED}❌ Nenhum arquivo de build encontrado!${NC}"
    exit 1
fi

# Verificar se o Wayfinder gerou os arquivos (se existirem)
echo ""
echo -e "${YELLOW}🔍 Verificando arquivos Wayfinder...${NC}"

WAYFINDER_ROUTES=$(docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "test -d /var/www/resources/js/routes && echo 'exists' || echo 'missing'" || echo "missing")
WAYFINDER_ACTIONS=$(docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "test -d /var/www/resources/js/actions && echo 'exists' || echo 'missing'" || echo "missing")

if [ "$WAYFINDER_ROUTES" = "exists" ] || [ "$WAYFINDER_ACTIONS" = "exists" ]; then
    echo -e "${GREEN}✅ Wayfinder gerou arquivos durante o build${NC}"
    if [ "$WAYFINDER_ROUTES" = "exists" ]; then
        ROUTE_COUNT=$(docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "find /var/www/resources/js/routes -type f 2>/dev/null | wc -l" 2>/dev/null | tr -d '[:space:]' || echo "0")
        echo -e "   📁 routes: $ROUTE_COUNT arquivo(s)"
    fi
    if [ "$WAYFINDER_ACTIONS" = "exists" ]; then
        ACTION_COUNT=$(docker run --rm --entrypoint="" "$IMAGE_NAME" sh -c "find /var/www/resources/js/actions -type f 2>/dev/null | wc -l" 2>/dev/null | tr -d '[:space:]' || echo "0")
        echo -e "   📁 actions: $ACTION_COUNT arquivo(s)"
    fi
else
    echo -e "${YELLOW}⚠️  Wayfinder não gerou arquivos (pode ser normal se não houver rotas/controllers)${NC}"
fi

# Verificar se o Node.js foi instalado
echo ""
echo -e "${YELLOW}🔍 Verificando instalação do Node.js...${NC}"
NODE_VERSION=$(docker run --rm --entrypoint="" "$IMAGE_NAME" node --version 2>/dev/null || echo "not found")
if [ "$NODE_VERSION" != "not found" ]; then
    echo -e "${GREEN}✅ Node.js instalado: $NODE_VERSION${NC}"
else
    echo -e "${RED}❌ Node.js não encontrado!${NC}"
    exit 1
fi

# Verificar se o PHP está funcionando
echo ""
echo -e "${YELLOW}🔍 Verificando instalação do PHP...${NC}"
PHP_VERSION=$(docker run --rm --entrypoint="" "$IMAGE_NAME" php --version 2>/dev/null | head -n 1 || echo "not found")
if [ "$PHP_VERSION" != "not found" ]; then
    echo -e "${GREEN}✅ PHP instalado: $(echo $PHP_VERSION | cut -d' ' -f1-2)${NC}"
else
    echo -e "${RED}❌ PHP não encontrado!${NC}"
    exit 1
fi

# Limpar container temporário
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo ""
echo -e "${GREEN}✅✅✅ Todos os testes passaram!${NC}"
echo -e "${GREEN}🚀 A imagem está pronta para ser usada no GitHub Actions${NC}"
echo ""
echo "Para testar a imagem localmente:"
echo "  docker run --rm -p 9000:9000 $IMAGE_NAME"
echo ""
echo "Para limpar a imagem de teste:"
echo "  docker rmi $IMAGE_NAME"

#!/bin/bash

# =============================================================================
# Script para Build e Push da Imagem Docker para Registry
# =============================================================================
# Uso:
#   ./build-and-push.sh [registry] [tag]
#   ./build-and-push.sh docker.io/meu-usuario latest
#   ./build-and-push.sh ghcr.io/meu-usuario v1.0.0
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar argumentos
if [ -z "$1" ]; then
    echo -e "${RED}Erro: Registry não especificado${NC}"
    echo ""
    echo "Uso: $0 <registry/imagem> [tag]"
    echo ""
    echo "Exemplos:"
    echo "  $0 docker.io/meu-usuario/laravel-dokploy latest"
    echo "  $0 ghcr.io/meu-usuario/laravel-dokploy v1.0.0"
    echo "  $0 meu-usuario/laravel-dokploy latest  # Docker Hub (sem docker.io)"
    exit 1
fi

REGISTRY_IMAGE="$1"
TAG="${2:-latest}"
FULL_IMAGE="${REGISTRY_IMAGE}:${TAG}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build e Push Docker Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Imagem: ${FULL_IMAGE}"
echo ""

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Erro: Docker não está rodando${NC}"
    exit 1
fi

# Build da imagem
echo -e "${YELLOW}[1/3] Building image...${NC}"
docker build -t "${FULL_IMAGE}" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Erro no build!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build concluído${NC}"
echo ""

# Login no registry (se necessário)
echo -e "${YELLOW}[2/3] Verificando autenticação...${NC}"

# Extrair registry do nome da imagem
if [[ "$REGISTRY_IMAGE" == *"/"* ]]; then
    REGISTRY=$(echo "$REGISTRY_IMAGE" | cut -d'/' -f1)
else
    REGISTRY="docker.io"
fi

# Tentar fazer login se não estiver autenticado
if ! docker pull "${FULL_IMAGE}" > /dev/null 2>&1; then
    echo -e "${YELLOW}   Fazendo login no registry...${NC}"
    
    case "$REGISTRY" in
        "ghcr.io")
            echo "   Para GHCR, use um Personal Access Token como senha"
            echo "   Token: https://github.com/settings/tokens"
            docker login ghcr.io
            ;;
        "docker.io"|*)
            echo "   Login no Docker Hub ou registry..."
            docker login "$REGISTRY" 2>/dev/null || docker login
            ;;
    esac
else
    echo -e "${GREEN}✓ Já autenticado${NC}"
fi

echo ""

# Push da imagem
echo -e "${YELLOW}[3/3] Pushing image to registry...${NC}"
docker push "${FULL_IMAGE}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Erro no push!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Push concluído${NC}"
echo ""

# Mostrar próximos passos
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Imagem disponível: ${FULL_IMAGE}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Próximos passos:"
echo "1. Edite docker-compose.stack.yml linha 19:"
echo "   image: ${FULL_IMAGE}"
echo ""
echo "2. No Dokploy, configure o registry em Settings > Registry"
echo ""
echo "3. Faça o deploy do stack no Dokploy"
echo ""

# Deploy com Docker Stack no Dokploy

Este guia descreve como fazer deploy da aplicação Laravel usando Docker Stack (Swarm mode) no Dokploy.

## Índice

- [Diferenças: Compose vs Stack](#diferenças-compose-vs-stack)
- [Pré-requisitos](#pré-requisitos)
- [Passo 1: Build da Imagem](#passo-1-build-da-imagem)
- [Passo 2: Push para Registry](#passo-2-push-para-registry)
- [Passo 3: Configurar Dokploy](#passo-3-configurar-dokploy)
- [Passo 4: Deploy](#passo-4-deploy)
- [Gerenciamento](#gerenciamento)
- [Troubleshooting](#troubleshooting)

## Diferenças: Compose vs Stack

| Recurso | Docker Compose | Docker Stack (Swarm) |
|---------|----------------|---------------------|
| Arquivo | `docker-compose.yml` ou `docker-compose.prod.yml` | `docker-compose.stack.yml` |
| Build local | ✅ Suportado (`build:`) | ❌ Não suportado |
| Imagem | Pode buildar localmente | Deve estar em registry |
| Réplicas | 1 container por serviço | N réplicas configuráveis |
| Escalabilidade | Manual via CLI | Automática + Manual via UI |
| Zero-downtime | ❌ Não | ✅ Sim (rolling updates) |
| Load balancing | Externo (Traefik) | Interno (Swarm) + Externo |
| Rollback | Manual | Automático em caso de falha |
| Resource limits | ⚠️ Soft limits | ✅ Hard limits enforced |
| Flag necessário | Não | `--with-registry-auth` (registry privado) |

## Pré-requisitos

1. **Docker Swarm inicializado** no servidor Dokploy
   ```bash
   docker swarm init
   ```

2. **Registry configurado** (uma das opções):
   - Registry local do Dokploy: `registry.dokploy.local`
   - GitHub Container Registry: `ghcr.io/seu-usuario`
   - Docker Hub: `docker.io/seu-usuario`
   - Registry privado: `seu-registry.com`

3. **Variáveis de ambiente configuradas** (ver `.env.dokploy.example`)

## Passo 1: Build da Imagem

### Opção A: Build Local

```bash
# Clone o repositório (se ainda não tiver)
git clone https://github.com/seu-usuario/laravel-dokploy.git
cd laravel-dokploy

# Build da imagem
docker build -t registry.dokploy.local/laravel-dokploy:latest .

# Ou com tag específica
docker build -t registry.dokploy.local/laravel-dokploy:v1.0.0 .
```

### Opção B: Build via CI/CD

Exemplo de GitHub Actions (`.github/workflows/build.yml`):

```yaml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to Registry
        uses: docker/login-action@v2
        with:
          registry: registry.dokploy.local
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            registry.dokploy.local/laravel-dokploy:latest
            registry.dokploy.local/laravel-dokploy:${{ github.sha }}
          cache-from: type=registry,ref=registry.dokploy.local/laravel-dokploy:buildcache
          cache-to: type=registry,ref=registry.dokploy.local/laravel-dokploy:buildcache,mode=max
```

## Passo 2: Push para Registry

### Registry Local do Dokploy

```bash
# Login no registry (se necessário)
docker login registry.dokploy.local

# Push da imagem
docker push registry.dokploy.local/laravel-dokploy:latest
```

### GitHub Container Registry

```bash
# Login no GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u seu-usuario --password-stdin

# Tag da imagem
docker tag registry.dokploy.local/laravel-dokploy:latest ghcr.io/seu-usuario/laravel-dokploy:latest

# Push da imagem
docker push ghcr.io/seu-usuario/laravel-dokploy:latest
```

### Docker Hub

```bash
# Login no Docker Hub
docker login

# Tag da imagem
docker tag registry.dokploy.local/laravel-dokploy:latest seu-usuario/laravel-dokploy:latest

# Push da imagem
docker push seu-usuario/laravel-dokploy:latest
```

## Passo 3: Configurar Dokploy

### 3.1 Criar Novo Projeto

1. Acesse o Dokploy UI
2. Clique em **"New Project"**
3. Selecione **"Stack"** (não "Docker Compose")
4. Nome do projeto: `Laravel App Stack`

### 3.2 Configurar Repositório

- **Source:** Git Repository
- **Repository URL:** `https://github.com/seu-usuario/laravel-dokploy.git`
- **Branch:** `main`
- **Docker Compose File:** `docker-compose.stack.yml`

### 3.3 Configurar Variáveis de Ambiente

Na aba **Environment**, adicione:

```bash
# Application
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:sua-chave-aqui
APP_DEBUG=false
APP_URL=https://seu-dominio.com

# Docker Registry
DOCKER_REGISTRY=registry.dokploy.local
IMAGE_TAG=latest

# Scaling
APP_REPLICAS=2

# Database
DB_CONNECTION=mysql
DB_HOST=database
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel_user
DB_PASSWORD=senha-segura-aqui

# Redis
REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Session & Cache
SESSION_DRIVER=database
CACHE_STORE=redis
QUEUE_CONNECTION=database

# Logs
LOG_CHANNEL=stack
LOG_STACK=single,errorlog
LOG_LEVEL=info

# Mail
MAIL_MAILER=smtp
MAIL_FROM_ADDRESS=noreply@seu-dominio.com
MAIL_FROM_NAME="${APP_NAME}"

# Octane
OCTANE_SERVER=swoole
OCTANE_HTTPS=true

# Traefik Domain
APP_DOMAIN=seu-dominio.com
```

### 3.4 Configurar Comando Customizado

Na aba **Advanced** → **Custom Command**, adicione:

```bash
--with-registry-auth
```

⚠️ **IMPORTANTE:** O flag `--with-registry-auth` é **obrigatório** quando usar registry privado. Ele distribui as credenciais do registry para todos os nodes do Swarm.

### 3.5 Configurar Domínio

Na aba **Domains**, adicione:

- **Domain:** `seu-dominio.com`
- **Protocol:** HTTPS
- **Certificate:** Let's Encrypt (auto)

## Passo 4: Deploy

### Via Dokploy UI

1. Clique no botão **"Deploy"**
2. Aguarde o processo de deploy
3. Monitore os logs em tempo real

### Via CLI (alternativo)

```bash
# SSH no servidor Dokploy
ssh user@seu-servidor.com

# Deploy do stack
docker stack deploy -c docker-compose.stack.yml --with-registry-auth laravel-stack

# Verificar status
docker stack services laravel-stack
docker stack ps laravel-stack
```

## Gerenciamento

### Escalar Réplicas

**Via Dokploy UI:**
1. Vá até o projeto
2. Aba **General** → **Replicas**
3. Ajuste o número de réplicas
4. Clique em **Update**

**Via CLI:**
```bash
docker service scale laravel-stack_app=3
```

**Via Variável de Ambiente:**
```bash
# Atualizar APP_REPLICAS no .env
APP_REPLICAS=3

# Re-deploy
docker stack deploy -c docker-compose.stack.yml --with-registry-auth laravel-stack
```

### Atualizar Aplicação

#### 1. Build e Push Nova Imagem

```bash
# Build nova versão
docker build -t registry.dokploy.local/laravel-dokploy:v1.0.1 .

# Push
docker push registry.dokploy.local/laravel-dokploy:v1.0.1
```

#### 2. Atualizar Tag no Dokploy

Opção A - Atualizar variável `IMAGE_TAG`:
```bash
IMAGE_TAG=v1.0.1
```

Opção B - Forçar pull da tag `latest`:
```bash
docker service update --image registry.dokploy.local/laravel-dokploy:latest --force laravel-stack_app
```

### Visualizar Logs

**Via Dokploy UI:**
- Aba **Logs** → Selecione o serviço (app, database, redis)

**Via CLI:**
```bash
# Logs do serviço app
docker service logs laravel-stack_app -f

# Logs de uma réplica específica
docker logs <container-id> -f

# Logs do MySQL
docker service logs laravel-stack_database -f

# Logs do Redis
docker service logs laravel-stack_redis -f
```

### Monitorar Status

```bash
# Status geral do stack
docker stack ps laravel-stack

# Status dos serviços
docker stack services laravel-stack

# Detalhes de um serviço
docker service inspect laravel-stack_app

# Listar réplicas em execução
docker service ps laravel-stack_app
```

### Rollback

**Automático:**
- Se o deployment falhar, o Swarm faz rollback automático

**Manual:**
```bash
# Rollback para versão anterior
docker service rollback laravel-stack_app

# Ou especificar versão
docker service update --rollback laravel-stack_app
```

### Remover Stack

```bash
# Remove todo o stack (app + database + redis)
docker stack rm laravel-stack

# ⚠️ CUIDADO: Volumes não são removidos automaticamente
# Para remover volumes também:
docker volume rm laravel-stack_laravel-db
docker volume rm laravel-stack_laravel-redis
docker volume rm laravel-stack_laravel-storage
docker volume rm laravel-stack_laravel-bootstrap-cache
```

## Troubleshooting

### Problema: Imagem não encontrada

**Erro:**
```
no such image: registry.dokploy.local/laravel-dokploy:latest
```

**Solução:**
1. Verifique se a imagem foi construída: `docker images`
2. Verifique se foi feito push: `docker push registry.dokploy.local/laravel-dokploy:latest`
3. Verifique se o registry está acessível: `ping registry.dokploy.local`
4. Use o flag `--with-registry-auth` no comando de deploy

### Problema: Autenticação no Registry

**Erro:**
```
pull access denied for registry.dokploy.local/laravel-dokploy
```

**Solução:**
1. Faça login no registry: `docker login registry.dokploy.local`
2. Adicione `--with-registry-auth` ao comando de deploy
3. No Dokploy UI, configure as credenciais do registry

### Problema: Serviço não inicia

**Erro:**
```
task: non-zero exit (1)
```

**Solução:**
1. Verifique os logs: `docker service logs laravel-stack_app`
2. Verifique o healthcheck: `docker service ps laravel-stack_app`
3. Verifique as variáveis de ambiente (especialmente `APP_KEY`)
4. Verifique a conectividade com database e redis

### Problema: Database connection refused

**Erro:**
```
SQLSTATE[HY000] [2002] Connection refused
```

**Solução:**
1. Verifique se o database está rodando: `docker service ps laravel-stack_database`
2. Verifique o nome do host: deve ser `database` (nome do serviço)
3. Aguarde o database inicializar completamente (healthcheck)
4. Verifique credenciais: `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`

### Problema: Réplicas não distribuem carga

**Sintoma:**
- Badge do container ID sempre mostra o mesmo ID

**Solução:**
1. Verifique se tem múltiplas réplicas: `docker service ps laravel-stack_app`
2. Verifique o Traefik: deve detectar múltiplos backends automaticamente
3. Teste com `curl -v` em loop para ver mudanças no backend

### Problema: Update travado

**Sintoma:**
```
update paused: update paused due to failure or early termination of task
```

**Solução:**
1. Force continuação: `docker service update --force laravel-stack_app`
2. Ou faça rollback: `docker service rollback laravel-stack_app`
3. Ajuste `update_config.failure_action` no compose se necessário

## Backups

### Configurar Volume Backups no Dokploy

1. Vá até a aba **Volume Backups**
2. Configure destino S3:
   - **Bucket:** seu-bucket
   - **Region:** us-east-1
   - **Access Key:** sua-key
   - **Secret Key:** sua-secret
3. Selecione volumes para backup:
   - ✅ `laravel-db` (crítico)
   - ✅ `laravel-storage` (uploads)
   - ⚠️ `laravel-redis` (opcional - cache)
   - ⚠️ `laravel-bootstrap-cache` (opcional - pode ser regenerado)
4. Configure schedule:
   - Database: Diário às 03:00
   - Storage: Diário às 04:00
5. Retenção: 7 dias

### Backup Manual

```bash
# Backup do MySQL
docker exec $(docker ps -q -f name=laravel-stack_database) \
  mysqldump -u root -p${DB_PASSWORD} ${DB_DATABASE} > backup.sql

# Backup de volume
docker run --rm -v laravel-stack_laravel-storage:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/storage-backup.tar.gz /data
```

## Monitoramento Avançado

### Métricas

No Dokploy, aba **Monitoring**:
- CPU usage por serviço
- Memory usage por serviço
- Network I/O
- Disk I/O

### Alertas

Configure alertas para:
- CPU > 80%
- Memory > 90%
- Healthcheck failures
- Service down

## Referências

- [Dokploy Documentation - Docker Compose](https://docs.dokploy.com/docs/core/docker-compose)
- [Docker Stack Documentation](https://docs.docker.com/engine/swarm/stack-deploy/)
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Traefik with Swarm](https://doc.traefik.io/traefik/providers/docker/)

## Suporte

Em caso de problemas:
1. Verifique os logs no Dokploy UI
2. Consulte este guia de troubleshooting
3. Verifique a documentação oficial do Dokploy
4. Abra uma issue no repositório

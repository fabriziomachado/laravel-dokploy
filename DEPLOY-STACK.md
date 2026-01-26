# Deploy com Docker Stack no Dokploy

Este guia descreve como fazer deploy da aplicação Laravel usando Docker Stack (Swarm mode) no Dokploy.

> **Alternativa:** Para deploy via **Nixpacks** (Application, build no Dokploy a partir do Git), veja [DEPLOY-NIXPACKS.md](DEPLOY-NIXPACKS.md).

## Índice

- [Quick Start - Teste Local](#quick-start---teste-local)
- [Diferenças: Compose vs Stack](#diferenças-compose-vs-stack)
- [Pré-requisitos](#pré-requisitos)
- [Passo 1: Build da Imagem](#passo-1-build-da-imagem)
- [Passo 2: Push para Registry](#passo-2-push-para-registry)
- [Passo 3: Configurar Dokploy](#passo-3-configurar-dokploy)
- [Passo 4: Deploy](#passo-4-deploy)
- [Gerenciamento](#gerenciamento)
- [Troubleshooting](#troubleshooting)

## Quick Start - Teste Local

**Quer testar rapidamente sem fazer push para registry?** Use o arquivo de teste local:

```bash
# 1. Build da imagem localmente
docker build -t laravel-dokploy-local:latest .

# 2. Inicializar Swarm (se necessário)
docker swarm init

# 3. Criar rede (se não existir)
docker network create --driver overlay dokploy-network 2>/dev/null || true

# 4. Deploy local
docker stack deploy -c docker-compose.stack.local.yml laravel-stack

# 5. Ver logs
docker service logs laravel-stack_app -f
```

✅ **Vantagens:**
- Não precisa de registry
- Testa rapidamente
- Usa o mesmo Dockerfile padrão

⚠️ **Limitações:**
- Só funciona localmente
- Para Dokploy, você precisa fazer push para registry

**Quando estiver pronto para produção:**
1. Use `./build-and-push.sh seu-usuario/laravel-dokploy latest`
2. Edite `docker-compose.stack.yml` linha 19 com sua imagem
3. Deploy no Dokploy

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
   - **Docker Hub** (mais comum): `docker.io/seu-usuario` ou apenas `seu-usuario`
   - **GitHub Container Registry**: `ghcr.io/seu-usuario`
   - **Digital Ocean Registry**: `registry.digitalocean.com/seu-registry`
   - **Registry privado próprio**: `seu-registry.com`
   
   ⚠️ **Nota:** O Dokploy não fornece um registry local por padrão. Você precisa configurar um registry externo em **Settings > Registry** no Dokploy.

3. **Variáveis de ambiente configuradas** (ver `.env.dokploy.example`)

## ⚠️ Importante: Build Automático no Dokploy

**Build Server do Dokploy NÃO funciona para Docker Stack!**

A documentação oficial do Dokploy confirma:
> "Build servers are currently **only available for Applications**. This feature is **not supported for Docker Compose deployments**."

**Isso significa:**
- ✅ Build Server funciona para **Applications** (deploy direto)
- ❌ Build Server **NÃO funciona** para **Docker Compose/Stack**

**Para Docker Stack, você precisa:**
1. Fazer build e push manualmente, OU
2. Configurar CI/CD externo (GitHub Actions, GitLab CI, etc.)

## 📋 Para que serve o Registry no Dokploy?

O registry configurado em **Settings > Registry** serve para:

### ✅ Para Applications (com Build Server):
- **Fazer push** das imagens buildadas automaticamente
- **Armazenar** as imagens após o build

### ✅ Para Docker Stack/Compose:
- **Autenticação automática** quando você usa `--with-registry-auth`
  - O Dokploy usa as credenciais configuradas para fazer login nos nodes do Swarm
  - Permite pull de imagens privadas sem configurar credenciais manualmente em cada node
- **Não faz build** - você ainda precisa fazer build e push manualmente ou via CI/CD

### Resumo:
| Funcionalidade | Applications | Docker Stack |
|---------------|--------------|--------------|
| Build automático | ✅ Sim (Build Server) | ❌ Não |
| Push automático | ✅ Sim (via Build Server) | ❌ Não |
| Autenticação automática | ✅ Sim | ✅ Sim (com --with-registry-auth) |
| Pull de imagens privadas | ✅ Sim | ✅ Sim (com --with-registry-auth) |

**Conclusão:** Para Docker Stack, configure o registry no Dokploy para que o `--with-registry-auth` funcione corretamente, mas você ainda precisa fazer build e push da imagem antes do deploy.

## Passo 1: Build da Imagem

### ⚡ Teste Local Rápido (Sem Registry)

Para testar localmente **sem precisar fazer push para registry**:

```bash
# 1. Build da imagem local
docker build -t laravel-dokploy-local:latest .

# 2. Inicializar Swarm (se ainda não tiver)
docker swarm init

# 3. Criar rede externa (se não existir)
docker network create --driver overlay dokploy-network

# 4. Deploy usando arquivo de teste local
docker stack deploy -c docker-compose.stack.local.yml laravel-stack

# 5. Verificar status
docker stack ps laravel-stack
docker service logs laravel-stack_app -f
```

**Arquivo usado:** `docker-compose.stack.local.yml` (usa imagem local `laravel-dokploy-local:latest`)

⚠️ **Nota:** Este método só funciona localmente. Para deploy no Dokploy, você precisa fazer push para um registry.

### Opção A: Build Local (Para Registry)

**Método Manual (Docker Hub - fabriziomachado):**
```bash
# Build da imagem
docker build -t fabriziomachado/laravel-dokploy:latest .

# Login no Docker Hub
docker login

# Push da imagem
docker push fabriziomachado/laravel-dokploy:latest
```

**Ou use o script automatizado:**
```bash
./build-and-push.sh fabriziomachado/laravel-dokploy latest
```

**Método Automatizado (Recomendado):**
```bash
# Use o script helper que faz build + push automaticamente
./build-and-push.sh seu-usuario/laravel-dokploy latest

# Ou para GHCR:
./build-and-push.sh ghcr.io/seu-usuario/laravel-dokploy v1.0.0
```

O script `build-and-push.sh` faz:
1. ✅ Build da imagem
2. ✅ Login no registry (se necessário)
3. ✅ Push da imagem
4. ✅ Mostra próximos passos

### Opção B: Build via CI/CD (Recomendado)

**Vantagens:**
- ✅ Build automático a cada push
- ✅ Não precisa fazer build manual
- ✅ Cache de layers para builds mais rápidos
- ✅ Tags automáticas (latest, branch, sha, etc.)

**Já configurado:** O arquivo `.github/workflows/build-and-push.yml` está pronto para usar!

**Configuração necessária:**
1. Vá em **GitHub Repository → Settings → Secrets and variables → Actions**
2. Adicione os secrets:
   - `DOCKERHUB_USERNAME`: seu usuário do Docker Hub (ex: `fabriziomachado`)
   - `DOCKERHUB_TOKEN`: seu token de acesso do Docker Hub
     - Crie em: https://hub.docker.com/settings/security
     - Permissões: Read, Write, Delete

**Como funciona:**
- Push na branch `main` → build e push automático
- Push de tag `v1.0.0` → build e push com tag `v1.0.0`
- Manual → pode acionar via "Run workflow"

**Exemplo manual (se não usar CI/CD):**

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

> ⚠️ **Pular este passo se você fez o teste local** - você já precisa da imagem no registry para usar no Dokploy.

### Método Automatizado (Recomendado)

Use o script helper:
```bash
./build-and-push.sh seu-usuario/laravel-dokploy latest
```

### Método Manual

### Docker Hub (Mais Comum)

```bash
# Login no Docker Hub
docker login

# Push da imagem (substitua pelo seu usuário)
docker push seu-usuario/laravel-dokploy:latest

# Ou com tag específica
docker push seu-usuario/laravel-dokploy:v1.0.0
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

### 3.2.1 ⚠️ IMPORTANTE: Editar Imagem no Arquivo

**Antes do deploy**, você **DEVE** editar a linha 19 do `docker-compose.stack.yml` e substituir pela sua imagem completa:

```yaml
# No arquivo docker-compose.stack.yml, linha 19:
image: registry.dokploy.local/laravel-dokploy:latest
```

**Substitua por uma das opções:**

- **Docker Hub** (mais comum): `seu-usuario/laravel-dokploy:latest` ou `docker.io/seu-usuario/laravel-dokploy:latest`
- **GitHub Container Registry**: `ghcr.io/seu-usuario/laravel-dokploy:latest`
- **Digital Ocean Registry**: `registry.digitalocean.com/seu-registry/laravel-dokploy:latest`
- **Registry privado**: `seu-registry.com/laravel-dokploy:v1.0.0`

**Por que?** O Dokploy não substitui variáveis de ambiente (`${DOCKER_REGISTRY}`) no campo `image:` do Docker Stack. Você precisa definir a imagem completa diretamente no arquivo.

**Alternativa:** Se você usar múltiplas tags/registries, pode criar branches diferentes do repositório com imagens diferentes, ou editar o arquivo diretamente no Dokploy antes de cada deploy.

### 3.3 Configurar Variáveis de Ambiente

Na aba **Environment**, adicione:

```bash
# Application
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:sua-chave-aqui
APP_DEBUG=false
APP_URL=https://seu-dominio.com

# Docker Registry (apenas para referência - não usado no compose)
# Configure seu registry em Settings > Registry no Dokploy
# Exemplos:
#   - Docker Hub: docker.io/seu-usuario ou apenas seu-usuario
#   - GHCR: ghcr.io/seu-usuario
#   - Digital Ocean: registry.digitalocean.com/seu-registry
DOCKER_REGISTRY=docker.io/seu-usuario
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

### 3.4 Configurar Registry no Dokploy

**IMPORTANTE:** Mesmo que você faça build e push manualmente, configure o registry no Dokploy:

1. Vá em **Settings → Registry**
2. Clique em **Add Registry**
3. Configure:
   - **Registry Name:** Docker Hub (ou nome que preferir)
   - **Username:** `fabriziomachado`
   - **Password:** Seu token de acesso do Docker Hub
   - **Registry URL:** `https://index.docker.io/v1`
4. Clique em **Save**

**Por que configurar?** O Dokploy usa essas credenciais quando você usa `--with-registry-auth`, distribuindo automaticamente as credenciais para todos os nodes do Swarm, permitindo pull de imagens privadas.

### 3.5 Configurar Comando Customizado

Na aba **Advanced** → **Custom Command**, adicione:

```bash
--with-registry-auth
```

⚠️ **IMPORTANTE:** Este flag é **obrigatório** quando usar registry privado ou quando quiser que o Dokploy distribua as credenciais automaticamente. Ele usa as credenciais configuradas em **Settings → Registry**.

### 3.6 Configurar Domínio

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
no such image: seu-usuario/laravel-dokploy:latest
```

**Solução:**
1. **Verifique se editou a linha 19 do docker-compose.stack.yml** com a imagem correta
2. Verifique se a imagem foi construída: `docker images`
3. Verifique se foi feito push: `docker push seu-usuario/laravel-dokploy:latest`
4. Verifique se o registry está configurado no Dokploy: **Settings > Registry**
5. Para registries privados, use o flag `--with-registry-auth` no comando de deploy
6. **IMPORTANTE:** O Dokploy não substitui variáveis `${DOCKER_REGISTRY}` no campo `image:`. Você deve usar a imagem completa diretamente no arquivo.
7. **IMPORTANTE:** O Dokploy não fornece registry local. Configure um registry externo (Docker Hub, GHCR, etc.) em Settings > Registry.

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

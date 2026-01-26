# Deploy com Nixpacks no Dokploy (Laravel 12 + Inertia + React + SSR)

Este guia descreve como fazer deploy da aplicação usando **Dokploy Applications** com **Build Type: Nixpacks**. O `nixpacks.toml` é compatível com Coolify e foi ajustado para as melhores práticas do Dokploy.

## Índice

- [Visão geral](#visão-geral)
- [Nixpacks vs Docker Stack](#nixpacks-vs-docker-stack)
- [Pré-requisitos](#pré-requisitos)
- [Passo 1: Repositório e nixpacks.toml](#passo-1-repositório-e-nixpackstoml)
- [Passo 2: Criar Application no Dokploy](#passo-2-criar-application-no-dokploy)
- [Passo 3: Variáveis de ambiente](#passo-3-variáveis-de-ambiente)
- [Passo 4: Domínios e porta](#passo-4-domínios-e-porta)
- [Passo 5: Deploy](#passo-5-deploy)
- [Migrations, Queue e SSR](#migrations-queue-e-ssr)
- [Produção: Build Server e CI/CD](#produção-build-server-e-cicd)
- [Troubleshooting](#troubleshooting)
- [Referências](#referências)

---

## Visão geral

- **Build:** Nixpacks (PHP + Node) — `composer install`, `npm ci`, `npm run build:ssr`
- **Runtime:** Supervisor com Nginx, PHP-FPM, Laravel Queue e Inertia SSR (Node)
- **App root:** `/app` (Nixpacks padrão); docroot Nginx: `/app/public`

O `nixpacks.toml` na raiz do projeto define fases de setup/build e assets estáticos (scripts, configs Supervisor/Nginx/PHP-FPM).

---

## Nixpacks vs Docker Stack

| Recurso            | Nixpacks (Application)     | Docker Stack (DEPLOY-STACK.md) |
|--------------------|----------------------------|--------------------------------|
| Build              | No Dokploy (ou Build Server) | CI/CD ou manual (Dockerfile)   |
| Arquivo            | `nixpacks.toml`            | `docker-compose.stack.yml`     |
| Tipo no Dokploy    | **Application**            | **Stack**                      |
| Registry           | Opcional (push da imagem)  | Obrigatório                    |
| Migrations         | No `start.sh` (se `DB_HOST`) | Entrypoint                     |
| Stack              | Nginx + PHP-FPM + Queue + SSR | Octane/Swoole                  |

Use **Nixpacks** quando quiser build direto no Dokploy a partir do Git, sem Dockerfile. Use **Docker Stack** quando preferir imagem própria (Dockerfile) e orquestração com outros serviços no mesmo stack.

---

## Pré-requisitos

1. **Dokploy** instalado e acessível.
2. **Registry** (opcional para Nixpacks): só é necessário se usar Build Server remoto ou CI/CD que faz push da imagem. Para build local no Dokploy, não é obrigatório.
3. **MySQL/PostgreSQL** (ou SQLite para testes): via serviço no Dokploy ou externo. Defina `DB_HOST` etc. nas variáveis de ambiente.
4. **Redis** (opcional): para cache e filas. Se usar, configure `REDIS_*` e `CACHE_STORE=redis`, `QUEUE_CONNECTION=redis`.

---

## Passo 1: Repositório e nixpacks.toml

1. O repositório deve conter o `nixpacks.toml` na **raiz** do projeto.
2. Garanta que existem `composer.json`, `package.json` e `package-lock.json` (Nixpacks usa o provider PHP e instala dependências Node).

O Dokploy usa o `nixpacks.toml` automaticamente quando o **Build Type** é **Nixpacks**. O caminho do config pode ser alterado com a variável `NIXPACKS_CONFIG_FILE` (ex.: `nixpacks.toml`).

---

## Passo 2: Criar Application no Dokploy

1. Acesse o **Dokploy UI**.
2. **New Project** → escolha **Application** (não Stack).
3. **General:**
   - **Name:** ex. `laravel-inertia`
   - **Source Type:** Git Repository
   - **Repository URL:** `https://github.com/seu-usuario/laravel-dokploy.git`
   - **Branch:** `main`
   - **Build Type:** **Nixpacks**
   - **Build Path:** `/` (raiz)
   - **Publish Directory:** deixe vazio (não é app estático).

4. **Build Type → Nixpacks:** o `nixpacks.toml` será usado. Opcionalmente, em **Environment**, você pode sobrescrever:
   - `NIXPACKS_BUILD_CMD` — comando de build
   - `NIXPACKS_START_CMD` — comando de start (já definido no `nixpacks.toml` via `[start]`)
   - `NIXPACKS_INSTALL_CMD` — comando de install  
   Não defina esses se o `nixpacks.toml` já estiver correto.

5. Salve (**Save**).

---

## Passo 3: Variáveis de ambiente

Na aba **Environment** da Application, configure:

### Obrigatórias

```bash
APP_KEY=base64:sua-chave-aqui
APP_ENV=production
APP_DEBUG=false
APP_URL=https://seu-dominio.com

# Laravel + Nixpacks PHP
NIXPACKS_PHP_ROOT_DIR=/app/public
NIXPACKS_PHP_FALLBACK_PATH=/index.php
IS_LARAVEL=true
```

### Database (exemplo MySQL)

```bash
DB_CONNECTION=mysql
DB_HOST=seu-mysql-host
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel_user
DB_PASSWORD=senha-segura
```

### Sessão, cache e fila

```bash
SESSION_DRIVER=database
CACHE_STORE=redis
QUEUE_CONNECTION=redis
REDIS_HOST=seu-redis-host
REDIS_PORT=6379
REDIS_PASSWORD=null
```

### Logging (visível em `docker logs`)

```bash
LOG_CHANNEL=stack
LOG_STACK=single,errorlog
LOG_LEVEL=info
```

### Inertia SSR (opcional)

O SSR roda em `http://127.0.0.1:13714` (definido em `config/inertia.php`). O worker Supervisor já inicia `node /app/bootstrap/ssr/ssr.mjs`. Se o bundle gerado for `ssr.js`, altere o `worker-inertia-ssr` no `nixpacks.toml` para `ssr.js`.

### Exemplo completo

Use o `.env.dokploy.example` como base. A seção **Nixpacks / Application** lista variáveis úteis para esse tipo de deploy.

---

## Passo 4: Domínios e porta

1. Aba **Domains** da Application.
2. Adicione o domínio (ex. `app.seudominio.com`) ou use o dado do Traefik (ex. `traefik.me`).
3. **Porta do container:** o Nixpacks PHP expõe a app na variável **`PORT`**. O Dokploy costuma definir `PORT=80` ou `PORT=3000`. O `nginx.template.conf` usa `listen ${PORT}`.  
   - Se usar **Generated Domain** (Traefik), em **Port** informe a mesma porta que o container (ex. `80`).
4. Em **Advanced → Ports**, confirme que a porta usada (ex. 80) está exposta, se necessário.

---

## Passo 5: Deploy

1. Clique em **Deploy**.
2. Acompanhe os logs na aba **Deployments**. O build (Nixpacks) pode levar alguns minutos.
3. Após o deploy, acesse o domínio configurado.

Para **re-deploy** (ex. após push no Git), use **Deploy** de novo ou configure **Auto Deploy** (webhook).

---

## Migrations, Queue e SSR

- **Migrations:** o `start.sh` (definido no `nixpacks.toml`) executa `php artisan migrate --force` quando `DB_HOST` está definido e `APP_ENV != testing`.
- **Queue:** o worker Laravel (`queue:work`) é iniciado pelo Supervisor (`worker-laravel.conf`). Ajuste `numprocs` no `nixpacks.toml` se precisar de mais processos.
- **SSR:** o worker `worker-inertia-ssr` executa `node /app/bootstrap/ssr/ssr.mjs`. O `config/inertia.php` aponta para `http://127.0.0.1:13714`. Mantenha a configuração coerente.

---

## Produção: Build Server e CI/CD

Conforme o [Going Production](https://docs.dokploy.com/docs/core/applications/going-production) do Dokploy:

- Builds Nixpacks no próprio servidor podem consumir muita CPU/RAM e causar timeouts.
- **Recomendações:**
  1. **Build Server:** usar um **Remote Build Server** dedicado para builds.
  2. **CI/CD:** buildar a imagem via GitHub Actions (ou outro CI), push para um registry, e na Dokploy criar uma **Application** com **Source Type: Docker** e usar a imagem (ex. `usuario/laravel-dokploy:latest`). O fluxo fica igual ao do [DEPLOY-STACK](DEPLOY-STACK.md), mas como Application em vez de Stack.

Para **Nixpacks puro** em produção, prefira Build Server remoto ou máquina com recursos suficientes.

---

## Troubleshooting

### `prestart.mjs` não encontrado

O `start.sh` chama `node /assets/scripts/prestart.mjs` para transformar o `nginx.template.conf` em `/etc/nginx.conf`. Esse script é injetado pelo **provider PHP do Nixpacks**. Se você usar apenas provider Node ou um Nixpacks bem customizado, o `prestart.mjs` pode não existir.

**Soluções:**

- Garantir que o provider **PHP** está ativo (ex. `composer.json` na raiz).
- Se mesmo assim falhar: incluir um `prestart` próprio em `[staticAssets]` ou usar um `nginx.conf` estático (sem variáveis `$!{...}`) e copiá-lo no `start.sh` em vez do template.

### SSR: `ssr.mjs` vs `ssr.js`

O build SSR do Vite/Laravel gera o bundle em `bootstrap/ssr/`. O `nixpacks.toml` usa `ssr.mjs`. Se o seu build gerar `ssr.js`, edite o `worker-inertia-ssr.conf` no `nixpacks.toml`:

```ini
command=bash -c 'exec node /app/bootstrap/ssr/ssr.js'
```

### Erro 502 / conexão recusada

- Confirme que **PORT** está definida e que o domínio no Dokploy aponta para a mesma porta do container.
- Verifique os logs do Nginx e do PHP-FPM (Supervisor) na aba **Logs** da Application.

### Migrations não rodam

- Verifique se `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` estão corretos.
- O `start.sh` só roda migrations quando `DB_HOST` está definido. Confirme que o banco está acessível do container (rede Docker, etc.).

### Falha no build Nixpacks

- Veja os logs do deploy (build phase).
- Confirme que `npm run build:ssr` funciona localmente (`npm ci && npm run build:ssr`).
- Se faltar memória, use Build Server remoto ou CI/CD (imagem pré-buildada).

---

## Referências

- [Dokploy – Applications](https://docs.dokploy.com/docs/core/applications)
- [Dokploy – Build Type (Nixpacks)](https://docs.dokploy.com/docs/core/applications/build-type)
- [Dokploy – Going Production](https://docs.dokploy.com/docs/core/applications/going-production)
- [Nixpacks – Configuration](https://nixpacks.com/docs/configuration/file)
- [Nixpacks – PHP Provider](https://nixpacks.com/docs/providers/php)
- [DEPLOY-STACK.md](DEPLOY-STACK.md) – deploy com Docker Stack e Dockerfile

# Staging server (M2.8)

Staging runs on one virtual machine with Docker: the game server, Postgres,
Redis and Caddy for HTTPS, all from `docker-compose.yml` at the repo root plus
`docker-compose.staging.yml` here. README section 6 plans managed Postgres for
production. Staging can use the bundled Postgres container, or a managed one
through `DATABASE_URL`.

Status: the files are ready but nothing is deployed. Deploying needs a hosting
account, a VM and a domain name, which are still to be decided.

## What is needed

| Item | Notes |
|---|---|
| A VM | Ubuntu 24.04, 1 vCPU, 1 to 2 GB RAM is plenty for staging. Any provider. |
| A domain name | For example `staging.<domain>`, an A record pointing at the VM. Caddy gets the certificate. |
| Ports | 22 (ssh), 80 and 443 open. Nothing else. |
| Secrets | `SESSION_SECRET`, `POSTGRES_PASSWORD`, and for real sandbox payments the MoMo keys (`MOMO_SUBSCRIPTION_KEY`, `MOMO_API_USER`, `MOMO_API_KEY`) or Airtel keys (`AIRTEL_CLIENT_ID`, `AIRTEL_CLIENT_SECRET`). `server/.env.example` says where each comes from. |

## One-time setup on the VM

```sh
# As root
apt-get update && apt-get install -y docker.io docker-compose-v2 git curl
adduser --disabled-password deploy && usermod -aG docker deploy
mkdir -p /opt/arena && chown deploy /opt/arena

# As deploy (put your ssh public key in ~deploy/.ssh/authorized_keys first)
git clone https://github.com/<owner>/Arena.git /opt/arena
cd /opt/arena
```

Create `/opt/arena/.env` for compose. It is not in git:

```sh
DOMAIN=staging.example.ug
POSTGRES_PASSWORD=<openssl rand -hex 24>
# Optional: a managed database instead of the bundled container
# DATABASE_URL=postgres://user:pass@host:5432/arena?sslmode=require
```

Create `/opt/arena/server/.env` with the server settings, copied from
`server/.env.example`. At least:

```sh
SESSION_SECRET=<openssl rand -base64 48>
AUTH_PROVIDER=fake          # firebase once the Firebase project exists
PAYMENTS_PROVIDER=fake      # mtn,airtel needs AUTH_PROVIDER=firebase
APP_DOWNLOAD_URL=https://example.ug/download
# For MoMo sandbox deposits (with AUTH_PROVIDER=firebase and FIREBASE_PROJECT_ID):
# PAYMENTS_PROVIDER=mtn
# MOMO_SUBSCRIPTION_KEY=...  MOMO_API_USER=...  MOMO_API_KEY=...
# MOMO_CALLBACK_URL defaults to https://$DOMAIN/v1/payments/callback/mtn
```

The server refuses to start with fake login and real payments, so sandbox
MoMo on staging also needs Firebase login.

## Deploying

From a checkout on your machine, with ssh access to the VM:

```sh
DEPLOY_HOST=deploy@staging.example.ug server/deploy/deploy.sh claude/arena-m0-m1-m2-build-xy3qa3
```

The script does the following:

1. Checks out that branch or ref on the VM.
2. Builds the server image. The build context is the repository root, because the server needs `packages/*`, `server/auth` and `server/wallet`.
3. Restarts the stack.
4. Waits until `https://$DOMAIN/health` reports the new commit as its version.

On startup the server runs the database migrations, and reloads any live rooms from Redis.

## Checking it

```sh
curl https://staging.example.ug/health          # {"ok":true,"version":"<commit>"}
docker compose -f docker-compose.yml -f server/deploy/docker-compose.staging.yml logs -f server
```

Point the app at staging with
`--dart-define=ARENA_SERVER_URL=https://staging.example.ug`. Room links are
`https://staging.example.ug/r/<CODE>`.

## Running the same stack locally

```sh
docker compose up --build        # server on http://localhost:8080
```

Without `server/.env`, this runs with fake login and fake payments and a random
session secret. The server's own tests need no Docker: `cd server && dart test`
(add `DATABASE_URL` and `REDIS_URL` to include the Postgres and Redis tests).

## Backups

With the bundled Postgres, add a nightly dump to cron:

```sh
docker compose exec -T postgres pg_dump -U arena arena | gzip > /opt/backups/arena-$(date +%F).sql.gz
```

A managed database has its own backups.

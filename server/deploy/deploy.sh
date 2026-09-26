#!/usr/bin/env bash
# Deploys a git ref of this repository to the staging VM and checks /health.
#
#   DEPLOY_HOST=deploy@staging.example.ug server/deploy/deploy.sh [ref]
#
# ref defaults to the current branch's upstream head. The VM must be set up
# once as described in server/deploy/README.md.
set -euo pipefail

host="${DEPLOY_HOST:?set DEPLOY_HOST, for example deploy@staging.example.ug}"
dir="${DEPLOY_DIR:-/opt/arena}"
ref="${1:-$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null | sed 's|^origin/||' || echo main)}"

echo "Deploying $ref to $host:$dir"
ssh "$host" bash -s -- "$dir" "$ref" <<'REMOTE'
set -euo pipefail
dir="$1"
ref="$2"
cd "$dir"
git fetch --quiet origin
git checkout --quiet --detach "origin/$ref" 2>/dev/null || git checkout --quiet --detach "$ref"
export APP_VERSION="$(git rev-parse --short HEAD)"
compose="docker compose -f docker-compose.yml -f server/deploy/docker-compose.staging.yml"
$compose build server
$compose up -d
set -a; . ./.env; set +a
for i in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN/health" | grep -q "\"$APP_VERSION\""; then
    echo "Healthy: version $APP_VERSION at https://$DOMAIN"
    exit 0
  fi
  sleep 2
done
echo "Server did not report version $APP_VERSION in time" >&2
$compose logs --tail 50 server >&2
exit 1
REMOTE

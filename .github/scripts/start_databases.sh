#!/usr/bin/env bash
# Starts PostgreSQL and Redis on a GitHub Ubuntu runner for the server tests,
# with the arena/arena login the tests expect. PostgreSQL comes with the
# runner image and Redis from the Ubuntu archive, so no image registry and
# its anonymous pull limits are involved (D47).
set -euo pipefail

sudo systemctl start postgresql.service
for _ in $(seq 1 30); do
  pg_isready -h localhost -q && break
  sleep 1
done
pg_isready -h localhost
sudo -u postgres psql -v ON_ERROR_STOP=1 -q \
  -c "CREATE ROLE arena LOGIN SUPERUSER PASSWORD 'arena'" \
  -c "CREATE DATABASE arena OWNER arena"

if ! command -v redis-server >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends redis-server
fi
sudo systemctl start redis-server.service || redis-server --daemonize yes
for _ in $(seq 1 30); do
  [ "$(redis-cli ping 2>/dev/null)" = PONG ] && break
  sleep 1
done
redis-cli ping
psql "postgres://arena:arena@localhost:5432/arena" -tAc 'SELECT version()'

#!/usr/bin/env bash
# Start (or reuse) the RustChap dev Postgres in Docker.
# Data persists in the named volume `rustchap-pgdata` across restarts.
set -euo pipefail

NAME=rustchap-db
PORT="${RUSTCHAP_DB_PORT:-5433}"

if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
  echo "${NAME} already running on port ${PORT}"
elif docker ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
  docker start "${NAME}" >/dev/null
  echo "${NAME} restarted on port ${PORT}"
else
  docker run -d --name "${NAME}" \
    -e POSTGRES_USER=rustchap \
    -e POSTGRES_PASSWORD=rustchap \
    -e POSTGRES_DB=rustchap \
    -p "127.0.0.1:${PORT}:5432" \
    -v rustchap-pgdata:/var/lib/postgresql/data \
    postgres:17 >/dev/null
  echo "${NAME} created on port ${PORT}"
fi

echo "DATABASE_URL=postgres://rustchap:rustchap@localhost:${PORT}/rustchap"

#!/bin/bash
# 建角色 + 授权。密码从容器环境变量取，不落盘。
set -euo pipefail

if [ -z "${AUTH_PASSWORD:-}" ]; then
  echo "[roles] AUTH_PASSWORD 没传进来，跳过建角色" >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v pw="$AUTH_PASSWORD" \
     -f /docker-entrypoint-initdb.d/sql/99-roles.sql

echo "[roles] anon / authenticator 已就绪"

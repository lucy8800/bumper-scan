#!/bin/bash
# 每日备份数据库，保留最近 14 天
set -euo pipefail
cd "$HOME/bumper"
mkdir -p backup
f="backup/bumper-$(date +%F).sql"
docker compose exec -T db pg_dump -U postgres -d bumper > "$f" </dev/null
gzip -f "$f"
find backup -name 'bumper-*.sql.gz' -mtime +14 -delete
echo "backup ok: $f.gz ($(du -h "$f.gz" | cut -f1))"

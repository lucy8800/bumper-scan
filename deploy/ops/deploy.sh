#!/bin/bash
# ============================================================
#  一键发布：拉 GitHub → 同步发布目录 → 注入域名/anonKey → reload nginx → 自检
#  用法：cd ~/bumper && ./deploy.sh
#  前置：~/bumper/src 是本仓库的 git clone；~/bumper/.env 已存在
# ============================================================
set -euo pipefail
cd "$HOME/bumper"

echo "[1/6] 拉取 GitHub 最新代码 ..."
git -C src pull --ff-only
echo "      当前提交：$(git -C src log --oneline -1)"

echo "[2/6] 同步到发布目录 site/ ..."
# deploy/ 是本目录的运维源码，不应对外暴露；.git 同样排除
rsync -a --delete \
      --exclude '.git' \
      --exclude '.gitignore' \
      --exclude 'deploy' \
      src/ site/
mkdir -p site/img
cp -f src/*.jpg site/img/ 2>/dev/null || true

echo "[3/6] 注入云端地址与 anonKey（读取 .env）..."
python3 gen_env.py

echo "[4/6] 语法自检 ..."
docker compose config -q
docker exec bumper-web-1 nginx -t 2>/dev/null || true

echo "[5/6] 重载 nginx ..."
docker exec bumper-web-1 nginx -s reload 2>/dev/null || docker compose up -d web

echo "[6/6] 自检 ..."
curl -sk --resolve bumper.fat.plus:10443:127.0.0.1 -o /dev/null \
     -w "      页面 page=%{http_code}" https://bumper.fat.plus:10443/
KEY=$(grep '^ANON_KEY=' .env | cut -d= -f2-)
curl -sk --resolve bumper.fat.plus:10443:127.0.0.1 -o /dev/null \
     -w "   接口 rest=%{http_code}\n" \
     "https://bumper.fat.plus:10443/rest/v1/bumpers?select=id&limit=1" \
     -H "apikey: $KEY"
echo "完成：https://bumper.fat.plus:10443"

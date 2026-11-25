# deploy/ — 腾讯云生产环境的运维文件

这个目录是**服务器 `~/bumper/` 的源码版**。服务器哪天出问题，clone 仓库 + 补齐敏感文件，就能原样重搭。

生产地址：**https://bumper.fat.plus:10443**
完整说明见 [`DEPLOY.md`](DEPLOY.md)。

---

## 目录结构

| 仓库路径 | 服务器路径 | 作用 |
| --- | --- | --- |
| `deploy/docker-compose.yml` | `~/bumper/docker-compose.yml` | 三个容器：`db`(PostgreSQL 16) / `api`(PostgREST) / `web`(nginx) |
| `deploy/nginx/bumper.conf` | `~/bumper/nginx/bumper.conf` | 80 端口做 ACME 验证+跳转；443 映射到宿主 10443 提供网页，`/rest/v1/` 反代 PostgREST |
| `deploy/db/01-schema.sql` | `~/bumper/db/01-schema.sql` | 建表 `bumpers` / `records`、索引、RLS 策略；容器首次启动自动执行 |
| `deploy/db/99-roles.sh` | `~/bumper/db/99-roles.sh` | 建 `anon` / `authenticator` 角色并授权，密码取自环境变量，不落盘 |
| `deploy/db/sql/99-roles.sql` | `~/bumper/db/sql/99-roles.sql` | 上一条调用的 SQL 本体 |
| `deploy/ops/deploy.sh` | `~/bumper/deploy.sh` | 一键发布：git pull → rsync → 注入域名/anonKey → reload nginx → 自检 |
| `deploy/ops/backup.sh` | `~/bumper/backup.sh` | 每日 `pg_dump` 压缩备份，保留 14 天（cron 02:30） |
| `deploy/gen_env.py` | `~/bumper/gen_env.py` | 首次运行生成 `.env`；每次发布把域名和 anonKey 注入 `site/index.html` |
| `deploy/.env.example` | `~/bumper/.env.example` | `.env` 的模板（真实 `.env` 不入库） |

---

## 敏感文件：不入库，需手动放到服务器

以下 4 类**故意没有**提交到仓库。重建服务器时，从别处拷回或重新生成。

### 1. `~/bumper/.env`（最关键）

```
DB_PASSWORD=      # PostgreSQL 超级用户密码
AUTH_PASSWORD=    # authenticator 角色密码，PostgREST 用它连库
JWT_SECRET=       # PostgREST 验签密钥，改了必须重新生成 ANON_KEY
ANON_KEY=         # 前端用的 HS256 JWT（role=anon），由 JWT_SECRET 签出
```

- **怎么恢复**：如果没有备份，删掉 `.env` 后执行 `python3 gen_env.py` 会自动生成一整套新的。
  注意：**换新 JWT_SECRET 后所有已发出的 anonKey 失效**，但因为 anonKey 是每次发布时注入到 html 的，跑一次 `./deploy.sh` 即可自愈。
- 权限必须是 `600`：`chmod 600 ~/bumper/.env`

### 2. `~/bumper/certs/fullchain.pem` + `privkey.pem`

- **不用备份**。由 acme.sh 在服务器上签发（Let's Encrypt，HTTP-01），续期自动完成。
- 重建时执行一次签发即可，见 `DEPLOY.md` 证书章节。

### 3. `~/bumper/db/import/10-import.sql`

- 从原 Supabase 导出的**真实生产数据快照**（34 件 / 30 条）。里面有实际二维码内容和操作记录，
  公开仓库不合适放，所以只在服务器本地保存。此路径已在 `.gitignore` 中忽略。
- **怎么恢复**：日常靠 `~/bumper/backup/bumper-YYYY-MM-DD.sql.gz`，解压后 `psql` 灌回即可，比这个快照更新。

### 4. `~/.acme.sh/`（acme.sh 账号密钥）

- 也不入库。重建时重新注册一次账号即可，不影响已签证书的可用性。

---

## 首次/重建部署顺序

```bash
# 1) 拉代码
git clone https://github.com/lucy8800/bumper-scan.git ~/bumper/src

# 2) 铺运维文件
cd ~/bumper
cp src/deploy/docker-compose.yml .
cp -r src/deploy/nginx .
cp -r src/deploy/db .
cp src/deploy/gen_env.py .
cp src/deploy/ops/deploy.sh src/deploy/ops/backup.sh .
chmod +x deploy.sh backup.sh db/99-roles.sh

# 3) 生成密钥
python3 gen_env.py          # 生成 .env，自动 chmod 600
cat .env                    # 记下 ANON_KEY，验证用

# 4) 铺发布目录（deploy.sh 会做，第一次先手动跑一遍）
mkdir -p site
rsync -a --delete --exclude '.git' --exclude 'deploy' src/ site/
mkdir -p site/img && cp -f src/*.jpg site/img/

# 5) 起容器
docker compose up -d
docker compose ps

# 6) 证书（见 DEPLOY.md）
# 7) 自检
./deploy.sh
```

---

## 日常更新流程

```bash
# 本地改 index.html → 推到 GitHub main
ssh lujie@81.71.143.128
cd ~/bumper && ./deploy.sh
```

`deploy.sh` 会打印 `页面 page=200  接口 rest=200`，两个都 200 才算发布成功。

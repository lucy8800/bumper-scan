# 保险杠扫码记录 · 腾讯云部署说明

> 文档版本：2026-11-25　|　对应前端版本：`2026-11-23 14:10`
> 服务器：`81.71.143.128`（腾讯云 · Ubuntu 24.04 LTS）
> 访问地址：**https://bumper.fat.plus:10443**
> 代码仓库：https://github.com/lucy8800/bumper-scan
> 运维文件：仓库 `deploy/` 目录（本文档即 `deploy/DEPLOY.md`）。**代码与部署配置统一由这个仓库管理，生产环境只跑在腾讯云这台机器上。**

---

## 1. 一句话结论

已经**完整跑起来了**：域名 + 正式 HTTPS 证书 + 三容器（nginx / PostgREST / PostgreSQL）全部在线，
Supabase 的历史数据（34 件、30 条记录）已迁入自建库，前端读写实测通过，证书到期自动续期，数据库每天自动备份。

| 验收项 | 实测结果 |
| --- | --- |
| 网页 | `200`，180,625 字节，云端地址已指向 `https://bumper.fat.plus:10443` |
| 图片与脚本 | `img/hanfront.jpg 200`、`vendor/supabase.js 200`、`vendor/qrcode.js 200` |
| 接口读 | `GET /rest/v1/bumpers` → `200`，件数 34 |
| 接口写 | `POST` 建件 `201`、建记录 `201`、`DELETE` `204`（测完已清理） |
| HTTPS | 证书校验通过，`CN=bumper.fat.plus`，签发者 `Let's Encrypt YE1`，到期 `2027-02-22` |
| 真机浏览器 | 首页「已同步」，记录页「全部记录 · 共 34 个码」，无 JS 报错 |

---

## 2. 架构

```
工业手机 / 电脑浏览器
        │  https (10443)
        ▼
┌──────────────────────────── 服务器 81.71.143.128 ────────────────────────────┐
│                                                                              │
│  ┌─────────────┐   静态页 + 反代   ┌──────────────┐   SQL    ┌────────────┐  │
│  │  web        │ ───────────────▶ │  api         │ ───────▶ │  db        │  │
│  │ nginx 1.27  │  /rest/v1/ →     │ PostgREST    │          │ PostgreSQL │  │
│  │ :80 :10443  │                  │ :3000(内网)  │          │ :5432(内网)│  │
│  └─────────────┘                  └──────────────┘          └────────────┘  │
│        │ 挂载                                                      │         │
│   site/ 发布目录                                            pgdata 数据卷    │
│   certs/ 证书    acme-webroot/ 证书验证                                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

- 前端仍然是**单文件静态页**，通过 `supabase-js` 走 REST（`/rest/v1/...`），没有自研后端代码。
- `PostgREST` 负责把 HTTP 请求翻成 SQL，权限模型用 `anon` 角色 + RLS 策略，**和原来 Supabase 那一套完全一致**，前端代码零改动。
- 为什么不用 443：按你的要求网页走 `10443`；`80` 只留给证书验证和跳转。

---

## 3. 服务器信息

| 项目 | 值 |
| --- | --- |
| 公网 IP | `81.71.143.128` |
| 系统 | Ubuntu 24.04 LTS（内核 6.8） |
| 规格 | 1 核 / 961MB 内存 / 40GB 磁盘（已用 16%） |
| 登录用户 | `lujie`（已在 `sudo`、`docker` 组） |
| SSH 私钥 | 本地 `_srvcfg/rsa_key/rsa_key_lujie`（**切勿外传**） |
| 域名 | `bumper.fat.plus` → A 记录 `81.71.143.128` |
| 端口 | 对外：`22`、`80`、`10443`；`5432`/`3000` **不对外暴露** |
| 时区 | 容器与数据库均为 `Asia/Shanghai` |

> 登录命令（本机 Git Bash 不可用，用 PowerShell）：
> ```powershell
> ssh -i <私钥路径> lujie@81.71.143.128
> ```
> 若在公司办公网被拦 22 端口，切手机热点即可。

---

## 4. 目录结构（`/home/lujie/bumper`）

```
~/bumper/
├── .env                  # 密钥：DB_PASSWORD / AUTH_PASSWORD / JWT_SECRET / ANON_KEY（权限 600，不进 git）
├── docker-compose.yml    # 三容器编排
├── src/                  # git clone 下来的仓库（只读，别手改）
├── site/                 # 发布目录（rsync 自 src + 注入云端地址，nginx 挂载这个）
├── gen_env.py            # 把 site/index.html 里的 url 与 anonKey 换成 .env 里的值
├── deploy.sh             # 一键更新（拉代码 → 同步 → 注入 → 语法自检 → 重载 → 自检）
├── backup.sh             # 每日备份，保留 14 天
├── backup/               # 备份产物 bumper-YYYY-MM-DD.sql.gz
├── db/
│   ├── 01-schema.sql     # 建表 + 索引 + RLS（首次初始化自动执行）
│   ├── 99-roles.sh       # 建 anon / authenticator 角色（自动执行）
│   ├── sql/99-roles.sql
│   └── import/10-import.sql   # Supabase 历史数据（手工执行一次，含生产数据，不进 git）
├── nginx/bumper.conf     # 站点配置（80 验证+跳转，10443 正式）
├── certs/                # fullchain.pem / privkey.pem（acme.sh 自动写入）
├── site.bak/             # 迁移前那一版发布目录，留着兜底，确认无问题后可删
└── acme-webroot/         # 证书验证用的隐藏目录
```

**为什么 `src` 和 `site` 要分两份**：仓库里的 `index.html` 连的是 Supabase（公开仓库不能放服务器密钥），
所以每次发布都要拷一份出来、把 `url` 和 `anonKey` 换成自建服务，再让 nginx 指向这份。`site/` 是**构建产物**，别在里面手改。

**运维文件的源头在仓库 `deploy/`**：上表里 `docker-compose.yml`、`nginx/`、`db/`、`deploy.sh`、`backup.sh`、`gen_env.py`
的权威版本都在仓库 `deploy/` 目录（`git clone` 后位于 `~/bumper/src/deploy/`），服务器上的这些文件是从那里拷过来的。
改配置请改仓库那份，再拷到 `~/bumper/`，不要只改服务器本地——否则下次重建就对不上了。
`deploy/` 已在 `deploy.sh` 的 rsync 排除列表里，不会被发布到 `site/` 对外暴露。
哪些文件故意不入库，见 [`README.md`](README.md) 的「敏感文件」一节。

---

## 5. 容器与端口

| 容器 | 镜像 | 端口映射 | 内存上限 | 作用 |
| --- | --- | --- | --- | --- |
| `bumper-web-1` | `nginx:1.27-alpine` | `80`、`10443` | 64m | 静态页 + 反代 `/rest/v1/` |
| `bumper-api-1` | `postgrest/postgrest:v12.2.3` | 仅内网 3000 | 96m | REST → SQL |
| `bumper-db-1` | `postgres:16-alpine` | 仅内网 5432 | 320m | 数据存储（卷 `bumper_pgdata`） |

三容器均 `restart: unless-stopped`，**服务器重启后自动拉起**。

---

## 6. 日常运维命令（覆盖 80% 场景）

```bash
cd ~/bumper

# 状态
docker compose ps

# 启停
docker compose up -d            # 全起
docker compose restart web      # 只重启网页
docker compose down             # 全停（数据卷保留）

# 日志
docker compose logs -f web      # 网页访问日志
docker compose logs -f api      # 接口日志（看 401/500）
docker compose logs --tail 100 db

# 进数据库
docker compose exec db psql -U postgres -d bumper
# 常用：\dt 看表；select count(*) from records;

# 手动备份 / 恢复
~/bumper/backup.sh
gunzip -c ~/bumper/backup/bumper-2026-11-24.sql.gz | docker compose exec -T db psql -U postgres -d bumper
```

---

## 7. 改完代码怎么发布

1. 本地改 `index.html`（或其它前端文件）；
2. 上传到 GitHub 仓库（覆盖同名文件即可，**不用**动 `deploy.sh` / `.env`）；
3. 登录服务器执行一条命令：

```bash
cd ~/bumper && ./deploy.sh
```

`deploy.sh` 做 6 步，末尾自带自检：

| 步骤 | 动作 |
| --- | --- |
| 1/6 | `git -C src pull --ff-only` 拉最新提交，并打印当前 commit |
| 2/6 | `rsync -a --delete` 同步到 `site/`（排除 `.git`、`.gitignore`、`deploy`），把 7 张示意图复制进 `site/img/` |
| 3/6 | `python3 gen_env.py` 注入 `https://bumper.fat.plus:10443` 与 anonKey |
| 4/6 | `docker compose config -q` + `nginx -t` 语法自检，配置有问题就停在这一步 |
| 5/6 | `nginx -s reload`（不断连接） |
| 6/6 | 自检输出 `页面 page=200　接口 rest=200` |

> **一次性动作**：仓库有了 `deploy/` 之后，旧版 `deploy.sh` 会把 `deploy/` 也同步进 `site/`（运维脚本变成可下载的静态文件）。
> 更新后第一次发布前，先执行一次：
> ```bash
> cd ~/bumper && cp src/deploy/ops/deploy.sh deploy.sh && chmod +x deploy.sh
> ```
> 之后正常 `./deploy.sh` 即可。

**回滚**：`git -C ~/bumper/src log --oneline` 找到上一个提交，然后
```bash
git -C ~/bumper/src checkout <提交号> && ~/bumper/deploy.sh
```

> 如果以后想让服务器自己改文件、再推回 GitHub，需要先配 Git 凭据（PAT）。目前是「本地改 → GitHub → 服务器拉」的单向流，最简单也最不容易出错。

---

## 8. HTTPS 证书（acme.sh）

- 工具：`acme.sh v3.1.7`（装在 `~/.acme.sh`），签发机构：**Let's Encrypt**，密钥类型 `ec-256`。
- 当前证书：`CN=bumper.fat.plus`，有效期 `2026-11-24 → 2027-02-22`。
- 证书落地：`~/bumper/certs/fullchain.pem` 与 `privkey.pem`，被 nginx 以只读方式挂载。
- **自动续期**：acme.sh 装了 cron，每天 5/11/17/23 点各检查一次；到期前 30 天左右自动续，续完自动执行
  `docker exec bumper-web-1 nginx -s reload`，不用人工干预。
- 续期的前提：**80 端口必须一直对外开放**（Let's Encrypt 走 HTTP-01，验证文件放在 `acme-webroot`）。

手动操作备用命令：

```bash
# 看证书还剩多久
openssl x509 -in ~/bumper/certs/fullchain.pem -noout -dates

# 强制重签（比如证书出问题）
~/.acme.sh/acme.sh --issue -d bumper.fat.plus --webroot /home/lujie/bumper/acme-webroot \
  --server letsencrypt --keylength ec-256 --force
~/.acme.sh/acme.sh --install-cert -d bumper.fat.plus --ecc \
  --key-file /home/lujie/bumper/certs/privkey.pem \
  --fullchain-file /home/lujie/bumper/certs/fullchain.pem \
  --reloadcmd "docker exec bumper-web-1 nginx -s reload"
```

> 注：`curl https://get.acme.sh | sh` 在本服务器取不到安装脚本（SSL 超时），所以是 `git clone acme.sh 源码` 后 `./acme.sh --install` 装的。

---

## 9. 备份

- 脚本：`~/bumper/backup.sh`（`pg_dump` + gzip，自动删 14 天前的）。
- 定时：`crontab` 每天 **02:30** 执行，日志追加到 `~/bumper/backup.log`。
- 产物：`~/bumper/backup/bumper-2026-11-24.sql.gz`（当前约 5KB）。

```bash
crontab -l                 # 看定时任务（应能看到 acme 的 4 条检查 + 1 条备份）
ls -lh ~/bumper/backup     # 看备份文件
```

**建议**：每月把 `backup/` 里的文件拉回本地电脑存一份（服务器挂了备份也就没了）。

---

## 10. 数据迁移现状与切换注意

| 项 | 情况 |
| --- | --- |
| 迁移方式 | Supabase REST 导出 → 生成 `db/import/10-import.sql`（`insert ... on conflict do nothing`，可重复执行） |
| 已迁数据 | `bumpers` 34 行、`records` 30 行 |
| 幂等 | `records.client_uid` 有唯一约束，重复导入不会产生重复记录 |
| 现在写入 | 前端已指向自建服务，**新扫码直接写自建库** |

⚠️ **两件事必须注意**：

1. **旧链接不要再用**。GitHub Pages 上那版 `index.html` 连的还是 Supabase。请只对外发 `https://bumper.fat.plus:10443`；
   建议到仓库 `Settings → Pages` 把 Pages 关掉，避免有人打开旧链接把数据写回 Supabase。
2. **如果要补迁 Supabase 后期新增的记录**：需要重新导出一份 SQL 覆盖 `db/import/10-import.sql`，再执行
   ```bash
   docker compose exec -T db psql -U postgres -d bumper -f /docker-entrypoint-initdb.d/import/10-import.sql
   ```

---

## 11. 排障速查

| 现象 | 先查什么 | 处理 |
| --- | --- | --- |
| 网页打不开 | `docker compose ps` | 容器没起 → `docker compose up -d` |
| 502 Bad Gateway | `docker compose logs api` | api 挂了或连不上库 → 看 api 日志里的连接串/密码 |
| 页面能开但显示「未配置/同步失败」 | 浏览器控制台看 `/rest/v1/` 状态码 | `401` → anonKey 与 `.env` 的 `JWT_SECRET` 不匹配，重跑 `./deploy.sh`；`404` → `/rest/v1/` 反代丢了 |
| 证书告警 | `openssl x509 ... -dates`、`crontab -l` | 过期就按第 8 节强制重签；确认 80 端口未被关 |
| 内存吃紧 / 容器被杀 | `free -m`、`docker stats` | 已设 mem_limit；1G 机器不要加多余服务 |
| 磁盘满 | `df -h`、`docker system df` | `docker image prune -f`；备份保留期调短 |
| 域名解析变了 | `ping bumper.fat.plus` | 改 DNS A 记录后记得重签证书 |

---

## 12. 安全须知

- `.env` 里有数据库密码与 JWT 密钥，权限 `600`，**绝不提交到 GitHub**。
- `5432`、`3000` 没有映射到宿主机，只能容器间访问。
- 数据库权限模型与 Supabase 一致：`anon` 角色可读写全部表（RLS 策略 `using(true)`）。这适合**车间内网/可信场景**，
  公网暴露时相当于「知道网址就能读写」。若要收紧，优先做：① nginx 加 Basic Auth；② 前端改成带登录换 JWT；
  ③ 把 `anon` 策略改成只读，写入走单独的 `writer` 角色。
- 腾讯云安全组只放行 `22 / 80 / 10443`，其它端口一律关闭。
- SSH 私钥只存在你本机，建议再给 `lujie` 关掉密码登录（`PasswordAuthentication no`）。

---

## 13. 已知小问题 / 待办

| 项 | 说明 |
| --- | --- |
| 仓库根目录有历史文件 | `package.json`、`check.html`、`supabase-schema.sql`，以及图片/js 在根目录和 `vendor/` 各存了一份，无害，可清理 |
| `site.bak/` | 迁移前的旧发布目录，观察一两周确认无问题后删除即可 |
| GitHub Pages | 建议关闭（见第 10 节） |
| 运维文件已入仓库 | 2026-11-25 起，`docker-compose.yml`、`nginx/bumper.conf`、`db/*`、`deploy.sh`、`backup.sh`、`gen_env.py` 的权威版本在仓库 `deploy/` 目录，服务器上的文件由其拷贝而来。4 类敏感文件（`.env`、`certs/`、`db/import/10-import.sql`、`~/.acme.sh/`）故意不入库，见 `README.md` |

---

## 14. 迁移当天做过的事（可追溯）

1. 盘环境：Ubuntu 24.04、git 2.43、Docker 27.5.1、Compose v2.32.4，40G 盘 / 961MB 内存。
2. 确认 Docker 镜像加速可用（`mirror.ccs.tencentyun.com`、`docker.1panel.live`），拉取 postgres / postgrest / nginx 三个镜像。
3. `git clone` 仓库到 `src/`，`rsync` 出 `site/`，`gen_env.py` 注入域名与 anonKey。
4. `docker compose up -d db` → 初始化建表、建角色；手工导入历史数据（34 件 / 30 条）。
5. 起 `api` + `web`，本机 curl 验证页面/图片/REST 全 200。
6. 外网侧验证 `80`、`10443` 可达 → 装 acme.sh → 签发 Let's Encrypt 证书 → 安装到 `certs/` 并 reload。
7. 本机做端到端验收：TLS 校验、REST 读、写入→查询→删除往返、浏览器实跑（已同步、34 个码）。
8. 落地 `deploy.sh`、`backup.sh`、每日备份 cron、favicon 204 小修。
9. 2026-11-25：运维文件整理成仓库 `deploy/` 目录入库（单个 commit `bd4acb97`），服务器 `src/` 拉取后即成为权威版本；`deploy.sh` 升级为 6 步并排除 `deploy/` 对外暴露。

# 服务端部署、备份与恢复

NianBox Server 独立于 Mac App 运行。需要 Mac 关机时仍可使用 Hermes，请部署到常开的 Linux 设备。macOS 客户端只需安装 App；服务端支持 Linux AMD64／ARM64。

## 启动服务

准备 Docker Compose、仓库中的 `compose.yaml` 与 `.env.example`。将 `.env.example` 复制为私有 `.env`，用下列命令生成令牌并填写 `NIANBOX_API_TOKEN`，设置文件权限 `chmod 600 .env`：

```sh
python3 -c 'import secrets; print(secrets.token_urlsafe(48))'
docker compose pull
docker compose up -d --no-build
docker compose ps
```

默认镜像为 `ghcr.io/takboo/nianbox:stable`，允许匿名拉取；应用数据持久化在 `nianbox-data` 命名卷，端口仅绑定 `127.0.0.1:8088`。Mac 与 Hermes 使用相同令牌；令牌至少 32 个非空白 ASCII 字符，留在私有环境中。将实际服务域名加入 `NIANBOX_ALLOWED_HOSTS`，不包含协议或端口。

服务以 UID/GID 10001 运行，根文件系统只读、移除 Linux capabilities，仅 `/data` 持久化。部署不需要源码构建、Python 或 Xcode。镜像使用锁定依赖与固定摘要的 Python 基础镜像；依赖升级需重建并重新部署。

## 网络与接入

推荐通过自己的 HTTPS 或私有网络访问。已安装并登录 Tailscale、启用 tailnet HTTPS 的常开主机，可执行：

```sh
tailscale serve --bg http://127.0.0.1:8088
```

使用 Serve 实际输出的 HTTPS URL。Tailnet ACL 仅允许自己的设备和 Hermes 主机访问，保留 Bearer 认证；不要开启 Funnel 或把 8000／8088 直接暴露到公网。自有 HTTPS 反向代理可参考 `deploy/Caddyfile.example`：代理在宿主上连接 loopback，TLS 在代理终止，保留适当防火墙规则。

Mac 设置填写服务根地址；Hermes 使用 `/mcp/`，详见[Hermes 接入](hermes.md)。REST 与 MCP 均需 `Authorization: Bearer <token>`；只有不含用户数据的 `/health` 免认证。服务校验 Host 并拒绝浏览器 Origin，不提供浏览器客户端或 CORS。代理日志不要记录认证头或任务正文。

## 升级与固定版本

[对应 Release](https://github.com/takboo/nianbox/releases) 提供同版本 DMG、SHA256SUMS 与完整镜像索引摘要。生产部署推荐把 `.env` 中的 `NIANBOX_IMAGE` 固定为该摘要：

```dotenv
NIANBOX_IMAGE=ghcr.io/takboo/nianbox@sha256:<release 中的索引摘要>
```

升级前备份、记录旧摘要，再修改镜像引用并运行 `docker compose pull`、`docker compose up -d --no-build`。检查健康与已认证的数据读取，保留旧卷。`stable` 只由完整版本发布提升；`:main` 随开发主线变化。发布机制见[发布流程](releases/README.md)。

二进制回退时使用旧摘要，保留现有卷并先核对数据兼容性。客户端与服务端都升级到 0.3.0 或以上后，才能依赖游标历史摘要保护；首次升级不能追溯验证升级前的区间。恢复与换服需要先对账，不能清空队列或游标来消除错误。

本地源码镜像仅用于开发或明确需要的部署：

```sh
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

## 备份

使用 SQLite online backup，保证包含 WAL 中已提交的数据。以下文件名仅为示例，每次选择新名字；命令拒绝覆盖已有备份或导出：

```sh
docker compose exec server python -m nianbox backup /data/backup-2026-10-24.sqlite
docker compose cp server:/data/backup-2026-10-24.sqlite ./backup-2026-10-24.sqlite
docker compose exec server python -m nianbox export /data/export-2026-10-24.json
docker compose cp server:/data/export-2026-10-24.json ./export-2026-10-24.json
```

将副本安全保存在另一台设备。SQLite 备份是完整恢复格式，包含变更历史、墓碑与幂等回执。JSON 导出适合查看和迁移用户数据，不等于完整数据库备份。直接复制正在写入的主 `.sqlite` 文件可能漏掉 WAL 数据。

## 恢复

先停止写入与服务，保留原数据卷。向**新卷**恢复备份，验证后再切换客户端。示例中日期、备份路径与卷名需要按本次恢复替换：

```sh
docker compose stop server
docker volume create nianbox-restored-20261024
docker run --rm --user 0 \
  -v nianbox-restored-20261024:/restore \
  -v "$PWD/backup-2026-10-24.sqlite:/backup.sqlite:ro" \
  python:3.12-slim python -c 'from pathlib import Path; import shutil,os; p=Path("/restore/nianbox.sqlite"); assert not p.exists(); shutil.copyfile("/backup.sqlite",p); os.chown(p,10001,10001); os.chown("/restore",10001,10001)'
```

创建忽略的 `restore.override.yaml`：

```yaml
services:
  server:
    volumes:
      - nianbox-restored:/data
volumes:
  nianbox-restored:
    external: true
    name: nianbox-restored-20261024
```

执行 `docker compose -f compose.yaml -f restore.override.yaml up -d --no-build`。确认健康、事项数量、完成历史、墓碑与已认证 MCP，保留旧卷供回退；回退时先停恢复服务，再不用 override 启动原卷。升级或恢复均不使用 `docker compose down -v`。

旧备份可能让 Mac 游标领先，或重新使用同一序列号。客户端分别以 `cursor_ahead`、`history_diverged` 暂停，保留本机数据与队列，先导出并核对缺失区间。数据库身份变化也会暂停；换服是数据迁移，不能仅改设置继续上传旧缓存。令牌轮换需同步更新服务端、Mac 与 Hermes，不改变任务数据。

## Mac 本地数据

Settings → Export local data 导出事项、历史、墓碑及全部待同步／阻塞条目，不含 API 令牌。远端已删除事项的保留文字可人工恢复为新 UUID，旧墓碑不会复活。

完整本机备份需先退出 App，再复制整个 `NianBox` Application Support 目录及附属文件。沙盒 App 通常使用 `~/Library/Containers/org.nianbox.NianBox/Data/Library/Application Support/NianBox/`；无沙盒开发进程使用 `~/Library/Application Support/NianBox/`。同版本停止运行时整体恢复，先保留当前目录副本，并沿用原服务 URL／数据库身份。降级或换服前先导出对账。

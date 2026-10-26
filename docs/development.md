# 开发指南

先读根目录 [AGENTS.md](../AGENTS.md)，按[文档索引](README.md)选择需要的契约。README 面向产品使用者，开发命令集中在本文。

## 环境与构建

需要可构建 macOS 14 目标的 Xcode、Ruby 3.2+、Bundler 4、Python 3.12 与 uv。当前本地验证使用 Xcode 26.3、Ruby 3.4.11；CI 环境以工作流为准。用 `xcode-select -p` 确认开发工具路径；同时装有 Command Line Tools 时，可为命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
bundle install
bundle exec ruby Scripts/generate_project.rb
bundle exec ruby Scripts/verify_project_generation.rb
xcodebuild build -project NianBox.xcodeproj -scheme NianBox \
  -configuration Release -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

生成器是项目目标、文件引用、版本与签名的来源。只生成 NianBox、NianBoxTests、NianBoxUITests 三个 macOS 目标；生成后运行校验。免费临时签名即可构建，保留应用沙盒与已有文件／网络能力。

## 提交前检查

在仓库根目录执行：

```sh
uv sync --project Server --locked --python 3.12
(cd Server && uv run pytest -q)
python3 Scripts/check_version.py
bundle exec ruby Scripts/verify_project_generation.rb
xcodebuild test -project NianBox.xcodeproj -scheme NianBox \
  -destination 'platform=macOS' -derivedDataPath .local/DerivedData \
  -only-testing:NianBoxTests CODE_SIGNING_ALLOWED=NO
git diff --check
```

构建与单元测试在宿主保持非交互。单元测试环境使用内存库并跳过全局快捷键、角落监测和服务连接。交互测试发出真实系统输入，先读 [VM 测试流程](macos-vm-testing.md)。验证记录写入[当前验证](verification.md)，注明源提交与产物身份；旧日志不作为新构建通过的依据。

GitHub CI 的 `container-toolchain` 任务实际运行固定 SHA 的 QEMU、Buildx 与 GHCR 登录 Action，使用只读权限构建带 provenance／SBOM 的 AMD64／ARM64 OCI 归档，并核对导出的架构。该任务不推送镜像；发布任务同时等待它、原生服务端检查和 macOS 检查通过。维护 Docker Action 时同步检查冒烟、publish 与 release 中的引用，保留 QEMU 缓存关闭设置。

同步修改另验证持久化队列重开、写入幂等、并发重试、墓碑与删除冲突。`Scripts/hermes_smoke.py` 和 `Scripts/verify_sync.sh` 使用合成凭据连接隔离服务，方法见 [Hermes 集成验证](hermes.md#集成验证)。容器修改可运行 `Scripts/verify_container.py IMAGE`；它只操作自己创建的临时容器和卷。

## 本地服务开发

```sh
cd Server
uv sync --locked --python 3.12
# 在私有环境中设置 NIANBOX_API_TOKEN（至少 32 位）与 NIANBOX_DB。
uv run uvicorn nianbox.app:create_app --factory \
  --host 127.0.0.1 --port 8088 --no-access-log
```

真实部署与恢复读[部署指南](deployment.md)，协议或持久化修改读[同步契约](sync.md)。数据目录使用 NianBox 命名空间；测试使用内存库或独立合成数据库，保留用户存储。

## 版本与上游维护

版本统一来自 `VERSION`，服务端包与锁文件、发布说明和生成项目需同步更新，详见[发布流程](releases/README.md)。

本仓库保留 Peekaboo 的 Git 历史。维护上游改进时逐项审阅 macOS 交互补丁；本分支已替换旧移动端／CloudKit 数据契约，直接套用上游生成器会重新引入不适用的目标和能力。上游 remote 是否存在以 `git remote -v` 为准。

`.local/` 保存可复用 VM、工具、构建和原始验收结果，不进入版本控制；清理时先确认归属与是否仍被使用。旧设计过程和验收流水账从[归档](archive/README.md)按需追溯。

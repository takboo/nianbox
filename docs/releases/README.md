# 发布流程

用户授权发布后执行。当前版本读取根目录 `VERSION`；已发布产物、镜像摘要与校验值以对应 [GitHub Release](https://github.com/takboo/nianbox/releases) 为准，本文不缓存可变标签的摘要。

## 准备版本

1. 更新 `VERSION`、`Server/pyproject.toml`、`Server/nianbox/__init__.py`，刷新 `Server/uv.lock`，添加 `docs/releases/vVERSION.md`。
2. 运行项目生成器与 `Scripts/check_version.py`，确保 App、服务端与发布说明版本一致。构建号由生成器管理。
3. 按[开发指南](../development.md)运行服务端测试、项目生成校验与相关 macOS 测试。改动记录与真实验收范围更新到[验证记录](../verification.md)。
4. 构建并检查 Universal DMG；交互与安装验收在[隔离 VM](../macos-vm-testing.md)中完成。准备干净提交后核对远程 main，正常推送；为该固定提交创建新的 `vX.Y.Z` 标签，保留已有标签。

## 自动发布的完成条件

版本标签触发完整 CI：原生 Linux AMD64／ARM64 测试及受限容器检查、macOS 单元测试、Universal DMG 构建与校验。macOS 任务检查双架构、签名、沙盒能力、Applications 链接与 Finder 布局，再上传 DMG 和 SHA256SUMS 到草稿 Release。

检查通过后构建同版本服务端镜像，附 revision、provenance 和 SBOM。最后任务验证实际下载的镜像与草稿 DMG，公开 Release，并将同一个镜像索引提升为 `stable` 和 `vX.Y.Z`。只有以下条件全部成立才报告发布完成：

- 标签工作流全部成功，Release 已公开且源码提交匹配。
- 正式下载的 DMG 与 SHA256SUMS 匹配，Universal 架构、签名和沙盒校验通过。
- 镜像 `X.Y.Z`、`vX.Y.Z`、`stable` 指向同一摘要，包含 Linux AMD64 与 ARM64。
- 已验证正式下载与固定版本的对应关系；记录哪些交互验收使用本地候选、哪些使用正式产物。

常规 main 推送只更新 `:main` 与 commit 标签，不移动 `stable`。失败可能留下草稿或未提升的版本镜像，它们不代表发布完成。优先重跑失败任务；已公开的源码标签和 DMG 保持不变。Release 已公开但 stable 提升失败时重跑最后任务，并重新核对三个摘要。旧版本不可使 stable 倒退。

## 本地打包

从仓库根目录运行，选择未存在的输出目录；打包器拒绝覆盖 DMG：

```sh
python3 -m venv .local/packaging-venv
.local/packaging-venv/bin/python -m pip install -r Scripts/dmg-requirements.txt
NIANBOX_PACKAGING_PYTHON="$PWD/.local/packaging-venv/bin/python" \
  bash Scripts/build_release.sh
```

`Scripts/build_release.sh` 非交互构建临时签名的双架构 App、生成 DMG 并校验布局。公开构建未通过 Apple 公证；发布说明保留首次打开的系统提示。Gatekeeper 首次下载决定、物理 Intel、多屏与人类体验验收分别记录，不能用构建通过替代。

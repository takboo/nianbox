# 文档索引

安装与产品介绍从[念匣首页](../README.md)开始，英文入口为 [README.en.md](../README.en.md)。这里维护现行操作与工程契约；版本与依赖以 `VERSION`、锁文件和工作流为准。

| 需要做什么 | 阅读入口 |
| --- | --- |
| 使用面板、快捷键、草稿与状态栏 | [使用指南](usage.md) |
| 部署、升级、备份与恢复数据 | [部署指南](deployment.md) |
| 配置 Hermes、验证 MCP 接入 | [Hermes 接入](hermes.md) |
| 构建、测试、维护上游与生成项目 | [开发指南](development.md) |
| 修改同步协议、离线队列或冲突处理 | [数据与同步契约](sync.md) |
| 运行交互验收、使用隔离测试桌面 | [macOS VM 测试](macos-vm-testing.md) |
| 核对当前结果、产物与未验证范围 | [验证记录](verification.md) |
| 打版本、生成 DMG、发布镜像 | [发布流程](releases/README.md) |
| 修改图标与导出资源 | [图标说明](../Branding/README.md) |

## 当前资料与历史快照

现行事实以本索引所列文档为准。各版本的用户可见改动保留在 `releases/v*.md`，发布产物、校验值与镜像摘要以对应 [GitHub Release](https://github.com/takboo/nianbox/releases) 为准。

[历史归档](archive/README.md)保留固定提交下的验收与环境记录。旧计划、失败记录、临时路径和当时的授权仅用于追溯，不构成当前任务；当前任务范围来自用户指令。

`.ignore` 将 `docs/archive/` 排除出普通 `rg` 搜索。需要追溯时显式使用 `rg --no-ignore docs/archive`。`.local/`、`vendor/`、构建目录和测试结果属于忽略的本地产物，可能来自旧提交；接手时先核对记录中的提交与摘要，重新执行当前变更需要的检查。

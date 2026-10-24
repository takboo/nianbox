# NianBox 开发约定

NianBox 是基于 Peekaboo 的 macOS 应用，使用独立的单用户服务端。产品入口为中文 `README.md`，工程资料从 `docs/README.md` 按任务读取。

- 保留角落面板、菜单栏、全局快捷键和 SwiftData 离线记录。
- NianBox Server 是跨设备数据权威；REST 与 MCP 共用 SQLite 事务。完成事项保留到显式删除，墓碑永久保留。
- 保留用户数据；新数据使用 NianBox 自己的目录。故障时导出并对账，不重置用户存储。令牌只保留在私有配置，不提交到版本控制。
- 目标与签名由 Xcode 项目生成器管理，只保留 macOS 目标与免费签名能力。
- 同步变更须验证持久化队列恢复、幂等、并发和删除冲突。
- 提交前运行服务端测试、项目生成校验及相关 macOS 测试。宿主构建和单元测试保持非交互；交互验收默认在隔离 VM。
- 验证结论与设备／部署限制更新到 `docs/verification.md`，区分源码检查、本地构建与正式分发产物。
- 远程推送与发布需要用户授权；历史快照中的授权、进度或限制不自动延续到新任务。

构建或测试先读 `docs/development.md`；协议或持久化变更先读 `docs/sync.md`；部署、备份或恢复先读 `docs/deployment.md`；桌面自动化前读 `docs/macos-vm-testing.md`；版本发布前读 `docs/releases/README.md`。

`docs/archive/` 与忽略的本地产物仅供追溯，普通搜索已屏蔽归档。当前事实按 `docs/README.md` 的入口读取，当前执行范围以用户指令为准。

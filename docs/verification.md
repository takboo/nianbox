# 当前验证范围

更新于 2026-10-24。本文只维护当前交付范围与证据入口；各轮过程、失败记录和旧发布摘要见[历史归档](archive/README.md)。正式分发的提交、DMG 校验与镜像摘要以 [0.3.0 Release](https://github.com/takboo/nianbox/releases/tag/v0.3.0) 及其标签工作流为准。

## 本次范围

0.3.0 包含原生菜单栏图形与真实生命周期反馈、独立本地保存／服务端同步确认、静默空轮询、减少动态效果、跨 Tasks／Backlog 草稿恢复，以及丢失写入回执后与远端新编辑一致的收敛。服务端修复截止时间过滤、MCP SQLite 锁等待阻塞，增加整数边界与游标历史摘要校验。

文档改为中文产品首页与英文对应入口，开发操作移入工程文档；旧验收流水账归档并从普通搜索排除。未改变用户存储与认证令牌。

## 检查记录

| 检查 | 结果与依据 |
| --- | --- |
| 服务端回归 | 26 项通过，`.local/v030-server-tests.log` |
| macOS 单元测试 | 77 项通过，`.local/v030-native.xcresult` |
| 版本与生成项目 | 0.3.0 版本一致；确定性生成与 macOS-only 目标校验通过，`.local/v030-project-generation.log` |
| 文档相对链接与归档屏蔽 | 19 份 Markdown、82 个相对链接／资源／锚点通过；普通 `rg` 不包含归档 |
| Universal DMG | 0.3.0 本地候选构建、签名、双架构、沙盒与 DMG 布局通过，`.local/v030-package.log`；正式分发由标签 CI 独立构建 |
| 原生 VM | 0.3.0 候选八项全通过，干净源码 `1bf01a9`，`.local/v030-vm-candidate-evidence/`；另有 `013ddcd` 的原生状态栏补验 |
| 真实 HTTP 与 MCP | 本次已安装 Hermes 六工具重验通过，`.local/v030-hermes.log`。功能源码 `013ddcd`：提交写入后丢弃响应、再通过 MCP 更新，Mac 重试后保留最新标题与备注才报告 Synced；已安装 Hermes 原生客户端六工具与磁盘往返通过 |

0.3.0 本地候选 DMG SHA-256：`76cb2c319f81d314d69159ffd4d0b425bbb3b7453d966ecf577a2eb43431f4c8`；执行文件 SHA-256：`f9b2a205f588e0ad2ae521f0adcf6d3952d9d087f6a350310955931f2132fc8e`。VM 结果中的源提交、App、probe 与 controller 均已核对。正式包由标签 CI 另行构建，不能混用两组摘要。

宿主环境为 macOS 15.7.9、Xcode 26.3；原生 VM 为 macOS 15.7.7／VirtualMac2,1。`013ddcd` 原始记录见 `.local/final-native.xcresult`、`.local/server-full.log`、`.local/http-sync-roundtrip.log`、`.local/hermes-live.log`、`.local/vm-acceptance-evidence/` 与 `.local/vm-menu-evidence/`。这些是固定历史构建的证据，不代表新包自动通过；旧完整摘要见归档。

## 兼容与未验证范围

- 未提交草稿仅保留在进程会话内；提交后的记录与 outbox 才具有跨重开的原子持久化保证。
- 历史摘要需要新版客户端与服务端配合；旧非零游标不能追溯校验首次升级前区间。缺少必要标准快照的旧缓存会暂停并保留请求，而非重置后宣称成功，详见[同步契约](sync.md)。
- `dueAt` 只存储与展示时间，尚无本地提醒调度。
- Universal 含 Intel slice 不等于物理 Intel 运行通过。物理多屏／Spaces／混合 DPI、VoiceOver、登录启动、真实手机渠道与目标常开 HTTPS 部署仍需对应环境验收。
- 公开构建为临时签名，未获 Apple 公证。VM 内 SSH 传入的安装包没有浏览器下载的 quarantine，不能证明 Gatekeeper 首次下载体验。
- VM 为原生功能验收，未执行完整 XCUITest；测试不操作宿主桌面、不替换宿主 App。宿主供电的 VM 不能证明关机后的服务可用性。

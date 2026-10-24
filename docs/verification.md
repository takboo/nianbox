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
| Universal DMG | 本地候选与正式 Actions 包分别通过构建、签名、双架构、沙盒与布局检查；正式下载 SHA256SUMS 一致，`.local/v030-public-dmg-check.json` |
| 原生 VM | 候选八项通过；正式包八项及原生状态栏补验全部通过，干净发布源码 `94a2491`，`.local/v030-vm-public-evidence/`；39 份证据／驱动文件与客体哈希一致 |
| 真实 HTTP 与 MCP | 已安装 Hermes 原生六工具重验通过，`.local/v030-hermes.log`、`.local/v030-hermes-release.log`；正式包完成 Hermes → 服务端 → VM → REST 往返。丢失回执与并发编辑回归包含在本次单元测试中，原始 HTTP 故障复核见归档 |
| 发布 CI | [0.3.0 标签工作流](https://github.com/takboo/nianbox/actions/runs/40045331785)全部成功，包含原生 Linux AMD64／ARM64、macOS、镜像发布与实际容器验证；Release 已公开 |
| 匿名分发 | 公开下载与已测 DMG 字节一致；`0.3.0`、`v0.3.0`、`stable` 索引摘要一致且均包含 Linux AMD64／ARM64，`.local/v030-public-release/distribution.json` |

0.3.0 本地候选 DMG SHA-256：`76cb2c319f81d314d69159ffd4d0b425bbb3b7453d966ecf577a2eb43431f4c8`；执行文件 SHA-256：`f9b2a205f588e0ad2ae521f0adcf6d3952d9d087f6a350310955931f2132fc8e`。VM 结果中的源提交、App、probe 与 controller 均已核对。正式包由标签 CI 另行构建，不能混用两组摘要。

正式分发固定身份（与上面的本地候选分别记录）：

| 产物 | 身份 |
| --- | --- |
| 源码标签 | `v0.3.0` → `94a2491af75087bf394baf5bbcda2e6b4f047669` |
| 正式 DMG SHA-256 | `89ce3e36887e7456dc9a181364fdbd4886ee39518293e0d775461fcc1590f8b7` |
| 正式 App 执行文件 SHA-256 | `29f4561dfeae7871f46c117f90d8dde0e2cac727be0aff0fb2751629cd65687e` |
| 发布时镜像索引 | `ghcr.io/takboo/nianbox@sha256:5305f9650220a9df2b7d69eb04709a230c53d5460d55606be6f99d19505380df` |

宿主环境为 macOS 15.7.9、Xcode 26.3；原生 VM 为 macOS 15.7.7／VirtualMac2,1。正式包 VM 报告位于 `.local/v030-vm-public-evidence/`，身份清单位于 `.local/v030-vm-public-sha256.txt`，客体原件保留在 `~/nianbox-testing/v030-github/`。服务端测试只有三条依赖弃用警告，无失败。

发布后已删除生成的客体／宿主测试凭据、关闭隔离服务与 tunnel、停止自有 VM；保留数据盘、合成历史和证据。工作区回到 main。更早的固定构建结果只从归档追溯，不用旧包的通过记录替代本次正式包。

## 兼容与未验证范围

- 未提交草稿仅保留在进程会话内；提交后的记录与 outbox 才具有跨重开的原子持久化保证。
- 历史摘要需要新版客户端与服务端配合；旧非零游标不能追溯校验首次升级前区间。缺少必要标准快照的旧缓存会暂停并保留请求，而非重置后宣称成功，详见[同步契约](sync.md)。
- `dueAt` 只存储与展示时间，尚无本地提醒调度。
- Universal 含 Intel slice 不等于物理 Intel 运行通过。物理多屏／Spaces／混合 DPI、VoiceOver、登录启动、真实手机渠道与目标常开 HTTPS 部署仍需对应环境验收。
- 公开构建为临时签名，未获 Apple 公证。VM 内 SSH 传入的安装包没有浏览器下载的 quarantine，不能证明 Gatekeeper 首次下载体验。
- VM 为原生功能验收，未执行完整 XCUITest；测试不操作宿主桌面、不替换宿主 App。宿主供电的 VM 不能证明关机后的服务可用性。

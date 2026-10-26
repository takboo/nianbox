# 当前验证范围

更新于 2026-10-26。本文只维护当前交付范围与证据入口；各轮过程、失败记录和旧发布摘要见[历史归档](archive/README.md)。正式分发的提交、DMG 校验与镜像摘要以 [0.3.0 Release](https://github.com/takboo/nianbox/releases/tag/v0.3.0) 及其标签工作流为准。

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

## 已合并的 checkout 升级 #2 — 2026-10-26

[PR #2](https://github.com/takboo/nianbox/pull/2) 已于北京时间 2026-10-26 12:54 合并为 `7dfd971b540756b6b93fc12f840ddf80465470e1`，只修改 `ci.yml` 中四处 checkout 引用。publish 固定到 v7.0.1 的完整 SHA `3d3c42e5aac5ba805825da76410c181273ba90b1`；其他三个 job 保留主版本标签写法。本次 main 日志确认已执行的 `@v7` 引用解析到同一 SHA。

跨版本兼容性按[固定版本上游说明](https://github.com/actions/checkout/blob/3d3c42e5aac5ba805825da76410c181273ba90b1/README.md)核对：v5 使用 Node 24，要求 runner ≥ 2.327.1；v6 将持久化凭据移到 `$RUNNER_TEMP`，容器 Action 内的认证 Git 操作要求 runner ≥ 2.329.0；v7 默认限制 `pull_request_target`／`workflow_run` 事件中的 fork PR 检出。已读取的 Linux AMD64、macOS 与 publish 日志均为 runner 2.338.0。当前只用 `push`／`pull_request`，没有读取 `.git/config` 凭据或在容器 Action 内执行认证 Git 的自定义步骤，Docker 构建使用 `./Server` 本地上下文；未发现这些变更造成的不兼容。

合并后的 [main 工作流 40271448067](https://github.com/takboo/nianbox/actions/runs/40271448067)全部应运行的 job 成功：Linux AMD64／ARM64 服务端检查与受限容器验证、macOS 项目生成及单元测试、实际双架构镜像发布。AMD64 日志为 26 项服务端测试通过；macOS 日志为 77 项通过。三个已读取 job 的 checkout 与清理步骤也均成功。发布日志确认 `:main` 与 `:sha-7dfd971b540756b6b93fc12f840ddf80465470e1` 已推送，索引摘要为 `sha256:9e705545da74ede00f40883ab91813387d46367fca3075b4158efe4ae9364fd7`；此处依据远端日志，未重新拉取验证镜像。

结论：保留 #2，无需回退。当前工作流通过 Actionlint。标签专用的 DMG 构建、Release 与 stable 提升在此 main 运行中跳过，不能将此前 0.3.0 标签流程的通过结果视为 checkout v7 的验证；下次标签发布需单独核对。本次仅审查既有运行，未触发远端任务、发布或修改工作流，也未重跑本地应用测试。

## Dependabot Actions 实施前审查 — 2026-10-26

本地 `codex/nianbox-macos` 从 `5c9e2f2` 快进到 `origin/main` 的 `7dfd971b540756b6b93fc12f840ddf80465470e1`，包含 0.3.0 与已合并的 checkout v7 升级。保留原分支；本地旧 `main` 仍跟踪 `upstream/main`，更新本 fork 应显式指定 `origin/main`。

| PR | 审查时 head | 升级 | 该 head 的 Actions 检查 |
| --- | --- | --- | --- |
| [#1](https://github.com/takboo/nianbox/pull/1) | `5954ebe87c0c15653f89d18eee66700bc100b737` | setup-uv v6 → v7 | [Linux 双架构与 macOS 成功](https://github.com/takboo/nianbox/actions/runs/40271632342)；publish／release 跳过 |
| [#4](https://github.com/takboo/nianbox/pull/4) | `9086bea970ac35d27ee1bfeab5521a778c732cc8` | setup-qemu 3.7.0 → 4.4.0 | [Linux 双架构与 macOS 成功](https://github.com/takboo/nianbox/actions/runs/40271610069)；publish／release 跳过 |
| [#5](https://github.com/takboo/nianbox/pull/5) | `61a703f795b6164e0929454ff44cb91c9a05d1c5` | setup-buildx 3.12.0 → 4.4.1 | [Linux 双架构与 macOS 成功](https://github.com/takboo/nianbox/actions/runs/40271615005)；publish／release 跳过 |
| [#6](https://github.com/takboo/nianbox/pull/6) | `85fed15623c26421c7659aebde2cc86a2e6e4340` | login 3.7.0 → 4.7.0 | [Linux 双架构与 macOS 成功](https://github.com/takboo/nianbox/actions/runs/40271630831)；publish／release 跳过 |

审查时四个 PR 均可合并、只改 `ci.yml` 中对应的 Action 引用；没有评审、讨论或未解决行内线程。逐一与远端分支比对，四份工作流及组合后的候选均通过 Actionlint 1.7.12；0.3.0 版本一致性与 `git diff --check` 通过。候选文件保留于忽略目录 `.local/dependabot-review-20261026/`。

新版 Action 均使用 Node 24。Docker v4 要求 runner ≥ 2.327.1；当前全部为 GitHub 托管 runner。按目标版本的 `action.yml` 核对，现用参数仍受支持，QEMU 的 `platforms: arm64`、`cache-image: false` 与 Docker Action 的完整 SHA 固定均保留。setup-uv v7 移除的 `server-url` 未被使用，安装的 uv 仍固定为 0.7.13。上游依据：[setup-uv v7](https://github.com/astral-sh/setup-uv/releases/tag/v7.0.0)、[QEMU v4](https://github.com/docker/setup-qemu-action/releases/tag/v4.0.0)、[Buildx v4](https://github.com/docker/setup-buildx-action/releases/tag/v4.0.0)、[login v4](https://github.com/docker/login-action/releases/tag/v4.0.0)。

当时建议先接受 #1；其 Linux 安装路径已有实际 CI 证据，但标签专用的 DMG 路径未执行。#4／#5／#6 没有发现接口不兼容，原 PR 绿灯却没有执行升级后的 Docker Action，因此先补 GitHub runner 上的只读登录与 `push: false` 双架构冒烟检查，再逐项合并并核对 main 的 publish。无需为依赖升级打新版本；main 合并会发布 `:main`／提交镜像，只有版本标签流程才提升 `stable`。

上述为实施前审查快照，表中的旧 PR 检查不替代升级后的实际 Action 验证；实施结果见下节。

## Actions 升级实施 — 2026-10-26

本轮完成 #1、#4、#5、#6，并通过 [#7](https://github.com/takboo/nianbox/pull/7) 补充 `container-toolchain` CI：直接使用目标 SHA，安装 ARM64 QEMU、创建 Buildx、以 `contents: read`／`packages: read` 登录 GHCR，执行 `push: false` 的双架构构建并检查 OCI 归档中的平台。保留 provenance／SBOM，关闭 QEMU 镜像缓存与冒烟任务的 Buildx 二进制缓存。publish 增加对此任务的依赖；三个 Docker Dependabot PR 随后逐项更新 publish／release 引用。静态核对确认冒烟、publish 与 release 的相关 SHA 一致；QEMU 共两处，Buildx 与 login 各三处。

提交前本地检查：Python 3.12.11／uv 0.7.13 下 26 项服务端测试、77 项 macOS 单元测试、确定性项目生成、版本一致性、Actionlint 1.7.12 与差异空白检查通过。宿主 Xcode 为 26.2。系统 Ruby 2.6.10 配合仓库既有 `.local/gems` 直接运行生成校验通过；CI 的 Ruby 3.4／Bundler 检查另由工作流执行。初次沙箱内 Xcode 检查因 SwiftData 宏插件失败，沙箱外非交互重跑通过；没有运行 UI 自动化或改动用户存储。证据位于 `.local/dependabot-implementation-20261026/` 的 `server.log`、`native-unsandboxed.log` 与 `native-unsandboxed.xcresult`。初始失败结果也保留。

| PR | 合并提交 | 远端结果 |
| --- | --- | --- |
| [#1](https://github.com/takboo/nianbox/pull/1) setup-uv v7 | `ccae3da` | [main 检查及镜像发布通过](https://github.com/takboo/nianbox/actions/runs/40278014918) |
| [#7](https://github.com/takboo/nianbox/pull/7) 工具链冒烟 | `8c60abd` | [PR 冒烟、原生双架构与 macOS 检查通过](https://github.com/takboo/nianbox/actions/runs/40278448772) |
| [#4](https://github.com/takboo/nianbox/pull/4) QEMU 4.4.0 | `6147604` | [main 检查及镜像发布通过](https://github.com/takboo/nianbox/actions/runs/40278854672) |
| [#5](https://github.com/takboo/nianbox/pull/5) Buildx 4.4.1 | `eb11142` | [main 检查及镜像发布通过](https://github.com/takboo/nianbox/actions/runs/40279452369) |
| [#6](https://github.com/takboo/nianbox/pull/6) login 4.7.0 | `43a5f94` | [main 检查及镜像发布通过](https://github.com/takboo/nianbox/actions/runs/40279948726) |

先合并 #1；#7 的实际只读登录与双架构导出通过后合并 #7／#4，#4 的 main 发布成功后合并 #5，#5 的 main 发布成功后合并 #6。#5／#6 在 Dependabot 自动重基后也分别通过了新冒烟检查。#7 的独立 main 运行由后续 #4 main 取代；其 PR 证据及 #4 起完整 main 证据分别保留。

最终发布源码为 `43a5f94b19a2793eb2f9301f53fceaf333d88b8f`。发布日志及独立匿名 Registry 查询确认，`:main` 与 `:sha-43a5f94b19a2793eb2f9301f53fceaf333d88b8f` 的索引摘要均为 `sha256:035ac1ead7acd08a27a0cd9b1cd8bc90fcca19121980e16f628f4f07c50d846f`。索引包含 Linux AMD64／ARM64，两种架构的配置标签均匹配该源码提交；已校验索引、manifest 与 config 的内容摘要。`stable` 实施前后均为 0.3.0 的 `sha256:5305f9650220a9df2b7d69eb04709a230c53d5460d55606be6f99d19505380df`，没有提高产品版本或创建版本标签。结构化证据见 `.local/dependabot-implementation-20261026/actions-results.json`、`stable-before.json`、`registry-final.json`。

本轮只改 Actions 与工程文档。原生服务端容器运行由对应 CI 检查覆盖；最终 Registry 复核只检查公开索引／配置身份，没有把最终镜像重新下载运行。标签专用的 DMG／Release／stable 提升未执行，仍需在下一次版本发布核对；没有新增物理设备、UI 或实际部署验收。

## 兼容与未验证范围

- 未提交草稿仅保留在进程会话内；提交后的记录与 outbox 才具有跨重开的原子持久化保证。
- 历史摘要需要新版客户端与服务端配合；旧非零游标不能追溯校验首次升级前区间。缺少必要标准快照的旧缓存会暂停并保留请求，而非重置后宣称成功，详见[同步契约](sync.md)。
- `dueAt` 只存储与展示时间，尚无本地提醒调度。
- Universal 含 Intel slice 不等于物理 Intel 运行通过。物理多屏／Spaces／混合 DPI、VoiceOver、登录启动、真实手机渠道与目标常开 HTTPS 部署仍需对应环境验收。
- 公开构建为临时签名，未获 Apple 公证。VM 内 SSH 传入的安装包没有浏览器下载的 quarantine，不能证明 Gatekeeper 首次下载体验。
- VM 为原生功能验收，未执行完整 XCUITest；测试不操作宿主桌面、不替换宿主 App。宿主供电的 VM 不能证明关机后的服务可用性。

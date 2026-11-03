# 当前验证范围

更新于 2026-11-03。当前正式版本为 [0.4.0](https://github.com/takboo/nianbox/releases/tag/v0.4.0)，包含复制、Homebrew 与应用内更新提醒。本文分别保留实现阶段候选、既有功能验收和正式分发证据；当前发布结论见“0.4.0 正式发布”一节。各轮过程与旧发布摘要见[历史归档](archive/README.md)，先前 0.3.0 的固定身份仍在其对应记录中。

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

## 复制改进本地候选 — 2026-11-03

实施前执行 `git fetch --all --prune`：工作区干净，`codex/nianbox-macos` 与 `origin/main` 同为 `40d29db877d7e109b7267c5ed28c53b68aa9e478`，ahead／behind 为 0／0；Peekaboo `upstream/main` 为 `54c23bf`，已包含其全部提交，本分支领先 24 个提交。没有待合入的上游变更，也未执行推送或发布。

本地工作区新增悬停复制、事项选中与上下键导航、列表焦点下的系统 Copy 命令，以及完整备注浮层。菜单提供标题与完整备注、仅标题、Markdown 三种格式；成功反馈约两秒后清除。源码中将列表复制限制在列表焦点、非标题编辑、非备注浮层状态，并在开始录入／编辑、切换分组、筛选隐藏或删除后清除相关选择；浮层打开期间锁定面板自动收起。数据模型、用户存储和同步协议未改。

| 检查 | 结果与依据 |
| --- | --- |
| 服务端回归 | Python 3.12.8／uv 0.7.13，26 项通过，三条依赖弃用警告；`.local/copy-improvements-20261103/server.log` |
| macOS 单元测试 | 88 项通过，含 11 项新增复制与交互状态测试；完整备注和格式、独立剪贴板写入、键盘 ItemProvider 实际载荷、筛选／删除后的选中恢复、浮层锁定及连续反馈覆盖；`native-final.log`、`native-final.xcresult` |
| 项目生成与静态检查 | 使用既有 `.local/gems` 的 xcodeproj 1.27.0 重新生成并通过确定性／macOS-only／免费签名能力校验；版本仍为 0.3.0；Python 驱动语法与 `git diff --check` 通过；`project-generation.log` |
| UI 测试编译 | `build-for-testing` 通过，新增一键复制粘贴、上下键选中复制和搜索框文字复制用例，更新三种菜单名称；`build-for-testing.log`。仅编译，未执行 XCUITest |
| 本地 Release 候选 | `arm64`／`x86_64` 构建与临时签名通过，`codesign --verify --deep --strict` 通过，保留沙盒、网络客户端和用户选择文件三项既有 entitlement；`release-build.log` |

以上证据均在 `.local/copy-improvements-20261103/`。宿主为 macOS 15.8.1、Xcode 26.2；初次沙箱内构建被 SwiftData 宏插件限制阻止，保留 `native-initial.log`／`.xcresult`，沙箱外非交互重跑通过。单元测试使用内存数据库与独立命名剪贴板，不写宿主通用剪贴板或发送桌面输入。

本地候选 App 位于 `.local/CopyReleaseDerivedData/Build/Products/Release/NianBox.app`，执行文件 SHA-256 为 `26487761a3ea200f075a247c472f6cfd78f1582d17ec97a66ab5714ee393dc0d`；源码为上述基线加本轮未提交改动，文件摘要见 `source-manifest.json`。它不是正式分发产物，未生成 DMG、安装到 `/Applications`、启动宿主 App、提高版本或创建标签。

首轮本地构建时缺少文档记录的 `.local/vm-tools/` 与 `.local/tart/`，当时未执行隔离 VM 交互验收；后续已重新准备环境并完成下节补验。上述首轮结果仍只代表本地构建，不能与后续固定候选或旧正式包的 VM 结果混用。

## 复制交互隔离 VM 补验 — 2026-11-03

重新下载并核对 Tart 2.41.1 的发布归档 SHA-256，使用文档固定 digest 创建本仓库专用 `nianbox-lifecycle-test`。客体为 macOS 15.7.7／VirtualMac2,1、2 CPU、4096 MiB，最终实际逻辑桌面为 1440×1080、1x。使用默认 NAT 与严格 host key 校验的任务专用 SSH，关闭宿主剪贴板、目录、音频和 USB 共享；未连接真实服务器、使用生产令牌或操作宿主 App。

原开发分支继续保留未提交改动。在忽略目录创建独立干净 Git 快照 `f4cb29409972fe729ec0cb371264a648d5daceed`，对应工作区基线仍为 `40d29db877d7e109b7267c5ed28c53b68aa9e478`；从快照构建并传入签名 Universal 候选。最终执行文件 SHA-256 为 `aae721f943c94c81735cd03da8a65bbb13a77e7db0d888f38c5a840ba6191295`，本地产物在 `.local/copy-vm-20261103/DerivedData-r3/Build/Products/Release/NianBox.app`，完整归档与工具身份见 `.local/copy-vm-20261103/identity-r3.json`。

本轮实际定位并修复了浮层父容器的无障碍标识覆盖关闭按钮标识的问题：增加独立的无障碍分组，保留子控件标识。修复前浮层仍然可见，完整复制已成功，但 AX 树中关闭按钮错误继承父标识，原断言失败；修复后同一交互用例通过。另修正测试驱动在点击隐藏的复制按钮前缺少真实悬停的步骤，并补充右键菜单、客体剪贴板、滚动与局部文字选择断言。没有改动数据模型、存储路径或同步协议。

在正常启动模式下验证复制与浮层行为，最终控制器没有使用 `--only`，完整十项均通过：

| 交互 | 最终结果 |
| --- | --- |
| 一键复制与菜单 | 悬停后实际点击；标题＋完整长备注、仅标题、Markdown、真实右键菜单通过；中文、空行、缩进、链接与末尾标记完整；成功反馈可见 |
| 键盘与焦点 | 从 Finder 直接点击非激活面板后 `⌘C` 正常，上下键切换目标；搜索／零匹配搜索／录入／标题编辑中的选中文字复制正常 |
| 备注浮层 | 局部选择 `COPY-NOTES` 的真实键盘复制、滚动至末尾、仅备注全文复制、按钮复制整条内容、关闭按钮、鼠标离开时保持打开、关闭后自动收起及角落重开均通过 |
| 原有七项 | 录入／状态／菜单／完成历史、原生拖动顺序、跨标签草稿、长标题换行、搜索、默认全局快捷键／角落／磁盘重开、自定义快捷键／冲突／取消／持久化／停用／恢复默认全部通过 |

客体原件位于 `~/nianbox-testing/copy-r3/acceptance-full-r3/`；宿主副本位于 `.local/copy-vm-20261103/acceptance-full-r3/`。取回的 41 份报告、UI 树和截图逐份与客体 SHA-256 一致，见 `evidence-sha256.json`；20 张截图已检查，其中完整复制反馈、局部选择、末尾滚动和关闭后重开另作原图检查。报告中的干净快照提交、App 执行文件、probe 源码和控制器哈希均与宿主身份清单一致。早期失败及 r2 定向修复复测保留在同目录对应的日志和证据子目录。

环境问题分别留证：基础镜像实际使用 1024×768 HiDPI 桌面，不能只依赖 Tart 配置中的尺寸；已在客体用 CoreGraphics 显示配置事务设置并读取确认 1440×1080。客体 CLT 6.1.2 缺少 SwiftData 宏插件，probe 与快捷键 holder 在客体编译，夹具工具从同一模型源码在宿主编译后仅在客体执行。夹具仅在新库中播种两条合成事项，已有库会拒绝写入；后续回归复用并保留它，未重置存储。初轮截图出现客体 sshd-session 屏幕录制提示，未自动批准；最终截图未遮挡被测界面。没有修改宿主权限、TCC 数据库或系统保护。

修复后宿主 88 项 macOS 单元测试、26 项服务端测试、项目生成校验、版本一致性、驱动语法与差异检查通过；日志位于 `.local/copy-vm-20261103/` 的 `native-final.log`／`.xcresult`、`server-final.log`、`project-generation-final.log`。最终双架构构建与 `codesign --verify --deep --strict` 通过，源自干净快照的签名候选仍为 0.3.0。本轮是原生 AX＋客体 CoreGraphics 功能验收，未执行完整 XCUITest，也未验证 VoiceOver、物理 Intel、多显示器／Spaces、真实人类操作、正式下载的 Gatekeeper 或网络同步。没有生成正式 DMG、推送、打标签或发布。

取回并核对证据后，结束本轮自己的 App 并停止 VM；保留磁盘、固定基础镜像、SSH identity、合成数据库、夹具 JSON 与原始证据供复用。复现步骤见[隔离 VM 流程](macos-vm-testing.md#复制与备注验收)。

## Homebrew 与应用内更新提醒 — 2026-11-03

按用户选定的免费、自用范围实施：本仓库的 `Casks/nianbox.rb` 同时提供自建 tap，固定到真实公开的 Universal DMG；没有新增独立远程仓库。应用提供菜单栏／Settings 手动检查、默认开启且可关闭的每日后台检查、角落面板与菜单中的新版入口，以及 Homebrew 升级命令复制。后台只在 App 运行期间判断到期，失败尝试也按 24 小时间隔节制请求，手动检查可立即重试。只接受公开稳定版及官方 DMG 地址，按数值比较版本；检查不读取服务端令牌、不发送事项内容。没有引入 Sparkle、下载替换、自动执行 Homebrew、自动重启或付费签名能力。

Cask 当前仍指向公开的 0.3.0，DMG SHA-256 为 `89ce3e36887e7456dc9a181364fdbd4886ee39518293e0d775461fcc1590f8b7`。维护命令 `Scripts/update_homebrew_cask.py` 实际下载公开 Release 元数据、SHA256SUMS 与 DMG，校验摘要后在本地确定性生成 Cask，拒绝倒退版本，不提交或推送。Cask 没有自更新声明、quarantine 绕过、强制覆盖、自动退出或用户数据清理脚本。公开的旧 0.3.0 包不含本轮新增提醒，须等新版本正式发布后安装。

| 检查 | 结果与证据 |
| --- | --- |
| macOS 单元测试 | 100 项通过，包含 12 项新增版本边界、稳定版／官方地址筛选、缓存、离线／限流、重开节流、手动检查、开关持久化、并发合并与真实 URLSession 请求契约测试；`native-final.log`、`native-final.xcresult` |
| 服务端与 Cask 维护 | 26 项服务端通过、三条既有依赖弃用警告；4 项 Python Cask 测试通过，真实公开 0.3.0 Cask `--check` 通过；`server.log`、`cask-public-final.log` |
| Homebrew 实际操作 | 客体 Homebrew 7.0.7 的 12 步通过，包括 Cask 样式、公开 0.2.0 安装 → 0.3.0 升级、签名／双架构校验、卸载、相同 App 的 `--adopt`、再次卸载和临时 tap 清理；`homebrew-r2/results.json` 及逐步日志 |
| 包管理数据保留 | 原合成数据库及偏好共 4 个文件在包管理操作前后逐份 SHA-256 相同；公开 0.3.0 安装后的执行文件为 `29f4561dfeae7871f46c117f90d8dde0e2cac727be0aff0fb2751629cd65687e`，与既有正式包身份相符 |
| 原生 VM 完整回归 | 11 项全部通过：本轮更新提醒，加此前复制／备注三项与原有七项；`acceptance-full-r4/results.json`。没有使用 `--only`，未连接服务器夹具 |
| 更新提醒 UI | 实际菜单栏检查入口、新版 Release 链接与面板提示、命令复制、关闭自动检查后的手动检查、已最新／失败状态、草稿保留、进程重开后的开关持久化通过。模拟新版为 99.0.0，未打开其下载页；25 张最终截图已检查 |
| 真实 GitHub API | 非交互编译生产 `GitHubReleaseClient`／解析逻辑，使用无认证请求实际取得并接受公开 0.3.0；`live-api.json`。与确定性 UI 夹具、离线／限流单元测试分别记录 |
| 工程与构建 | 确定性 macOS-only 项目生成、版本 0.3.0 一致性、Cask Ruby 语法、Python 驱动语法、Actionlint 1.7.12 与差异空白检查通过；最终双架构 Release 与严格签名校验通过，保持既有三项 entitlement |

证据根目录为 `.local/install-updates-20261103/`。Homebrew 检查使用本地干净快照 `6f0ce65f98ba0d366ec5accee197fcc89d9bd5aa`；最终 UI 使用干净快照 `fe0fbbd16d194bc0577e00cd3d55f350ee5e8c39`。后者的 Cask、维护脚本和包管理驱动与前者逐字节一致。根开发分支基线仍是 `40d29db877d7e109b7267c5ed28c53b68aa9e478`，保留此前复制改动及本轮未提交代码，没有推送或发布。

最终候选位于 `.local/install-updates-20261103/DerivedData-r4/Build/Products/Release/NianBox.app`，执行文件 SHA-256 为 `532e3e27beb50d76afaa39efc8a1490b63f26bce7acd0110c76c5fed2a99261c`，源／归档／工具身份见 `identity-r4.json`。客体原件位于 `~/nianbox-testing/install-updates-r2/homebrew-r2/` 和 `~/nianbox-testing/install-updates-r4/acceptance-full-r4/`；取回的 64 份报告、日志、UI 树与截图逐份和客体 SHA-256 匹配，见 `evidence-sha256.json`。UI 报告中的源提交、App、probe 源码与控制器身份均已独立核对。

本轮修正了 Homebrew 样式检查指出的最低系统声明，使用 `macos: :sonoma`；初始失败和修复复测均保留。一次完整回归在重开 Settings 时未命中开关，截图显示客体 Tips 自动打开且 Settings 尚未打开；相同产品候选原样重跑通过。为避免持久化检查依赖无关应用的首次鼠标焦点，该复测步骤改用 AX 语义动作，首次菜单栏入口仍用实际鼠标输入；最终完整回归通过，没有据此修改或宣称修复产品焦点逻辑。

宿主 macOS 15.8.1／Xcode 26.2；客体继续为 macOS 15.7.7／VirtualMac2,1、2 CPU、4096 MiB、1440×1080。包管理检查与 UI 检查顺序执行，避免数据库比对期间有 App 写入。公开包只做安装／升级／文件检查，未启动它来绕过 Gatekeeper，因此包管理升级不等于首次下载启动、真实凭据访问或跨版本数据库运行验收。当前候选实际 UI 使用 AX＋客体 CoreGraphics，未执行完整 XCUITest；真实人类／VoiceOver／物理 Intel／多屏／浏览器首次下载仍按既有限制记录。

本轮未修改签名方式、Hardened Runtime 或系统保护，也未请求宿主桌面权限。取回证据后，确认自己的 App 结束、包管理的 App 和临时 tap 已移除，再停止本轮启动的 VM；磁盘、SSH identity、合成数据库及证据继续保留。远端 tap 命令须在本轮 Cask 改动经授权推送后才可用，提醒功能须随新的正式版本分发；当前完成的是本地实现与验收。使用和维护步骤见[安装与更新](installation.md)。

## 0.4.0 发布准备 — 2026-11-03

用户已在本轮明确授权推送与发布。实施前刷新 origin／upstream 后，本地基线与 `origin/main` 仍同为 `40d29db877d7e109b7267c5ed28c53b68aa9e478`，公开最新版本为 0.3.0，0.4.0 标签尚未存在。版本统一提高到 0.4.0，生成器管理的构建号为 3；服务端只有版本元数据变化，锁文件保留现有格式与全部依赖固定值。

提交前的最终 0.4.0 源码检查：100 项 macOS 单元测试、26 项服务端测试、4 项 Cask 维护测试、locked 依赖同步、确定性项目生成、版本一致性、Actionlint 与 `git diff --check` 全部通过。证据位于 `.local/release-v040-20261103/` 的 `native.log`／`native.xcresult`、`server.log`、`server-sync.log`、`project-generation.log`。此前 0.3.0 工作版本的候选及 VM 结果分别保留于上节，不能代替本次最终产物。

从干净提交 `dc72341c47b596e219914deae0811a593334a9aa` 构建并检查了本地 0.4.0 Universal DMG，候选 SHA-256 为 `30c3351f975711f68461dc905b8ba416ee6f5c8455a0a6c460bfd6b093ae6852`。用户随后明确要求不重复已经完成的整套功能验收，因此取消本轮重复 VM 回归，复用此前已通过的功能结果；最终版本元数据、正式安装包与分发身份单独核对。Cask 在 0.4.0 正式 DMG 公开前保持 0.3.0，公开后才按实际摘要提升。

## 0.4.0 正式发布 — 2026-11-03

已按本轮授权推送 main 并发布新的 `v0.4.0` 标签，固定源提交为 `dc72341c47b596e219914deae0811a593334a9aa`。首次标签 CI 在已完成测试、DMG 构建后，因 GitHub 创建 Release 草稿接口返回 HTTP 500 失败；创建同目标的草稿并只重试失败 job 后，[标签工作流第二次尝试](https://github.com/takboo/nianbox/actions/runs/41603946175)全部成功，未改动源提交或移动标签。[main 工作流](https://github.com/takboo/nianbox/actions/runs/41603938737)也已成功。

| 正式分发检查 | 结果与身份 |
| --- | --- |
| Release | [0.4.0 已公开](https://github.com/takboo/nianbox/releases/tag/v0.4.0)，非草稿、非预发布，targetCommitish 与上述标签提交一致 |
| 正式 DMG | 匿名下载 `NianBox-0.4.0-universal.dmg` 与 SHA256SUMS、GitHub 资源摘要一致；SHA-256 为 `d7012fefd7a18c770f0c5b21909a97172b2d7f6d9ccd246dc83ce1738ef3496d` |
| DMG 结构 | 实际下载包的版本 0.4.0、bundle ID、arm64／x86_64、临时签名、三项既有沙盒 entitlement、Applications 链接与布局检查通过；仍未公证 |
| 服务端镜像 | `0.4.0`、`v0.4.0`、`stable` 均为 `sha256:0149d866c1d62512f6448c02a910072c81d2bd3efc83dbd9a4584d158bebaade`；匿名 Registry 查询及内容摘要校验通过 |
| 镜像源码与架构 | 两个 Linux 架构 manifest/config 的内容摘要有效，包含 AMD64／ARM64；revision 均为标签源提交，version label 按 workflow 为 `v0.4.0`。实际容器运行由标签 CI 完成，本地未重复启动容器测试 |
| Homebrew | 正式包公开后才用维护脚本下载、校验并生成 0.4.0 Cask；固定 DMG 地址和上述正式 SHA-256，4 项维护测试与 Ruby 语法通过。Cask 与本节发布记录随后以单独元数据提交推送，不改正式源码标签或 DMG |

正式检查证据位于 `.local/release-v040-20261103/`：`tag-ci-final.json`、`main-ci.json`、`release-state.json`、`public/`、`public-dmg-check.json`、`registry-final.json`、`cask-update.log`。本地候选与正式 CI 包字节不同，分别记录，不混用摘要。根工作区的功能源码在版本准备前与上一轮通过全部验收的清单一致；本次产品变更只提高版本／构建号，没有新增功能逻辑。

按照用户要求，本轮没有重跑完整 VM 功能或 Homebrew 安装／升级回归；沿用上节 11 项功能验收、12 步包管理验收，并保留各自固定源码与候选身份。正式包本轮覆盖的是下载、结构、身份和分发检查，不能称为正式包完整 UI 验收或 Gatekeeper 首次下载启动验收。未部署到用户服务器，未改用户存储、签名方案或系统保护；本轮启动后取消重复验收的自有 VM 已停止，数据与既有证据保留。

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

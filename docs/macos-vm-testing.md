# 隔离 macOS VM 验收

交互检查会发送真实鼠标与键盘事件，默认在独立 VirtualMac 客体执行。宿主只做非交互构建、单元测试与打包。旧机器与旧验收产物从[归档](archive/README.md)追溯，不能把其当时状态作为当前可用性依据。

## 当前可复用环境

本仓库 task-owned 环境存放在忽略目录 `.local/`：

| 项目 | 值 |
| --- | --- |
| Tart | `.local/vm-tools/tart.app/Contents/MacOS/tart`，2.41.1 |
| 数据根 | `TART_HOME="$PWD/.local/tart"`，同时设置 `TART_NO_AUTO_PRUNE=1` |
| 测试 VM | `nianbox-lifecycle-test` |
| 固定基础镜像 | `ghcr.io/cirruslabs/macos-sequoia-base@sha256:eee659985b01e4df2a6c0754bd8d25e54969933c43fdcd4edef8bea337b3d354` |
| 客体 | macOS 15.7.7／VirtualMac2,1，2 CPU、4096 MiB、1440×1080 |
| 客体工具 | Swift 6.1.2 Command Line Tools，无完整 Xcode／XCUITest runtime |
| SSH | `.local/vm_ed25519` 与 `.local/vm-known-hosts`，严格核对 host key |

这些路径仅在该工作区准备过；新机器先核对是否存在。VM 的实际运行状态以 `tart list` 为准，发现其他任务正在使用时先协调，保留磁盘和基础镜像。

2026-11-03 已按上述固定版本与镜像重新准备本任务独立 VM，Tart 发布归档 SHA-256 为 `e680a734febccfce7d4e910c1f7f13fc3b00f19a181c945e2d746de3214c32c2`。客体沿用表中系统与资源配置。不能只依据 `tart get` 判断逻辑分辨率：本次基础镜像实际保留了 1024×768 的 HiDPI 模式，即使 Tart 配置显示 1440×1080。先在客体用 `swift -e 'import AppKit; print(NSScreen.screens.map { $0.frame })'` 核对；本次已通过客体 CoreGraphics 显示配置事务永久设为 1440×1080 的 1x 模式，并再次读取确认。固定角落坐标的驱动须在匹配的逻辑分辨率下运行。

## 启动与连接

从仓库根目录执行：

```sh
export TART_HOME="$PWD/.local/tart"
export TART_NO_AUTO_PRUNE=1
.local/vm-tools/tart.app/Contents/MacOS/tart list
.local/vm-tools/tart.app/Contents/MacOS/tart run nianbox-lifecycle-test \
  --no-graphics --no-audio --no-clipboard --no-usb-accessories
```

在另一个终端用相同环境执行 `tart ip nianbox-lifecycle-test` 获取当次 NAT 地址，不能假设旧 IP。连接使用 task-local SSH identity、known-hosts 和 StrictHostKeyChecking，不开放宿主剪贴板、共享目录或桌面输入。当前宿主 macOS 15 使用默认 NAT；Tart 的 host-only 模式要求更新的宿主系统。

## 固定产物验收

1. 从干净提交导出 Git source bundle，构建签名的 Universal App 或 DMG，记录源提交与 SHA-256。经 SSH 传入客体 `~/nianbox-testing/` 的新目录；从 bundle 检出固定源、验证干净状态、App 签名与摘要。
2. 从同一源码传入 `Scripts/vm_ui_probe.swift`、`Scripts/vm_ui_smoke.py`、`Scripts/vm_shortcut_holder.swift`，核对哈希，在客体编译。probe 与 controller 都会拒绝物理 Mac，controller 也拒绝与已有 NianBox 进程混用。
3. 在客体目录执行，使用新的输出目录：

   ```sh
   swiftc -parse-as-library vm_ui_probe.swift -o probe
   swiftc -parse-as-library vm_shortcut_holder.swift -o shortcut-holder
   python3 vm_ui_smoke.py --app NianBox.app --probe probe \
     --source source --output acceptance-RUN --shortcut-holder shortcut-holder
   ```

4. 网络往返检查先用[Hermes 测试](hermes.md#集成验证)创建合成凭据与未完成事项。将 mode-0600 夹具放入 NianBox 自己的 guest sandbox，通过 SSH reverse forward 仅从客体 loopback 访问隔离服务，追加 `--fixture /absolute/guest/path.json`。服务仍需 Bearer 认证；测试不编辑真实 Hermes profile 或调用手机渠道。
5. 取回 results.json、UI 树和截图，核对源／App／驱动身份及每项断言，逐一检查截图。结果中明确区分本地候选与正式 Release 下载；本地产物通过不能自动等同于公开包通过。
6. 结束自己的 App、服务与 tunnel，只删除生成的凭据。保留 VM、测试历史与原始证据；若 VM 由本次启动且无人接用，执行 `tart stop nianbox-lifecycle-test`，确认停止。

无网络夹具时运行七项，包含快捷键 holder；加夹具后共八项：录入／菜单／历史、原生拖动、草稿跨标签恢复、长标题、搜索、默认快捷键／角落／磁盘重开、自定义快捷键／冲突／持久化，以及 Hermes → 服务端 → 面板完成 → REST 确认。`--only CHECK_NAME` 可用于诊断，完整验收不使用过滤。

## 复制与备注验收

`--copy-fixture /absolute/guest/copy-fixture.json` 增加三项正常启动模式检查：悬停一键复制／完整备注／三种菜单格式／真实右键菜单；从 Finder 点击非激活面板后的 `⌘C`、上下键选择与搜索／录入／标题编辑的文字复制；备注浮层局部文字复制、长内容滚动、完整复制、关闭及自动收起恢复。与上述无网络七项一起运行共十项；只有传入网络夹具才再增加 Hermes 往返。复制断言读取的是客体通用剪贴板，不开启宿主剪贴板共享。

首次准备复制夹具时使用新建的专用 VM。可以先以 `NIANBOX_UI_TESTING=1` 启动并结束自己的候选 App，以建立沙盒目录而不创建磁盘库。`Scripts/vm_copy_fixture.swift` 随后在客体 App 沙盒中创建两条合成离线事项，包含中文、空行、缩进、链接、长备注与末尾标记；只要数据库已存在就拒绝写入。已有数据库而没有对应夹具时应新建独立 VM，不删除或重置原库。

客体只有 Command Line Tools，缺少 SwiftData 宏插件。`probe` 与 `shortcut-holder` 仍在客体从固定源码编译；夹具工具在宿主从同一固定源码非交互编译，传入客体并核对哈希后执行：

```sh
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  Scripts/vm_copy_fixture.swift NianBox/Models/TaskItem.swift \
  NianBox/Models/TaskTypes.swift NianBox/Models/SyncRecord.swift \
  NianBox/Services/PersistenceController.swift -o seed-copy-fixture
# 仅在客体内执行；拒绝物理 Mac 与已有数据库。
./seed-copy-fixture > copy-fixture.json
python3 source/Scripts/vm_ui_smoke.py --app NianBox.app --probe probe \
  --source source --output acceptance-NEW --shortcut-holder shortcut-holder \
  --copy-fixture /absolute/guest/copy-fixture.json
```

保留夹具 JSON、合成数据库与已执行的工具身份，后续直接复用，不重复播种。复制测试先于其他正常模式测试执行，并通过标题前缀筛选保留的测试历史。开发工作区尚未提交时，可以在忽略目录中创建独立的干净 Git 快照并构建其候选；记录原工作区基线、快照提交与 App 哈希，不把该快照称为主分支提交或正式发布。

## Homebrew 与更新提醒验收

包管理检查使用 `Scripts/vm_homebrew_smoke.py`，只允许 VirtualMac；要求客体已有合成数据库，且没有已安装的 `/Applications/NianBox.app`、正在运行的 NianBox 或同名 tap。它从传入的固定源码添加仅属于本轮的本地 tap，用真实公开旧版安装包安装，再用当前 Cask 升级，检查签名和双架构，卸载后以相同 App 测试 `--adopt`。全程不启动公开安装包；每次操作前后比较离线数据库与偏好文件 SHA-256。最后只卸载本轮自己的 App 并移除本轮 tap，保留数据和证据。不覆盖已有客体 App 或 tap，也不使用 `--force`／`--no-quarantine`。

在宿主先向一个新文件生成旧版 Cask，并将它和固定源码传入客体。示例：

```sh
python3 Scripts/update_homebrew_cask.py --release v0.2.0 --output .local/nianbox-older.rb
# 以下在客体执行，output 必须是新目录。
python3 source/Scripts/vm_homebrew_smoke.py --source source \
  --older-cask nianbox-older.rb --output homebrew-NEW
```

包管理升级通过不等于 Gatekeeper 首次下载启动通过，也不代表实际运行了旧版／新版数据库迁移。需要首次启动验收时在客体遵循正常系统流程单独记录，不通过脚本绕过保护。

原生 UI 控制器的 `--update-fixture /absolute/guest/path.json` 增加一项更新提醒检查：真实菜单栏 Check for Updates…、新版链接、角落面板提示、Homebrew 命令复制、后台检查开关持久化、手动检查、已最新状态、失败状态和草稿保留。该路径应是本轮创建的沙盒内测试文件，例如 `~/Library/Containers/org.nianbox.NianBox/Data/Library/Application Support/NianBox/update-testing/release.json`；先创建父目录。控制器会写入模拟的公开 Release 元数据并检查链接，不打开模拟下载页、不安装或重启 App。生产模式不读取该环境变量，也不能通过它更改真实更新 API。与复制夹具和原有七项一起运行共十一项：

```sh
python3 source/Scripts/vm_ui_smoke.py --app NianBox.app --probe probe \
  --source source --output acceptance-NEW --shortcut-holder shortcut-holder \
  --copy-fixture /absolute/guest/copy-fixture.json \
  --update-fixture /absolute/guest/sandbox/update-testing/release.json
```

与包管理的数据保留检查顺序执行，避免其他 App 进程同时写入被比对的数据库或偏好。真实公开 GitHub API 连通与解析、断网／限流／版本边界的单元测试，以及 UI 中的确定性夹具结果分别记录。

## 权限与验证边界

客体需要 Accessibility／事件投递权限。缺失时只在客体正常授权，不修改 TCC 数据库或系统保护，不请求宿主桌面权限。截图可能出现 guest sshd-session 的屏幕录制对话框；记录是否影响被测界面，不能静默批准系统提示。

这是原生 AX 与客体 CoreGraphics 输入的功能验收，不能称为完整 XCUITest。真实人类操作、多屏／Spaces／混合 DPI、Intel 硬件、VoiceOver、首次浏览器下载的 Gatekeeper 决定、真实手机 Hermes 和常开部署分别验证。当前结果集中在[验证记录](verification.md)。

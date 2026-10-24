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
   swiftc vm_shortcut_holder.swift -o shortcut-holder
   python3 vm_ui_smoke.py --app NianBox.app --probe probe \
     --source source --output acceptance-RUN --shortcut-holder shortcut-holder
   ```

4. 网络往返检查先用[Hermes 测试](hermes.md#集成验证)创建合成凭据与未完成事项。将 mode-0600 夹具放入 NianBox 自己的 guest sandbox，通过 SSH reverse forward 仅从客体 loopback 访问隔离服务，追加 `--fixture /absolute/guest/path.json`。服务仍需 Bearer 认证；测试不编辑真实 Hermes profile 或调用手机渠道。
5. 取回 results.json、UI 树和截图，核对源／App／驱动身份及每项断言，逐一检查截图。结果中明确区分本地候选与正式 Release 下载；本地产物通过不能自动等同于公开包通过。
6. 结束自己的 App、服务与 tunnel，只删除生成的凭据。保留 VM、测试历史与原始证据；若 VM 由本次启动且无人接用，执行 `tart stop nianbox-lifecycle-test`，确认停止。

无网络夹具时运行七项，包含快捷键 holder；加夹具后共八项：录入／菜单／历史、原生拖动、草稿跨标签恢复、长标题、搜索、默认快捷键／角落／磁盘重开、自定义快捷键／冲突／持久化，以及 Hermes → 服务端 → 面板完成 → REST 确认。`--only CHECK_NAME` 可用于诊断，完整验收不使用过滤。

## 权限与验证边界

客体需要 Accessibility／事件投递权限。缺失时只在客体正常授权，不修改 TCC 数据库或系统保护，不请求宿主桌面权限。截图可能出现 guest sshd-session 的屏幕录制对话框；记录是否影响被测界面，不能静默批准系统提示。

这是原生 AX 与客体 CoreGraphics 输入的功能验收，不能称为完整 XCUITest。真实人类操作、多屏／Spaces／混合 DPI、Intel 硬件、VoiceOver、首次浏览器下载的 Gatekeeper 决定、真实手机 Hermes 和常开部署分别验证。当前结果集中在[验证记录](verification.md)。

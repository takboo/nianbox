# 安装、升级与更新提醒

念匣提供 Universal DMG 和本仓库维护的 Homebrew Cask，适用于 macOS 14+ 的 Apple Silicon 与 Intel Mac。两种方式使用同一份公开 Release DMG。Cask 固定版本和 SHA-256，不会安装未发布的 main 分支构建；源码中的新功能须等对应版本发布后才进入安装包。

## Homebrew

本仓库同时作为自建 tap，无需另建仓库。安装命令：

```sh
brew tap takboo/nianbox https://github.com/takboo/nianbox
brew install --cask takboo/nianbox/nianbox
```

升级前保存草稿并退出念匣，再执行：

```sh
brew update
brew upgrade --cask takboo/nianbox/nianbox
```

已经通过 DMG 安装的用户可以用 `brew install --cask --adopt takboo/nianbox/nianbox` 尝试接管；Homebrew 只接管与待安装产物完全一致的 App。若拒绝接管，保留现有 App 与记录，先核对版本和来源，不使用强制覆盖来忽略差异。

普通卸载使用 `brew uninstall --cask takboo/nianbox/nianbox`。Cask 只管理 App，不声明删除用户数据、Keychain 令牌或整个沙盒目录的清理步骤；本地记录、待同步更改与配置保留。重新安装后继续使用原有数据库。

本构建仍使用免费临时签名，未通过 Apple 公证。Homebrew 保留 quarantine 和系统安全检查，不执行清除 quarantine、关闭 Gatekeeper、修改 SIP 或自动批准提示的脚本。首次打开的系统提示与 DMG 安装相同，可核对来源后在系统设置中查看“仍要打开”。

## 应用内更新提醒

菜单栏的 Check for Updates… 会打开 Settings 并立即检查；Settings 顶部的 App updates 提供相同操作。发现更新时，角落面板底部、Settings 和菜单栏显示新版入口，打开对应版本的 GitHub Release 页面查看说明和下载；不弹出打断录入的窗口。Settings 还提供可复制的 Homebrew 升级命令。

Automatically check for updates 默认开启，可随时关闭，选择会保留到下次启动。后台在启动及运行期间检查是否到期，两次尝试至少间隔 24 小时；手动检查不受间隔与开关限制。网络失败和 GitHub 限流只显示状态，可手动重试；此前已确认的更新信息会保留。测试模式不执行生产后台请求。

更新检查只向固定的公开 GitHub Release API 发送无认证 GET，不读取自托管服务器令牌，不发送事项内容。只接受本仓库已公开、非预发布、具有对应 Universal DMG 的版本，按数字比较版本；不会推荐降级，也不会打开响应中提供的其他站点。

本阶段仅提醒与跳转，不下载或替换 App、不执行 Homebrew 命令、不重启应用；检查失败或发现新版均不改变草稿、离线记录、同步队列或服务器部署。手动安装新版前请保存未提交草稿。0.4.0 起提供更新检查；更早版本需要先手动安装一次。

## 发布后维护 Cask

正式 Release 公开且产物验证完成后，在仓库根目录执行：

```sh
python3 Scripts/update_homebrew_cask.py --release vX.Y.Z
python3 Scripts/update_homebrew_cask.py --release vX.Y.Z --check
```

也可省略 `--release` 检查 GitHub 标记为 latest 的公开版本。维护命令校验发布状态、官方固定下载地址、实际下载的 DMG、SHA256SUMS 和 GitHub 提供的资源摘要，然后生成确定性的 Cask；拒绝草稿、预发布、缺失或损坏产物，以及把现有 Cask 改回旧版。命令只修改本地文件，不提交、推送或发布。审阅差异后按用户授权推送，Homebrew 用户下次 `brew update` 才会获得新定义。

Cask 当前可以落后于开发中的 `VERSION`，它始终代表已公开的版本；不要在公开 Release 之前把 Cask 指向尚不存在的 DMG。它不声明 `auto_updates true`，因为应用只提供提醒，没有自行下载安装。相关发布与验收边界分别见[发布流程](releases/README.md)和[验证记录](verification.md)。

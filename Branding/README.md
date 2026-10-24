# 念匣图标

应用图标采用深绿色立体抽屉、圆形把手与折角纸张，置于有透明外边距的陶土色圆角底板。`AppIcon-source.png` 是当前母版，标准 16–1024 像素资源由脚本导出：

```sh
swift Scripts/generate_app_icon.swift Branding/AppIcon-source.png NianBox/Resources/Assets.xcassets
```

菜单栏使用 `NianBox/Design/MenuBarIconRenderer.swift` 运行时绘制的单色模板图，包含 18 与 36 像素表示；沿用抽屉、圆把手与折角纸张，不从应用图标缩小导出。`MenuBarLifecycle` 根据真实录入、本地保存和同步活动更新图形；状态规则见[同步契约](../docs/sync.md#展示与录入)。

连接失败以断开的插头表示，本地保存失败在抽屉正面显示大叉，删除冲突使用分开的纸张。错误状态同时提供文字原因；减少动态效果与空轮询静默必须保留。图形应在真实菜单栏尺寸及明暗背景下检查。

候选图、生成提示词与已弃用设计过程可通过 Git 历史追溯；预览与试验产物留在忽略目录，不作为现行实现。应用图标未使用第三方符号，导出资源随项目采用 MIT 许可。

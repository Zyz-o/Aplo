# 当前集成状态：Aplo 3.0

自 3.0 起，已将 LaunchNext 的 FuzzyMatcher.swift、SearchIndexEntry.swift、CJKTransliterator.swift 原样复制到 Sources/Vendor/LaunchNextSearch，直接参与编译，并由 IntegratedSearch 接入 LauncherModel。支持拼音、首字母、英文缩写与不连续字母搜索。来源、版本、许可与源码交付见 THIRD_PARTY_NOTICES.md。

全屏面板与显示方式切换由 Aplo 实现，保留原有六列、18 项分页和布局模型；不会复刻 LaunchNext 的完整动画、壁纸引擎或所有附加功能。改名为 Aplo，保留原 bundle ID 与布局路径以继续使用个人数据。新安装默认全屏，可切回小面板。

下面记录的是此前版本的调研过程；其中“未合入源码”等描述仅适用于 2.x 历史版本。

# LaunchNow 与 LaunchNext 参考结论

核对日期：2026-10-16。

- [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) 提供网格、分页、文件夹、即时搜索、键盘导航和自身布局备份；它的 SwiftData 存储不等同于旧版系统 Launchpad 数据库。
- [LaunchNext](https://github.com/RoversX/LaunchNext) 明确基于 LaunchNow；两个项目并非两套独立的旧布局数据源。
- LaunchNext 的 [NativeLaunchpadImporter.swift](https://github.com/RoversX/LaunchNext/blob/main/LaunchNext/NativeLaunchpadImporter.swift) 展示历史 SQLite 的 items / apps / groups 结构与 .lmy / .zip 输入处理。[LayoutPresetCatalog.swift](https://github.com/RoversX/LaunchNext/blob/main/LaunchNext/LayoutPresetCatalog.swift) 是系统应用默认预设，不是用户个人排列。
- 简启独立实现读取器，导入前校验、匹配当前安装应用，再自动备份并原子保存；不改写源数据。仅支持历史 Launchpad 模式数据库及含此数据库的归档，不承诺其他 ZIP 或任意 SwiftData 存储兼容。没有数据库或旧备份时无法恢复个人布局。
- 简启保留用户应用范围和 640×480 面板，将旧布局按每页 18 项重新分页；未安装项目、系统项目和原有空位不会原样复制。新安装应用会追加，用户排列保留。
- LaunchNow 的 [GlobalPinchGestureMonitor.swift](https://github.com/ggkevinnnn/LaunchNow/blob/main/LaunchNow/GlobalPinchGestureMonitor.swift) 使用 MultitouchSupport 私有框架。这类全局手势增加系统升级维护成本和权限要求；简启只实现面板内翻页手势及可配置系统热键。
- 两项目采用 GPL-3.0，见 [LaunchNow LICENSE](https://github.com/ggkevinnnn/LaunchNow/blob/main/LICENSE)、[LaunchNext LICENSE](https://github.com/RoversX/LaunchNext/blob/main/LICENSE)。当前简启应用实现未合入其代码或资源；若以后引入并分发衍生实现，需要按具体引入内容核对许可、版权声明与对应源码义务。

本次检查的源码版本：LaunchNext `d3dd4a39335bc7d46f01545692cd672e7e1ee0e2`；LaunchNow `747f26440249cd46e05e6711f483a3fde2b78db0`。

## 本地参考副本与 2.0.1 优化

用户已授权复制项目用于优化。完整浅克隆保存在 `References/LaunchNext` 与 `References/LaunchNow`，各自保留 `.git`、LICENSE 和原始版权信息；两者均不参与简启的构建或打包。

对照 `LaunchNow/LaunchNow/LaunchpadView.swift` 的键盘导航与跨页交互，以及 `LaunchNext/LaunchNext/GridDragDrop.swift` 的拖放状态处理，简启新增 Tab / Shift＋Tab 翻页，将页码投放区域从 14×14 扩为 28×24，并以 AppKit 直接接收跨页拖放载荷。仍沿用独立模型与存储，没有直接移植上述源码。

不默认改成全屏，不启用私有全局手势接口，不以参考项目的默认预设充当个人旧布局。

## 2.1 美化与优化

对照 LaunchNext 的 IconStore、文件夹预览、页码和设置界面的职责划分，简启独立调整视觉样式，并保留既有应用扫描与布局存储结构。优化内容包括图标缓存的增量失效、七页窗口式页码、访达定位入口，以及文件夹名称输入框的延迟聚焦处理。本次未将参考项目源码或资源合入应用，也未读取或改写 LaunchNext 的 Data.store。

# Aplo

A native macOS application launcher built with Swift, SwiftUI and AppKit.

原生 Mac 应用启动台，原名「简启」。支持全屏浏览和可移动、可调整尺寸的小窗口。

## 功能

- 全屏与小窗口保留独立排列，支持网格、自由摆放、拖动排序和文件夹。
- 连续滚动可选择左右或上下方向；也可使用分页模式。
- 中英文名称、拼音和首字母搜索；支持分类筛选、键盘选择和回车启动。
- 全屏与小窗可分别设置列数及横向／分页行数；“自动”沿用原布局。显示密度不会改写布局。
- 文件夹可独立选择纵向连续滚动、分页，或跟随主界面。
- 整理菜单可开启多选（切换到网格）：点击或用方向键＋空格选择应用，批量拖动、合并、移入／移出文件夹。
- 整理菜单的“页面顺序…”支持整页拖放或箭头换序；仅在手动排列、自动行列、主界面可用。全屏和小窗口各自保存并可撤销。
- 从网格中拖动应用到 macOS 程序坞的应用区域即可固定；导出原生文件链接，不移动应用包，不自动修改 Dock。文件夹仅在 Aplo 内拖放。
- 自动分类、系统应用中文名称、名称字体及颜色设置。
- 图标与文字百分比调整、透明背景、浅深外观及辅助配色。
- 可设置全局快捷键、悬停放大、工具栏位置、收起方式及系统音效。
- 整理操作支持 ⌘Z 撤销、⇧⌘Z 重做；文字编辑保留系统撤销。历史仅保留当前会话最近 50 次操作，应用清单变化时清除。
- 可隐藏应用并在设置中管理，保留其原分组及位置。
- JSON 布局备份、自动备份历史、手动快照与双布局预览恢复，以及旧版系统 Launchpad 数据库导入。清理保留最近 20 份自动备份及所有手动快照，旧自动备份移至废纸篓。

浏览时把指针移到应用上按 **空格**，或在右键菜单选择“应用速览”，查看版本、架构和包体积。右键还可显示包内容、拷贝路径、打开所在目录的终端，以及确认后移至废纸篓（系统应用不可移除）。

搜索框支持 `= (2+3)*4` 等基本算式，回车拷贝结果；支持 `lock`、`sleep`、`trash`（也可加 `/` 前缀），执行前都显示确认，默认按钮是取消。`trash` 仅清空当前用户 `~/.Trash`，永久删除且无法撤销，不处理外置磁盘。系统若拒绝访问，不会申请完全磁盘访问权限。新 macOS 缺少 `CGSession` 时，`lock` 会提示使用 **Control + Command + Q**；不会用关闭显示器冒充锁屏。未提供最近打开栏与 ⌘1–⌘9 启动。

默认快捷键 **Control + Option + Space** 显示或收起；**Control + Command + F** 切换全屏和小窗口。设置可通过面板齿轮或菜单栏打开，并记住上次分类。可额外开启 **F4**（部分键盘需 **Fn+F4**，搜索图案键可能仍触发 Spotlight）；冲突时保留原入口。可选择一个屏幕热角，指针停留约 0.35 秒呼出；默认关闭，避免与系统热角选择同一角落。滚动期间暂停悬停放大，停下后恢复。

## 安装与构建

当前构建脚本面向 **Apple Silicon（arm64），macOS 13 或更新版本**。Intel 版本尚未提供，需要 Xcode 或 Command Line Tools 构建源码。

```sh
git clone https://github.com/Zyz-o/Aplo.git
cd Aplo
zsh test.sh
zsh build.sh
zsh Scripts/install-local.sh
```

安装脚本会备份已有同身份应用、布局和偏好，再更新 `/Applications/Aplo.app`；共享目录不可写或属于其他用户时安装至 `~/Applications/Aplo.app`，已有用户目录安装会继续原路径。锁位于当前用户的私有缓存目录，进程检查限定当前 UID。请不要同时运行多个副本，以免争用快捷键。

下载版为本机临时签名构建，**没有 Apple Developer ID 签名或公证**；macOS 可能阻止首次打开。它不等同于经过 Apple 公证的正式发行包。也可自行审阅并构建源码。

## 数据与兼容性

- 布局：`~/Library/Application Support/简启/layout.json`。
- 偏好域及 bundle ID：`local.jianqi.SimpleLauncher`。
- 原身份与历史路径保留，避免品牌改名后丢失已有设置。
- 本次新增偏好默认关闭或跟随现有行为，无布局格式迁移。CLI 布局管理尚未实现，另行设计。
- 扫描 `/Applications`、`~/Applications` 和系统应用目录，不进入应用包内部；启动时异步预扫，频繁呼出时采用 20 秒最短扫描间隔。安装目录由 FSEvents 监听并合并刷新，20 秒限频仍作为呼出时的兜底。菜单栏“刷新应用列表”可立即强制刷新。
- 不添加登录启动项，不请求辅助功能或完全磁盘访问权限；应用不访问网络或记录搜索内容。
- 全屏显示临时隐藏菜单栏和系统 Dock，关闭后恢复；不改写系统 Dock 布局设置。

旧布局导入仅读取历史 Launchpad SQLite 数据库，或包含该数据库的 `.lmy` / `.zip` 文件。**不支持直接导入 LaunchNext 的 SwiftData `Data.store`**。没有旧数据库或备份时无法还原个人历史布局。恢复前会保留旧布局备份。

完整兼容性记录见 [BRAND_COMPATIBILITY.md](BRAND_COMPATIBILITY.md)，更新记录见 [CHANGELOG.md](CHANGELOG.md)。

## 验证与限制

使用 `swift test`（或 `./test.sh`）运行回归检查；SwiftPM 支持增量构建。`./build.sh` 复用 SwiftPM 的 release 产物，再打包为应用。检查覆盖扫描、布局、搜索、偏好、导入和滚动几何逻辑。自动检查不等同于真实触控板帧率测试，不能保证所有设备、外接屏和应用数量下均无卡顿。系统拼音转写也可能存在多音字差异。

## 发布打包

```sh
zsh Scripts/package-release.sh
```

构建完成后在 `dist/` 输出 arm64 应用 ZIP 和 SHA-256 校验文件。构建产物、个人布局、安装备份和完整上游参考仓库不纳入 Git。

## 许可与致谢

Aplo 按 [GNU GPL version 3](LICENSE) 分发，包含 [LaunchNext](https://github.com/RoversX/LaunchNext) 的搜索模块和适配后的音效模块。LaunchNext 基于 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)。具体来源、版本及修改见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

应用包包含许可证、第三方声明及 `CorrespondingSource.zip` 对应源码。保留上游版权与许可；无任何担保，详见 LICENSE。应用图标使用项目提供的照片。

## Validation and upgrade safety

`./test.sh` runs Swift layout/search regressions and Python installer failure-injection tests. GitHub Actions checks every main-branch push and pull request; version changes also publish a preview after validation.

`./Scripts/install-local.sh` backs up the installed app, final layout and preferences, stages a clean replacement bundle, verifies it and checks launch liveness. Verification or activation failure restores the previous bundle and backed-up data. If filesystem errors prevent rollback, the script reports the retained recovery path. This short launch check does not guarantee the absence of later runtime failures.

`./Scripts/benchmark-search.sh` measures optimized cold/warm search-index preparation and per-query latency for installed apps and 300 synthetic CJK apps. Measurements are machine-specific, not frame-rate guarantees. Normal UI discovery prepares the index off the main actor; synchronous `refresh` is reserved for deterministic tests/import support.

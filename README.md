# Aplo

A native macOS application launcher built with Swift, SwiftUI and AppKit.

原生 Mac 应用启动台，原名「简启」。支持全屏浏览和可移动、可调整尺寸的小窗口。

## 功能

- 全屏与小窗口保留独立排列，支持网格、自由摆放、拖动排序和文件夹。
- 连续滚动可选择左右或上下方向；也可使用分页模式。
- 中英文名称、拼音和首字母搜索；支持键盘选择和回车启动。
- 自动分类、系统应用中文名称、隐藏应用、名称字体及颜色设置。
- 图标与文字百分比调整、透明背景、浅深外观及辅助配色。
- 可设置全局快捷键、悬停放大、工具栏位置、收起方式及系统音效。
- JSON 布局备份与恢复，以及旧版系统 Launchpad 数据库导入。

默认快捷键 **Control + Option + Space** 显示或收起；**Control + Command + F** 切换全屏和小窗口。设置可通过面板齿轮或菜单栏打开。滚动期间暂停悬停放大，停下后恢复。

## 安装与构建

当前构建脚本面向 **Apple Silicon（arm64），macOS 13 或更新版本**。Intel 版本尚未提供，需要 Xcode 或 Command Line Tools 构建源码。

```sh
git clone https://github.com/Zyz-o/Aplo.git
cd Aplo
zsh test.sh
zsh build.sh
zsh Scripts/install-local.sh
```

安装脚本会备份已有同身份应用、布局和偏好，再更新 `/Applications/Aplo.app`。请不要同时运行多个副本，以免争用快捷键。

下载版为本机临时签名构建，**没有 Apple Developer ID 签名或公证**；macOS 可能阻止首次打开。它不等同于经过 Apple 公证的正式发行包。也可自行审阅并构建源码。

## 数据与兼容性

- 布局：`~/Library/Application Support/简启/layout.json`。
- 偏好域及 bundle ID：`local.jianqi.SimpleLauncher`。
- 原身份与历史路径保留，避免品牌改名后丢失已有设置。
- 扫描 `/Applications`、`~/Applications` 和系统应用目录，不进入应用包内部；每次呼出后台刷新。
- 不添加登录启动项，不请求辅助功能或完全磁盘访问权限；应用不访问网络或记录搜索内容。
- 全屏显示临时隐藏菜单栏和系统 Dock，关闭后恢复；不改写系统 Dock 布局设置。

旧布局导入仅读取历史 Launchpad SQLite 数据库，或包含该数据库的 `.lmy` / `.zip` 文件。**不支持直接导入 LaunchNext 的 SwiftData `Data.store`**。没有旧数据库或备份时无法还原个人历史布局。恢复前会保留旧布局备份。

完整兼容性记录见 [BRAND_COMPATIBILITY.md](BRAND_COMPATIBILITY.md)，更新记录见 [CHANGELOG.md](CHANGELOG.md)。

## 验证与限制

3.11.2 通过本机 292 项自动检查，覆盖扫描、布局、搜索、偏好、导入和滚动几何逻辑。自动检查不等同于真实触控板帧率测试，不能保证所有设备、外接屏和应用数量下均无卡顿。系统拼音转写也可能存在多音字差异。

## 发布打包

```sh
zsh Scripts/package-release.sh
```

构建完成后在 `dist/` 输出 arm64 应用 ZIP 和 SHA-256 校验文件。构建产物、个人布局、安装备份和完整上游参考仓库不纳入 Git。

## 许可与致谢

Aplo 按 [GNU GPL version 3](LICENSE) 分发，包含 [LaunchNext](https://github.com/RoversX/LaunchNext) 的搜索模块和适配后的音效模块。LaunchNext 基于 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)。具体来源、版本及修改见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

应用包包含许可证、第三方声明及 `CorrespondingSource.zip` 对应源码。保留上游版权与许可；无任何担保，详见 LICENSE。应用图标使用项目提供的照片。

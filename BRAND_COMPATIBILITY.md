# Aplo 品牌与升级兼容性（2026-10-17）

| 项目 | 当前值 | 决定 |
|---|---|---|
| 显示名称、窗口和菜单 | Aplo | 对外统一使用 |
| 安装包与可执行文件 | Aplo.app / Aplo | 已统一 |
| 安装位置 | /Applications/Aplo.app | 本机升级位置 |
| bundle ID / 偏好域 | local.jianqi.SimpleLauncher | 保留，避免创建新的用户偏好域 |
| 布局 | ~/Library/Application Support/简启/layout.json | 保留，不迁移或覆盖为新空布局 |
| 外观和音效偏好键 | aplo.preferences.v1 | 增量解码，保留旧字段，新增字段使用默认值 |
| 拖放类型 | local.jianqi.layout-item | 保留兼容 |
| 源码目录 | SimpleLauncher | 内部工程路径，保持现有链接可用 |

构建：zsh build.sh。验证：zsh test.sh。本机安装：zsh Scripts/install-local.sh。

安装脚本核验 bundle ID 和签名，备份现有应用、布局及偏好，退出旧实例，再覆盖安装并重新登记 LaunchServices。旧 SimpleLauncher.app 只在身份匹配时移入恢复备份，避免双实例争用热键。安装不修改用户数据路径，不导入 LaunchNext 的布局或偏好。

本机临时签名版本沿用当前已授权安装方式。公开分发另需用户确定发布签名身份、公证及安装包形式；更换 bundle ID 或迁移数据目录也须单独确定迁移方案，本次未实施这些变更。


3.4.0 新增语言、Dock、辅助配色和百分比偏好，沿用原 UserDefaults 域及 aplo.preferences.v1 数据键；新增字段使用兼容默认值。旧 iconSize 被保留读取并迁移到近似百分比。浏览排序和系统分类不改动个人布局 JSON。语言切换不改变 bundle ID、应用文件名、用户数据目录或个人文件夹名称。

### 3.5.0

普通应用激活策略与 LSUIElement=false 让 Aplo 显示在 Dock；bundle ID、用户数据目录及偏好键保持不变。新 arrangement 字段默认 grid。layout.json 新增可选 freePositions 坐标字典，旧布局不需要迁移，旧版缺省值为空；坐标随布局导出及恢复。网格顺序与文件夹不因自由拖动而改变。

### 3.6.0

保留原身份和目录。窗口位置键 aplo.windowPositions.v1 新增可选 width／height，旧位置无需迁移；界面偏好新增工具栏位置、收起策略、桌面固定及悬停放大，旧偏好保留原来的底部工具栏和外部点击收起。用户布局未改变。程序坞上／下位置功能指 Aplo 内部工具栏，不写入系统 Dock 的位置设置。

### 3.7.0

新增应用名称字体、字重、RGB 颜色与繁体显示偏好；缺少字段时使用系统字体、常规字重及自动颜色。简繁体转换只作用于显示和搜索，原应用名称、个人文件夹标题及布局文件不因语言切换而重写。原生图层放大不改变拖放命中区域，手动网格下开始真实拖动时自动进入整理状态。

3.8.0 保持 bundle ID、偏好域和布局路径不变。布局 version 1 新增可选 otherDisplayLayout 和 activeLayoutIsFullscreen 字段，同一 JSON 原子保存两种显示模式。旧数据将原有页、文件夹及自由位置保留为全屏布局，小窗口复制顺序并默认规整网格；应用扫描同时更新两份布局。compactArrangement 是可选偏好字段，缺失时小窗口使用网格。两份布局随导出备份保留；旧版应用会忽略新字段，降级前请保留安装备份及 3.8.0 导出文件。

3.11.0 保留原身份和路径。导出 JSON 在 version 1 上新增可选 backupPresentation（两套排列方式）；旧备份不含此字段时不强制改变排列。读取采用文件元数据预检和限长流式读取。普通扫描遇到不完整数据不删布局，确认卸载的保存前归档。安装脚本继续备份旧应用、两套布局和偏好。

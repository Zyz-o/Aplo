# 3.15.5 — 2026-11-03

- Add name sorting and non-system apps first to the Arrange menu. Back up the layout before saving the new order.
- Restore optional system-last display ordering without a separate system category.
- Use a spring transition for adjacent pages; jump directly across non-adjacent pages.

<!-- summary-zh -->
- 整理菜单新增「下载应用优先」和「按名称排序」，保存新顺序前先备份。
- 可在连续滚动时将系统应用排在最后，仍按用途分类。
- 相邻页使用弹簧动画，跨多页直接跳转。

# 3.15.4 — 2026-11-03

- Group built-in and installed apps by function, pin a recent-app row above the home grid, and resolve drag thumbnails only when dragging starts.

<!-- summary-zh -->
- 取消系统应用单独分组；主页顶部固定显示最近使用的一排图标。
- 滚动时不再为拖放层重复准备图标，拖动开始时才读取缩略图。

# 3.15.3 — 2026-11-03

- Restrict system classification to Apple bundles in macOS app locations and categorize Tailscale as networking.

<!-- summary-zh -->
- 修正系统应用识别：数据卷中的普通应用不归入系统区，保留 Safari 等系统自带应用；Tailscale 归入网络与浏览。

# 3.15.2 — 2026-11-03

- Preserve native trackpad momentum for vertical scrolling and render fixed-height lazy rows. Add recent launches and a system-app section to the vertical home view.
- Stack wide settings controls below labels and explain which choices each page reset affects.

<!-- summary-zh -->
- 优化纵向滚动，保留系统原生惯性。纵向主页新增最近使用和底部系统应用分区。
- 改善窄窗口设置排版，恢复默认前明确列出受影响的选项。

# 3.15.1 — 2026-11-03

- Add manual checks for published GitHub releases with a complete arm64 download. Show release notes and link to GitHub.

<!-- summary-zh -->
- 在「更新内容」页加入手动检查更新。发现新版时显示版本、预览版标识和更新说明，可前往 GitHub 下载。
- 仅在点击时联网，不自动下载或安装。

# 3.15.0 — 2026-11-03

- Add optional F4 and dwell-based hot corner entry points without changing system keyboard or Dock settings. F4 registration reports conflicts; Apple search keys may require Fn+F4.
- Add independent compact/fullscreen grid density, search category filters and folder-only vertical scrolling or paging. Grid reflow leaves stored layouts intact.
- Add opt-in multi-selection with batch dragging, grouping and folder/page moves, and whole-page drag reordering with arrow controls. Organization remains undoable and display layouts stay independent. Page reordering uses saved pages and is available with automatic grid density.
- Export native application file URLs during drags to support dropping installed apps onto the macOS Dock. Folders remain internal; external drags advertise copy, never file movement.
- Auto-dismiss informational notices while retaining errors, animate launch icons and editing hints with native layers, respect Reduce Motion, improve empty states and remember the last settings category.
- Cache filtered browsing layouts and display-page reflow; split application window, input, gesture and dialog responsibilities. Preserve legacy branding fields and storage identity.
- Add regression coverage for batch grouping at its original slot, single-step undo, layout isolation, page ordering, grid reflow, folder navigation, notice replacement, preference migration and search filtering.

<!-- summary-zh -->
- 新增可选 F4 呼出和屏幕热角；不改系统键盘或程序坞设置。
- 全屏与小窗可分别调整行列；搜索增加分类筛选，文件夹可独立选择纵向滚动或分页。
- 新增多选、批量拖动／分组／移入文件夹，以及整页拖动换序，均可撤销。页面换序需使用自动行列。
- 应用可原生拖到 macOS 程序坞；普通提示自动淡出，错误保留关闭按钮。
- 加入启动图标动画、整理轻微抖动和空态提示，并记住上次设置页面；系统“减少动态效果”会关闭这些动画。
- 保留原有数据位置、双布局及偏好，修复批量合并时的位置与成员一致性。

# 3.14.1 — 2026-11-03

- Store notification templates separately from interpolation arguments, localizing at render time. Preserve app names and system error details verbatim and support language changes while a message is visible.
- Translate the empty-folder-name validation and display recorded / legacy shortcut key names according to the current language, without migrating saved bindings.
- Inset folder count badges and constrain their width inside the icon, including small icons and large text.
- Add localization regressions for import counts, shortcut confirmation, save/export/action/launch failures, literal percent markers and language switching.

<!-- summary-zh -->
- 修复英文提示中夹杂中文的问题；切换语言后，屏幕上的消息会同步更新，应用名和错误详情保留原文。
- 补全文件夹空名称提示，快捷键的空格／回车名称随界面语言显示，原快捷键保持不变。
- 文件夹数量角标移入图标内部，小图标或大字号下也不会向外溢出。

# 3.14.0 — 2026-11-02

- Guard empty application names and malformed folder merges. Use a private, no-follow installer lock and UID-scoped process matching; preserve personal-directory installations and fall back when shared installation is unavailable.
- Resize backup previews, adapt the settings sidebar to language and text scale, share actual label styles with comparison previews, and add settings search, scoped reset, live appearance preview and hidden-only filtering with app icons.
- Set an icon cache budget of 48 MiB / 160 entries, render immutable thumbnails sized for current scale and magnification on the serial worker and remove full-catalog warmup. Disable pointer tracking when hover magnification is off. Debounce FSEvents discovery; retain incomplete-scan layout protection.
- Separate hide-after-launch from desktop-click dismissal, preserving migrated preferences.
- Add Space app metadata, package/path/Terminal context actions, confirmed app recycling, a bounded arithmetic parser and confirmed system commands. Empty Trash is restricted to the current user's local Trash. Lock Screen explains the native keyboard shortcut when CGSession is unavailable.
- Add user-facing Chinese release summaries alongside developer records. No claim is made about a fixed memory-saving percentage or measured trackpad frame rate.

<!-- summary-zh -->
- 修复特殊应用名称及异常合并数据的崩溃隐患，改进安装锁、多用户处理与安装路径选择。
- 放大备份预览；设置支持搜索、本页重置、隐藏筛选和外观实时预览。大字号侧栏与大小对比更准确。
- 图标缓存有容量上限，关闭悬停放大后停止对应追踪，安装或卸载应用后自动刷新。
- 新增空格速览、右键高级操作、算式计算，以及执行前确认的系统指令；启动后自动收起可独立设置。
- 新系统无法直接锁屏时提示系统快捷键；清空废纸篓仅处理本机当前用户目录，无法撤销。

# 3.13.1 — 2026-11-02

- Leave the folder navigation context when hiding its final visible child, so returning to the root free canvas uses root coordinates. Preserve the hidden folder and positions in saved layouts.

<!-- summary-zh -->
修复隐藏文件夹内最后一个应用后，返回主界面时位置不正确的问题。原分组和坐标继续保留。

# 3.13.0 — 2026-11-02

- Replace apps with new folders in their original page and slot, preserving free-placement coordinates and the other display layout.
- Navigate free layouts using actual tile coordinates in either direction. Reveal keyboard selections in the native scroll view and show a lightweight keyboard-only focus ring.
- Add bounded, session-local organization undo/redo (Command-Z / Shift-Command-Z). Text editors retain their native undo behavior; inventory changes invalidate stale layout history.
- Hide apps from browsing and search without changing stored folders or positions. Manage hidden apps in Settings; manual backups include visibility choices.
- Browse automatic and manual backup history, preview both layouts, and restore through validated import. Cleanup moves older automatic backups to Trash, retains the latest 20, and preserves manual snapshots.
- Generate in-app update history from the bundled CHANGELOG.

<!-- summary-zh -->
- 新建文件夹保留原位置，方向键按照图标实际位置导航。
- 新增撤销／重做、隐藏应用管理，以及可预览和恢复的备份历史。
- 全屏与小窗口继续独立保存布局。

# 3.12.2 — 2026-11-01

- Preserve unknown applications, folders and positions in both layouts when organizing after incomplete discovery. Archive before the first write during an untrusted inventory and before confirmed removals; stop safely if the backup fails.
- Stage clean app bundles and verify signatures before replacement. Roll back the prior bundle and backed-up user state if installed verification or launch checks fail; serialize local installations.
- Run source tests and signed app builds on every main-branch push and pull request, including Python installer failure-injection tests.
- Measure search independently with an optimized benchmark. Prepare immutable pinyin/alias indices alongside discovery on a background task; keep low-latency queries synchronous and commit inventory/index together with generation checks.

<!-- summary-zh -->
- 扫描不完整时保护原布局，整理和升级前自动备份。
- 安装失败时恢复旧版本，并加强自动检查。
- 在后台准备搜索索引，减少界面等待。

# 3.12.1 — 2026-11-01

- Remove the central header photo and its size control; retain the Aplo title and existing saved preferences.
- Isolate hover magnification to one icon’s original bounds. Gaps and adjacent icons remain at normal size.
- Use consistent 32-point fullscreen / 24-point compact outer margins and a 16-point header gap; share geometry with paging and drag targets.

# 3.12.0 — 2026-11-01

- Diff preference side effects; debounce continuous-value saves and flush them on quit. Avoid redundant frame updates and menu rebuilds.
- Bound and cache resolved-language translations, reuse tile names, narrow tile inputs and icon render identities, and prune stale drag feedback.
- Prefetch native icons on a serial worker, prioritize visible requests, and deliver readiness notifications only to affected tiles.
- Scan once at startup; throttle repeated panel-open scans to 20 seconds. Add an immediate refresh menu entry; imports and failure recovery still force discovery.
- Normalize search variants once, pre-expand alias entries, and keep compact layout files while preserving readable exports.
- Use SwiftPM for incremental app builds and XCTest regression suites; make build/test/install/package scripts executable.

# 3.11.2 — 2026-11-01

- Suspend hover magnification during scrolling and resume after motion stops, avoiding repeated geometry traversal and animation replacement during momentum.
- Use preload-aware viewport updates for free placement instead of rebuilding its visible tiles for every pixel; large jumps and viewport resizing update immediately.
- Defer catalog commits and icon prewarming during continuous scrolling. Cache native icon view content in backing layers.
- Preserve paging choices, scroll sensitivity, application layouts and preferences.

# 3.11.0 — 2026-10-20

- Require a completed, trustworthy inventory before restoring layouts. Incomplete application scans retain existing entries and both layouts; confirmed removals archive the prior layout before saving.
- Export full-screen and compact arrangement choices with layout backups; restore them with coordinates. Legacy backups retain the current presentation choice.
- Reject oversized backup files before allocation, cap streamed reads and encoded output, and parse backups and legacy imports off the main actor. Add cancellable import status, bounded archive/database work and a 30-second legacy read deadline.
- Cull free-canvas tiles outside the viewport plus preload margin, keep dragged tiles alive, and protect direct free dragging from background inventory updates.
- Recognize Apple-silicon iPhone/iPad WrappedBundle installations without treating them as corrupt Mac app bundles.
- Add regression coverage for the review's data-loss cases, old backup compatibility, cancelled/timed-out imports and free-drag update deferral.

# 3.10.0 — 2026-10-19

- Read modern Apple InfoPlist.loctable localization tables, including mac-specific overrides, alongside legacy InfoPlist.strings. Honor the selected application language during background discovery.
- Retain original bundle and file names as searchable aliases when displaying translated app names; preserve bundle identifiers, folders and ordering.
- Enable direct dragging in Free Placement without first entering edit mode. Add explicit Move and Arrange controls and selected-mode feedback; each display mode retains its own positions.

# 3.9.0 — 2026-10-19

- Move UI-triggered application discovery and metadata checks off the main actor. Present cached applications immediately; accept only the latest scan and preserve queries typed while it runs.
- Avoid republishing unchanged inventories, rebuilding their search indices or restarting icon warmup. Defer completed inventory updates during native dragging and page transitions.
- Replace per-app nested SwiftUI icon hosts with lightweight NSImageViews. Keep SwiftUI only for composite folder thumbnails and retain Retina images and layer magnification.
- Cache resolved label fonts and pace icon warmup one image at a time, pausing during native dragging/page transitions.

# 3.8.1 — 2026-10-19

- Isolate drag-destination feedback in per-tile observable state. Crossing destinations no longer publishes changes to the entire grid, labels or search field.
- Suppress SwiftUI hover state and unnecessary magnification scans during native icon dragging; retain direct AppKit drag tracking and existing drop behavior.
- Add rapid-destination, unaffected-tile, stale-exit and merge-to-reorder regression checks.

# 3.8.0 — 2026-10-19

- Expand full-screen grids across available screen width with adaptive column counts; use the available height for horizontal continuous browsing.
- Save independent full-screen and compact orders, folders and free positions atomically in the existing layout.json. Legacy layouts and positions seed full screen; compact starts as a regular grid.
- Retain independent arrangement choices, both layouts in exports/restores, and application reconciliation for each profile. Display switches clear transient drag, folder and scroll state.
- Match native drag targets and keyboard navigation to the actual adaptive grid geometry.

# 3.7.1 — 2026-10-19

- Remove full-tile selection/drop borders, checkmarks and edit handles; retain accessible selection semantics.
- Preview actual application thumbnails during folder creation/join instead of a folder symbol; dim the source icon while dragging.
- Cache unchanged native icon hosting content and coalesce pointer events to the latest sample per main-loop turn.
- Tighten horizontal grid width and row/column spacing without changing stored order or positions.

# 3.7.0 — 2026-10-19

- Replace isolated hover zoom with distance-based native layer magnification for the pointed icon and nearby neighbors.
- Enable direct native drag initiation in manual grids and show folder-creation/join feedback over center drop targets.
- Remove label/header/toolbar dark text backing, retain the high-contrast Settings button, and add app-label font, weight and color preferences.
- Add Traditional Chinese display using the system transform without rewriting personal folder names or layout data.

# 3.6.1 — 2026-10-18

- Add Dock-only, menu-bar-only and both access-point choices; retain both for existing preferences.
- Apply activation policy and status-item visibility without replacing user layout, identity or data paths. Keep Settings open during the activation-policy transition.

# 3.6.0 — 2026-10-18

- Apply sensitivity to native continuous scroll event deltas while retaining phases and momentum. Accumulate fractional integer-pixel deltas, retain fixed-point precision, and clear stale carry on direction reversal.
- Resize compact windows and persist dimensions per screen; add an explicit bottom-right resize handle and native minimization.
- Keep a window on its desktop, with outside-click or Esc-only dismissal. Pinning defaults to Esc-only and preserves the screen; launching apps retains Esc-only panels.
- Move Search, Settings and Arrange together between top and bottom toolbars.
- Add spring icon hover magnification, press feedback and scale/fade opening animation, respecting Reduce Motion.
- Allow 0–100% transparency for solid and glass backgrounds; keep the Settings button independently bright and backed by a contrasting capsule.

# 3.5.0 — 2026-10-18

- Fix size-preview sheet focus changes hiding the launcher; keep the parent visible through presentation.
- Display Aplo in the Dock and retain menu-bar and global-hotkey access.
- Move search into a collapsible bottom-left control; retain centered bottom Settings.
- Add selectable free placement, grid editing and backup-before-shuffle. Free coordinates are normalized, bounded, and included in layout backups; grid order and folders remain available.
- Cache derived application containers and remove hover animation during continuous scrolling. Free canvases bypass paged gesture interception.

# Aplo 更新记录

## 3.4.1 · 2026-10-17

- 小窗口与设置标题区域可拖动，按屏幕记住位置并支持重置。
- 顶部图标和名称居中排列，设置入口移至底部正中央。
- 顶部图标和名称可独立按百分比调整大小，不影响应用网格。

## 3.4.0 · 2026-10-17

- 程序坞：隐藏、跟随窗口、显示，仅在面板打开时临时生效，收起后恢复。
- 界面语言：跟随系统、简体中文、English，支持即时切换菜单、设置和提示。
- 色盲友好：标准、红绿友好、蓝黄友好、单色高对比；选中状态同时使用边框与勾选。
- 图标 50–150%、面板与设置文字 80–140%，在独立窗口对比当前和调整后的效果，确认后应用。
- 旧图标大小迁移为相近百分比；横向网格在大尺寸下自动减少行数，避免裁切。
- 连续浏览时系统应用稳定置后：纵向在底部、横向在最右侧；保留原布局与文件夹。
- 设置新增“更新内容”，可查看本版本与之前版本的主要变化。

## 3.3.0

- 独立选择连续滚动／分页切换，以及左右／上下方向。
- 原生连续滚动可停留在任意位置，不吸附整页；保留原来的分页布局。

## 3.2.4

- 明确选择左右或上下翻页；修正相邻页面的连续衔接。
# 3.11.1 · 2026-10-31

- 打开面板时直接复用系统原生多分辨率图标，移除主线程逐个强制重绘 384 像素位图的开销。
- 保留原生高清图标、内存缓存及应用更新时的图标失效处理；布局和偏好格式不变。


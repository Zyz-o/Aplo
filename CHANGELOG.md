# 3.12.2 — 2026-11-01

- Preserve unknown applications, folders and positions in both layouts when organizing after incomplete discovery. Archive before the first write during an untrusted inventory and before confirmed removals; stop safely if the backup fails.
- Stage clean app bundles and verify signatures before replacement. Roll back the prior bundle and backed-up user state if installed verification or launch checks fail; serialize local installations.
- Run source tests and signed app builds on every main-branch push and pull request, including Python installer failure-injection tests.
- Measure search independently with an optimized benchmark. Prepare immutable pinyin/alias indices alongside discovery on a background task; keep low-latency queries synchronous and commit inventory/index together with generation checks.

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


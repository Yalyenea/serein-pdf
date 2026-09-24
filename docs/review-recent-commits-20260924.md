# 近期三次提交审查（2026-09-24）

范围：

- `7106d78` feat(navigation): add workspace selectors and MRU split launchers
- `6905cc5` feat(app): integrate recursive panes and configurable reader shortcuts
- `65676bc` docs: document workspace and reader navigation workflows

未提交的改动不在范围内。行号对应审查时的工作区。

## 处理结果（2026-09-24）

本次复核与修复完成后，原审查记录保留在下方。第 3 项的原因判断已被实测否定；第 4 项的永久保留符合工作区恢复要求。

| 项目 | 处理 |
|---|---|
| 1 方向键截获 | 翻页键只在 PDF 阅读区拥有键盘焦点时处理；窗口事件回归测试覆盖列表选择和阅读翻页。 |
| 2 最近窗口默认选择 | 当前窗口排末，默认选择最近的其他窗口；只有一个窗口时仍可选择。 |
| 3 过滤时输入框跳动 | 实际面板过滤测试确认输入框屏幕位置保持不变，无需修改尺寸逻辑。 |
| 4 关闭窗口保留与排序 | 按实际关闭顺序记录，重启后保留；重复关闭通知不改变顺序。保存的窗口组继续保留。 |
| 5 旧接口 | 删除仅测试调用的文档定位、旧面板重载、双窗标记与阅读区别名，测试迁移到现行接口；最近文件面板复用共享面板。 |
| 6 分屏提示 | 按实际配置显示向右、向下分屏快捷键；清除绑定后对应提示消失。 |
| 7 重复刷新、单复数、阅读位置 | 移除重复列表刷新，修正 `1 tab`；列表分屏继承源工作区最近阅读组中该 PDF 的阅读位置、缩放和锁定状态。 |
| Control 编辑键 | 真实 AppKit 事件循环确认菜单快捷键会截获文本编辑，禁用菜单仍会吞键；辅助窗口获得焦点时移除阅读快捷键，返回阅读窗口时恢复。 |
| 快速 Ctrl+Tab | 面板显示后检查实时 Control 状态，已松开则立即激活目标；回归测试覆盖仅激活一次。 |

主题验证覆盖最近窗口输入框的全部明暗预设、自定义背景、编辑内容和选区保持；底部提示验证默认、自定义及清空的分屏绑定。

验证：`just test` 全量通过，629 项 XCTest 与 240 项 Swift Testing，共 869 项。真实菜单键盘测试在独立 XCTest 进程中运行，避免 AppKit 应用生命周期影响其他窗口测试。

## 原审查记录

## 问题一览

| # | 级别 | 问题 | 来源 |
|---|---|---|---|
| 1 | 中高 | ↑/↓ 在整个窗口里都会翻页，右栏列表无法用方向键选择 | `6905cc5` |
| 2 | 中 | 最近窗口面板默认选中当前窗口，直接按 ↩ 无效 | `7106d78` |
| 3 | 低 | 最近窗口面板过滤时输入框上下跳动 | `7106d78` |
| 4 | 低 | 关掉的窗口永久保留，排序按创建时间 | `c19c141`，由 `7106d78` 暴露 |
| 5 | 低 | 只剩测试在调用的旧接口 | `6905cc5` / `7106d78` |
| 6 | 低 | Ctrl+Tab 面板底部提示缺少分屏快捷键 | `7106d78` |
| 7 | 细节 | 重复刷新、"1 tabs"、副本分屏的阅读位置 | `7106d78` |

## 1. ↑/↓ 在整个窗口里都会翻页

`ReaderShortcutWindow.sendEvent` 在事件交给焦点视图之前先调用阅读快捷键（`App/ReaderShortcutWindow.swift:24`）。`shouldHandlePlainShortcut` 只对可编辑文本放行（`UI/CenterReader/ReaderShortcutsController.swift:177`），之后竖直模式下的 ↑/↓ 一律翻页并吞掉事件（`:66`，`App/AppDelegate.swift:148`）。

影响：

- 焦点在 Annotations 列表或 Search 结果表时，↑/↓ 会翻页，选中项不动。
- `AnnotationTableView.keyDown` 里处理 ↑/↓ 的分支（`UI/RightOutline/AnnotationsViewController.swift:27`）永远收不到事件。批注编辑结束后焦点正好回到这张表（`:891`）；点击搜索结果后焦点也留在结果表上。
- Book 模式的 ←/→ 从 `6f951ab` 起就走这条路径，这次把 ↑/↓ 也加了进来。

现有测试直接调用 handler，没有经过 `window.sendEvent`，所以没抓到。

建议：只在焦点位于阅读区视图内时处理翻页键，并补一条经过 `sendEvent`、焦点在表格上的回归测试。

## 2. 最近窗口面板默认选中当前窗口

列表以 `NSApp.orderedWindows` 开头（`App/AppDelegate.swift:1731`），第一项就是当前窗口，`filterItems` 又默认高亮第 0 项（`App/RecentWindowsPaletteController.swift:150`）。打开面板直接按 ↩ 没有反应，按 ⌥↩ 会把当前 PDF 分屏给当前窗口自己。按住 Control 的 Ctrl+Tab 列表从上一项开始，两边不一致。

建议：把当前窗口排到最后，默认高亮上一个窗口。

## 3. 过滤时输入框跳动

`setContentSize` 改高度时窗口左下角不动（`App/RecentWindowsPaletteController.swift:158`），结果数量一变，顶部的输入框就跟着移动。`RecentFilesPaletteController.resizePanelToFitResults`（`App/RecentFilesPaletteController.swift:359`）已经处理了保持顶边不动，照搬即可。

## 4. 关掉的窗口永久保留

`closeWindow` 只标记 `isClosed`（`Core/DocumentStore.swift:280`）。`WindowWorkspace` 整体写入状态文件，加载时也不过滤（`:1746`），关过的窗口会一直留着。

最近窗口面板用 `closedWindowWorkspaces().reversed()` 排序（`App/AppDelegate.swift:1733`）。新窗口追加在数组末尾，所以实际顺序是创建时间倒序，和关闭时间无关。

这部分 Core 逻辑来自 `c19c141`，这次新加的最近窗口面板把它暴露给了用户。

建议：关闭时把窗口移到数组末尾，并限制保留数量。

## 5. 只剩测试在调用的旧接口

项目规则不保留兼容层，下面这些现在只有测试在调用：

- `DocumentStore.openLocation(for:)`、`activateOpenDocument(at:)` 和 `DocumentOpenLocation`（`Core/DocumentStore.swift:458`、`:473`）。最后一个生产调用在 `6905cc5` 删除。
- `OpenTabsPaletteController.show(with sessions:…)` 旧重载（`App/OpenTabsPaletteController.swift:115`），以及 `OpenTabsPaletteState` 里的 `paneBadge`、`isFocusedPane`。`OpenTabsPaletteState(sessions:activeSessionID:)` 在生产代码里只用来构造空的初始状态（`:69`）。
- `ReaderWorkspaceViewController` 的 `secondaryReaderViewController`（`:112`）和 `canSplitActivePane`（`:623`）。`:105` 的注释说它们服务于 "existing integrations"，实际只有测试在用。

`RecentFilesPalettePanel` 与 `CompactPalettePanel` 重复，已在 REVIEW.md 的 S4 跟踪。

## 6. Ctrl+Tab 面板提示缺少分屏快捷键

手动选择模式的提示写死为 `↑ ↓ Select ↩ Open Esc Cancel`（`App/OpenTabsPaletteController.swift:132`）。这个面板支持 `palette_split_right` / `palette_split_down`，最近文件和最近窗口两个面板也都显示了这两个快捷键。

## 7. 细节

- `show(items:)` 调用 `reloadUI()` 之后，`refreshChromeColors()` 里又调用一次（`App/OpenTabsPaletteController.swift:127`）。
- 窗口摘要会显示 "1 tabs"（`App/AppDelegate.swift:1743`）。
- 从 Ctrl+Tab 或最近文件面板分屏时，传入的是标签页本身的会话。如果这份文档当前只在副本分屏里阅读，新分屏会停在标签页的旧位置，因为副本的阅读位置不会写回标签页（`Core/DocumentStore.swift:1141`）。

## 待验证

- **分屏时 Ctrl+H/J/K/L 可能被菜单抢走**：切换分屏焦点的菜单项启用状态是缓存的，分屏时可能在面板、Settings、sheet 的输入框里拦下 Ctrl+H（删字）和 Ctrl+K（删到行尾）。主窗口已经处理，其他窗口没有。复现：分屏后打开最近文件面板，输入几个字，再按 Ctrl+H。
- **快速点按 Ctrl+Tab**：如果面板出现前 Control 已经松开，面板可能一直停在等待松开 Control 的状态。可以在面板显示后立即检查一次 `NSEvent.modifierFlags`。

## 已核对

- 关窗时丢弃未保存批注，只影响该窗口独占的会话（`exclusiveDirtySessions`，`Core/DocumentStore.swift:244`）。
- 打开已打开的文档会复用当前工作区的标签页，与文档描述一致；恢复已关闭的窗口会重建窗口控制器。
- 配置迁移正确并有测试：`Cmd+T` 改给分屏放大，新建空白标签页改为 `Cmd+Opt+T`。快捷键录入改用 `keyToken` 没有问题。
- 用小程序实测：无修饰键的菜单快捷键不会抢走面板输入框的输入；工作区选择器的 `contentTintColor` 能跟随主题。
- `65676bc` 的文档与实现一致，文档里提到的测试文件都存在。

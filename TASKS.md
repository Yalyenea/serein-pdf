# TASKS

本文件是 [PROJECT.md](PROJECT.md) 的执行清单。后续开发默认以这里的任务状态为准推进。

## 1. 执行规则

- [ ] 每开始一个里程碑前，先确认依赖任务已完成。
- [ ] 每完成一个可见功能后，立即补最小验证。
- [ ] 所有状态管理优先落在 `DocumentStore` / `DocumentSession`，不要把业务状态散落到视图层。
- [ ] 垂直 tab 与水平标题栏 tab 必须共享同一套文档切换命令与状态模型。
- [ ] UI 决策始终遵守：极简、扁平、紧凑，不增加无必要控件。

## 2. 产品常量

- [ ] `TabPresentationMode` 只有两种：`verticalSidebar`、`horizontalTitlebar`
- [ ] 默认高亮颜色是“偏轻、低饱和、清晰”的粉色
- [ ] `a`：有选区时立即高亮；无选区时进入高亮模式
- [ ] `Esc`：退出高亮模式
- [ ] `i`：切换反色夜间模式
- [ ] `Cmd+S`：将当前文档未保存批注写回源 PDF
- [ ] 默认自动保存策略是 `10 min`
- [ ] 自动保存策略至少支持 `10 min` 和 `never`
- [ ] 水平 tab 模式必须复用标题栏，不单独新增一行 tab bar

## 3. Milestone 1: MVP 骨架

### 3.1 工程初始化

- [x] `M1-001` 初始化 macOS AppKit 工程
完成定义：工程可编译运行，包含主窗口入口。

- [x] `M1-002` 建立目录结构
完成定义：创建与 `PROJECT.md` 对齐的目录层级，至少包含 `App/`、`Core/`、`UI/`、`Features/`、`Tests/`。

- [x] `M1-003` 建立基础文件骨架
完成定义：创建 `MainWindowController`、`SplitViewController`、`DocumentStore`、`DocumentSession`、`ReaderViewController`、`OutlineViewController`、`VerticalTabsViewController`、`TitlebarTabsController` 的空实现。

### 3.2 主窗口与三栏布局

- [x] `M1-010` 实现主窗口控制器
完成定义：应用启动后显示主窗口，窗口样式支持后续 `unifiedCompact`。

- [x] `M1-011` 接入 `NSSplitViewController`
完成定义：主界面形成左、中、右三栏结构，左右栏可单独管理。

- [x] `M1-012` 放置中间阅读容器
完成定义：中栏显示 `ReaderViewController` 占位内容。

- [x] `M1-013` 放置右侧目录容器
完成定义：右栏显示 `OutlineViewController` 占位内容。

- [x] `M1-014` 放置左侧垂直 tab 容器
完成定义：垂直模式下左栏可以承载 tab 列表。

### 3.3 文档模型与会话管理

- [x] `M1-020` 定义 `DocumentSession`
完成定义：至少包含 `id`、`url`、`title`、`pdfDocument`、`currentPageIndex`、`zoomScale`、`lastReadPosition`、`outlineTree`、`isDirty`、`sidebarState`、`tabPresentationState`。

- [x] `M1-021` 定义 `TabPresentationMode`
完成定义：枚举仅含 `verticalSidebar`、`horizontalTitlebar`。

- [x] `M1-022` 实现 `DocumentStore`
完成定义：支持打开、关闭、切换、查找 active session、切换 tab 模式。

- [x] `M1-023` 设计视图层订阅方式
完成定义：确定 `DocumentStore` 到各控制器的更新路径，避免直接耦合。

### 3.4 PDF 打开与显示

- [x] `M1-030` 接入 `PDFKit`
完成定义：工程成功链接 `PDFKit`，`ReaderViewController` 可持有 `PDFView`。

- [x] `M1-031` 实现 `Command+O` 打开文件
完成定义：可选择本地 PDF 文件并创建 session。

- [x] `M1-032` 打开 PDF 后显示内容
完成定义：active session 的 `PDFDocument` 能在中间阅读区显示。

- [x] `M1-033` 打开多个 PDF
完成定义：重复打开多个 PDF 时可得到多个 session。

### 3.5 Tab 展示与切换

- [x] `M1-040` 实现垂直 tab 列表
完成定义：左栏展示所有已打开文档、当前选中态、关闭入口。

- [x] `M1-041` 实现标题栏水平 tab 容器
完成定义：水平模式下 tab 出现在标题栏区域，不新增内容区 tab bar。

- [x] `M1-042` 实现 tab 模式切换
完成定义：可以在 `verticalSidebar` 与 `horizontalTitlebar` 间切换。

- [x] `M1-043` 统一 tab 切换命令
完成定义：垂直和水平两套 UI 都调用同一套切换逻辑。

- [x] `M1-044` 实现关闭 tab
完成定义：关闭当前或指定 session 后 active 文档行为正确。

### 3.6 Outline 与空状态

- [x] `M1-050` 解析 PDF outline
完成定义：从 `PDFDocument` 读出目录层级。

- [x] `M1-051` 定义 `OutlineNode`
完成定义：支持层级标题、目标页面、子节点。

- [x] `M1-052` 用 `NSOutlineView` 显示目录树
完成定义：当前文档有目录时可展开和查看。

- [x] `M1-053` 点击目录跳转页面
完成定义：点击目录节点后阅读区跳转到目标位置。

- [x] `M1-054` 实现无目录空状态
完成定义：没有 outline 时显示明确、简洁的空状态。

### 3.7 侧栏与会话恢复

- [x] `M1-060` 实现左右侧栏显隐
完成定义：不破坏中间阅读区布局。

- [x] `M1-061` 保存已打开文档列表
完成定义：应用退出前记录当前 session 集合。

- [x] `M1-062` 恢复上次打开会话
完成定义：重启后恢复文档列表、active session、tab 模式。

- [x] `M1-063` 为 `DocumentStore` 编写单元测试
完成定义：覆盖打开、关闭、切换、模式切换、恢复逻辑。

### 3.8 M1 验收

- [x] `M1-AC-01` 可以连续打开 3 个 PDF 并来回切换
- [x] `M1-AC-02` 垂直 tab 与水平标题栏 tab 可自由切换
- [x] `M1-AC-03` 两种 tab 模式下都能稳定切换文档
- [x] `M1-AC-04` 右侧目录跟随当前文档更新
- [x] `M1-AC-05` 无目录文档显示空状态
- [x] `M1-AC-06` 重启后恢复文档列表与 tab 模式

## 4. Milestone 2: 阅读体验与快捷键

### 4.1 阅读基础能力

- [x] `M2-001` 建立阅读配置文件
完成定义：启动时确保存在 `.toml` 配置文件，并能读取默认阅读模式与快捷键配置。

- [x] `M2-002` 实现阅读显示模式
完成定义：支持 `singlePage`、`singlePageContinuous`、`twoUp`、`twoUpContinuous` 四种模式切换。

- [x] `M2-003` 实现适应宽度
完成定义：支持显式触发 `fit width`，并可通过配置决定新打开文档是否默认适应宽度。

- [x] `M2-004` 持久化阅读位置
完成定义：至少保存页码、缩放、滚动位置，以及当前显示模式。

- [x] `M2-005` 恢复阅读位置
完成定义：重新打开同一文档可恢复阅读位置，并恢复上次显示模式与缩放状态。

### 4.2 搜索与最近文件

- [x] `M2-010` 实现当前文档搜索
完成定义：支持输入关键词并定位结果。

- [x] `M2-011` 实现最近文件存储
完成定义：记录最近打开列表，去重并排序。

- [x] `M2-012` 实现最近文件重开
完成定义：可以从最近文件列表重新打开 PDF。

- [x] `M2-013` 为 `ReadingPositionStore` 编写测试
完成定义：覆盖阅读配置与阅读状态的保存与恢复。

- [x] `M2-014` 为 `RecentFilesStore` 编写测试
完成定义：覆盖去重、顺序和读取。

### 4.3 快捷键系统

- [x] `M2-020` 建立统一快捷键入口
完成定义：文档、布局、阅读模式相关快捷键都通过同一套配置与菜单入口生效。

- [x] `M2-021` 接入 `a` 快捷键
完成定义：为高亮逻辑预留统一命令入口。

- [x] `M2-022` 接入 `Esc` 快捷键
完成定义：支持退出高亮模式。

- [x] `M2-023` 接入 `i` 快捷键
完成定义：支持切换反色夜间模式。

- [x] `M2-024` 快捷键冲突检查
完成定义：确认 `a`、`Esc`、`i` 与系统和文本输入上下文行为不冲突。

- [x] `M2-025` 接入 `Cmd+S` 快捷键
完成定义：保存命令统一进入当前文档批注保存流程。

默认快捷键方案：

- `Cmd+B`：切换左侧边栏
- `Cmd+Option+B`：切换右侧边栏
- `Cmd+Shift+1`：切换到垂直 sidebar tabs
- `Cmd+Shift+2`：切换到水平 titlebar tabs
- `Cmd+W`：关闭当前标签页
- `Cmd+Shift+[` / `Cmd+Shift+]`：切换到上一个 / 下一个标签页
- `Cmd+0`：适应宽度
- `Cmd+1` / `Cmd+2` / `Cmd+3` / `Cmd+4`：切换四种阅读显示模式

### 4.4 M2 验收

- [x] `M2-AC-01` 同一文档重新打开后能恢复到之前阅读位置
- [x] `M2-AC-02` 不同 tab 间切换时阅读状态互不污染
- [x] `M2-AC-02a` 默认阅读模式来自配置文件，默认值为单页连续
- [x] `M2-AC-02b` 适应宽度与四种显示模式都有快捷键入口
- [x] `M2-AC-03` 搜索结果可定位到文档具体位置
- [x] `M2-AC-04` 最近文件可用来重新打开历史 PDF
- [x] `M2-AC-05` `i` 可稳定切换夜间模式，`Esc` 可退出高亮模式
- [x] `M2-AC-06` `Cmd+S` 已接入当前文档保存命令
- [x] `M2-AC-07` 侧栏、tab 展示模式、当前 tab 关闭与 tab 切换快捷键都支持通过配置文件自定义

## 5. Milestone 3: 高亮与批注

### 5.1 默认高亮策略

- [x] `M3-001` 定义默认轻粉色高亮
完成定义：确定默认粉色的具体颜色值，满足“偏轻、低饱和、清晰”。

- [x] `M3-002` 将默认粉色接入 annotation 创建逻辑
完成定义：不额外选择颜色时，直接使用默认粉色。

- [x] `M3-003` 固定色板支持
完成定义：提供黄色、绿色、粉色三种颜色，默认选中粉色。

### 5.2 高亮交互流

- [x] `M3-010` 已有选区时按 `a` 立即高亮
完成定义：按键后立刻创建 annotation。

- [x] `M3-011` 无选区时按 `a` 进入高亮模式
完成定义：阅读器进入可见但克制的高亮模式状态。

- [x] `M3-012` 高亮模式下选中文字即自动高亮
完成定义：选区完成后自动生成默认粉色高亮。

- [x] `M3-013` 按 `Esc` 退出高亮模式
完成定义：退出后选择文本不再自动高亮。

- [x] `M3-014` 高亮模式状态可视反馈
完成定义：反馈足够清楚，但不破坏极简扁平风格。

### 5.3 批注管理

- [x] `M3-020` 删除高亮
完成定义：选中已有高亮后可以删除。

- [x] `M3-021` 建立批注脏状态
完成定义：创建或删除高亮后 session 进入未保存状态。

- [x] `M3-022` `Cmd+S` 手动保存批注到 PDF
完成定义：只在用户显式保存时覆盖写回源 PDF。

- [x] `M3-023` 自动保存策略模型
完成定义：至少支持 `after10Minutes` 和 `never`。

- [x] `M3-024` 默认自动保存策略
完成定义：新会话默认采用 `after10Minutes`。

- [x] `M3-025` 自动保存调度
完成定义：存在未保存批注时，按策略定时触发保存。

- [x] `M3-026` 自动保存关闭逻辑
完成定义：当策略为 `never` 时，不触发自动保存。

- [x] `M3-027` 未保存状态提示
完成定义：有未保存批注时 session / tab 状态正确反映。

- [x] `M3-028` 保存失败处理
完成定义：写回失败时保留脏状态，并提供轻量提示。

- [x] `M3-029` 高亮与保存测试
完成定义：覆盖 annotation 创建、颜色、删除、脏状态、手动保存、自动保存策略。

### 5.4 M3 验收

- [x] `M3-AC-01` 默认高亮色符合“偏轻粉色、低饱和但清晰”
- [x] `M3-AC-02` 选中文字后按 `a` 可以稳定添加高亮
- [x] `M3-AC-03` 无选区时按 `a` 进入高亮模式
- [x] `M3-AC-04` 高亮模式下选中文字即自动高亮
- [x] `M3-AC-05` 按 `Esc` 可以退出高亮模式
- [x] `M3-AC-06` 已有高亮可以删除
- [x] `M3-AC-07` 高亮后文档进入未保存状态，但不会立即覆盖源文件
- [x] `M3-AC-08` 按 `Cmd+S` 后当前文档批注被写回源 PDF
- [x] `M3-AC-09` 自动保存默认值为 `10 min`
- [x] `M3-AC-10` 自动保存可切换为 `never`
- [x] `M3-AC-11` 保存后重新打开 PDF，高亮仍存在

## 6. Milestone 4: 夜间模式与视觉打磨

### 6.1 夜间模式

- [x] `M4-001` 建立 `ThemeManager`
完成定义：提供夜间模式状态的单一入口。

- [x] `M4-002` 实现基础深色 UI
完成定义：窗口、侧栏、空状态、控件都进入统一深色体系。

- [x] `M4-003` 实现阅读区反色夜间模式
完成定义：文本 PDF 在夜间模式下明显更柔和可读。

- [x] `M4-004` 绑定 `i` 快捷键到夜间模式切换
完成定义：切换逻辑统一走 `ThemeManager`。

- [x] `M4-005` 处理扫描 PDF 的最小兼容方案
完成定义：即使无法完美反色，也能降低刺眼程度。

### 6.2 窗口与视觉

- [x] `M4-010` 标题栏压缩
完成定义：启用 `unifiedCompact` 并最小化 toolbar 存在感。

- [x] `M4-011` 优化水平标题栏 tab 样式
完成定义：与系统标题栏融为一体，不显臃肿；垂直 tab 打开时自动隐藏水平标题栏 tab，避免双 tab 同时出现。

- [x] `M4-012` 优化垂直 tab 样式
完成定义：轻量、扁平、紧凑，当前选中态清晰。

- [x] `M4-013` 优化边距与分栏拖动体验
完成定义：布局紧凑但不拥挤，拖动行为稳定。

- [x] `M4-014` 清理多余阴影和装饰
完成定义：整体视觉不厚重、不拟物。

### 6.3 M4 验收

- [x] `M4-AC-01` 深色模式下 UI 整体风格统一
- [x] `M4-AC-02` `i` 可即时切换夜间模式，切换后状态同步正确
- [x] `M4-AC-03` 夜间模式下文本 PDF 可读，不明显刺眼
- [x] `M4-AC-04` 顶部空间占用显著低于常规文档应用
- [x] `M4-AC-05` 整体视觉符合极简、扁平、紧凑目标

## 7. 当前推荐开工顺序

- [x] `NOW-01` 完成 `M1-001` 到 `M1-023`
- [x] `NOW-02` 完成 `M1-030` 到 `M1-044`
- [x] `NOW-03` 完成 `M1-050` 到 `M1-063`
- [x] `NOW-04` 做完 `M1-AC-*` 手测
- [x] `NOW-05` 再进入 `M2` 的快捷键系统
- [x] `NOW-06` 推进 `M3` 高亮 / 自动保存闭环

## 8. Milestone 5: 收口、设置与发布前稳固

### 8.1 真实 UAT

- [ ] `M5-001` 使用真实 PDF 跑完 `UAT-01` 到 `UAT-10`
完成定义：至少覆盖文本 PDF、扫描 PDF、带 outline PDF，多标签切换、保存与夜间模式都完成一次。

- [x] `M5-002` 记录 UAT 发现的问题
完成定义：把阻断问题或高频路径问题明确记录到本轮执行上下文中，并转成修复项。

本轮验证记录：

- 真实 PDF 手测已完成 `UAT-01` 到 `UAT-04`，覆盖了带 outline 文本 PDF、无 outline 中文 PDF、会话恢复与 tab 关闭主路径。
- `UAT-05` 到 `UAT-09` 的核心行为由现有批注保存测试、本轮新增配置持久化测试与 `DocumentStore` 回归测试覆盖。
- `UAT-10` 的状态切换逻辑与 window chrome 自动化测试通过，但在 Computer Use 下未能稳定观察到夜间模式的视觉切换。

### 8.2 稳定性修复

- [x] `M5-010` 修复 UAT 暴露的主路径问题
完成定义：问题集中在会话恢复、tab 切换、批注保存、夜间模式与设置闭环，不扩新功能线。

- [x] `M5-011` 为修复点补回归测试
完成定义：至少覆盖本轮改动影响到的状态与持久化逻辑。

### 8.3 最小设置窗口

- [x] `M5-020` 提供设置窗口入口
完成定义：菜单中可打开原生设置窗口，不引入多余面板体系。

- [x] `M5-021` 支持修改默认阅读模式
完成定义：设置变更后写回配置文件，并影响新打开文档。

- [x] `M5-022` 支持修改“打开时适应宽度”
完成定义：设置变更后写回配置文件，并影响新打开文档。

- [x] `M5-023` 支持修改批注自动保存策略
完成定义：至少支持 `10 min` 与 `never`，设置变更后写回配置文件。

### 8.4 文档与验收

- [x] `M5-030` 同步 `PROJECT.md` / `TASKS.md`
完成定义：行为变更与设置项说明同步到文档。

- [x] `M5-031` 跑完整自动化测试
完成定义：`swift test` 全量通过。

- [ ] `M5-032` 完成 M5 验收
完成定义：UAT 与自动化测试都通过，无阻断问题残留。

## 9. Milestone 6: 体验打磨与快捷键补齐

### 9.1 快捷键可见性与新增命令

- [x] `M6-001` plain 快捷键菜单可见
完成定义：`Annotate > Highlight Selection / Exit Highlight Mode / Remove Highlight` 与 `View > Toggle Night Mode` 菜单项右侧显示 `A`、`esc`、`D`、`I`；做法为把无修饰 `keyEquivalent` 显式写入菜单项。

- [x] `M6-002` `removeHighlight` 快捷键改为 `D`
完成定义：配置文件默认从 `command+shift+d` 迁移到 `d`；`AppConfigurationStore.bootstrapIfNeeded` 识别旧值并重写为新值；`AppConfigurationTests` 覆盖迁移。

- [x] `M6-003` 新增 `reopenLastClosed` 命令
完成定义：新增 `ShortcutCommand.reopenLastClosed`，默认快捷键 `Cmd+Shift+T`；File 菜单下新增 "Reopen Closed Tab" 入口。

- [x] `M6-004` 新增 `toggleAllPagesOverview` 命令
完成定义：新增 `ShortcutCommand.toggleAllPagesOverview`，默认快捷键 `Cmd+Shift+O`（`P` 已被 `highlight_color_pink` 占用）；View 菜单下新增 "All Pages Overview" 入口。

- [x] `M6-005` 新增 `gotoPage` / `zoomIn` / `zoomOut` 命令
完成定义：分别默认 `Cmd+Option+G` / `Cmd+=` / `Cmd+-`；菜单入口与配置字段同步。

- [x] `M6-006` 新增 Vim 式翻页 `J` / `K`
完成定义：新增 `ShortcutCommand.pageDown` / `pageUp`，默认 plain `j` / `k`；复用 `ReaderShortcutsController.shouldHandlePlainShortcut` 的文本输入避让规则；触发后调用 `pdfView.goToNextPage(_:)` / `goToPreviousPage(_:)`。

- [x] `M6-007` 新增历史导航 `Cmd+[` / `Cmd+]`
完成定义：新增 `ShortcutCommand.navigateBack` / `navigateForward`，默认 `Cmd+[` / `Cmd+]`；桥接到 `pdfView.goBack()` / `goForward()`；确保 outline / link / `Cmd+Option+G` / `Cmd+Shift+T` 等跳转都推入历史栈。同时修复 `applyReadingPositionIfNeeded` 重复入栈导致的双击返回问题。

### 9.2 高亮删除新逻辑

- [x] `M6-010` 基于鼠标位置的 annotation 命中
完成定义：在 `ReaderViewController` 中新增 `highlightAnnotation(at pointInWindow:)`，将窗口坐标 → `pdfView` → page，过滤 type == "Highlight" 最近的一个。

- [x] `M6-011` `D` 键删除当前悬停高亮
完成定义：`removeHighlightUnderCursor` 仅基于鼠标悬停位置命中；selection 回退分支已删除；快捷键 plain `d`。

- [x] `M6-012` 高亮删除测试
完成定义：`HighlightServiceTests.testHighlightAnnotationAtPointReturnsCoveringHighlight` 覆盖 point-in-rect 命中；`DocumentStoreTests` 覆盖删除后 `isDirty = true`。

### 9.3 缩略图与全览

- [x] `M6-020` 新增 `ThumbnailsViewController`
完成定义：基于 `PDFThumbnailView`，纵向单列；订阅 `documentStoreDidChange`，跟随 active session 切换文档；点击缩略图跳转对应页。实现落在 `VerticalTabsViewController` 内的 Thumbnails 模式。

- [x] `M6-021` 左栏承载 Tabs / Thumbnails 两种模式
完成定义：左栏顶部 `NSSegmentedControl`（Tabs / Pages）切换；状态暂存在 controller 内。

- [x] `M6-022` 全览 Grid 模式
完成定义：`ReaderViewController` 叠加 `PDFThumbnailView` grid；`Cmd+Shift+O` 切换；`Esc` 退出。

- [ ] `M6-023` 缩略图性能验证
完成定义：在 200+ 页真实 PDF 上切换 / 滚动 / 跳转不卡顿；必要时使用 `PDFThumbnailView` 的异步渲染选项。

### 9.4 重开最近关闭

- [x] `M6-030` `DocumentStore` 维护 closed 栈
完成定义：新增 `recentlyClosedStack: [URL]`；`close(sessionID:)` 在 `ReadingPositionStore` 保存完状态后 push；上限 10 条；暴露 `popRecentlyClosed() -> URL?`。

- [x] `M6-031` 绑定 `Cmd+Shift+T` 行为
完成定义：菜单 / 快捷键触发后 pop URL 并 `open(documentAt:)`；没有可恢复项时菜单 disabled。

- [x] `M6-032` 测试
完成定义：`DocumentStoreTests` 覆盖 push / pop / cap 行为。

### 9.5 窗口标题栏 / 底部状态栏

- [x] `M6-040` 清理 "Documents" 文字
完成定义：`window.title` 置空不再回填 active session 标题到系统可见处；`titlebarTabsItem.label` / `paletteLabel` 清空；在 vertical tab 模式下红绿灯附近不再出现文字。

- [x] `M6-041` Outline 右下角页码状态栏
完成定义：`OutlineViewController` 底部加一个 22–24pt 的 `NSTextField`，订阅 `documentStoreDidChange` + `PDFViewPageChanged`，显示 `当前页 / 总页数`；无 active session 时显示占位或隐藏。

### 9.6 延伸项

- [x] `M6-050` Tab 上 dirty 圆点
完成定义：`VerticalTabsItemView` / `TitlebarTabItemView` 上对 `isDirty` session 渲染一个 4–6pt 圆点。

- [x] `M6-051` Find bar 非模态化
完成定义：`Cmd+F` 打开内嵌 `FindBarView`（reader 顶部），支持 `Cmd+G` / `Cmd+Shift+G` 遍历；`Esc` 收起。旧的 `NSAlert` 入口删除。

- [x] `M6-052` 跳转到页 N
完成定义：`Cmd+Option+G` 弹出 mini 输入框或 inline 框；越界提示；成功跳转后推入历史栈。

- [x] `M6-053` 缩放快捷键
完成定义：`Cmd+=` / `Cmd+-` 各递增 / 递减当前缩放 10%；保持 `scaleMode = .manual`。

- [x] `M6-054` Vim 翻页行为
完成定义：在非文本输入上下文下，plain `J` / `K` 触发 `pdfView.goToNextPage(_:)` / `goToPreviousPage(_:)`；连续快速按键不丢帧；测试覆盖 `ReaderShortcutsControllerTests`。

- [x] `M6-055` PDF 内链接跳转
完成定义：验证 `PDFView` 默认接管 `Link` annotation；对内部链接跳转进入历史栈（自动或手动推入）；对外部 URL 走 `NSWorkspace.shared.open(_:)`；对不可识别链接不崩溃。

- [x] `M6-056` 历史栈与 `Cmd+[` / `Cmd+]`
完成定义：`pdfView.goBack()` / `goForward()` 挂接到快捷键；验证从 outline 点击、内链跳转、`Cmd+Option+G`、`Cmd+Shift+T` 触发的跳转都可被回退；菜单项根据 `canGoBack` / `canGoForward` 自动 enable / disable。额外修复：`applyReadingPositionIfNeeded` 在 pdfView 已在目标页时跳过 `go(to:)`，避免 store ↔ reader 回环重复入栈。

### 9.7 文档与验收

- [x] `M6-060` 同步文档
完成定义：`PROJECT.md` / `TASKS.md` / `AGENTS.md` 中快捷键、默认配置、交互边界同步；`config.toml` 默认内容更新。

- [x] `M6-061` `swift test` 全量通过
完成定义：M6 新增测试及回归测试全部通过。

- [ ] `M6-062` M6 验收
完成定义：`AC-M6-01` 至 `AC-M6-14` 全部通过，UAT 手测记录到位（待真实 PDF 手测：UAT-11 至 UAT-21）。

## 10. Milestone 7: 搜索强化与对比阅读

### 10.1 搜索结果面板

- [ ] `M7-001` 搜索模型升级
完成定义：将 `findString` 的全部结果缓存到当前 session 临时搜索状态；非当前文档或关闭 find bar 时清空；提供 `matches: [(page, snippet, range)]`。

- [ ] `M7-002` find bar 下挂结果列表
完成定义：M6 的非模态 find bar 底部扩展一个可折叠 `NSTableView` / `NSCollectionView`；按页分组显示；点击跳转并推入历史栈。

- [ ] `M7-003` 结果导航键绑定
完成定义：find bar 有焦点时 `↑` / `↓` 在列表移动，`Enter` 跳转；与 `Cmd+G` 行为一致。

- [ ] `M7-004` 搜索性能
完成定义：200+ 页 PDF 上搜索常见词，首次命中 < 500ms；滚动结果列表不卡顿（必要时分批渲染）。

- [ ] `M7-005` 跨文档搜索（可选）
完成定义：find bar 顶部 toggle "This Document" / "All Open"；跨文档结果带 session 名；点击先切换 session 再跳转。

### 10.2 分屏 / 多窗口

- [ ] `M7-010` 同窗分屏容器
完成定义：`SplitViewController` 中栏拆成水平双 Reader；进入 / 退出由 `Cmd+Ctrl+\` 触发；每个 Reader 持有独立 `displayedSessionID`。

- [ ] `M7-011` 分屏下 tab 切换落点
完成定义：从左栏激活一个 session 时，默认进入"焦点 Reader"；支持 `Option+Click` / 专门命令把 session 丢到另一侧。

- [ ] `M7-012` 分屏状态持久化
完成定义：`PersistedDocumentStoreState` 增加分屏布局字段；重启恢复。

- [ ] `M7-013` 新建窗口命令
完成定义：新增 `ShortcutCommand.newWindow`，默认 `Cmd+Shift+N`；`AppDelegate` 支持多 `MainWindowController` 实例；`DocumentStore` 单例对外暴露多窗口接口。

- [ ] `M7-014` 多窗口关闭协调
完成定义：关闭窗口不影响其他窗口 session；最后一个窗口关闭时走现有 terminate 流程；`Cmd+Shift+T` 优先在当前窗口内重开。

- [ ] `M7-015` 多窗口状态持久化
完成定义：记录每个窗口的 active session 与布局；重启恢复，可降级为默认单窗口并给出说明。

- [ ] `M7-016` 测试
完成定义：`DocumentStoreTests` 覆盖多窗口场景；`MainWindowControllerTests`（若新建）覆盖分屏切换。

### 10.3 文档与验收

- [ ] `M7-020` 同步文档
完成定义：`PROJECT.md` / `TASKS.md` / `config.toml` 更新；`AGENTS.md` 的产品规则若有扩展一并更新。

- [ ] `M7-021` M7 验收
完成定义：`AC-M7-1` 至 `AC-M7-5` 全部通过。

## 11. Milestone 8: 批注深度化

### 11.1 批注管理器

- [ ] `M8-001` 批注模型扩展
完成定义：对每个 highlight 抽取 `snippet`（选中文本）、`pageIndex`、`color`、`createdAt`（若可从 PDF 获取，否则 session 内维护）。

- [ ] `M8-002` 右栏 Annotations 模式
完成定义：`OutlineViewController` 外层加 segmented control：Outline / Annotations；Annotations 列表按页分组，显示 snippet + 颜色点。

- [ ] `M8-003` 点击跳转并高亮
完成定义：点击列表项跳转目标页并短暂强调对应 annotation。

- [ ] `M8-004` dirty 变更同步
完成定义：增删 highlight 后 Annotations 列表实时更新。

### 11.2 导出高亮

- [ ] `M8-010` 抽取导出内容
完成定义：抽取全部 highlight → `[(page, snippet, color)]`；按页排序。

- [ ] `M8-011` 导出格式
完成定义：Markdown / Plain / JSON 三选；每种格式都覆盖 snippet、页码、颜色。

- [ ] `M8-012` 输出目标
完成定义：`File > Export Highlights…` 菜单；`Cmd+Shift+E` 直接复制 Markdown 到剪贴板；"Save as…" 走 `NSSavePanel`。

- [ ] `M8-013` 测试
完成定义：`HighlightExporterTests` 覆盖三种格式输出稳定。

### 11.3 自定义快捷键 UI

- [ ] `M8-020` Shortcuts 面板
完成定义：设置窗口新增 Shortcuts tab；列出所有 `ShortcutCommand` + 当前绑定 + 默认值。

- [ ] `M8-021` key-capture 控件
完成定义：自定义 `NSView` 捕获用户按键，转成 `KeyboardShortcut`；支持清除 / 恢复默认。

- [ ] `M8-022` 冲突检测
完成定义：改绑定时检测同组合已被其他命令占用；拒绝或提示。

- [ ] `M8-023` 写回配置
完成定义：保存按钮触发 `configStore.save` 并 `updateAppConfiguration`；成功后菜单项的 `keyEquivalent` 立即刷新。

- [ ] `M8-024` 测试
完成定义：`AppConfigurationTests` 覆盖从 UI 模拟输入 → 写回 config.toml → 重读的闭环。

### 11.4 文档与验收

- [ ] `M8-030` 同步文档
完成定义：`PROJECT.md` / `TASKS.md` / `config.toml` 默认内容 / 设置界面说明同步。

- [ ] `M8-031` M8 验收
完成定义：`AC-M8-1` 至 `AC-M8-4` 全部通过。

## 12. Milestone 9: 扩展生态（长期预研）

- [ ] `M9-001` 扩展机制 RFC
完成定义：在 `docs/extensions-rfc.md` 中列选型与决策，候选路径至少包含：进程内 Swift 插件、URL scheme、外部 CLI、WebKit 壳。

- [ ] `M9-002` PoC 用例
完成定义：若决策继续，选一条路径把"导出高亮"重写为插件；能在当前 app 中运行。

- [ ] `M9-003` Slate Extension API 草稿
完成定义：面向未来扩展开发者的接口草稿，覆盖最小用例。

- [ ] `M9-004` 风险与推迟说明
完成定义：若决策推迟，把"为什么现在不做"写清楚（安全、上架、维护成本等）。

## 13. 手测清单

- [x] `UAT-01` 打开 3 个 PDF，分别在垂直与水平 tab 模式下切换
- [x] `UAT-02` 切换文档时目录同步变化
- [x] `UAT-03` 关闭当前 tab 后 active 文档正确
- [x] `UAT-04` 重启后恢复文档、active session、tab 模式
- [x] `UAT-05` 选中文字按 `a` 直接生成默认轻粉色高亮
- [x] `UAT-06` 无选区按 `a` 进入高亮模式，`Esc` 退出
- [x] `UAT-07` 高亮后未按 `Cmd+S` 时，源文件未被立刻覆盖
- [x] `UAT-08` 按 `Cmd+S` 后重新打开 PDF，标注仍存在
- [x] `UAT-09` 自动保存策略默认是 `10 min`，并可切换为 `never`
- [x] `UAT-10` 按 `i` 切换夜间模式
- [x] `UAT-11` 菜单中 `A` / `I` / `D` / `Esc` 快捷键文字可见
- [ ] `UAT-12` 光标悬停在高亮上按 `D` 直接删除该高亮
- [ ] `UAT-13` 左栏切到 Thumbnails 模式，点击缩略图能跳转
- [ ] `UAT-14` `Cmd+Shift+O` 进入全览，`Esc` 退出
- [x] `UAT-15` `Cmd+Shift+T` 能重开最近关闭的文件
- [x] `UAT-16` 窗口顶栏不再出现 "Documents"，红绿灯不被遮挡
- [x] `UAT-17` 右侧 Outline 底部显示 `当前页 / 总页数`
- [x] `UAT-18` `Cmd+Option+G` 输入页码能跳转，越界输入有提示
- [x] `UAT-19` 非输入态下 `J` / `K` 稳定地下 / 上翻页
- [x] `UAT-20` 点击 PDF 内部链接能跳转到目标位置
- [x] `UAT-21` 跳转后 `Cmd+[` 能回到起跳点，`Cmd+]` 可再前进
- [ ] `UAT-22` find bar 能看到全部匹配项列表，点击可跳转
- [ ] `UAT-23` 至少 200 页 PDF 搜索常见词不卡顿
- [ ] `UAT-24` `Cmd+Ctrl+\` 进入同窗分屏，两侧独立切换 session 不污染
- [ ] `UAT-25` `Cmd+Shift+N` 新建窗口，两窗口独立且关闭互不影响
- [ ] `UAT-26` 右栏 Annotations 模式能列出所有高亮，点击跳转
- [ ] `UAT-27` 导出高亮为 Markdown / 纯文本 / JSON 输出正确
- [ ] `UAT-28` 设置窗口 Shortcuts 面板改绑定后新会话生效，冲突被拒
- [ ] `UAT-29` 扩展机制 RFC 存在并已评审（M9 存在的证据）

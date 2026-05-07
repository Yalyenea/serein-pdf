# PDF Reader for macOS

面向 macOS 的极简 PDF 阅读器。左侧文档 tabs(可切换到标题栏水平 tabs),右侧 Outline / Pages / Search / Annotations,中间沉浸式阅读区(支持同窗分屏与多窗口)。风格:极简、扁平、紧凑。

## 1. 产品原则

1. 左栏只回答"正在看哪些文档"、右栏只回答"当前文档结构"、中栏只回答"阅读本身"。
2. tab 形态可切换,垂直与水平模式共享同一套文档模型。
3. 水平 tab 复用 macOS 标题栏,不额外占内容高度。
4. 视觉极简扁平紧凑,避免厚重装饰、强阴影、松散间距。
5. 高频操作键盘驱动。
6. 不引入 fallback、兜底逻辑、不必要兼容层。

## 2. 范围

### 2.1 V1 涵盖

文档管理 / 阅读(单·双页、适应宽度、缩放、翻页)/ Outline / Search / 会话恢复 / 当前文档与跨打开文档搜索 / 文本高亮 / 高亮评论 / 删除高亮 / 手动 & 自动保存 / 高亮导出(Markdown / Plain / JSON) / 深色主题 / 反色夜间 / 配置化快捷键 / 设置窗口 / 侧栏显隐 & 互换 / 全览 grid / show all tabs / 历史前进后退 / 重开最近关闭 / find bar / 跳转页 / Vim 翻页 / 高亮撤销(50 步) / 同窗分屏 / 多窗口恢复。

### 2.2 V1 明确不做

- 自研 PDF 渲染器(直接 `PDFKit`)
- 文件树 / Finder 式侧栏
- 云同步 / 书签库 / 知识库
- 完美夜间模式 / 复杂微动效

## 3. 技术架构

### 3.1 选型

| 层级 | 选择 |
|---|---|
| 语言 | Swift |
| UI | AppKit(主阅读窗口)|
| PDF | PDFKit |
| 目录树 | NSOutlineView |
| 布局 | NSSplitViewController |
| 窗口样式 | `NSWindow.ToolbarStyle.unifiedCompact` |

### 3.2 架构图

```mermaid
flowchart LR
    A["AppDelegate"] --> B["MainWindowController * N"]
    B --> C["SplitViewController"]
    C --> D["VerticalTabsViewController"]
    C --> E["ReaderWorkspaceViewController"]
    C --> F["RightSidebarViewController"]
    C --> G["TitlebarTabsController"]
    E --> E1["Primary ReaderViewController"]
    E --> E2["Secondary ReaderViewController"]
    F --> F1["OutlineViewController"]
    F --> F2["PDFThumbnailView (Pages)"]
    F --> F3["SearchResultsViewController"]
    F --> F4["AnnotationsViewController"]
    D --> H["DocumentStore"]
    E --> H
    F --> H
    G --> H
    H --> I["DocumentSession"]
    H --> J["WindowWorkspace"]
    E1 --> K["PDFView / lazy PDFDocument"]
    E2 --> K
    E1 --> L["HighlightService + Undo"]
    E2 --> L
    E1 --> M["ThemeManager"]
    E2 --> M
    H --> N["ReadingStateStore"]
    H --> O["RecentFilesStore"]
```

### 3.3 关键设计决策

| 决策 | 结论 |
|---|---|
| 多文档管理 | `DocumentStore` 持有多个 `DocumentSession` |
| 多窗口管理 | 单 `DocumentStore` 持有多个 `WindowWorkspace`;每窗独立维护自己的 session/tab 集合,窗口只承载视图与交互 |
| tab 展示 | `verticalSidebar` / `horizontalTitlebar` 动态切换,共用同一套文档切换命令 |
| 中栏承载 | `ReaderWorkspaceViewController` 管理单 Reader / 双 Reader 分屏 |
| 目录来源 | 右栏需要时才从 `PDFDocument.outlineRoot` 抽取 `OutlineNode` |
| 搜索预览 | find bar 只负责输入 / scope / 导航,所有 preview 与命中列表都放右栏 |
| 搜索范围 | `This Document` / `All Open`;`All Open` 只覆盖当前窗口已打开文档,跨文档命中点击先切 session 再跳转 |
| 批注存储 | highlight group 共享 comment;dirty 后 `Cmd+S` 或自动保存策略触发时写回源 PDF |
| 自动保存 | 默认 `10 min`,可设 `never` |
| 分屏默认 | 新窗口始终空白且默认单屏;跨启动恢复也默认回到单屏;分屏只作为当前运行期内的主动切换状态 |
| 状态持有 | 阅读状态 / 缩放 / 翻页 / dirty / undoStack / searchCache 挂在 `DocumentSession`;live `PDFDocument` 由 `DocumentStore` 小容量 LRU 按需持有;窗口 UI 状态挂在 `WindowWorkspace` |
| 左右互换 | `layout.sidebarsSwapped` 翻转时 split items 重排,per-session 宽度 / 可见状态原子对调 |
| 高亮撤销 | 每 session 独立 undo 栈,上限 50,无 redo |
| 视图层订阅 | 通过 `Notification.Name.documentStoreDidChange` 与 `PDFViewPageChanged`,视图层不持业务状态 |

## 4. UI 与交互

### 4.1 信息架构

| 区域 | 职责 | 边界 |
|---|---|---|
| 左栏 Vertical Sidebar | 已打开文档 tabs | 不放 outline / 不放缩略图 / 不做文件树 |
| 标题栏 Horizontal Tabs | 水平模式下的 tab strip | 占标题栏,不新增内容区 tab bar |
| 中栏 Reader Workspace | PDF 渲染、选择、find bar、批注、全览、同窗分屏 | 单窗最多双 Reader,焦点 pane 决定 tab 落点 |
| 右栏 Sidebar | Outline / Pages / Search / Annotations (segmented 切换) | 所有预览类内容都在右栏,不回流到中栏 |
| 左右互换 | 配置项或 `Cmd+Shift+X` | 不改变上述职责,仅改变物理位置 |

### 4.2 视觉规范

- 紧凑布局,轻量圆角,无厚重阴影
- 侧栏平铺嵌入,最多保留一条淡分割线(禁悬浮 / 液态玻璃 / 漂浮面板感)
- 按钮 / tab 视觉重量轻,突出选中态
- 水平 tab 与系统标题栏融为一体
- 外观配置拆为 `Mode` + `Light Theme` + `Dark Theme`,默认 `system + normal + rose_pine_moon`
- 亮色至少支持 `normal` / `rose_pine_dawn`,暗色至少支持 `normal` / `rose_pine_moon`
- `rose_pine_dawn` 不只改阅读区外围,也把 PDF 白底映射成暖纸色
- 反色夜间模式采用暖色、低刺激的 Rose Pine Moon 映射,避免生硬黄蓝互翻
- `Settings` 按当前页内容自适应尺寸,`Shortcuts` 页会自动放大到合适大小
- 高亮模式提示使用轻量 inline 状态,不使用居中大块 badge
- 默认高亮色:偏轻、低饱和但清晰的粉色

### 4.3 快捷键总表

配置文件:`~/Library/Application Support/Serein/config.toml` — schema 与默认值见 `Core/AppConfiguration.swift`。

**批注**
- `A`:有选区 → 立即高亮;无选区 → 进入高亮模式
- `Esc`:退出高亮模式 / 关闭 Find bar / 退出全览
- `D`:删除鼠标所在高亮(多行整组删除)
- `Cmd+S`:写回源 PDF
- `Cmd+Z`:撤销最近一次高亮新增或删除(上限 50,无 redo)

**阅读**
- `Cmd+0` / `Cmd+9`:适应宽度 / 适应高度
- `Cmd+=` / `Cmd+-`:放大 / 缩小(进入 manual 缩放)
- `Cmd+1` / `Cmd+2` / `Cmd+3` / `Cmd+4`:`singlePage` / `singlePageContinuous` / `twoUp` / `twoUpContinuous`
- `J` / `K`:下一页 / 上一页(文本输入上下文让路)
- `Ctrl+D` / `Ctrl+U`:下滚 / 上滚半页
- `G` / `g`:跳到文末 / 文首
- `Cmd+Option+G`:跳转到页 N(越界给轻量提示)
- `Cmd+[` / `Cmd+]`:历史后退 / 前进
- `Cmd+F` / `Cmd+G` / `Cmd+Shift+G`:Find bar / 下一 / 上一 匹配
- Find bar 内 `↑` / `↓` / `Enter`:选择上一 / 下一结果 / 首次提交搜索;同一 query 连续 `Enter` 继续跳转
- `I`:切换 light / dark mode,并保留各自已选 theme

**文档与 tab**
- `Cmd+O`:打开 PDF 或文件夹(自动扫描并打开文件夹内 PDF,支持多选文件夹)
- `Cmd+R`:在 Finder 中显示当前 PDF
- `Cmd+W`:关闭当前 tab
- `Cmd+Shift+T`:重开上次关闭(栈上限 10)
- `Cmd+Shift+N`:新建窗口
- `Cmd+Shift+Space`:最近文件启动器
- `Ctrl+Tab`:显示当前窗口所有 tabs 的轻量文本总览;点击 / Enter 切换,`Option+Click` / `Option+Enter` 打开到另一 pane;重复 `Ctrl+Tab` 或 `Esc` 关闭
- `Cmd+Shift+[` / `Cmd+Shift+]`:上一 / 下一 tab
- `Option+Click` tab:丢到另一 pane(必要时自动开分屏)

**布局**
- `Cmd+B` / `Cmd+Option+B`:切换左 / 右侧栏
- `Cmd+Shift+1` / `Cmd+Shift+2`:垂直 sidebar tabs / 水平 titlebar tabs
- `Cmd+Shift+L`:右栏 Outline / Pages 切换
- `Cmd+Ctrl+\`:切换同窗分屏(新窗口与重启恢复默认单屏)
- `Cmd+Shift+O`:进入 / 退出全览(自动隐藏左右侧栏,`Esc` 退出)
- `Cmd+L`:进入 / 退出演示模式(直接全屏播放,页面完整适配,退出后恢复进入前布局)
- `Cmd+Ctrl+L`:进入 / 退出沉浸模式(隐藏侧栏与 tab chrome,只保留 PDF 页面)
- `Cmd+Shift+X`:互换左右侧栏(宽度 / 可见状态随内容迁移)

**系统**
- `Cmd+H` / `Cmd+Option+H`:隐藏当前 app / 隐藏其他 app
- `Cmd+M`:最小化当前窗口

### 4.4 批注保存策略

- 高亮新增 / 删除后只更新 session 与 dirty 标记,**不立即落盘**
- 多行高亮视为一组,删除任一行时整组删除
- `Cmd+S`:当前文档未保存批注覆盖写回源 PDF
- 关闭 dirty tab 或退出 app 时必须提示 `Save / Cancel / Discard`
- 自动保存:默认 `10 min`,至少支持 `10 min` / `never`;失败需显式提示

## 5. 数据模型

### 5.1 `DocumentSession`

| 字段 | 说明 |
|---|---|
| `id: UUID` | session 唯一标识 |
| `url: URL` | PDF 位置 |
| `title: String` | 标题或文件名 |
| `pageCount: Int?` | 激活或搜索后得到的页数元数据 |
| live `PDFDocument` | 不存入 session,由 `DocumentStore` 按需加载并通过小容量 LRU 保留当前 / 分屏 / 最近文档 |
| `currentPageIndex: Int` | 当前页 |
| `displayMode` | 四种阅读模式 |
| `scaleMode` | `fitWidth` / `manual` |
| `zoomScale: CGFloat` | 缩放比例 |
| `lastReadPosition` | 页码 + 页内位置 |
| `outlineTree: [OutlineNode]` | 目录树 |
| `isDirty: Bool` | 是否有未保存批注 |
| `sidebarState` | 左右栏显隐 / 宽度 |
| `tabPresentationState` | 当前 tab 模式下的局部状态 |
| `annotationSavePolicy` | `after10Minutes` / `never` |
| `undoStack` | 高亮撤销栈,上限 50 |
| `searchCache` | 当前 query 的匹配缓存(snippet + page + selection) |

### 5.2 `DocumentStore`

- 管理 sessions(open / close / activate / reorder)
- 维护多个 `WindowWorkspace`,驱动多窗口 / 分屏 / 焦点 pane / 右栏模式 / 搜索 scope
- 每个 `WindowWorkspace` 独立维护自己的 session/tab 集合,open/close 不跨窗扩散
- 维护 active session,驱动左栏 tab 与中栏 reader 联动
- 按需创建 `PDFDocument`,用小容量 LRU 保留当前 pane / 分屏 pane / 最近文档;干净后台文档可释放
- 持久化阅读状态 / 最近文件 / 每窗口最近关闭栈(上限 10)
- 提供 tab 模式切换
- 左右互换时对调 per-session 宽度 / 可见状态

### 5.3 `WindowWorkspace`

| 字段 | 说明 |
|---|---|
| `id: UUID` | window 唯一标识 |
| `sessionIDs: [UUID]` | 当前窗口拥有的 tab 顺序 |
| `tabPresentationMode` | 当前窗口 tabs 形态 |
| `rightSidebarMode` | `outline` / `pages` / `search` |
| `searchQuery` / `searchScope` | 当前窗口搜索上下文 |
| `isSplitEnabled` | 是否双 Reader |
| `primarySessionID` / `secondarySessionID` | 两个 pane 当前展示的 session |
| `focusedPane` | tab 激活与搜索跳转的落点 |
| `recentlyClosedURLs` | 本窗最近关闭栈 |
### 5.4 辅助模型

| 模型 | 用途 |
|---|---|
| `ReaderState` | 阅读区 UI 状态 |
| `OutlineNode` | 目录树节点 |
| `ReadingPosition` | 页码 + 页内定位 |
| `TabPresentationMode` | `verticalSidebar` / `horizontalTitlebar` |
| `AnnotationSavePolicy` | `after10Minutes` / `never` |
| `HighlightUndoOperation` | undo 栈元素 |

## 6. 项目结构

```text
App/                                      # AppKit 入口、窗口与设置/启动器
  AppMain.swift                           # @main 入口,构造 NSApplication 与 AppDelegate 并 run
  AppDelegate.swift                       # 应用委托:菜单、窗口生命周期、配置加载、自动保存驱动
  MainWindowController.swift              # 主窗口控制器:工具栏、titlebar tabs 宿主、demo/immersive 模式
  ReaderShortcutWindow.swift              # 自定义 NSWindow,拦截 keyDown 分发 plain(无 modifier)快捷键
  SplitViewController.swift               # 三栏 NSSplitViewController:左 tabs / 中 reader / 右 sidebar
  SettingsWindowController.swift          # 设置窗口:外观 / 阅读 / 批注 / 快捷键 配置 UI
  RecentFilesPaletteController.swift      # Spotlight 风格最近文件启动器的窗口与交互控制器
  RecentFilesPaletteState.swift           # 最近文件启动器的查询匹配与多选状态(纯模型)
  OpenTabsPaletteController.swift         # 当前窗口所有 tabs 轻量文本总览
  OpenTabsPaletteState.swift              # tabs 总览的选中状态(纯模型)

Core/                                     # 文档 / 窗口 / 配置 / 持久化 核心模型
  AppConfiguration.swift                  # config.toml schema、默认值与 AppConfigurationStore 读写
  DocumentStore.swift                     # 多文档 + 多窗口中枢:sessions / workspaces / 命令入口
  DocumentStorePersistence.swift          # UserDefaults 编解码 sessions / workspaces / 分屏状态
  DocumentSession.swift                   # 单文档会话:页码、缩放、显示模式、dirty、undo 栈等
  DocumentAnnotations.swift               # 高亮分组 / 缓存 / 导出 相关数据模型
  DocumentSearch.swift                    # PDF 全文匹配与 preview snippet 构造(DocumentSearchService)
  WindowWorkspace.swift                   # 单窗口状态:tab 顺序、侧栏、搜索、分屏、焦点 pane
  OutlineExtractor.swift                  # PDFDocument.outlineRoot → [OutlineNode] 转换
  OutlineNode.swift                       # Outline 树节点数据结构
  ReaderState.swift                       # 阅读区 UI 状态(夜间、高亮模式、高亮颜色)
  ReaderDisplayMode.swift                 # 显示模式 / 缩放模式 / ShortcutCommand 枚举
  ReadingPosition.swift                   # 页码 + 页内坐标的阅读位置
  ReadingStateStore.swift                 # 每 PDF 的阅读状态 UserDefaults 持久化
  RecentFilesStore.swift                  # 最近文件 URL 栈 UserDefaults 持久化
  PDFTextSanitizer.swift                  # PDF 文本清洗(去控制字符、折叠空白)

UI/LeftTabs/                              # 左侧垂直 tabs
  VerticalTabsViewController.swift        # 左侧 tabs 列表视图控制器,含可选最近文件 footer
  VerticalTabItemView.swift               # 单个垂直 tab 条目视图

UI/TitlebarTabs/                          # 标题栏水平 tabs
  TitlebarTabsController.swift            # 标题栏 tabs 控制器,挂在 NSToolbarItem 上
  TitlebarTabItemView.swift               # 单个水平 tab 条目视图

UI/CenterReader/                          # 中栏阅读区
  ReaderWorkspaceViewController.swift     # 中栏 workspace:单 / 双 Reader 分屏 + 焦点 pane
  ReaderViewController.swift              # 单 Reader:PDFView、find bar、高亮、全览 grid 等交互
  PDFContainerView.swift                  # PDFView 宿主,切夜间模式时同步背景色
  ReaderShortcutsController.swift         # plain 快捷键(j/k/g/…)分发
  FindBarView.swift                       # find bar:查询框 + scope 切换 + 匹配导航按钮

UI/RightOutline/                          # 右栏 outline / pages / search / annotations
  RightSidebarViewController.swift        # 右栏容器,segmented 切换四种子模式
  OutlineViewController.swift             # 目录树 NSOutlineView
  SearchResultsViewController.swift       # 搜索命中列表,支持跨 session 跳转
  AnnotationsViewController.swift         # 批注列表与 comment 编辑

UI/Shared/                                # 跨栏复用视图
  PlaceholderViewController.swift         # 侧栏空状态 / 占位视图

Features/Annotations/                     # 高亮批注功能域
  HighlightColor.swift                    # 高亮颜色枚举(pink / yellow / green)与相近色匹配
  HighlightService.swift                  # 应用 / 删除 / 重建 高亮的核心逻辑
  HighlightExporter.swift                 # 高亮导出 Markdown / Plain / JSON
  HighlightOCRService.swift               # 扫描件高亮走 Vision OCR 提取 snippet
  HighlightUndoOperation.swift            # 撤销栈元素:added / removed

Features/Theme/                           # 主题与夜间模式
  ThemeManager.swift                      # ReaderState 包装:夜间、高亮模式、高亮颜色
  NightModeStyle.swift                    # 夜间反色与 Rose Pine Moon 色彩映射样式

Resources/                                # 资源
  Info.plist                              # Bundle 信息与 PDF 文档类型声明
  AppIcon.icns                            # 应用图标(发布)
  AppIcon.png                             # 应用图标(源文件)

Scripts/                                  # 打包脚本
  make-app.sh                             # 构建 .app(ad-hoc 签名)
  make-dmg.sh                             # 打包 .dmg
  make-icon.sh                            # 生成 .icns 图标

Tests/SereinTests/                      # Swift Testing + XCTest 测试套件
  AppConfigurationTests.swift             # 配置加载 / 写回 / shortcut 冲突
  DocumentStoreTests.swift                # 多文档 / 多窗口 / 分屏 / 搜索 scope 等核心行为
  ReadingStateStoreTests.swift            # 阅读状态持久化
  RecentFilesStoreTests.swift             # 最近文件栈
  OutlineExtractorTests.swift             # PDF outline 解析
  OutlineViewControllerTests.swift        # 目录树视图交互
  VerticalTabsViewControllerTests.swift   # 左栏 tabs 行为
  TitlebarTabsControllerTests.swift       # (若存在)标题栏 tabs 行为,否则见 WindowChromeTests
  RightSidebarViewControllerTests.swift   # 右栏 segmented 切换
  SearchNavigationTests.swift             # 搜索结果导航与跨 session 跳转
  FindBarViewTests.swift                  # find bar 输入 / scope / 导航
  AnnotationsViewControllerTests.swift    # 批注列表 / comment 编辑
  AnnotationSaveTests.swift               # 手动 / 自动批注保存策略
  HighlightServiceTests.swift             # 高亮 apply / remove / 分组
  HighlightExporterTests.swift            # 三种导出格式
  HighlightUndoTests.swift                # 撤销栈上限与 added/removed 还原
  NightModeStyleTests.swift               # 夜间反色映射
  ReaderShortcutsControllerTests.swift    # plain 快捷键分发与文本上下文让路
  RecentFilesPaletteStateTests.swift      # 启动器模型的过滤 / 多选
  RecentFilesPaletteControllerTests.swift # 启动器控制器交互
  OpenTabsPaletteStateTests.swift         # show all tabs 预览目标与网格选中
  OpenTabsPaletteControllerTests.swift    # show all tabs 鼠标 / 键盘切换交互
  WindowChromeTests.swift                 # 窗口 chrome / 工具栏 / titlebar tabs 行为
```

## 7. 已完成里程碑(概览)

| 里程碑 | 状态 | 要点 |
|---|---|---|
| M1 MVP 骨架 | ✅ | 三栏、`DocumentStore`、tab 双模式、outline、会话恢复 |
| M2 阅读体验 | ✅ | 四种阅读模式、适应宽度、搜索、最近文件、阅读位置持久化、快捷键系统 |
| M3 高亮批注 | ✅ | 选区 + 键盘 `a` 高亮、`D` 删除、手动 / 自动保存、默认粉色 |
| M4 夜间与打磨 | ✅ | `ThemeManager`、反色夜间、压缩标题栏、视觉减重 |
| M5 设置与收口 | ✅ | 设置窗口(默认阅读模式 / fit-width / 自动保存策略);综合验收通过 |
| M6 体验打磨 | ✅ | plain 快捷键菜单可见、全览 grid、find bar、历史栈、Vim 翻页、缩放、页跳转、左右互换、高亮 undo;真实 PDF 手测与 200+ 页缩略图验证通过 |
| M7 搜索强化与对比阅读 | ✅ | 右栏 Search 面板、This Document / All Open、同窗分屏、多窗口、窗口级持久化、搜索与分屏状态测试补齐 |
| M8 批注深度化 | ✅ 开发完成,待手测 | 右栏 Annotations、评论编辑、Markdown / Plain / JSON 导出、Shortcuts 页、`none` 清空绑定、批注测试补齐 |
| M9 最近文件启动器 | ✅ 开发完成,待手测 | Spotlight 风格 recent-files palette,支持搜索、空格多选、回车打开、底部常驻操作提示 |

已完成细项以 commit 历史为准,不在本文件展开。

## 8. 待开发里程碑

### 8.1 Milestone 8:批注深度化

目标:把当前高亮从"能做"升级为"能管理、能评论、能导出、能配置"。当前代码已完成,仅余手测验收。

**交付物**
1. 右栏 Annotations 模式,按页列所有高亮并支持点击跳转与评论编辑
2. Markdown / Plain / JSON 三种高亮导出,评论随导出带出
3. Shortcuts 面板与快捷键冲突检测、清除、恢复默认
4. 配置改动即时写回 `config.toml` 并刷新菜单

**验收要点**
- Annotations 面板按页分组并支持跳转,comment 可编辑
- 三种导出格式均包含 snippet / 页码 / 颜色 / comment
- Shortcuts UI 写回配置文件并实时生效,冲突绑定被拒,清除后写回 `none`

**当前状态**
1. 开发与自动化测试已完成
2. 下一步只剩手测 `Annotations / Export / Shortcuts`

### 8.2 Milestone 9:最近文件启动器

目标:补一个像 Spotlight 的最近文件启动器,把“打开最近文件”从菜单提升为键盘主路径。

**交付物**
1. `Cmd+Shift+Space` 拉起最近文件面板
2. 面板基于最近打开列表支持文件名 / 路径搜索
3. `Space` 多选,`Enter` 打开选中项,底部常驻操作提示

**验收要点**
- 空窗口也能直接拉起并打开最近文件
- 最近文件结果保持最近优先,搜索后仍可纯键盘完成
- 无查询时默认选中第一条最近历史,可直接 `↓` 浏览
- 查询变化后默认回到第一条结果,继续 `↓` 浏览
- 操作提示固定显示在底部,不再依赖额外帮助切换

**当前状态**
1. `Cmd+Shift+Space` 面板、文件名 / 路径搜索、`Space` 多选、`Enter` 打开与底部常驻操作提示已完成
2. 面板已改为更窄更长的紧凑窗口,隐藏红绿灯,并调整为搜索框编辑态下也能直接用方向键驱动候选
3. 状态模型与快捷键配置测试已补齐
4. 最近文件历史上限扩到 200,并增加每 24h 定期清理失效链接
5. 下一步只剩真实 PDF 手测

### 8.3 Milestone 10(长期预研):扩展生态

只产出**设计决策 + 最小 PoC**,不承诺全量实现。

- 扩展机制 RFC:进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳 的候选比较
- PoC:若决策继续,把"导出高亮"重写为首个插件
- Serein Extension API 草稿
- 风险评估:沙箱、上架(若走 MAS)、维护成本;若推迟,说明"为什么现在不做"

## 9. 风险

| 风险 | 策略 |
|---|---|
| 夜间模式对 `PDFView` 内部视图层级的依赖 | 保持轻量反色方案,不自研渲染管线 |
| 多文档状态污染 | 状态严格挂 `DocumentSession`,视图层无业务状态 |
| 双 tab 模式分叉 | 共享同一套 `DocumentStore` 与切换命令 |
| 批注写回失败 | 保留 dirty + 显式提示,不静默 |
| 侧栏职责膨胀 | 严守"左栏只 tabs / 右栏只 outline+pages+search/annotations" |
| UI 过早打磨 | 主路径优先于视觉;新功能进 M7+ |

## 10. 开发约束

1. 先结构正确,再视觉精致。
2. 不为未来假设场景预埋抽象。
3. 不写 fallback、不写兼容层。
4. 优先系统原生能力:`AppKit`、`PDFKit`、`NSOutlineView`、`NSSplitViewController`。
5. 任何改动回同步本文件;边做边漂移的决策要回头写进来。
6. 状态管理落在 `DocumentStore` / `DocumentSession`,不散到视图层。
7. 垂直 tab 与水平 titlebar tab 必须共享同一套文档切换命令与状态模型。

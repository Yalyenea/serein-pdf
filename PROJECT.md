# PDF Reader for macOS

面向 macOS 的极简 PDF 阅读器。左侧文档 tabs(可切换到标题栏水平 tabs),右侧 Outline / Pages,中间沉浸式阅读区。风格:极简、扁平、紧凑。

## 1. 产品原则

1. 左栏只回答"正在看哪些文档"、右栏只回答"当前文档结构"、中栏只回答"阅读本身"。
2. tab 形态可切换,垂直与水平模式共享同一套文档模型。
3. 水平 tab 复用 macOS 标题栏,不额外占内容高度。
4. 视觉极简扁平紧凑,避免厚重装饰、强阴影、松散间距。
5. 高频操作键盘驱动。
6. 不引入 fallback、兜底逻辑、不必要兼容层。

## 2. 范围

### 2.1 V1 涵盖

文档管理 / 阅读(单·双页、适应宽度、缩放、翻页)/ Outline / 会话恢复 / 当前文档搜索 / 文本高亮 / 删除高亮 / 手动 & 自动保存 / 深色主题 / 反色夜间 / 配置化快捷键 / 设置窗口 / 侧栏显隐 & 互换 / 全览 grid / 历史前进后退 / 重开最近关闭 / find bar / 跳转页 / Vim 翻页 / 高亮撤销(50 步)。

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
    A["MainWindowController"] --> B["SplitViewController"]
    B --> C["VerticalTabsViewController"]
    B --> D["ReaderViewController"]
    B --> E["RightSidebarViewController"]
    E --> E1["OutlineViewController"]
    E --> E2["PDFThumbnailView (Pages)"]
    C --> F["DocumentStore"]
    D --> F
    E --> F
    F --> G["DocumentSession"]
    D --> H["PDFView / PDFDocument"]
    D --> L["HighlightService + Undo"]
    D --> M["ThemeManager"]
    F --> J["ReadingStateStore"]
    F --> K["RecentFilesStore"]
```

### 3.3 关键设计决策

| 决策 | 结论 |
|---|---|
| 多文档管理 | `DocumentStore` 持有多个 `DocumentSession` |
| tab 展示 | `verticalSidebar` / `horizontalTitlebar` 动态切换,共用同一套文档切换命令 |
| 中栏承载 | 单 `ReaderViewController` 按 active session 切换文档 |
| 目录来源 | `PDFDocument.outlineRoot` → `OutlineNode` |
| 批注存储 | 内存 + dirty;`Cmd+S` 或自动保存策略触发时写回源 PDF |
| 自动保存 | 默认 `10 min`,可设 `never` |
| 状态持有 | 阅读状态 / 缩放 / 翻页 / dirty / undoStack 都挂在 `DocumentSession` |
| 左右互换 | `layout.sidebarsSwapped` 翻转时 split items 重排,per-session 宽度 / 可见状态原子对调 |
| 高亮撤销 | 每 session 独立 undo 栈,上限 50,无 redo |
| 视图层订阅 | 通过 `Notification.Name.documentStoreDidChange` 与 `PDFViewPageChanged`,视图层不持业务状态 |

## 4. UI 与交互

### 4.1 信息架构

| 区域 | 职责 | 边界 |
|---|---|---|
| 左栏 Vertical Sidebar | 已打开文档 tabs | 不放 outline / 不放缩略图 / 不做文件树 |
| 标题栏 Horizontal Tabs | 水平模式下的 tab strip | 占标题栏,不新增内容区 tab bar |
| 中栏 Reader | PDF 渲染、选择、搜索、批注、find bar、全览 | 单 Reader |
| 右栏 Sidebar | Outline / Pages (segmented 切换) | 仅服务当前文档 |
| 左右互换 | 配置项或 `Cmd+Shift+X` | 不改变上述职责,仅改变物理位置 |

### 4.2 视觉规范

- 紧凑布局,轻量圆角,无厚重阴影
- 侧栏平铺嵌入,最多保留一条淡分割线(禁悬浮 / 液态玻璃 / 漂浮面板感)
- 按钮 / tab 视觉重量轻,突出选中态
- 水平 tab 与系统标题栏融为一体
- 默认高亮色:偏轻、低饱和但清晰的粉色

### 4.3 快捷键总表

配置文件:`~/Library/Application Support/SlatePDF/config.toml` — schema 与默认值见 `Core/AppConfiguration.swift`。

**批注**
- `A`:有选区 → 立即高亮;无选区 → 进入高亮模式
- `Esc`:退出高亮模式 / 关闭 Find bar / 退出全览
- `D`:删除鼠标所在高亮(多行整组删除)
- `Cmd+S`:写回源 PDF
- `Cmd+Z`:撤销最近一次高亮新增或删除(上限 50,无 redo)

**阅读**
- `Cmd+0`:适应宽度
- `Cmd+=` / `Cmd+-`:放大 / 缩小(进入 manual 缩放)
- `Cmd+1` / `Cmd+2` / `Cmd+3` / `Cmd+4`:`singlePage` / `singlePageContinuous` / `twoUp` / `twoUpContinuous`
- `J` / `K`:下一页 / 上一页(文本输入上下文让路)
- `Cmd+Option+G`:跳转到页 N(越界给轻量提示)
- `Cmd+[` / `Cmd+]`:历史后退 / 前进
- `Cmd+F` / `Cmd+G` / `Cmd+Shift+G`:Find bar / 下一 / 上一 匹配
- `I`:切换反色夜间模式

**文档与 tab**
- `Cmd+O`:打开
- `Cmd+W`:关闭当前 tab
- `Cmd+Shift+T`:重开上次关闭(栈上限 10)
- `Cmd+Shift+[` / `Cmd+Shift+]`:上一 / 下一 tab

**布局**
- `Cmd+B` / `Cmd+Option+B`:切换左 / 右侧栏
- `Cmd+Shift+1` / `Cmd+Shift+2`:垂直 sidebar tabs / 水平 titlebar tabs
- `Cmd+Shift+L`:右栏 Outline / Pages 切换
- `Cmd+Shift+O`:进入 / 退出全览(自动隐藏左右侧栏,`Esc` 退出)
- `Cmd+Shift+X`:互换左右侧栏(宽度 / 可见状态随内容迁移)

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
| `pdfDocument: PDFDocument` | 文档对象 |
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

### 5.2 `DocumentStore`

- 管理 sessions(open / close / activate / reorder)
- 维护 active session,驱动左栏 tab 与中栏 reader 联动
- 持久化阅读状态 / 最近文件 / 最近关闭栈(上限 10)
- 提供 tab 模式切换
- 左右互换时对调 per-session 宽度 / 可见状态

### 5.3 辅助模型

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
App/
  AppDelegate.swift
  AppMain.swift
  MainWindowController.swift
  SplitViewController.swift
  SettingsWindowController.swift
  ReaderShortcutWindow.swift

Core/
  AppConfiguration.swift
  DocumentSession.swift
  DocumentStore.swift
  DocumentStorePersistence.swift
  ReaderState.swift
  ReaderDisplayMode.swift
  ReadingPosition.swift
  ReadingStateStore.swift
  RecentFilesStore.swift
  OutlineNode.swift
  OutlineExtractor.swift

UI/LeftTabs/
  VerticalTabsViewController.swift
  VerticalTabItemView.swift

UI/TitlebarTabs/
  TitlebarTabsController.swift
  TitlebarTabItemView.swift

UI/CenterReader/
  ReaderViewController.swift
  PDFContainerView.swift
  ReaderShortcutsController.swift
  FindBarView.swift

UI/RightOutline/
  OutlineViewController.swift
  RightSidebarViewController.swift

UI/Shared/
  PlaceholderViewController.swift

Features/Annotations/
  HighlightColor.swift
  HighlightService.swift
  HighlightUndoOperation.swift

Features/Theme/
  ThemeManager.swift

Tests/SlatePDFTests/
```

## 7. 已完成里程碑(概览)

| 里程碑 | 状态 | 要点 |
|---|---|---|
| M1 MVP 骨架 | ✅ | 三栏、`DocumentStore`、tab 双模式、outline、会话恢复 |
| M2 阅读体验 | ✅ | 四种阅读模式、适应宽度、搜索、最近文件、阅读位置持久化、快捷键系统 |
| M3 高亮批注 | ✅ | 选区 + 键盘 `a` 高亮、`D` 删除、手动 / 自动保存、默认粉色 |
| M4 夜间与打磨 | ✅ | `ThemeManager`、反色夜间、压缩标题栏、视觉减重 |
| M5 设置与收口 | ✅ 主体 | 设置窗口(默认阅读模式 / fit-width / 自动保存策略);UAT-01~10 完成 |
| M6 体验打磨 | ✅ 主体 | plain 快捷键菜单可见、全览 grid、find bar、历史栈、Vim 翻页、缩放、页跳转、左右互换、高亮 undo |

已完成细项以 commit 历史为准,不在本文件展开。

**M5 / M6 遗留**(详见 TASKS.md):
- `M5-032` 综合验收收口
- `M6-023` 缩略图 200+ 页性能验证
- `M6-062` 真实 PDF 手测(UAT-12 / 13 / 14 / 21b)

## 8. 待开发里程碑

### 8.1 Milestone 7:搜索强化与对比阅读

目标:把搜索从"能找到"升级为"扫视所有命中",并支持"同时看两份 PDF 做对比"。

**交付物**
1. find bar 下挂结果面板(按页分组,点击跳转入历史栈)
2. 跨文档搜索(可选 toggle "All Open")
3. 同窗分屏:中栏拆成双 Reader,`Cmd+Ctrl+\` 切换
4. 多窗口:`Cmd+Shift+N` 新建窗口,共享 `DocumentStore`
5. 布局持久化(可降级为单窗口并给出说明)

**关键快捷键**
- `Cmd+Ctrl+\`:切换同窗分屏
- `Cmd+Shift+N`:新建窗口
- find bar 内 `↑` / `↓` / `Enter`:结果导航与跳转

**验收要点**
- 200+ 页 PDF 搜索常见词不卡顿(首次命中 < 500ms)
- 分屏两侧 session 状态互不污染
- 多窗口关闭互不影响,重启可恢复布局或明确降级说明

### 8.2 Milestone 8:批注深度化

**交付物**
1. 右栏 Annotations 模式:与 Outline 并列,列表按页分组,点击跳转并强调 annotation
2. 批注导出:Markdown / Plain / JSON,目标为剪贴板或磁盘
3. 设置窗口新增 Shortcuts 面板(GUI 改快捷键,冲突检测,写回 `config.toml`)

**关键快捷键**
- `Cmd+Shift+A`:切换右栏 Outline / Annotations
- `Cmd+Shift+E`:导出当前文档高亮(默认 Markdown 到剪贴板)

**验收要点**
- Annotations 面板按页分组并支持跳转
- 三种导出格式均包含 snippet / 页码 / 颜色
- Shortcuts UI 写回配置文件并实时生效;冲突绑定被拒

### 8.3 Milestone 9(长期预研):扩展生态

只产出**设计决策 + 最小 PoC**,不承诺全量实现。

- 扩展机制 RFC:进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳 的候选比较
- PoC:若决策继续,把"导出高亮"重写为首个插件
- Slate Extension API 草稿
- 风险评估:沙箱、上架(若走 MAS)、维护成本;若推迟,说明"为什么现在不做"

## 9. 风险

| 风险 | 策略 |
|---|---|
| 夜间模式对 `PDFView` 内部视图层级的依赖 | 保持轻量反色方案,不自研渲染管线 |
| 多文档状态污染 | 状态严格挂 `DocumentSession`,视图层无业务状态 |
| 双 tab 模式分叉 | 共享同一套 `DocumentStore` 与切换命令 |
| 批注写回失败 | 保留 dirty + 显式提示,不静默 |
| 侧栏职责膨胀 | 严守"左栏只 tabs / 右栏只 outline+pages" |
| UI 过早打磨 | 主路径优先于视觉;新功能进 M7+ |

## 10. 开发约束

1. 先结构正确,再视觉精致。
2. 不为未来假设场景预埋抽象。
3. 不写 fallback、不写兼容层。
4. 优先系统原生能力:`AppKit`、`PDFKit`、`NSOutlineView`、`NSSplitViewController`。
5. 任何改动回同步本文件;边做边漂移的决策要回头写进来。
6. 状态管理落在 `DocumentStore` / `DocumentSession`,不散到视图层。
7. 垂直 tab 与水平 titlebar tab 必须共享同一套文档切换命令与状态模型。

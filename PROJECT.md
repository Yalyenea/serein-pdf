# PDF Reader for macOS

## 1. 项目概述


一个面向 macOS 的极简 PDF 阅读器：支持在“左侧垂直文档标签”和“标题栏水平标签”两种 tab 形态之间自由切换；右侧为目录 sidebar，中间为沉浸式 PDF 阅读区，支持高亮与夜间模式，整体强调极简、扁平、紧凑的布局风格。


### 1.4 产品原则

1. 左边只解决“我正在看哪些文档”。
2. 右边只解决“当前文档的结构是什么”。
3. 中间只解决“阅读本身”。
4. tab 形态必须可切换，垂直模式和水平模式共享同一套文档模型与状态。
5. 水平 tab 模式优先复用 macOS 标题栏区域，不额外占据独立内容高度。
6. 视觉风格明确采用极简、扁平、紧凑布局，避免厚重装饰、强阴影和松散间距。
7. 高频操作优先键盘驱动，交互尽量短路径、低心智负担。
8. 第一版不追求全功能，只追求结构清晰、体验成立。
9. 不引入 fallback、兜底逻辑或不必要兼容层，保持实现简洁。

## 2. 范围定义

### 2.1 V1 范围内

| 模块 | 包含内容 |
|---|---|
| 文档管理 | 打开多个 PDF、tab 切换、关闭 tab、恢复会话、tab 方向切换 |
| 阅读器 | PDF 显示、滚动、适应宽度、单页/双页显示模式切换 |
| 目录 | 解析并展示 PDF outline，支持点击跳转 |
| 状态恢复 | 最近文件、恢复上次打开文档、记住每个文档阅读位置与显示模式 |
| 搜索 | 当前文档文本搜索 |
| 批注 | 文本高亮、删除高亮、保存批注、默认轻粉色高亮、脏状态后手动保存 |
| 主题 | UI 深色主题、基础夜间阅读模式、反色切换 |
| 快捷键 | `a` 进入或执行高亮、`Esc` 退出高亮模式、`i` 切换夜间模式、`Cmd+S` 保存批注、可配置文档/布局快捷键 |
| 保存策略 | 默认 10 分钟自动保存，可切换为永不自动保存 |
| 窗口体验 | 三栏布局、左右栏显隐、压缩标题栏、减少顶部控件、标题栏水平 tab |

### 2.2 V1 明确不做

| 不做项 | 原因 |
|---|---|
| 自研 PDF 渲染器 | 直接使用 PDFKit，避免无谓复杂度 |
| 文件树 / Finder 式侧边栏 | 左栏只做 tab，不做资源管理器 |
| 缩略图面板 | 初版先不分散左栏职责 |
| 云同步 | 非核心路径，拖重产品 |
| 书签库 / 知识库 | 超出阅读器第一版边界 |
| 完美夜间模式 | 成本高，先做够用版本 |
| 复杂微动效 | 优先性能和阅读流畅度 |

## 3. 技术方案

### 3.1 技术选型

| 层级 | 选择 | 原因 |
|---|---|---|
| 语言 | `Swift` | 原生 macOS 开发首选 |
| UI 框架 | `AppKit` | 更适合窗口、分栏、sidebar、标题栏压缩等桌面能力 |
| PDF 能力 | `PDFKit` | 已有 `PDFView`、`PDFDocument`、选择、搜索、批注能力 |
| 目录树 | `NSOutlineView` | 原生层级结构控件，适合 PDF outline |
| 布局容器 | `NSSplitViewController` | 天然适合左-中-右三栏 |
| 窗口样式 | `NSWindow.ToolbarStyle.unifiedCompact` | 压缩头部空间，突出内容 |

### 3.2 为什么不以 SwiftUI 为主

可以在后期用 SwiftUI 包设置页或轻量面板，但主阅读窗口优先用 AppKit。原因很直接：这个项目最核心的是窗口、分栏、标题栏、sidebar 这些桌面级布局与交互控制，而不是声明式 UI 的表达方式。

### 3.3 总体架构

```mermaid
flowchart LR
    A["MainWindowController"] --> B["SplitViewController"]
    B --> C["LeftTabsViewController"]
    B --> D["ReaderViewController"]
    B --> E["OutlineViewController"]
    C --> F["DocumentStore"]
    D --> F
    E --> F
    F --> G["DocumentSession"]
    D --> H["PDFView / PDFDocument / PDFKit"]
    E --> I["OutlineNode Tree"]
    F --> J["ReadingPositionStore"]
    F --> K["RecentFilesStore"]
    D --> L["HighlightService"]
    D --> M["ThemeManager / NightModeRenderer"]
```

### 3.4 关键设计决策

| 决策 | 结论 |
|---|---|
| 多文档管理 | 采用 `DocumentStore` 持有多个 `DocumentSession` |
| tab 展示模式 | 支持 `verticalSidebar` 与 `horizontalTitlebar` 两种模式动态切换 |
| 当前文档切换 | tab 视图只负责切换 active session，不持有文档状态 |
| PDF 承载方式 | 中间单个 `ReaderViewController` 根据 active session 切换文档 |
| 目录来源 | 从当前 `PDFDocument` 提取 outline，映射为 `OutlineNode` |
| 批注存储 | 高亮先只进入内存与脏状态，按 `Cmd+S` 时覆盖写回源 PDF |
| 自动保存 | 提供自动保存策略，默认 `10 min`，允许设为 `never` |
| 夜间模式 | V1 先做基础版，不深挖自定义渲染管线 |
| 状态恢复 | 每个 session 持有阅读状态，持久化到 store |

## 4. 信息架构与界面结构

### 4.1 可切换 Tab 结构

| 区域 | 职责 | 设计边界 |
|---|---|---|
| 左栏 Vertical Tabs | 在垂直模式下显示已打开 PDF，负责切换 | 不放目录，不放文件树，不放缩略图 |
| 标题栏 Horizontal Tabs | 在水平模式下承载已打开 PDF 的 tab strip | 使用标题栏区域，不额外新增一行内容区 tab |
| 中栏 Reader | 负责 PDF 阅读体验 | 显示、滚动、缩放、选择、搜索、批注 |
| 右栏 Outline Sidebar | 显示当前 PDF 目录树 | 只服务当前文档 |

### 4.2 窗口策略

1. 主窗口使用 `NSSplitViewController`。
2. tab 展示模式支持在“左侧垂直”与“标题栏水平”之间切换。
3. 垂直模式下左侧栏承担文档 tab；水平模式下左侧栏默认可收起，仅保留右侧目录与中间阅读区。
4. 左右侧栏支持折叠和显隐。
5. 中间阅读区自适应扩展。
6. 分栏位置需设置合理约束，避免侧栏被拖到失衡。
7. 标题栏和 toolbar 尽量压缩，保留必要入口即可。

### 4.3 视觉风格规范

| 维度 | 要求 |
|---|---|
| 整体气质 | 极简、扁平、紧凑，避免“功能堆叠感” |
| 间距 | 优先紧凑布局，减少无意义留白，但保持点击与阅读舒适度 |
| 形态 | 尽量使用清晰矩形与轻量圆角，不依赖拟物装饰 |
| 阴影 | 弱化或避免厚重阴影，更多依靠层级、边线和底色区分 |
| 颜色 | 克制、低噪音，以内容为中心，不让 UI 抢夺注意力 |
| 控件 | 按钮和 tab 视觉重量尽量轻，突出当前选中态即可 |
| 标题栏 | 在水平 tab 模式下应尽量与系统标题栏融为一体 |
| 侧栏整合 | 禁止悬浮、液态玻璃或漂浮面板感；左右侧栏必须与窗口内容区平铺嵌入，最多保留一条很淡的分割线 |
| 高亮颜色 | 默认高亮色采用偏轻、低饱和但清晰可辨的粉色 |
| 批注保存 | 默认不即时落盘，高亮后先进入未保存状态，由 `Cmd+S` 或自动保存策略触发写回 |

### 4.4 关键交互约定

| 交互 | 约定 |
|---|---|
| `a` | 若当前已有文本选区，则立即以默认轻粉色创建高亮 |
| `a` | 若当前没有选区，则进入“高亮模式”，此后选中文字即自动高亮 |
| `Esc` | 退出高亮模式 |
| `i` | 切换反色夜间模式 |
| `Cmd+S` | 将当前文档未保存批注写回源 PDF |

### 4.5 批注保存策略

| 项目 | 约定 |
|---|---|
| 默认行为 | 创建、删除高亮后只更新当前 session 与脏状态，不立即写回文件 |
| 手动保存 | 用户按 `Cmd+S` 时，将当前文档未保存批注覆盖写回源 PDF |
| 自动保存默认值 | `10 min` |
| 自动保存选项 | 至少支持 `10 min`、`never` |
| UI 状态 | 当前文档有未保存批注时，tab 或窗口状态应有轻量提示 |

## 5. 数据模型

### 5.1 核心对象：`DocumentSession`

表示一个打开的 PDF tab。

| 字段 | 类型建议 | 说明 |
|---|---|---|
| `id` | `UUID` | session 唯一标识 |
| `url` | `URL` | PDF 文件位置 |
| `title` | `String` | 文档标题或文件名 |
| `pdfDocument` | `PDFDocument` | 当前文档对象 |
| `currentPageIndex` | `Int` | 当前页索引 |
| `displayMode` | `ReaderDisplayMode` | 当前阅读显示模式 |
| `scaleMode` | `ReaderScaleMode` | 当前是手动缩放还是适应宽度 |
| `zoomScale` | `CGFloat` | 当前缩放比例 |
| `lastReadPosition` | 自定义结构 | 页码 + 页面内位置 |
| `outlineTree` | `[OutlineNode]` | 目录树 |
| `isDirty` | `Bool` | 是否有未保存的批注变更 |
| `sidebarState` | 自定义结构 | 左右侧栏显隐状态 |
| `tabPresentationState` | 自定义结构 | 当前 tab 展示模式下的局部状态 |
| `annotationSavePolicy` | 自定义结构 | 当前批注保存策略，如 `10 min` 或 `never` |

### 5.2 核心对象：`DocumentStore`

负责整个 app 的文档生命周期管理。

| 职责 | 说明 |
|---|---|
| 管理已打开 sessions | 新建、插入、关闭、排序 |
| 维护当前激活 session | 左栏 tab 与中间 reader 联动 |
| 恢复上次会话 | 启动时重建已打开文档 |
| 持久化阅读状态 | 保存页码、缩放、滚动位置、显示模式 |
| 管理最近文件 | 提供 reopen 入口 |

### 5.3 辅助模型

| 模型 | 用途 |
|---|---|
| `ReaderState` | 阅读区当前 UI 状态 |
| `OutlineNode` | 目录树节点 |
| `ReadingPosition` | 记录页码与定位信息 |
| `ThemeState` | 主题与夜间模式状态 |
| `TabPresentationMode` | `verticalSidebar` / `horizontalTitlebar` |
| `AnnotationSavePolicy` | 批注保存策略，如 `after10Minutes` / `never` |

## 6. 项目结构

```text
App/
  AppDelegate.swift
  MainWindowController.swift
  SplitViewController.swift

Core/
  DocumentSession.swift
  DocumentStore.swift
  ReaderState.swift
  ReadingPosition.swift

UI/LeftTabs/
  VerticalTabsViewController.swift
  VerticalTabsItemView.swift

UI/TitlebarTabs/
  TitlebarTabsController.swift
  TitlebarTabItemView.swift

UI/CenterReader/
  ReaderViewController.swift
  PDFContainerView.swift
  ReaderShortcutsController.swift

UI/RightOutline/
  OutlineViewController.swift
  OutlineNode.swift

Features/Annotations/
  HighlightService.swift

Features/Theme/
  ThemeManager.swift
  NightModeRenderer.swift

Features/Persistence/
  RecentFilesStore.swift
  ReadingPositionStore.swift
  SessionRestoreStore.swift

Tests/
  Core/
  Features/
```

## 7. 里程碑计划

### 7.1 Milestone 1: MVP 骨架

目标：让应用成为一个真的能打开并切换多个 PDF 的阅读器。

#### 交付物

1. 三栏主窗口。
2. 中间 `PDFView`。
3. 可切换的 tab 承载层。
4. 右侧 outline 展示。
5. 打开文件与基础会话恢复。

#### 任务拆分

| 编号 | 任务 | 说明 |
|---|---|---|
| M1-1 | 创建 AppKit 工程骨架 | 主窗口、split view、controller 层级 |
| M1-2 | 接入 `PDFKit` | reader 中嵌入 `PDFView` |
| M1-3 | 设计 `DocumentSession` / `DocumentStore` | 多文档管理核心 |
| M1-4 | 实现 `Command+O` 打开文件 | 打开后加入 tab 列表 |
| M1-5 | 实现 tab 展示模式切换 | 垂直 sidebar / 标题栏水平 tab |
| M1-6 | 实现 tab 切换 | 激活不同 session |
| M1-7 | 解析并展示 outline | 无目录时显示空状态 |
| M1-8 | 实现左右栏显隐 | 保持中间阅读区自适应 |
| M1-9 | 启动时恢复打开文档列表 | 至少恢复文件集合与 active 文档 |

#### 验收标准

| 编号 | 标准 |
|---|---|
| AC-M1-1 | 可以连续打开多个 PDF |
| AC-M1-2 | 垂直 tab 与水平标题栏 tab 可自由切换 |
| AC-M1-3 | 两种 tab 模式下都可以稳定切换当前文档 |
| AC-M1-4 | 右侧目录跟随当前文档更新 |
| AC-M1-5 | 无 outline 的 PDF 会显示明确空状态 |
| AC-M1-6 | 左右侧栏可隐藏且不破坏阅读区布局 |
| AC-M1-7 | 重启应用后可恢复上次打开文档列表与 tab 模式 |

### 7.2 Milestone 2: 阅读体验

目标：从“能用”提升到“顺手”。

#### 交付物

1. 阅读配置文件、适应宽度与单双页显示模式。
2. 当前文档搜索（当前为菜单触发并定位首个命中）。
3. 最近文件（当前通过 `File > Open Recent` 提供 reopen）。
4. 阅读位置恢复。
5. 更顺手的快捷键。
6. 高亮模式键盘流。

#### 任务拆分

| 编号 | 任务 | 说明 |
|---|---|---|
| M2-1 | 阅读配置文件 | 用 `.toml` 管理默认阅读模式与快捷键 |
| M2-2 | 阅读显示模式 | 支持单页、单页连续、双页、双页连续 |
| M2-3 | 文本搜索 | 基于 `PDFDocument` / `PDFSelection` 能力 |
| M2-4 | 最近文件列表 | 记录最近打开项 |
| M2-5 | 阅读位置持久化 | 页码、缩放、滚动位置、显示模式 |
| M2-6 | 上次会话恢复增强 | 恢复 active 文档与定位 |
| M2-7 | 快捷键系统 | 落实 `a` / `Esc` / `i` 等阅读快捷键 |

#### 验收标准

| 编号 | 标准 |
|---|---|
| AC-M2-1 | 同一文档重新打开后能恢复到之前阅读位置 |
| AC-M2-2 | 不同 tab 间切换时阅读状态互不污染 |
| AC-M2-2a | 默认阅读模式来自配置文件，默认值为单页连续 |
| AC-M2-2b | 适应宽度与四种显示模式都有快捷键入口 |
| AC-M2-3 | 搜索结果可定位到文档具体位置 |
| AC-M2-4 | 最近文件可用来重新打开历史 PDF |
| AC-M2-5 | `i` 可稳定切换夜间模式，`Esc` 可退出高亮模式 |

#### 默认快捷键方案

- 配置文件路径：`~/Library/Application Support/SlatePDF/config.toml`
- `Cmd+B`：切换左侧边栏
- `Cmd+Option+B`：切换右侧边栏
- `Cmd+Shift+1`：切换到垂直 sidebar tabs
- `Cmd+Shift+2`：切换到水平 titlebar tabs
- `Cmd+W`：关闭当前标签页
- `Cmd+Shift+[` / `Cmd+Shift+]`：切换到上一个 / 下一个标签页
- `Cmd+0`：适应宽度
- `Cmd+1` / `Cmd+2` / `Cmd+3` / `Cmd+4`：切换 `singlePage` / `singlePageContinuous` / `twoUp` / `twoUpContinuous`

### 7.3 Milestone 3: 高亮与批注

目标：让产品进入长期可用状态。

#### 交付物

1. 文本选择高亮。
2. 固定颜色高亮菜单。
3. 删除高亮。
4. 批注保存。
5. 默认轻粉色高亮与键盘高亮流。
6. 手动保存与自动保存策略。

#### 任务拆分

| 编号 | 任务 | 说明 |
|---|---|---|
| M3-1 | 选择文本并创建高亮 annotation | 基于 `PDFSelection` + `PDFAnnotation` |
| M3-2 | 默认高亮色 | 默认使用偏轻、低饱和、清晰的粉色 |
| M3-3 | 提供固定色板 | 黄色、绿色、粉色即可，默认选中粉色 |
| M3-4 | 键盘高亮流 | `a` 立即高亮或进入高亮模式，`Esc` 退出 |
| M3-5 | 删除已有高亮 | 支持选中后删除 |
| M3-6 | 手动保存策略 | 高亮后不立即落盘，`Cmd+S` 时覆盖写回源 PDF |
| M3-7 | 自动保存策略 | 默认 `10 min`，允许设为 `never` |
| M3-8 | 脏状态管理 | tab 中展示未保存状态 |

#### 验收标准

| 编号 | 标准 |
|---|---|
| AC-M3-1 | 默认高亮色符合“偏轻粉色、低饱和但清晰”的要求 |
| AC-M3-2 | 选中文字后按 `a` 可以稳定添加高亮 |
| AC-M3-3 | 无选区时按 `a` 进入高亮模式，之后选中文字即自动高亮 |
| AC-M3-4 | 按 `Esc` 可以退出高亮模式 |
| AC-M3-5 | 已有高亮可以删除 |
| AC-M3-6 | 高亮后文档进入未保存状态，但不会立即覆盖源文件 |
| AC-M3-7 | 按 `Cmd+S` 后当前文档批注被写回源 PDF |
| AC-M3-8 | 自动保存默认值为 `10 min`，并允许设置为 `never` |
| AC-M3-9 | 保存后重新打开 PDF，高亮仍存在 |

### 7.4 Milestone 4: 夜间模式与窗口打磨

目标：从“工具”提升到“舒服、愿意常开”。

#### 交付物

1. UI 深色主题。
2. 基础夜间阅读模式与反色切换。
3. 压缩标题栏与 toolbar。
4. 优化分栏、边距与留白。
5. 统一极简扁平紧凑视觉语言。

#### 任务拆分

| 编号 | 任务 | 说明 |
|---|---|---|
| M4-1 | ThemeManager | 统一主题状态入口 |
| M4-2 | 夜间模式基础版 | 背景变深、页边暗化、UI 跟随深色 |
| M4-3 | 反色切换交互 | `i` 触发阅读区反色夜间模式切换 |
| M4-4 | 扫描 PDF 最小兼容方案 | 降亮度或温和处理 |
| M4-5 | 标题栏压缩 | `unifiedCompact` 与最小 toolbar，兼容水平 tab 模式 |
| M4-6 | 视觉细节打磨 | 边距、拖动体验、选中态、hover 态 |
| M4-7 | 极简视觉统一 | 扁平化、紧凑布局、控件减重 |

#### 验收标准

| 编号 | 标准 |
|---|---|
| AC-M4-1 | 深色模式下 UI 整体风格统一 |
| AC-M4-2 | `i` 可即时切换夜间模式，切换后状态正确同步 |
| AC-M4-3 | 夜间模式下文本 PDF 可读，不明显刺眼 |
| AC-M4-4 | 顶部空间占用显著低于常规文档应用 |
| AC-M4-5 | 整体视觉符合极简、扁平、紧凑目标，不出现厚重装饰感 |

## 8. 开发顺序建议

按最短闭环推进：

1. 三栏主窗口。
2. 中间 `PDFView`。
3. tab 展示模式与切换。
4. 右侧目录树。
5. 会话恢复与阅读状态。
6. 搜索、翻页、缩放。
7. 高亮与保存。
8. 夜间模式。
9. 窗口与视觉打磨。

原因：先确保信息架构和主路径成立，再做增强体验，最后做“舒服感”。

## 9. 测试策略

### 9.1 测试原则

1. 核心状态管理必须有测试。
2. UI 复杂交互不强求全自动化，但关键路径至少手测清单覆盖。
3. 优先测试 `Core` 和 `Persistence`，其次测试 features。

### 9.2 自动化测试建议

| 模块 | 测试类型 | 重点 |
|---|---|---|
| `DocumentStore` | Unit Test | 打开、关闭、切换、恢复逻辑 |
| `AppConfigurationStore` | Unit Test | `.toml` 配置创建与读取 |
| `ReadingStateStore` | Unit Test | 状态持久化读写 |
| `RecentFilesStore` | Unit Test | 最近文件去重与排序 |
| `HighlightService` | Unit Test / 集成测试 | annotation 创建与删除 |

### 9.3 手动验收清单

| 编号 | 检查项 |
|---|---|
| UAT-1 | 连续打开 3 个 PDF 并来回切换无错乱 |
| UAT-2 | 每个 PDF 的目录正确更新 |
| UAT-3 | 文档关闭后 active tab 行为正确 |
| UAT-4 | 重启后恢复正确文档与阅读位置 |
| UAT-5 | 选中文字按 `a` 可直接生成默认轻粉色高亮 |
| UAT-6 | 无选区按 `a` 进入高亮模式，`Esc` 退出 |
| UAT-7 | 高亮后未按 `Cmd+S` 时，源文件未被立刻覆盖 |
| UAT-8 | 按 `Cmd+S` 后重新打开 PDF，高亮仍存在 |
| UAT-9 | 自动保存策略默认是 `10 min`，并可切换为 `never` |
| UAT-10 | 按 `i` 可切换夜间模式，普通文本 PDF 与扫描 PDF 都能接受 |

## 10. 风险与规避

| 风险 | 说明 | 策略 |
|---|---|---|
| 夜间模式复杂度高 | `PDFView` 内部视图层级可能限制改造 | V1 先做轻量方案 |
| 多文档状态污染 | 切换 tab 时缩放/页码容易串 | 状态严格挂在 `DocumentSession` 上 |
| 双 tab 模式一致性 | 垂直与水平模式容易出现行为分叉 | 使用统一 `DocumentStore` 和统一切换命令 |
| 批注写回失败 | 手动保存或自动保存时可能因文件权限或 PDF 结构失败 | V1 聚焦常规 PDF，失败显式提示且保留未保存状态 |
| 侧栏职责膨胀 | 很容易把左栏做成文件浏览器 | 严守边界，左栏只做 tab |
| UI 过早打磨 | 会拖慢主路径交付 | 先确保主功能闭环 |

## 11. 第一开发周期任务单

建议把第一轮开发聚焦为 `MVP Skeleton`，只做以下事项：

| 优先级 | 任务 |
|---|---|
| P0 | 建立 AppKit 工程与三栏窗口 |
| P0 | 接入 `PDFView` 并打开本地 PDF |
| P0 | 建立 `DocumentSession` / `DocumentStore` |
| P0 | 实现垂直 tab 与标题栏水平 tab 两种模式 |
| P0 | 右侧 outline 展示与点击跳转 |
| P1 | 左右侧栏显隐 |
| P1 | 恢复上次打开文档列表 |

第一轮结束后，软件应达到“我可以真的用它打开几份 PDF 来回看”的程度。

## 12. 开发约束

1. 先做结构正确，再做视觉精致。
2. 不为未来假设场景预埋复杂抽象。
3. 不写多余兼容层，不引入 fallback 逻辑。
4. 优先使用系统原生能力：`AppKit`、`PDFKit`、`NSOutlineView`、`NSSplitViewController`。
5. 所有后续实现应尽量围绕本文件维护，不要边做边漂移。

## 13. 下一步建议

如果围绕这个计划正式开工，下一步应该直接做下面三件事：

1. 建立 Xcode AppKit 工程骨架。
2. 先实现 `DocumentStore` 和三栏主窗口。
3. 跑通“打开 PDF -> 左侧出现 tab -> 中间显示 -> 右侧出现目录”的第一条闭环。

---

这份 `PROJECT.md` 应作为当前阶段的主项目文档。后续如果进入实际编码阶段，建议再补两份执行文档：

1. `ARCHITECTURE.md`：记录关键类关系、事件流、状态流。
2. `TASKS.md`：拆成可逐项勾选的开发任务列表。

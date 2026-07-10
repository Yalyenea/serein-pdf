# Serein 项目评审:功能亮点、实现亮点与改进路线

> 评审日期:2026-06-10。方法:5 个子系统全量代码阅读(Core / PDF 服务 / Annotations+Theme / App 窗口层 / Reader+Sidebar UI)。
> 本文回答三个问题:作为 PDF 阅读器它有什么产品亮点;代码层有什么实现亮点;短板在哪、接下来改什么。
>
> **进度同步:** 2026-07-10。`fix/review-near-term-A-20260710` 落地 §5.1 全项。状态约定:`✅` 已实现 · `[ ]` 未实现 · `◐` 部分缓解。

## 1. 规模概览

| 指标 | 数值 |
|---|---|
| 源码 | 18,285 行 Swift(App / Core / Features / UI) |
| 测试 | 8,339 行,298 个测试函数,测试:源码 ≈ 0.46 |
| 外部依赖 | 0(`Package.swift` 仅系统框架;TOML 解析也是手写) |
| 最大文件 | `AppDelegate` 2,197 / `DocumentStore` 1,999 / `ReaderViewController` 1,639 |

## 2. 产品功能亮点 —— 作为 PDF 阅读器

一句话定位:**键盘优先、纯本地、零依赖的原生 macOS PDF 阅读器**,核心人群是 LaTeX/Typst 写作者、多文献科研阅读者、CJK 扫描书读者。单看任一功能多有同类,但以下组合在一个 18k 行的极简原生 app 里非常少见。

### 2.1 写作者工作流(LaTeX / Typst)

- **编译热重载**:外部编译器原地写入或原子替换(写临时文件再 rename)后自动重载并保持阅读位置;**有未保存批注的文档拒绝自动重载**,笔记永远不被编译产物冲掉。
- **Clean Copy 导出**:去掉所有可见用户批注、保留超链接与表单控件的干净副本,适合发审稿人/合作者。
- Share 三态(原始 / Clean Copy / 高亮 Markdown)、`Cmd+R` Finder 定位、`Cmd+Shift+C` 路径复制——把 PDF 当工程产物管理。

### 2.2 多文献阅读模型

- **多 PDF 连续阅读组**:选中若干 tab 后按序当一本书读,翻页自动跨文件边界,右栏目录把组内所有 PDF 合并分组显示。论文集、多卷扫描书场景的硬差异化,主流阅读器基本没有。
- **浏览器式对比分屏**:split pair 记忆绑定的两个 PDF——普通点 tab 恢复或临时离开 pair,`Option` 激活才编辑 pane;支持**同一 PDF 两个独立视口对比**(独立页码/缩放),且不产生幽灵 tab、不进历史不持久化。
- **多窗口 workspace**:每窗独立 tab 集 / 搜索 / 最近关闭栈;一键合并所有窗口、把当前 PDF 甩到新窗口。

### 2.3 键盘驱动

- vim 阅读层:`j/k` 翻页、`Ctrl+D/U` 半页、`g/G` 首末、`c` 切连续模式;文本输入上下文自动让路。
- VS Code 式 `Cmd+K` chord 体系(主题 / 库 / 设置页 / 分享 / 窗口管理)。
- 三个键盘 palette:`Ctrl+Tab` tabs 总览(HJKL 网格导航)、`Cmd+Shift+Space` 最近文件启动器(空格多选)、`Cmd+K Cmd+O` PDF 库浏览器——全程不碰鼠标。
- 快捷键全可配:设置页录制、冲突拒绝、`none` 显式解绑;一切落在 `config.toml` 纯文本配置。
- find bar:有选中文本时 `Cmd+F` 预填并立即搜索;同一 query 连续 `Enter` 持续跳转;`This Document` / `All Open` 双范围,命中列表与预览全在右栏。

### 2.4 笔记工作流

- `a` 一键高亮(有选区即高亮、无选区进高亮模式),`D` 鼠标所在处整组删除(多行算一组),50 步 undo/redo。
- 高亮可挂评论;**Markdown 导出按页分组输出 snippet + comment**,直接贴进笔记软件;另有 Plain / JSON 保留颜色等元信息。
- **扫描件高亮自动 OCR 摘录**:文本层缺失或 CJK 乱码(CMap 损坏)时走 Vision 逐字符识别,只取高亮框内文字——中文扫描书做摘录的真差异化。
- 批注用标准 PDF 注解写回文件本身,换任何阅读器打开都不丢。

### 2.5 视觉与阅读体验

- **Rose Pine Dawn / Moon 主题**:把 PDF 纸面本身映射成暖纸色 / 暗底(亮度轴重映射,彩图保留色调),不是生硬的黄蓝互翻反色。
- 亮 / 暗主题独立配置,`i` 一键切换 mode 且各自记住 theme。
- 沉浸模式、演示模式(全屏整页适配、退出还原布局)、全览 grid(可缩放缩略图矩阵)。
- 每 PDF 记忆页码 + 缩放,跨启动恢复;每次状态变更先落盘,崩溃最多丢一步。

### 2.6 轻量库与会话管理

- PDF 库文件夹递归索引、库 root / 子文件夹二级浏览、即时搜索——是"书库"不是知识库,刻意克制。
- 重复打开(系统 open / Open Recent / 库 / `Cmd+O`)聚焦已有 tab 和窗口,绝不产生重复 tab。
- 最近历史 200 条、每 24h 自动清理失效链接;`Cmd+Shift+T` 重开关闭 tab(每窗 10 条)。
- 首启一次性授权 `/Users`(security-scoped bookmark 持久化),重装不重新逐文件授权。

## 3. 实现亮点 —— 代码层

### 3.1 架构与状态管理

| 亮点 | 位置 | 机制 |
|---|---|---|
| 单中枢 + 值类型会话 | `Core/DocumentStore.swift` | `@MainActor` store 全局持有值类型 `DocumentSession`;`WindowWorkspace` 仅按 UUID 引用,多窗共享文档但 UI 状态隔离;视图层零业务状态 |
| OptionSet 位掩码通知 | `Core/DocumentStore.swift:14-52` | 通知携带 `DocumentStoreChange` 掩码,观察者按"是否纯 chrome 变化"跳过重绘;未知发送者解码为 `.all`,宁多刷不漏刷 |
| PDFDocument LRU + pin | `Core/DocumentStore.swift:1691-1704` | 最多 4 个活文档;dirty 与分屏可见会话被 pin 不可驱逐;驱逐连带清搜索/批注派生缓存 |
| 崩溃即新鲜持久化 | `Core/DocumentStore.swift:1784-1834` | 每次发通知前全量落盘,不存在"退出时保存"这条会被遗忘的路径 |
| 单点不变量修复 | `Core/DocumentStore.swift:1536-1597` | open/close/分屏/恢复/合并全部漏斗进 `normalizeWorkspace` 修悬挂 ID、死 pair、fallback 主会话 |
| 隐形对比会话 | `Core/DocumentStore.swift:1402-1423` | 同 PDF 对比静默克隆 session(继承位置/缩放),并系统性排除在持久化/去重/最近/监听之外 |
| 空白 tab 合成 URL | `Core/DocumentSession.swift:35` | `serein-blank://tab/<uuid>` 让整套 URL 键控机制零改造,`isBlank` 只在 IO 边界检查 |
| 三级恢复回退 + decoder 内迁移 | `Core/DocumentStorePersistence.swift:202-239` | UUID+URL 双键持久化;旧单窗格式在 Codable decoder 内单向升级;重复 ID 自动换新 |

### 3.2 PDF 服务

| 亮点 | 位置 | 机制 |
|---|---|---|
| 双层 kqueue 热重载 | `Core/PDFFileMonitor.swift:95-185` | 文件 FD + 父目录 FD 双监听;原子替换孤儿化文件 FD 后目录监听兜底,事件后按路径重开 FD 自愈;inode 级快照判等去噪 |
| dirty 一票否决 | `Core/DocumentStore.swift:821-836` | 外部变化只在所有匹配会话 clean 时重载,未保存批注永远赢 |
| 手写 TOML 子集解析 | `Core/AppConfiguration.swift:639-944` | 零依赖;字符串数组恰为合法 JSON,直接喂 `JSONSerialization`;缺 key 即整体重渲染自迁移,用"缺新 key"做配置代龄指纹避免误伤用户改键 |
| bookmark 双 base64 | `Core/AppConfiguration.swift:628-636` | security-scoped bookmark 存 `base64(path):base64(blob)`,路径也编码,彻底消灭转义问题 |
| reconcile 式授权控制器 | `Core/SecurityScopedAccessController.swift:10-43` | 同步即对账:停掉越界 scope、清孤儿 bookmark、防 bookmark 跟随移动目录逃出授权集、stale 时再生成并返回新值由调用方持久化 |
| Clean Copy 深拷贝 | `Core/CleanPDFService.swift:5-32` | `dataRepresentation()` 往返副本,绝不污染在显文档;只保留 Link/Widget 白名单,默认拒绝 |
| 搜索去重游标 | `Core/DocumentSearch.swift:43-59` | 每页单调游标让同页 N 个相同命中映射到 N 个不同 snippet 位置 |

### 3.3 批注与主题(技术含量最高的两处)

| 亮点 | 位置 | 机制 |
|---|---|---|
| 解析式 CIColorMatrix 主题 | `Features/Theme/NightModeStyle.swift:324-360` | 从目标前/背景色代数推导单个颜色矩阵挂 `pdfView.contentFilters`,GPU 做亮度轴重映射 + 色度保留;白纸→主题底色、黑字→主题文字色;CPU 同构实现供测试比对 |
| 高亮分组寄生标准字段 | `Features/Annotations/HighlightService.swift:16-46` | 多行逐行建注解、共享 UUID 写 `userName`,分组随 PDF 文件持久,无 sidecar;外来高亮用 `page-index-bounds` 合成稳定组 ID |
| 跨调色板颜色往返 | `Features/Annotations/HighlightColor.swift:58-75` | 三套主题写入的"粉色" RGBA 各异,重开时对全部调色板最近邻分类恢复语义色,alpha 参与度量 |
| 逐字符 Vision OCR | `Features/Annotations/HighlightOCRService.swift:96-120` | 按每个字符 boundingBox 与高亮框 35% 双轴重叠裁剪 snippet;`isIdeographic` 启发式决定文本层 vs OCR;按 `ObjectIdentifier(page)` 一次 build 内缓存 |
| 零序列化 undo | `Core/DocumentStore.swift:1133-1177` | 撤销栈直接持有活 `PDFAnnotation` 对象,undo/redo 即摘下/重挂同一对象,颜色评论组 ID 天然保真 |

### 3.4 窗口与交互

| 亮点 | 位置 | 机制 |
|---|---|---|
| 双路径键拦截 | `App/ReaderShortcutWindow.swift:7-30` | `sendEvent` 截裸键(j/k)、`performKeyEquivalent` 抢在菜单匹配前截 chord;编辑态自动让路 |
| 合成标题栏拖拽区 | `App/ReaderShortcutWindow.swift:32-61` | 工具栏摘除后按 `contentLayoutRect.maxY` 重建拖拽带并避开红绿灯 |
| titlebar tabs = 居中 NSToolbarItem | `App/MainWindowController.swift:103-156` | tab strip 塞进单个 toolbar item,三步对账决定整条 toolbar 挂/摘 |
| demo 模式嵌套快照 | `App/MainWindowController.swift:287-367` | 全屏/沉浸/阅读状态分层快照逆序还原;用户 Esc 退全屏视为隐式退出 demo |
| 侧栏互换防回环 | `App/SplitViewController.swift:103-206` | 互换=重排 NSSplitViewItem 而非移视图、宽度对调;宽度持久化四重防护(应用中标志 / 首次应用门 / 4pt 写入死区 vs 1pt 应用容差 / 合并重试)斩断写读回环 |
| palette 事件回放 | `App/RecentFilesPaletteController.swift:342-436` | 导航态检测到可打印键,焦点弹回搜索框并重放同一 NSEvent,体验为连续打字;过滤/多选/环绕逻辑是纯值类型 struct,完全可单测 |
| 设置窗自适应 | `App/SettingsWindowController.swift:448-458` | 每页声明首选尺寸,token 防抖 + 像素取整 + diff 后 setContentSize |

### 3.5 阅读器 UI

| 亮点 | 位置 | 机制 |
|---|---|---|
| 跨 PDF 翻页零特判 | `UI/CenterReader/ReaderWorkspaceViewController.swift:173-227` | reader 翻页返回 `false` 表示撞边界,workspace 捕获后向 store 要组内相邻 PDF 定向跳页;reader 不知连续阅读存在 |
| 手写 outline 树 | `UI/RightOutline/OutlineViewController.swift` | 放弃 NSOutlineView:翻转容器手动排行、`boundingRect` 算换行行高、折叠态为 `Set<[Int]>`;自定义 ClipView 钉死 x=0 + 吞横向滚轮 |
| 视口锚点保缩放 | `UI/CenterReader/ReaderViewController.swift:1421-1460` | 记录视口中心页+页内点,缩放后换算回滚;对抗 PDFKit 异步重排刻意循环三次 layout+restore |
| 像素级阅读位置 | `UI/CenterReader/ReaderViewController.swift:1216-1251` | 位置=clipView 左上角换算页空间,不依赖粗糙的 `currentDestination` |
| 回声环断路器 | `UI/CenterReader/ReaderViewController.swift:93-98, 916-990` | store→view 应用期间挂 `isApplyingStoreState` 抑制写回;三方 diff(显示/活视口/store)判断谁最新 |
| 全览复用 PDFThumbnailView | `UI/CenterReader/ReaderViewController.swift:528-598` | 不写 collection view,绑同一 pdfView 点击天然导航,列数 `max(3, ceil(sqrt(pageCount)))` |
| find 重提交即跳转 | `UI/CenterReader/ReaderViewController.swift:712-743` | 选区预填并预登记为已提交 key,首个 Enter 直接跳;`SubmittedSearchKey(query, scope)` 判同 query 重提交转 `.activateNext` |

## 4. 短板(按严重度)

> 状态列跟踪到 2026-07-10。`✅` 已按 §5.1 缓解/修复;`◐` 部分缓解;`[ ]` 仍待处理(多在 §5.2)。

### 4.1 结构性债务

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| S1 | [ ] | `AppDelegate` god object:菜单构建、share/export 管线、open-URL 解析、palette 所有权、config 持久化、~140 case 的 `validateMenuItem` 集中一处 | `App/AppDelegate.swift` | 任何全局行为改动都要进同一文件;menu / 打开 / 分享相互纠缠,回归面大 |
| S2 | [ ] | `DocumentStore`:tab / split / search / annotation / undo / persistence 全在一个类型;所有 accessor 对 sessions/workspaces 做 O(n) 线性扫描 | `Core/DocumentStore.swift` | tab 数量级下性能无虞,但单类型承载七种职责,演进成本持续上升 |
| S3 | [ ] | `ReaderViewController` 缩放管理由 ~8 个交互标志位构成隐式状态机,正确性依赖微妙时序 | `UI/CenterReader/ReaderViewController.swift` | 极易回归、难以单测;新缩放/布局需求都在加标志位 |
| S4 | [ ] | 三个 palette 的 NSPanel/NSTableView 子类与面板配置近乎复制粘贴,无共享基类 | `App/*PaletteController.swift` | 改一处键处理要同步三处 |
| S5 | [ ] | `ThemeManager` 贫血包装,真正主题引擎是 `NightModeStyle` 的静态层 | `Features/Theme/` | 职责名实不符,主题状态散落静态变量(另见 C4) |

### 4.2 性能

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| P1 | ◐ | 持久化写放大:ReadingState 无修剪曾无限增长;workspace 全量 JSON 在每次 `notifyChange` 写入 | `ReadingStateStore` / `DocumentStore` | **已做:** 500 LRU + 0.75s debounce + quit flush;`.readingPosition` 跳过 workspace 全量写。**未做:** 一般 content 变更的 workspace 写合并节流 |
| P2 | ✅ | 翻页/滚动写回曾全量重建左右 tab 条并 reload 搜索列表 | tabs / search / annotations observers | **已做:** `.readingPosition` 掩码 + `TabsFingerprint` + lightweight 短路(含 annotations) |
| P3 | [ ] | OCR:6x 栅格、`tiffRepresentation` 往返、`.accurate` 同步;缓存只活一次 `buildHighlightGroups` | `HighlightOCRService` | 扫描书高亮多时侧栏刷新明显卡顿 |
| P4 | [ ] | `searchSections(in:)` 是带副作用的 getter;`totalSearchMatches` 又重复调用它 | `DocumentStore` | 读路径隐藏 IO;同一帧内重复重建 |
| P5 | ✅ | `shortcutHandlerMap()` 60+ 项字典可能每次快捷键事件重建 | `AppDelegate` | **已做:** 生命周期缓存 handler map(与 config 绑定解耦,无需 config 失效) |

### 4.3 正确性 / 健壮性风险

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| C1 | ◐ | config 四份手工平行清单曾漂移:`new_blank_tab` 缺 `requiredKeys` | `AppConfiguration` | **已做:** 补 key + default/render/required 一致性单测 + self-heal。**根治**仍见 §5.2 表驱动 |
| C2 | ✅ | `parseString` 不处理引号外行内 `#` 注释 | `AppConfigurationParser` | **已做:** `stripInlineComment`;bool/width/array 路径仍不剥注释(范围外) |
| C3 | ✅ | 夜间模式依赖 PDFKit 私有类名,曾无哨兵 | `ReaderViewController` | **已做:** `PDFKitPrivateViewSentinelTests` 探测 `ContentBackgroundView` / `PDFPageView` |
| C4 | [ ] | `nonisolated(unsafe)` 主题全局变量被 dynamic color provider 读取 | `NightModeStyle` | 严格并发模式下是数据竞争豁免点 |
| C5 | ✅ | 持久化错误曾全部 `try?` 吞掉 | `DocumentStore` / `ReadingStateStore` | **已做:** 主路径 `os.Logger`;迁移等次要路径仍有少量 `try?` |
| C6 | ✅ | `matchIndex` 恒 0;高亮 hit 取 first;sRGB 欧氏距离 | Search / Highlight | **已做:** 递增 index;取 topmost(`last`);加权 sRGB |

### 4.4 工程卫生

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| H1 | [ ] | UI 字符串中英混杂且硬编码;无本地化方案 | 多处 | 语言不一致,后续本地化需全量翻找 |
| H2 | [ ] | `controller(for:)` 与菜单状态刷新在每次 store 变更做线性扫描 / 全菜单树遍历 | `AppDelegate` | 规模小尚可,属可见的模式问题 |

## 5. 改进路线

### 5.1 近期(低成本高收益) — ✅ 已完成

分支:`fix/review-near-term-A-20260710`(2026-07-10)。自动化测试全绿。

- [x] **1. 修 C1**:`requiredKeys` 补 `new_blank_tab`;`AppConfigurationFile.requiredKeys` 上提为共享清单;一致性单测覆盖 defaultContents ≡ render、required ⊆ templates、全部 shortcut key ∈ required;缺 key 自愈回归测。
- [x] **2. 修 C2**:`parseString` 剥离引号外的行内 `#` 注释(尊重转义)。
- [x] **3. 修 C5**:document-store / reading-state 持久化主路径改为 `os.Logger` 记录失败;退出时 `flushPersistence()`。
- [x] **4. P1 减写放大**:ReadingState 500 LRU + 0.75s debounce + 内存写即时、磁盘 debounced;纯 `.readingPosition` 跳过 workspace JSON 全量写。*(一般 content 的 workspace 写节流未做,见 P1 ◐)*
- [x] **5. P2 加 diff guard**:`DocumentStoreChange.readingPosition` + tab `TabsFingerprint`;翻页不再重建 tab/search/annotations 列表;outline 仍更新页码。
- [x] **6. C3 加哨兵测试**:`PDFKitPrivateViewSentinelTests` 运行时探测私有类名。
- [x] **7. C6 + P5**:matchIndex / topmost highlight / 加权色距;shortcut handler map 生命周期缓存。

### 5.2 中期(结构重构,宜在功能冻结窗口做)

- [ ] **1. 拆 `AppDelegate`**(S1):`MenuBuilder` / `ShareCoordinator` / `OpenURLCoordinator` / `PaletteCoordinator`;`validateMenuItem` 随菜单域走。
- [ ] **2. 拆 `ReaderViewController`**(S3):`ReaderScaleController` + `PDFKitThemeApplier` + `OverviewController`。
- [ ] **3. 拆 `DocumentStore`**(S2):search / split coordinator; `searchSections` 副作用改为显式 `rebuildSearchIfNeeded()`(兼治 P4)。
- [ ] **4. config schema 表驱动**(C1 根治):单一 `[ShortcutSpec]` 生成 parser / render / defaults / requiredKeys。
- [ ] **5. palette 共享基类**(S4):`PaletteWindowController` 收 panel 样式与键处理。
- [ ] **6. OCR 异步化 + 持久缓存**(P3):后台队列 + `(URL, page, mtime)` 缓存;栅格 6x → 3–4x 自适应。
- [ ] **7. 主题状态并发收口**(C4/S5):静态变量收进 `@MainActor` ThemeManager。
- [ ] **8. 本地化决策**(H1):短期统一英文;或引入 String Catalog。

### 5.3 产品功能候选(尊重 PROJECT.md 的"不做"清单)

按"复用现有管线、增量小"排序:

- [ ] **1. 下划线 / 删除线批注**:复用 group / undo / export / userName 管线。
- [ ] **2. find 选项**:大小写敏感 / 全词匹配(`PDFDocument.findString` options + find bar toggle)。
- [ ] **3. outline 过滤框**:手写树按标题剪枝。
- [ ] **4. 高亮色快捷切换**:高亮模式内数字键 1/2/3 → pink/yellow/green。
- [ ] **5. 跨文档批注汇总导出**:所有打开 PDF 高亮一次 Markdown 汇总。
- [ ] **6. URL scheme**(`serein://open?file=…&page=N`):扩展生态最小 PoC(对齐 TASKS **M11** / PROJECT 扩展预研)。

### 5.4 已规划事项(承接 PROJECT.md / TASKS.md)

- [x] **find bar 选区预填**:已合入主线(CHANGELOG: Preload selected PDF text into Find);旧分支名 `feature/find-prefill-selection` 作废。
- [x] **M8 / M9 开发与自动化测试**:完成。
- [ ] **M8 / M9 真实 PDF 手测验收**(TASKS Wave 0:`UAT-29` ~ `UAT-33` 等)。
- [ ] **M10 系列手测**(framing / 连续阅读 / 库 / 热重载 / 空白 tab / 路径复制 / 分屏等,见 TASKS Wave 1–7.5)。
- [ ] **M11 扩展生态预研**:设计决策 + 最小 PoC(见 §5.3 第 6 条);TASKS 中为 M11(REVIEW 原文曾写 M10,已按 TASKS 更正)。
- [ ] **M12 空窗体验收尾**:`M12-010` ~ `M12-014`(TASKS)。

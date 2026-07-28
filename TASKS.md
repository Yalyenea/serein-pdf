# TASKS

[PROJECT.md](PROJECT.md) 的执行清单。已完成里程碑只保留概览,细项以 commit 历史为权威;本文件只跟踪进行中与待开发项。

## 1. 执行规则

- 开启里程碑前确认依赖任务已完成。
- 每完成一个可见功能立即补最小验证。
- 状态管理落在 `DocumentStore` / `DocumentSession`,不散到视图层。
- 垂直 tab 与水平 titlebar tab 共享同一套命令与状态模型。
- UI 决策守"极简、扁平、紧凑",不增无必要控件。

## 2. 产品常量

- `TabPresentationMode`:`verticalSidebar` / `horizontalTitlebar`
- 外观配置:`mode(system/light/dark)` + `light_theme(normal/rose_pine_dawn)` + `dark_theme(normal/rose_pine_moon)`
- Rose Pine Dawn 仅替换 PDF 白底并保留原文档颜色;Rose Pine Moon 映射纸面 / 正文端点并保留暖冷强调色方向;两者使用不透明扁平侧栏
- 访问配置:`access.roots` 默认保存 `/Users`,`access.root_bookmarks` 保存启动时生成的持久访问授权,避免重装后逐个文件请求权限
- 本地安装签名:`just build` / `just install` 使用 `Serein Local Code Signing` 稳定签名身份,避免重装后变成新的 cdhash-only app 身份
- PDF 库配置:`library.folders` 保存一个或多个文件夹,打开库时递归扫描 PDF,建立轻量索引并缓存,按库 root / 子文件夹 / PDF 列表二级浏览
- 默认高亮色:偏轻、低饱和、清晰的粉色
- `a`:有选区 → 立即高亮;无选区 → 进入高亮模式
- `Esc`:退出高亮模式 / 关闭 Find bar / 退出全览 / 退出演示模式
- `d`:删除鼠标所在高亮;多行整组删除
- `i`:在 light / dark mode 间切换,并保留各自已选 theme
- `Cmd+K` → `Cmd+T`:切换当前外观侧的 theme,不改变 light / dark mode
- `Cmd+K` → `Cmd+O`:打开 PDF 库二级浏览面板
- `Cmd+K` → `Cmd+R`:刷新并重扫 PDF 库索引
- `Cmd+K` → `Cmd+L` / `Cmd+K` → `Cmd+S`:打开 Settings 的 Library / Shortcuts 页
- `Cmd+K` → `Cmd+M`:合并所有窗口到当前窗口
- `Cmd+K` → `Cmd+N`:把当前 PDF 移到新窗口
- `Cmd+F` / `Cmd+Shift+F`:打开 Find bar 时若当前 PDF 有选中文本,立即用选中文本搜索当前文档 / 所有已打开 PDF
- `Ctrl+D` / `Ctrl+U`:半页下滚 / 上滚
- `g` / `G`:跳到文首 / 文末
- `Cmd+S`:写回源 PDF
- `Cmd+R`:在 Finder 中显示当前 PDF 所在位置
- `Cmd+0` / `Cmd+9`:适应宽度 / 适应高度
- `F`:开启 / 关闭鼠标跟随阅读聚焦,外围统一压暗且不接管 PDF 交互
- `Option+F`:调整当前窗口聚焦宽度(Page / Column / Custom)与高度;Settings General 配置默认值
- `L`:水平平移锁定(放大后 X 居中并禁止左右滑动;竖直滚动保留;焦点 pane)
- `C`:在单页连续 / 单页不连续间切换;`Cmd+2`:直接切换到单页连续阅读模式
- `singlePage`:当前页完整放下时双轴居中并钳制空白区域滑动;放大到超出视口后仍允许页内平移
- `Cmd+T`:新建空白 tab;空白 tab 不绑定 PDF、不进入最近 / 重开历史、不跨启动恢复
- `Ctrl+Tab`:显示当前窗口所有 tabs 的轻量文本总览,点击或 Enter 普通切换;`Option+Click` / `Option+Enter` 进入 split-edit
- `Cmd+W`:多选 tabs 时按窗口顺序关闭选中的 PDFs;否则关闭当前 tab / window
- `Cmd+Shift+W`:关闭当前窗口,沿用 dirty 批注保存确认
- `Cmd+Shift+C`:复制当前 PDF 路径到剪贴板
- `Cmd+K` → `Cmd+E`:系统 Share 当前 PDF,可选 Original / Clean Copy / Highlights
- `File > Export Clean Copy…`:导出移除可见用户批注、保留链接与表单控件的 PDF 副本
- `Cmd+Ctrl+\`:左侧保持当前 PDF,右侧进入候选态;首项为同一个 PDF,后续为当前窗口其他 PDF
- 分屏 pair:普通 tab 点击恢复 pair 或离开 pair;`Option` 激活才替换当前焦点 pane,未分屏时建立当前 PDF + 目标 PDF pair
- 同 PDF comparison session:内部 session,独立页码 / 缩放,不显示普通 tab、不进最近 / 重开 / 持久化 / All Open 搜索
- 多 PDF 连续阅读:对当前选中的 tabs 通过 tab 右键菜单开启 / 退出;连续组内翻页跨 PDF 边界切换,右侧 Outline 按 PDF 分组显示
- PDF 热重载:LaTeX / Typst 等外部工具原地写入或原子替换已打开 PDF 后自动刷新 clean session;dirty 批注会话不自动刷新
- 自动保存默认 `10 min`,至少支持 `10 min` / `never`
- 左侧 tabs 栏底部可选显示 recent PDFs 快捷入口(设置可开关)
- 水平 tab 复用标题栏,不单独开行,可见宽度随标题内容自适应
- 右栏支持 Outline / Pages / Search / Annotations,`Cmd+Shift+L` 仍在 Outline / Pages 间切换;Outline 随侧栏宽度收缩且无水平滑动,目录树可一键折叠 / 展开
- 左右侧栏可见性切换只触发 chrome 布局更新,不得重建 reader / tabs / outline / search / annotations 数据
- `Cmd+L` 进入 / 退出演示模式(直接全屏播放,页面完整适配并复用单页居中钳制,退出后恢复进入前布局)
- `Cmd+Ctrl+L`:仅当左右侧栏都关闭时打开两个侧栏;其他任一状态关闭两个侧栏与 tab chrome
- 左右可互换:`Cmd+Shift+X` 或设置窗口
- 侧栏透明度:左右侧栏使用 native material,`layout.sidebar_opacity` 控制 tint 强度,设置窗口可调
- 设置窗口 General / Library / Shortcuts 页签保持等宽,维持紧凑稳定的页头视觉
- PDF 切换:从一个已显示 PDF 切到另一个 PDF 后,阅读区顶部短暂显示当前文件名
- 保留标准 macOS app / window 快捷键,至少包括 `Cmd+H` / `Cmd+Option+H` / `Cmd+M`
- 主窗口适配 macOS 原生绿灯菜单:Full Screen、Move & Resize、Fill、Center、Fill & Arrange;默认尺寸不变,最小尺寸需允许系统半屏 / 四分屏
- 透明标题栏顶部条带只负责窗口拖动,不得把拖拽事件传给 PDF 阅读区
- 重复打开已打开 PDF:系统 `open`、Open Recent、PDF Library 与 `Cmd+O` 都应激活已有 window/session,不创建重复普通 tab

## 3. 当前进度

| 里程碑 | 状态 |
|---|---|
| M1 MVP 骨架 | ✅ |
| M2 阅读体验 | ✅ |
| M3 高亮批注 | ✅ |
| M4 夜间与打磨 | ✅ |
| M5 设置与收口 | ✅ |
| M6 体验打磨 | ✅ |
| M7 搜索 + 对比 | ✅ |
| M8 批注深度化 | ✅ |
| M9 最近文件启动器 | ✅ |
| M10 阅读区 Framing 打磨 | ✅ |
| M10.5 多 PDF 连续阅读 | ✅ |
| M10.6 PDF 库 | ✅ |
| M10.7 PDF 热重载 | ✅ |
| M10.8 PDF 切换定位提示 | ✅ |
| M10.9 macOS 绿灯窗口管理 | ✅ |
| M10.10 阅读交互打磨 | ✅ |
| M10.11 空白标签页 | ✅ |
| M10.12 当前 PDF 路径复制 | ✅ |
| M10.13 浏览器式分屏 | ✅ |
| M10.12.1 Return 焦点收口 | ✅ |
| M11 扩展生态(预研) | 未开始 |
| M12 Backlog 体验分流 | 进行中 |
| M13 本地产品网站 | ✅ |
| M13.1 网站后续完善 | 待办 |
| M14 窗口工作流交互 | ✅ |
| M15 阅读聚焦 | ✅ |

## 4. 下一步执行顺序

权威债项与路线见 [REVIEW.md](REVIEW.md)。本节只跟踪执行勾选。

### 4.0 REVIEW 改进路线

#### 5.1 近期债 — 分支 `fix/review-near-term-A-20260710`

- [x] C1 `requiredKeys` + `new_blank_tab` + 一致性单测
- [x] C2 TOML 行内 `#` 注释
- [x] C5 持久化 `os.Logger`
- [x] P1 ReadingState LRU 500 + debounce + 跳过 readingPosition 全量 workspace 写
- [x] P2 `.readingPosition` 掩码 + tab fingerprint + lightweight 短路
- [x] C3 PDFKit 私有类名哨兵测试
- [x] C6 matchIndex / topmost highlight / 加权色距
- [x] P5 shortcut handler map 缓存

#### 5.2 中期重构

- [ ] S1 拆 `AppDelegate`
- [ ] S3 拆 `ReaderViewController`
- [ ] S2 拆 `DocumentStore`（兼 P4 search 副作用）
- [ ] C1 根治：config schema 表驱动
- [ ] S4 palette 共享基类
- [ ] P3 OCR 异步化 + 持久缓存
- [ ] C4/S5 主题状态并发收口
- [ ] H1 本地化决策

#### 5.3 产品候选

- [x] 放大后水平平移锁定（`l`，焦点 pane，X 居中）
- [ ] 下划线 / 删除线批注
- [ ] find 大小写 / 全词选项
- [ ] outline 过滤框
- [ ] 高亮色数字键 1/2/3
- [ ] 跨文档批注汇总导出
- [ ] URL scheme PoC（对齐 M11）

#### 5.4 承接里程碑

- [x] find bar 选区预填（已合入）
- [x] M8 / M9 开发、自动化测试与真实 PDF 手测
- [x] M10 系列（含 M10.5–M10.13 / M10.12.1）开发、自动化测试与手测
- [ ] M11 扩展生态预研
- [ ] M12 空窗收尾 `M12-010`–`014`

### 4.1 手测与里程碑波次

- [x] Wave 0 M8 / M9 手测：`UAT-29` ~ `UAT-33` 等通过。
- [x] Wave 1 M10 手测：`M10-021` framing 通过。
- [x] Wave 2 M10.5 手测：`UAT-37` 连续阅读通过。
- [x] Wave 3 M10.6 手测：`UAT-38` PDF 库通过。
- [x] Wave 4 M10.7 手测：`UAT-39` 热重载通过。
- [x] Wave 5 M10.11 手测：`UAT-46` 空白 tab 通过。
- [x] Wave 6 M10.12 手测：`UAT-47` 路径复制通过。
- [x] Wave 7 M10.13 手测：`UAT-48` ~ `UAT-50` 浏览器式分屏通过。
- [x] Wave 7.5 M10.12.1 手测：Go to Page 焦点与 Return 通过。
- Wave 8 M11 预研：做 `M11-001`，把扩展机制 RFC 先落出来。
- Wave 9 M12 体验分流：`M12-001` / `M12-003` ~ `M12-009` 已完成，`M12-002` 先暂缓；继续 `M12-010`–`014`。

## 5. Milestone 7:搜索强化与对比阅读

### 5.1 搜索结果面板

- [x] `M7-001` 搜索模型升级:缓存当前 session / all-open 匹配项,关闭 find bar 或切 tab 时清空。
- [x] `M7-002` 右栏 Search 面板:按页或按 session 分组显示 snippet + 页码,点击跳转并推入历史栈。
- [x] `M7-003` 结果导航键绑定:find bar 焦点下 `↑` / `↓` 移动列表,`Enter` 跳转,`Cmd+G` / `Cmd+Shift+G` 循环激活。
- [x] `M7-004` 搜索性能:本地 220 页合成 PDF 搜索测试通过,首次缓存命中 < 500ms。
- [x] `M7-005` 跨文档搜索:find bar 顶部 toggle `This Document` / `All Open`;`All Open` 只覆盖当前窗口已打开文档,跨文档结果带 session 名,点击先切 session 再跳转。
- [x] 所有预览相关内容统一放入右侧边栏。

### 5.2 同窗分屏 / 多窗口

- [x] `M7-010` 同窗分屏容器:中栏拆水平双 Reader;`Cmd+Ctrl+\` 切换;各 Reader 独立 `displayedSessionID`。
- [x] `M7-011` 分屏 tab 切换落点:完成基础双 Reader 与 Option 分屏入口;最终浏览器式 pair 语义见 `M10.13`。
- [x] `M7-012` 分屏状态持久化:保留 legacy splitState 编解码兼容;当前启动恢复默认单屏,运行期 pair 不持久化。
- [x] `M7-013` 新建窗口命令:`ShortcutCommand.newWindow`,默认 `Cmd+Shift+N`;`AppDelegate` 支持多 `MainWindowController`;`DocumentStore` 暴露多窗口接口。
- [x] `M7-014` 多窗口关闭协调:关闭一窗不影响其他;最后一窗关闭走 terminate;`Cmd+Shift+T` 优先本窗内重开。
- [x] `M7-015` 多窗口状态持久化:记录各窗口 session 集合 / active session / search / sidebar 布局;split pair 为运行期状态。
- [x] `M7-016` 测试:`DocumentStoreTests` 覆盖多窗口、分屏、搜索缓存、恢复与性能基线。

### 5.3 文档与验收

- [x] `M7-020` 同步 `PROJECT.md` / `TASKS.md` / `README.md`。
- [x] `M7-021` M7 手测验收:`AC-M7-1` ~ `AC-M7-5` 通过。

## 6. Milestone 8:批注深度化

### 6.1 批注管理器

- [x] `M8-001` 批注模型扩展:每 highlight 抽取 `snippet` / `pageIndex` / `color` / `createdAt`(PDF 可取则取,否则 session 内维护)。
- [x] `M8-002` 右栏 Annotations 模式:保留 Outline / Pages / Search,新增 Annotations;列表按页分组,显示 snippet + 颜色点。
- [x] `M8-003` 点击跳转并高亮:跳到目标页并短暂强调对应 annotation。
- [x] `M8-004` dirty 变更同步:增删 highlight / 评论实时更新列表。
- [x] `M8-005` 高亮评论:每个高亮组支持 comment,在右栏编辑并随 PDF 一起保存。

### 6.2 导出

- [x] `M8-010` 抽取导出内容:`[(page, snippet, color, comment)]`,按页排序。
- [x] `M8-011` 三种导出格式:Markdown / Plain / JSON;都覆盖 snippet、页码、颜色、评论。
- [x] `M8-012` 输出目标:`File > Export Highlights…`;`Cmd+Shift+E` 复制 Markdown 到剪贴板;"Save as…" 走 `NSSavePanel`。
- [x] `M8-013` `HighlightExporterTests` 覆盖三种格式稳定。

### 6.3 自定义快捷键 UI

- [x] `M8-020` Shortcuts 面板:设置窗口新增 tab;列出所有 `ShortcutCommand` + 当前绑定 + 默认值。
- [x] `M8-021` key-capture 控件:捕获按键 → `KeyboardShortcut`;支持清除 / 恢复默认。
- [x] `M8-022` 冲突检测:同组合冲突时拒绝或提示。
- [x] `M8-023` 写回配置:保存时触发 `configStore.save` + `updateAppConfiguration`;菜单 `keyEquivalent` 立即刷新。
- [x] `M8-024` 测试:`AppConfigurationTests` 覆盖清除为 `none`、新增导出快捷键、重读闭环。

### 6.4 文档与验收

- [x] `M8-030` 同步 `PROJECT.md` / `TASKS.md` / `config.toml` 默认内容。
- [x] `M8-031` M8 验收:`AC-M8-1` ~ `AC-M8-4` 通过。

## 7. Milestone 9:最近文件启动器

- [x] `M9-001` Spotlight 风格面板:`Cmd+Shift+Space` 拉起最近文件启动器,默认在当前窗口中心显示。
- [x] `M9-002` 搜索与排序:基于 `recentDocumentURLs` 提供文件名/路径匹配,结果保持最近打开优先。
- [x] `M9-003` 键盘交互:`↑` / `↓` 选中,`Space` 切换多选,`Enter` 打开选中或当前项,`Esc` 关闭。
- [x] `M9-004` 操作提示:面板底部常驻显示键盘操作说明,不跳出到外部文档。
- [x] `M9-005` 测试:覆盖搜索过滤、多选打开、空列表与帮助切换。
- [x] `M9-006` Show All Tabs:`Ctrl+Tab` 显示当前窗口所有 PDF tab 的轻量文本总览,不渲染缩略图,支持点击、方向键、H/J/K/L、Enter 切换、Esc 关闭。
- [x] `M9-007` Show All Tabs 关闭语义:严格单选,重复 `Ctrl+Tab` / `Esc` / app 失焦关闭,打开后关闭。
- [x] `M9-008` Show All Tabs 分屏联动:`Option+Click` / `Option+Enter` 进入 split-edit,未分屏时建立当前 PDF + 目标 PDF pair。
- [x] `M9-009` 多 PDF 打开懒加载:tab session 先保存 URL/title/阅读状态;live `PDFDocument` 由小容量 LRU 按需加载,干净后台文档可释放。
- [x] `M9-010` 右栏缓存延迟构建:outline / annotations / search 在对应面板或搜索动作需要时才解析 PDF。

## 8. Milestone 10:阅读区 Framing 打磨

### 8.1 单页居中与主窗口显示

- [x] `M10-001` 主窗口默认 framing:重新评估 `MainWindowController` 默认窗口尺寸与最小尺寸,兼顾纵向论文与横向 slide,避免首次打开时阅读区过矮或过窄。
- [x] `M10-002` 单页非连续居中:`singlePage` 模式下,当页面完整放下时,页面应保持在中栏内双轴居中并钳制空白区域滑动。
- [x] `M10-003` 单页缩放体验:在 `singlePage` 模式连续缩小 / 放大时,页面中心与阅读焦点保持稳定,避免缩放后突然跳边或滚动偏移过大。

### 8.2 Fit Width / Fit Page 语义收口

- [x] `M10-010` `Cmd+0` 行为校准:当前 fit width 计算改为“刚好显示完整内容且不横向裁切”,对 slide / paper 都成立。
- [x] `M10-011` 宽页与窄页验证:针对 16:9 slide、常规 A4/Letter PDF、双页模式分别校准 scale 计算,避免某一类文档过大或过小。
- [x] `M10-012` 打开默认行为:若配置为 `fit_width_on_open = true`,新打开文档默认直接落在校准后的 framing,不需要手动再缩放一次。

### 8.3 测试与验收

- [x] `M10-020` 测试:补充 `ReaderViewController` / `WindowChromeTests`,覆盖单页双轴居中、fit width scale 计算、演示模式 fit page 与主窗口默认 framing。
- [x] `M10-021` 手测:使用 `~/Downloads` 里的真实 slide PDF 和常规论文 PDF 各验证一次,记录视觉差异与最终默认值。

## 9. Milestone 10.5:多 PDF 连续阅读

- [x] `M10.5-001` 窗口级连续阅读状态:在 `WindowWorkspace` 保存 selected tabs 与有序连续组,并随持久化恢复。
- [x] `M10.5-002` tab 入口:批量打开自动预选本批 PDF;`Cmd` / `Shift` 点击支持多选;右键开启 / 退出连续阅读。
- [x] `M10.5-003` tab 表达:连续组内 tab 轻量缩进并显示细分组标记,垂直 / 标题栏 tabs 共用模型。
- [x] `M10.5-004` 阅读行为:在组内 PDF 边界执行下一页 / 上一页 / 半页滚动时切到相邻 PDF 首页 / 末页。
- [x] `M10.5-005` 连续 Outline:右侧 Outline 顶层按 PDF 分组,点击跨 PDF 目录项先切 session 再跳页。
- [x] `M10.5-006` 测试:覆盖连续组顺序、关闭清理、恢复、连续 Outline 与跨 PDF 翻页。
- [x] `M10.5-007` 多选关闭:多选 tabs 后 `Cmd+W` 一次关闭选中 PDFs,未多选时保持当前 tab / 分屏关闭语义。

## 10. Milestone 10.6:PDF 库

- [x] `M10.6-001` 配置模型:在 `config.toml` 增加 `[library] folders = []`,支持保存多个库文件夹。
- [x] `M10.6-002` 设置页:新增 Library 页,支持添加 / 移除库文件夹并即时写回配置。
- [x] `M10.6-003` 库扫描:打开库时递归扫描配置文件夹内 PDF,按路径稳定排序并去重。
- [x] `M10.6-004` 快捷键入口:`Cmd+K` → `Cmd+O` 打开 PDF Library 二级浏览面板,不落入标准 Open panel。
- [x] `M10.6-005` 测试:覆盖配置读写、库扫描、chord 分发、设置窗口尺寸。
- [x] `M10.6-006` 性能:PDF Library catalog 对同一组库文件夹复用缓存,并预计算 root / folder / search 索引,避免每次打开面板重复扫描。
- [x] `M10.6-007` Cmd+K 工作流:增加库索引刷新、Library / Shortcuts 设置直达、合并窗口、当前 PDF 移到新窗口,并放入 macOS menubar。
- [x] `M10.6-008` 权限:首次启动请求 `/Users` 持久 security-scoped bookmark,启动和配置变化时恢复访问,避免重装后反复询问用户文件夹内 PDF 授权。
- [x] `M10.6-009` 本地签名:构建时创建 / 复用 `Serein Local Code Signing` 身份并签名 `.app`,避免重装后 ad-hoc cdhash 变化导致 macOS 文件访问信任失效。

## 11. Milestone 10.7:PDF 热重载

- [x] `M10.7-001` 文件监听:按已打开 PDF 文件及其父目录监听外部写入 / rename / delete 事件,适配 LaTeX / Typst 原地写入与覆盖式编译。
- [x] `M10.7-002` Store 重载:文件快照变化后清理 clean session 的 `PDFDocument` / Outline / Search / Annotations 缓存,保持阅读位置、缩放与显示模式。
- [x] `M10.7-003` dirty 保护:存在未保存 Serein 批注时不自动重载对应 PDF,避免丢失内存批注。
- [x] `M10.7-004` 测试:覆盖 clean 重载、同 URL 多 session 重载、dirty session 不重载。

## 12. Milestone 10.8:PDF 切换定位提示

- [x] `M10.8-001` 阅读区提示:从一个 PDF 切到另一个 PDF 后,顶部短暂显示当前文件名;首次打开空窗口不显示。
- [x] `M10.8-002` 测试:覆盖切换 PDF 后提示使用当前 session title。
- [x] `M10.8-003` 手测:快速切换多个真实 PDF,确认提示短暂、轻量、不遮挡常驻 chrome。

## 13. Milestone 10.10:阅读交互打磨

- [x] `M10.10-001` 右栏 Outline:长标题自动换行,字号提升到 13pt,换行内部行距收紧,行高按内容紧凑动态增长,隐藏滚动条并禁横向滑动感。
- [x] `M10.10-002` 同窗分屏:进入分屏后 primary / secondary 两个 reader 自动适应各自 pane 宽度。
- [x] `M10.10-003` 阅读快捷键:普通 `C` 在 `singlePage` / `singlePageContinuous` 间切换,`Cmd+2` 保持直接进入连续。
- [x] `M10.10-004` 最近文件启动器:选中结果后 Return / keypad Enter 都能打开,不依赖双击。
- [x] `M10.10-005` 测试:覆盖 Outline wrap 与紧凑滚动行为、分屏 fit width、`C` toggle 与最近文件 Enter 路由。

## 14. Milestone 10.11:空白标签页

- [x] `M10.11-001` Store 模型:新增显式空白 session,不绑定 PDF URL 语义,保持 tab / pane 选择模型一致。
- [x] `M10.11-002` 快捷键入口:`Cmd+T` 新建空白 tab,菜单项为 `New Blank Tab`。
- [x] `M10.11-003` 历史与持久化:空白 tab 不进入最近文件、不进入最近关闭栈、不写入跨启动会话。
- [x] `M10.11-004` 测试:覆盖空白 tab 创建、关闭历史、持久化过滤与默认快捷键。

## 15. Milestone 10.12:当前 PDF 路径复制

- [x] `M10.12-001` 快捷键入口:`Cmd+Shift+C` 复制当前 PDF 路径到剪贴板。
- [x] `M10.12-002` 配置迁移:新增 `copy_current_pdf_path`,连续阅读默认快捷键改为 `none`,保留 tab 右键入口。
- [x] `M10.12-003` 测试:覆盖默认快捷键、旧连续阅读键位迁移与配置回写。

## 16. Milestone 10.13:浏览器式分屏

- [x] `M10.13-001` 状态模型:在 `WindowWorkspace` 增加运行期 `ReaderSplitPair`,把"显示双 Reader"与"绑定哪两个 PDF"分开。
- [x] `M10.13-002` 普通 tab 语义:点击 pair 内任一 PDF 恢复 A/B 分屏;点击其他 PDF 显示单屏并保留 pair。
- [x] `M10.13-003` split-edit 语义:`Option+Click` / `Option+Enter` 替换当前焦点 pane;未分屏时建立当前 PDF + 目标 PDF pair。
- [x] `M10.13-004` 同 PDF 对比:内部 comparison session 独立页码 / 缩放,不显示普通 tab、不进最近 / 重开 / 持久化 / All Open 搜索。
- [x] `M10.13-005` 候选 UI:`Cmd+Ctrl+\` 后右侧显示紧凑候选,首项为同一个 PDF,后续为当前窗口其他 PDF。
- [x] `M10.13-006` 测试与文档:覆盖 pair 隐藏 / 恢复、Option 替换、同 PDF clone、vertical/titlebar tabs 一致性,同步 README / PROJECT / TASKS / CHANGELOG。

## 17. Milestone 11:扩展生态(长期预研)

- [ ] `M11-001` 扩展机制 RFC:`docs/extensions-rfc.md` 列选型,至少比较进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳。
- [ ] `M11-002` PoC:若决策继续,选一条路径把"导出高亮"重写为插件,可在 app 中运行。
- [ ] `M11-003` Serein Extension API 草稿:面向未来扩展开发者。
- [ ] `M11-004` 若推迟,在 RFC 写清"为什么现在不做"(安全、上架、维护成本)。

## 18. Milestone 12:Backlog 体验分流

### 18.1 值得做

- [x] `M12-001` 侧边栏宽度收口:取消 per-PDF sidebar width 记忆,改为窗口运行期宽度 + 配置默认宽度;Settings General 可编辑左右默认宽度;切 PDF 不应导致左右侧栏宽度跳变。
- [x] `M12-003` 高亮导出模板优化:Markdown 默认模板按页输出 snippet + comment,适合笔记粘贴;Plain / JSON 保留颜色等元信息。
- [x] `M12-004` 系统 Share 与干净副本分享:接入 macOS `NSSharingServicePicker`,支持 `Cmd+K` → `Cmd+E`;提供导出/分享移除可见用户批注、保留链接与表单控件的 PDF 副本。
- [x] `M12-005` 高亮颜色主题化:按 `normal` / `rose_pine_dawn` / `rose_pine_moon` 优化 pink / yellow / green,保持低饱和、清晰、打印与暗色下不过刺眼。
- [x] `M12-006` macOS 原生最近项目与窗口集成:接入 `NSDocumentController` recent documents、窗口 `representedURL` / `representedFilename`,改善系统 Open Recent、App Expose 与窗口标题关联。
- [x] `M12-007` 侧栏透明度与沉浸切换收口:左右侧栏使用 native material,Settings General 可调 tint 强度;`Cmd+Ctrl+L` 仅在双侧栏都关闭时打开两个侧栏,否则关闭两个侧栏。
- [x] `M12-008` 重复打开收口:系统 `open`、Open Recent、PDF Library 与 `Cmd+O` 遇到已打开 PDF 时切回已有 window/session,不创建重复普通 tab。
- [x] `M12-009` 中栏空窗统一引导:无 PDF / 空白 tab 时,中栏显示主文案 + `⌘O` / 最近文件快捷键提示 + 拖放 PDF 打开;错误态只显示错误信息。
- [x] `M12-015` 文档侧栏空白区域拖窗:只让背景接管窗口拖动,不抢 tab、关闭按钮、divider、滚动与跨窗 tab 拖拽。
- [ ] `M12-010` 空窗侧栏占比收口:无 session 时自动折叠侧栏或采用更窄默认宽度,把引导集中到中栏。
- [ ] `M12-011` 右栏空窗 chrome 弱化:无文档时隐藏 / disable segmented 与 Outline 操作控件,避免「已就绪但未加载」噪音。
- [ ] `M12-012` 左栏空态层次增强:补 `Documents` section 标题;空态时上移 Recent 列表或在中栏同步展示快捷入口。
- [ ] `M12-013` 空态视觉语言统一:抽共享 empty state 组件,统一三栏与右栏各 mode 的字号 / 颜色 / 对齐。
- [ ] `M12-014` 侧栏顶部留白校准:空态时将侧栏内容垂直居中或收紧 titlebar 留白,减少顶部死区。

### 18.2 暂缓

- [ ] `M12-D002` Pages 缩略图滑动渲染优化:暂缓。当前依赖 `PDFThumbnailView`;只有在真实大 PDF 出现可复现卡顿、白屏或错序渲染样本后,再考虑自定义缓存/预热。
- [ ] `M12-D003` Zed / VS Code / LaTeX / Typst PDF sync:暂缓。热重载已覆盖基础编译预览;SyncTeX / 编辑器反向定位属于更大集成,先写 RFC 再决定。
- [ ] `M12-D004` 双屏同步滚动对照阅读:暂缓。需要跨窗口或跨 pane 阅读位置同步模型;等同窗分屏和同 PDF comparison 手测稳定后再启动。
- [ ] `M12-D005` 外部 rename 自动更新打开文档名称:暂缓。App 内重命名已更新文件、session、recent;Finder 外部 rename 需先定义如何从旧路径可靠发现新路径。
- [ ] `M12-D006` 批注双向定位:暂缓。右栏 Annotations 点击高亮已可跳到 PDF;从 PDF 高亮反向定位右栏评论先等点击/编辑态需求边界更明确后再做。

## 19. Milestone 13:本地产品网站

- [x] `M13-001` 新增 `Website/` 静态站点,覆盖展示、下载说明与紧凑文档。
- [x] `M13-002` 使用合成 PDF 捕获真实 Serein 窗口截图,并移除截图中的私人文档痕迹。
- [x] `M13-003` 增加 `just website` / `just website-check`,用于本地预览和基础结构检查。
- [x] `M13-004` 同步 `README.md` / `CHANGELOG.md` / `TASKS.md`。
- [x] `M13-005` 按 Jump 式编辑部/档案风重构站点:暖纸衬线、发丝品牌线、颗粒质感、rise/reveal、亮暗主题、EN/中文、能力分段与下载区。

### 19.1 Milestone 13.1:网站后续完善(待办)

结构与文案骨架已落地;以下留给后续有素材时再补,不阻塞主线。

- [ ] `M13.1-001` 实机截图替换编辑风占位卡:高亮批注、对照分屏、全览网格、连续阅读、搜索右栏、标签切换等。
- [ ] `M13.1-002` 截图规范:合成/脱敏 PDF、统一窗口尺寸与主题、导出到 `Website/assets/screens/`。
- [ ] `M13.1-003` 下载区接正式 release 产物说明(DMG 名、本地签名 / 右键打开提示保持准确)。
- [ ] `M13.1-004` 可选:GitHub Pages / 自定义域名部署与 `just` 发布入口。
- [ ] `M13.1-005` 可选:补充 1–2 张暗色 / Rose Pine 主题截图,与站点 dark theme 对照。
- [ ] `M13.1-006` 文案与 i18n 终稿校对(EN/中文),确认与 `README` 功能表述一致。

## 20. Milestone 14:窗口工作流交互

- [x] `M14-001` 多窗口文件移动:`DocumentStore` 原子迁移同一 session;Window 菜单与垂直 / 标题栏 tab 跨窗拖拽共用该入口。
- [x] `M14-002` 热重载定位:替换 `PDFDocument` 前捕获 PDFView 实时阅读位,新文档页数变化时钳制并写回 store。
- [x] `M14-003` 双向分屏:窗口运行期支持左右 / 上下方向,切换不改 pair、pane session、焦点与跨启动恢复语义。
- [x] `M14-004` 侧栏空白拖窗:仅背景区域调用原生窗口拖动,tab / close / divider / scroll 保持独立。
- [x] `M14-005` 物理 Command 数字键:左 `Cmd+1/2/3` 激活前三个 tab,右 `Cmd+1/2/3/4` 继续走可配置阅读模式。
- [x] `M14-006` 测试与文档:覆盖跨窗状态清理、两种分屏几何、stale-store 热重载、左右 Command 路由与拖拽事件边界;同步 README / PROJECT / CHANGELOG / 网站文案。

## 21. Milestone 15:鼠标跟随阅读聚焦

- [x] `M15-001` 聚焦遮罩:`F` 开关,按鼠标位置与真实 PDF page bounds 生成焦点区域,overlay 不接管 PDF hit-test。
- [x] `M15-002` 宽高交互:`Option+F` 提供当前窗口 Page / Column(半页) / Custom 宽度与高度调节,双 pane 同步。
- [x] `M15-003` 默认配置:Settings General 与 config.toml 保存默认宽度模式、自定义比例和高度;默认适应页宽、96 pt 高。
- [x] `M15-004` 视觉收口:单一 even-odd 圆角矩形镂空、统一外围压暗、轻描边与边缘阴影;移除渐变拼接与缩窄后的残留块。
- [x] `M15-005` 测试与文档:覆盖几何、配置持久化、快捷键、窗口同步、暗色强度与遮罩结构;同步 README / PROJECT / TASKS / CHANGELOG / 网站文案。

## 22. 手测清单(尚未覆盖)

- [x] `UAT-24` `Cmd+F` 搜索后,右栏 Search 按页或按文档分组展示 snippet / 页码;有 PDF 选中文本时会自动带入并立即搜索
- [x] `UAT-25` find bar 内 `↑` / `↓` / `Enter` 与 `Cmd+G` / `Cmd+Shift+G` 都能驱动右栏结果与跳转
- [x] `UAT-26` `This Document` / `All Open` 切换正确,跨文档命中会先切 session 再跳转
- [x] `UAT-27` `Cmd+Ctrl+\` 进入同窗分屏,两侧独立切换 session 不污染
- [x] `UAT-28` `Cmd+Shift+N` 新建窗口,两窗口独立且关闭互不影响,重启后恢复
- [x] `UAT-29` 右栏 Annotations 能列出所有高亮,点击跳转,并可编辑 / 清空评论
- [x] `UAT-30` 导出 Markdown / Plain / JSON 输出正确,Markdown 按页输出 snippet + comment,Plain / JSON 保留完整字段
- [x] `UAT-31` Shortcuts 面板改绑定后新会话生效,冲突被拒,清除后写回 `none`
- [x] `UAT-32` 最近文件启动器可搜索最近文件,支持 `Space` 多选与 `Enter` 打开
- [x] `UAT-33` 最近文件启动器底部常驻显示操作提示,无查询和有查询时都可直接 `↓` 浏览结果
- [x] `UAT-33A` Show All Tabs 可在大量已打开 PDF 中通过轻量文本总览切换 tab,且单选与分屏打开语义正确
- [x] `UAT-33B` 批量打开大量 PDF 时先出现 tabs,只加载当前 reader / 分屏 reader,后台干净 PDF 可被 LRU 释放
- [x] `UAT-34` 单页非连续模式缩小后页面保持居中,slide PDF 不贴边
- [x] `UAT-35` `Cmd+0` 或默认 fit width 后,页面刚好完整显示内容,无横向裁切
- [ ] `UAT-36` 扩展机制 RFC 存在并评审(M11 证据)
- [x] `UAT-37` 多选多个 slide PDF 后通过右键开启连续阅读,`J/K` 或半页滚动能跨 PDF 边界,右侧 Outline 按 PDF 连续分组显示
- [x] `UAT-37A` 多选多个 tabs 后按 `Cmd+W`,选中的 PDFs 同时关闭,未选中的 tab 保留并成为活动 tab
- [x] `UAT-38` Settings > Library 添加 Book 文件夹后,`Cmd+K` → `Cmd+O` 可搜索并打开库内 PDF
- [x] `UAT-39` 外部编译器连续覆盖当前 PDF 后,Serein 自动刷新内容并保持当前页 / 缩放;dirty 批注会话不自动刷新
- [x] `UAT-40` 快速切换多个 PDF 后,阅读区顶部短暂显示当前文件名,随后自动淡出
- [x] `UAT-41` 从透明标题栏顶部拖动窗口时只移动窗口,不会滑动 PDF;红黄绿按钮与水平 titlebar tabs 仍可正常点击
- [x] `UAT-42` 打开带长目录标题的 PDF,确认右栏 Outline 自动换行、行距紧凑、无可见滚动条且不会横向滑动
- [x] `UAT-43` 从手动缩放状态进入同窗分屏,确认两个 pane 都自动适应宽度
- [x] `UAT-44` 最近文件启动器中方向键选中文件后按 Enter / keypad Enter 都能打开
- [x] `UAT-45` 阅读区按 `C` 可在单页连续 / 单页不连续间切换,`Cmd+2` 仍直接进入单页连续模式
- [x] `UAT-46` 按 `Cmd+T` 新建空白 tab,确认左侧 / 标题栏 tabs 都显示 Untitled,关闭后不会出现在重开历史或最近文件
- [x] `UAT-47` 打开真实 PDF 后按 `Cmd+Shift+C`,确认系统剪贴板内容等于当前 PDF 绝对路径;空白 tab 下菜单项不可用
- [x] `UAT-48` `Cmd+Ctrl+\` 后右侧出现候选,选"同一个 PDF"后两个 pane 独立页码 / 缩放且都 fit width
- [x] `UAT-49` 建立 A/B pair 后普通点击 C 显示单屏 C,再点击 A 或 B 恢复 A/B 分屏
- [x] `UAT-50` 已分屏时 `Option+Click` / `Option+Enter` 替换当前焦点 pane,垂直 tabs 与标题栏 tabs 行为一致
- [x] `UAT-51` `File > Share…` 可分享 Original / Clean Copy / Highlights,`File > Export Clean Copy…` 可导出保留链接与表单控件的干净副本,`Cmd+K` → `Cmd+E` 可触发 Share
- [x] `UAT-52` 拖动左右侧栏后切换 PDF 宽度不跳变;Settings General 修改左右默认宽度后会写入配置并更新窗口运行期宽度
- [ ] `UAT-53` 打开两个窗口,分别用 Window 菜单和垂直 / 标题栏 tab 拖拽移动 PDF;页码、缩放、dirty 批注与目标激活状态不丢失
- [ ] `UAT-54` 在 PDFView 已翻页但 store 尚未收到 page-change 的瞬间覆盖编译 PDF,热重载后仍停在实时页码;新文件页数缩短时落在最后有效页
- [ ] `UAT-55` 在 View 菜单切换左右 / 上下分屏,两个 pane 的 PDF、页码与焦点不变,关闭后重开沿用本次运行期方向
- [ ] `UAT-56` 从文档侧栏空白处拖动窗口;tab 点击 / 跨窗拖拽、关闭按钮、侧栏滚动与 divider 拖动均不受影响
- [ ] `UAT-57` 左侧物理 `Cmd+1/2/3` 激活前三个 tab;右侧物理 `Cmd+1/2/3/4` 切换四种阅读模式,左 `Cmd+4` 不触发显示模式
- [x] `UAT-58` 阅读区按 `F` 开关鼠标跟随聚焦,PDF 文本选择、链接、拖拽与滚动不受遮罩影响
- [x] `UAT-59` `Option+F` 实时调整当前窗口宽度与高度,关闭面板后继续跟随鼠标,Reset 恢复 Settings 默认值
- [x] `UAT-60` 双栏 PDF 选择 Column 后按鼠标落点聚焦左 / 右半页;Page 与 Custom 在页面边缘正确钳制
- [x] `UAT-61` 缩小聚焦宽度后四周遮罩连续无残留块;焦点区为轻圆角矩形,外围压暗与轻阴影在亮 / 暗主题下均不过度污染正文

已完成:`UAT-01` ~ `UAT-23`(详见 commit 历史)。

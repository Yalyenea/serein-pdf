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
- 默认高亮色:偏轻、低饱和、清晰的粉色
- `a`:有选区 → 立即高亮;无选区 → 进入高亮模式
- `Esc`:退出高亮模式 / 关闭 Find bar / 退出全览
- `d`:删除鼠标所在高亮;多行整组删除
- `i`:切换反色夜间模式
- `Ctrl+D` / `Ctrl+U`:半页下滚 / 上滚
- `g` / `G`:跳到文首 / 文末
- `Cmd+S`:写回源 PDF
- `Cmd+R`:在 Finder 中显示当前 PDF 所在位置
- 自动保存默认 `10 min`,至少支持 `10 min` / `never`
- 左侧 tabs 栏底部可选显示 recent PDFs 快捷入口(设置可开关)
- 水平 tab 复用标题栏,不单独开行
- 右栏支持 Outline / Pages / Search / Annotations,`Cmd+Shift+L` 仍在 Outline / Pages 间切换
- `Cmd+L` 进入 / 退出演示模式(直接全屏播放,页面完整适配,退出后恢复进入前布局)
- `Cmd+Ctrl+L` 进入 / 退出沉浸模式(隐藏侧栏与 tab chrome,只保留 PDF 页面)
- 左右可互换:`Cmd+Shift+X` 或设置窗口
- 保留标准 macOS app / window 快捷键,至少包括 `Cmd+H` / `Cmd+Option+H` / `Cmd+M`

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
| M8 批注深度化 | ✅ 开发完成,待手测 |
| M9 最近文件启动器 | ✅ 开发完成,待手测 |
| M10 阅读区 Framing 打磨 | ✅ 开发完成,待手测 |
| M11 扩展生态(预研) | 未开始 |

## 4. 下一步执行顺序

- Wave 0 M8 / M9 手测：完成 `UAT-29` ~ `UAT-33`，确认批注、快捷键页、最近文件启动器都符合预期。
- Wave 1 M10 手测：完成 `M10-021`，用真实 slide / paper PDF 验证居中与 fit width framing。
- Wave 2 M11 预研：做 `M11-001`，把扩展机制 RFC 先落出来。


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
- [x] `M7-011` 分屏 tab 切换落点:从左栏激活进焦点 Reader;`Option+Click` 丢到另一侧。
- [x] `M7-012` 分屏状态持久化:`PersistedDocumentStoreState` 持久化窗口 split 状态并恢复。
- [x] `M7-013` 新建窗口命令:`ShortcutCommand.newWindow`,默认 `Cmd+Shift+N`;`AppDelegate` 支持多 `MainWindowController`;`DocumentStore` 暴露多窗口接口。
- [x] `M7-014` 多窗口关闭协调:关闭一窗不影响其他;最后一窗关闭走 terminate;`Cmd+Shift+T` 优先本窗内重开。
- [x] `M7-015` 多窗口状态持久化:记录各窗口 session 集合 / active session / split / search / sidebar 布局。
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
- [ ] `M8-031` M8 验收:`AC-M8-1` ~ `AC-M8-4` 通过。

## 7. Milestone 9:最近文件启动器

- [x] `M9-001` Spotlight 风格面板:`Cmd+Shift+Space` 拉起最近文件启动器,默认在当前窗口中心显示。
- [x] `M9-002` 搜索与排序:基于 `recentDocumentURLs` 提供文件名/路径匹配,结果保持最近打开优先。
- [x] `M9-003` 键盘交互:`↑` / `↓` 选中,`Space` 切换多选,`Enter` 打开选中或当前项,`Esc` 关闭。
- [x] `M9-004` 操作提示:面板底部常驻显示键盘操作说明,不跳出到外部文档。
- [x] `M9-005` 测试:覆盖搜索过滤、多选打开、空列表与帮助切换。

## 8. Milestone 10:阅读区 Framing 打磨

### 8.1 单页居中与主窗口显示

- [x] `M10-001` 主窗口默认 framing:重新评估 `MainWindowController` 默认窗口尺寸与最小尺寸,兼顾纵向论文与横向 slide,避免首次打开时阅读区过矮或过窄。
- [x] `M10-002` 单页非连续居中:`singlePage` 模式下,当页面缩小后小于阅读区可视宽度时,页面应保持在中栏内水平居中,不贴左侧漂移。
- [x] `M10-003` 单页缩放体验:在 `singlePage` 模式连续缩小 / 放大时,页面中心与阅读焦点保持稳定,避免缩放后突然跳边或滚动偏移过大。

### 8.2 Fit Width / Fit Page 语义收口

- [x] `M10-010` `Cmd+0` 行为校准:当前 fit width 计算改为“刚好显示完整内容且不横向裁切”,对 slide / paper 都成立。
- [x] `M10-011` 宽页与窄页验证:针对 16:9 slide、常规 A4/Letter PDF、双页模式分别校准 scale 计算,避免某一类文档过大或过小。
- [x] `M10-012` 打开默认行为:若配置为 `fit_width_on_open = true`,新打开文档默认直接落在校准后的 framing,不需要手动再缩放一次。

### 8.3 测试与验收

- [x] `M10-020` 测试:补充 `ReaderViewController` / `WindowChromeTests`,覆盖单页居中、fit width scale 计算与主窗口默认 framing。
- [ ] `M10-021` 手测:使用 `~/Downloads` 里的真实 slide PDF 和常规论文 PDF 各验证一次,记录视觉差异与最终默认值。

## 9. Milestone 11:扩展生态(长期预研)

- [ ] `M11-001` 扩展机制 RFC:`docs/extensions-rfc.md` 列选型,至少比较进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳。
- [ ] `M11-002` PoC:若决策继续,选一条路径把"导出高亮"重写为插件,可在 app 中运行。
- [ ] `M11-003` Slate Extension API 草稿:面向未来扩展开发者。
- [ ] `M11-004` 若推迟,在 RFC 写清"为什么现在不做"(安全、上架、维护成本)。

## 10. 手测清单(尚未覆盖)

- [x] `UAT-24` `Cmd+F` 搜索后,右栏 Search 按页或按文档分组展示 snippet / 页码
- [x] `UAT-25` find bar 内 `↑` / `↓` / `Enter` 与 `Cmd+G` / `Cmd+Shift+G` 都能驱动右栏结果与跳转
- [x] `UAT-26` `This Document` / `All Open` 切换正确,跨文档命中会先切 session 再跳转
- [x] `UAT-27` `Cmd+Ctrl+\` 进入同窗分屏,两侧独立切换 session 不污染
- [x] `UAT-28` `Cmd+Shift+N` 新建窗口,两窗口独立且关闭互不影响,重启后恢复
- [x] `UAT-29` 右栏 Annotations 能列出所有高亮,点击跳转,并可编辑 / 清空评论
- [ ] `UAT-30` 导出 Markdown / Plain / JSON 输出正确,且评论字段随导出带出
- [ ] `UAT-31` Shortcuts 面板改绑定后新会话生效,冲突被拒,清除后写回 `none`
- [ ] `UAT-32` 最近文件启动器可搜索最近文件,支持 `Space` 多选与 `Enter` 打开
- [ ] `UAT-33` 最近文件启动器底部常驻显示操作提示,无查询和有查询时都可直接 `↓` 浏览结果
- [ ] `UAT-34` 单页非连续模式缩小后页面保持居中,slide PDF 不贴边
- [ ] `UAT-35` `Cmd+0` 或默认 fit width 后,页面刚好完整显示内容,无横向裁切
- [ ] `UAT-36` 扩展机制 RFC 存在并评审(M11 证据)

已完成:`UAT-01` ~ `UAT-23`(详见 commit 历史)。

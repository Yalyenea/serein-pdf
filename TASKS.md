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
- `Cmd+S`:写回源 PDF
- 自动保存默认 `10 min`,至少支持 `10 min` / `never`
- 水平 tab 复用标题栏,不单独开行
- 右栏支持 Outline / Pages,`Cmd+Shift+L` 切换
- 左右可互换:`Cmd+Shift+X` 或设置窗口

## 3. 当前进度

| 里程碑 | 状态 |
|---|---|
| M1 MVP 骨架 | ✅ |
| M2 阅读体验 | ✅ |
| M3 高亮批注 | ✅ |
| M4 夜间与打磨 | ✅ |
| M5 设置与收口 | 主体 ✅,`M5-032` 待收口 |
| M6 体验打磨 | 主体 ✅,`M6-023` / `M6-062` 待 |
| M7 搜索 + 对比 | 未开始 |
| M8 批注深度化 | 未开始 |
| M9 扩展生态(预研) | 未开始 |


## 5. Milestone 7:搜索强化与对比阅读

### 5.1 搜索结果面板

- [ ] `M7-005` 跨文档搜索(可选):find bar 顶部 toggle "This Document" / "All Open";跨文档结果带 session 名,点击先切 session 再跳转。
- [ ] 查找多页预览

### 5.2 同窗分屏 / 多窗口

- [ ] `M7-010` 同窗分屏容器:中栏拆水平双 Reader;`Cmd+Ctrl+\` 切换;各 Reader 独立 `displayedSessionID`。
- [ ] `M7-011` 分屏 tab 切换落点:从左栏激活进焦点 Reader;`Option+Click` 或专门命令丢到另一侧。
- [ ] `M7-012` 分屏状态持久化:`PersistedDocumentStoreState` 增加布局字段;重启恢复。
- [ ] `M7-013` 新建窗口命令:`ShortcutCommand.newWindow`,默认 `Cmd+Shift+N`;`AppDelegate` 支持多 `MainWindowController`;`DocumentStore` 单例暴露多窗口接口。
- [ ] `M7-014` 多窗口关闭协调:关闭一窗不影响其他;最后一窗关闭走 terminate;`Cmd+Shift+T` 优先本窗内重开。
- [ ] `M7-015` 多窗口状态持久化:记录各窗口 active session 与布局;可降级单窗口并明示。
- [ ] `M7-016` 测试:`DocumentStoreTests` 覆盖多窗口场景。

### 5.3 文档与验收

- [ ] `M7-020` 同步 `PROJECT.md` / `TASKS.md` / `config.toml` / `AGENTS.md`。
- [ ] `M7-021` M7 验收:`AC-M7-1` ~ `AC-M7-5` 通过。

## 6. Milestone 8:批注深度化

### 6.1 批注管理器

- [ ] `M8-001` 批注模型扩展:每 highlight 抽取 `snippet` / `pageIndex` / `color` / `createdAt`(PDF 可取则取,否则 session 内维护)。
- [ ] `M8-002` 右栏 Annotations 模式:顶部 segmented Outline / Annotations;列表按页分组,显示 snippet + 颜色点。
- [ ] `M8-003` 点击跳转并高亮:跳到目标页并短暂强调对应 annotation。
- [ ] `M8-004` dirty 变更同步:增删 highlight 实时更新列表。

### 6.2 导出

- [ ] `M8-010` 抽取导出内容:`[(page, snippet, color)]`,按页排序。
- [ ] `M8-011` 三种导出格式:Markdown / Plain / JSON;都覆盖 snippet、页码、颜色。
- [ ] `M8-012` 输出目标:`File > Export Highlights…`;`Cmd+Shift+E` 复制 Markdown 到剪贴板;"Save as…" 走 `NSSavePanel`。
- [ ] `M8-013` `HighlightExporterTests` 覆盖三种格式稳定。

### 6.3 自定义快捷键 UI

- [ ] `M8-020` Shortcuts 面板:设置窗口新增 tab;列出所有 `ShortcutCommand` + 当前绑定 + 默认值。
- [ ] `M8-021` key-capture 控件:捕获按键 → `KeyboardShortcut`;支持清除 / 恢复默认。
- [ ] `M8-022` 冲突检测:同组合冲突时拒绝或提示。
- [ ] `M8-023` 写回配置:保存时触发 `configStore.save` + `updateAppConfiguration`;菜单 `keyEquivalent` 立即刷新。
- [ ] `M8-024` 测试:`AppConfigurationTests` 覆盖 UI 输入 → `config.toml` → 重读闭环。

### 6.4 文档与验收

- [ ] `M8-030` 同步 `PROJECT.md` / `TASKS.md` / `config.toml` 默认内容。
- [ ] `M8-031` M8 验收:`AC-M8-1` ~ `AC-M8-4` 通过。

## 7. Milestone 9:扩展生态(长期预研)

- [ ] `M9-001` 扩展机制 RFC:`docs/extensions-rfc.md` 列选型,至少比较进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳。
- [ ] `M9-002` PoC:若决策继续,选一条路径把"导出高亮"重写为插件,可在 app 中运行。
- [ ] `M9-003` Slate Extension API 草稿:面向未来扩展开发者。
- [ ] `M9-004` 若推迟,在 RFC 写清"为什么现在不做"(安全、上架、维护成本)。

## 8. 手测清单(尚未覆盖)

- [ ] `UAT-24` `Cmd+Ctrl+\` 进入同窗分屏,两侧独立切换 session 不污染
- [ ] `UAT-25` `Cmd+Shift+N` 新建窗口,两窗口独立且关闭互不影响
- [ ] `UAT-26` 右栏 Annotations 能列出所有高亮,点击跳转
- [ ] `UAT-27` 导出 Markdown / Plain / JSON 输出正确
- [ ] `UAT-28` Shortcuts 面板改绑定后新会话生效,冲突被拒
- [ ] `UAT-29` 扩展机制 RFC 存在并评审(M9 证据)

已完成:`UAT-01` ~ `UAT-23`(详见 commit 历史)。

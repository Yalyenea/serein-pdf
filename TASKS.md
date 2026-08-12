# TASKS

[PROJECT.md](PROJECT.md) 的执行清单。  
**只跟踪未完成项。** 已完成里程碑细项与 UAT 历史见 [docs/archive/TASKS-completed-milestones-20260805.md](docs/archive/TASKS-completed-milestones-20260805.md)；产品常量与快捷键以 [PROJECT.md](PROJECT.md) 为准；债项权威见 [REVIEW.md](REVIEW.md)。

## 1. 执行规则

- 开启里程碑前确认依赖任务已完成。
- 每完成一个可见功能立即补最小验证。
- 状态管理落在 `DocumentStore` / `DocumentSession`,不散到视图层。
- 垂直 tab 与水平 titlebar tab 共享同一套命令与状态模型。
- UI 决策守"极简、扁平、紧凑",不增无必要控件。
- 产品常量 / 快捷键 / 语义边界不在此重复，改 [PROJECT.md](PROJECT.md)。

## 2. 进度一览

| 范围 | 状态 |
|---|---|
| M1–M10.x / M13 / M14 / M15 | ✅ 见 archive + CHANGELOG |
| M11 扩展生态（预研） | 未开始 |
| M12 Backlog 体验分流 | 进行中（空窗 010–014） |
| M13.1 网站后续完善 | 待办 |
| 多主题预设 | 规划中 · [docs/theme-presets-plan.md](docs/theme-presets-plan.md) |
| REVIEW 5.1 近期债 | ✅ |
| REVIEW 5.2 中期重构 | 进行中（S2 / S3 已部分拆分） |
| 阅读跳转 / CI 侧栏 layout | ✅（已合 main） |

## 3. 下一步勾选

权威债项细节见 [REVIEW.md](REVIEW.md)。本节只跟踪执行勾选。

### 3.1 中期重构（REVIEW 5.2）

- [ ] S1 拆 `AppDelegate`
- [ ] S3 继续拆 `ReaderViewController` 的 scale / viewport / overview（annotation interaction 已提取）
- [ ] S2 继续拆 `DocumentStore` 的 tab / annotation / persistence（search snapshot 与 P4 已收口）
- [ ] C1 根治：config schema 表驱动
- [ ] S4 palette 共享基类
- [ ] H1 本地化决策

### 3.2 产品候选（REVIEW 5.3）

- [ ] 下划线 / 删除线批注
- [ ] URL scheme PoC（对齐 M11）

### 3.3 里程碑待办

#### M11 扩展生态（预研）

- [ ] `M11-001` 扩展机制 RFC：`docs/extensions-rfc.md` 列选型（进程内 Swift 插件 / URL scheme / 外部 CLI / WebKit 壳）
- [ ] `M11-002` PoC：若决策继续，选一条路径把「导出高亮」重写为插件
- [ ] `M11-003` Serein Extension API 草稿
- [ ] `M11-004` 若推迟，在 RFC 写清「为什么现在不做」

#### M12 空窗体验收尾

- [ ] `M12-010` 空窗侧栏占比收口：无 session 时折叠侧栏或更窄默认宽度，引导集中中栏
- [ ] `M12-011` 右栏空窗 chrome 弱化：无文档时隐藏 / disable segmented 与 Outline 操作
- [ ] `M12-012` 左栏空态层次：`Documents` section 标题；空态上移 Recent 或中栏同步入口
- [ ] `M12-013` 空态视觉语言统一：共享 empty state 组件
- [ ] `M12-014` 侧栏顶部留白校准：空态垂直居中或收紧 titlebar 留白

#### M12 暂缓（有触发条件再开）

- [ ] `M12-D002` Pages 缩略图滑动渲染：仅当大 PDF 可复现卡顿 / 白屏 / 错序后再做
- [ ] `M12-D003` Zed / VS Code / LaTeX / Typst SyncTeX：先 RFC
- [ ] `M12-D004` 双屏同步滚动：分屏 / comparison 手测稳定后再做
- [ ] `M12-D005` Finder 外部 rename 自动跟路径

#### M13.1 网站后续

- [ ] `M13.1-001` 实机截图替换占位卡
- [ ] `M13.1-002` 截图规范 + 导出到 `Website/assets/screens/`
- [ ] `M13.1-003` 下载区接正式 release 产物说明
- [ ] `M13.1-004` 可选：GitHub Pages / 自定义域名 + `just` 发布
- [ ] `M13.1-005` 可选：暗色 / Rose Pine 主题截图
- [ ] `M13.1-006` EN/中文文案终稿与 README 对齐

#### 多主题预设

- [ ] 按 [docs/theme-presets-plan.md](docs/theme-presets-plan.md) 开工（注册表式 curated 预设，不破坏 Mode + Light/Dark Theme 模型）

### 3.4 手测未覆盖

- [ ] `UAT-36` 扩展机制 RFC 存在并评审（M11）
- [ ] `UAT-53` 两窗：Window 菜单 + 垂直 / 标题栏 tab 拖拽移 PDF；页码 / 缩放 / dirty / 激活不丢
- [ ] `UAT-54` 热重载：PDFView 已翻页、store 尚未 page-change 时覆盖编译，仍停实时页；新文件页数缩短落末页
- [ ] `UAT-55` 左右 / 上下分屏切换：PDF、页码、焦点不变；重开沿用运行期方向
- [ ] `UAT-56` 文档侧栏空白拖窗；tab / 跨窗拖拽 / close / scroll / divider 不受影响
- [ ] `UAT-57` 左物理 `Cmd+1/2/3` 前三 tab；右物理 `Cmd+1/2/3/4` 四种阅读模式

## 4. 归档索引

| 文档 | 内容 |
|---|---|
| [docs/archive/TASKS-completed-milestones-20260805.md](docs/archive/TASKS-completed-milestones-20260805.md) | M7–M15 完成细项、已通过 UAT、产品常量旧副本 |
| [docs/archive/REVIEW-full-20260610.md](docs/archive/REVIEW-full-20260610.md) | 完整评审（亮点 + 已完成 5.1） |
| [CHANGELOG.md](CHANGELOG.md) | 用户可见变更史 |
| git history | 实现细节的权威来源 |

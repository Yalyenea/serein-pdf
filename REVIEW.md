# Serein 工程债与改进路线

> 活文档：只保留**未完成**短板与路线。  
> 完整评审原文（产品/实现亮点、§5.1 完成记录、规模快照）见 [docs/archive/REVIEW-full-20260610.md](docs/archive/REVIEW-full-20260610.md)。  
> 执行勾选同步 [TASKS.md](TASKS.md)。

**状态：** `✅` 已实现 · `◐` 部分缓解 · `[ ]` 未实现

## 1. 已收口（摘要）

| 批次 | 状态 | 说明 |
|---|---|---|
| §5.1 近期债（2026-07-10） | ✅ | C1/C2/C3/C5/C6、P1 部分、P2、P5；分支 `fix/review-near-term-A-20260710` |
| 导航历史 / 阅读位边界（2026-08） | ✅ | pane-local `sessionID + ReadingPosition`；大纲/搜索/内链显式入栈；滚动与顺序翻页不灌栈 |
| CI 侧栏 layout | ✅ | preferred widths 不被程序化 toggle 写坏 |
| 搜索快照 / 主题并发 / OCR 移除（2026-08） | ✅ | 窗口级只读 `SearchSnapshot`；主题选择收进 `@MainActor ThemeManager`；扫描件不再走 OCR |

细项与实现笔记见 archive 与 CHANGELOG。

## 2. 开放短板

### 2.1 结构

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| S1 | [ ] | `AppDelegate` god object：菜单、share/export、open-URL、palette、config、`validateMenuItem` | `App/AppDelegate.swift` | 全局行为改动回归面大 |
| S2 | ◐ | `DocumentStore` 仍承载 tab / split / annotation / undo / persistence；搜索已改窗口级显式快照 | `Core/DocumentStore.swift` | 非搜索职责的演进成本仍高 |
| S3 | ◐ | 批注交互已提取；缩放 / viewport / overview 仍是隐式状态机 | `UI/CenterReader/ReaderViewController.swift` | 剩余几何逻辑易回归、难单测 |
| S4 | [ ] | 三个 palette 近乎复制粘贴，无共享基类 | `App/*PaletteController.swift` | 键处理改动要同步三处 |

### 2.2 性能

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| P1 | ◐ | workspace 一般 content 变更仍全量 JSON 写（LRU/debounce/readingPosition 跳过已做） | `DocumentStore` / `ReadingStateStore` | 多 tab 频繁内容变更时写放大 |

### 2.3 正确性 / 工程

| # | 状态 | 问题 | 位置 | 影响 |
|---|---|---|---|---|
| C1 | ◐ | config 多清单曾漂移；一致性测 + self-heal 已做，**根治**仍需表驱动 | `AppConfiguration` | 新快捷键仍可能漏 key |
| H1 | [ ] | UI 字符串中英混杂、硬编码 | 多处 | 本地化需全量翻找 |
| H2 | [ ] | `controller(for:)` / 菜单状态每次 store 变更线性扫描 | `AppDelegate` | 规模小时可接受 |

## 3. 改进路线（开放项）

### 3.1 中期重构（功能冻结窗口更合适）

- [ ] **S1** 拆 `AppDelegate` → `MenuBuilder` / `ShareCoordinator` / `OpenURLCoordinator` / `PaletteCoordinator`
- [ ] **S3** 继续拆 `ReaderViewController` → scale / viewport / overview；批注交互已提取
- [ ] **S2** 继续拆 `DocumentStore` 的 tab / annotation / persistence；搜索已是显式窗口快照
- [ ] **C1 根治** config schema 表驱动：单一 spec 生成 parser / render / defaults / requiredKeys
- [ ] **S4** `PaletteWindowController` 共享 panel 与键处理
- [ ] **H1** 统一英文或引入 String Catalog
- [ ] **P1 余量** 一般 content 的 workspace 写合并 / 节流

### 3.2 产品候选（增量小、复用现有管线）

- [ ] 下划线 / 删除线批注（复用 group / undo / export）
- [ ] URL scheme `serein://open?file=…&page=N`（对齐 M11）

### 3.3 承接里程碑

- [ ] **M11** 扩展生态预研 + 最小 PoC
- [ ] **M12-010~014** 空窗体验收尾
- [ ] **多主题预设** [docs/theme-presets-plan.md](docs/theme-presets-plan.md)

## 4. 阅读指引

| 需求 | 去哪 |
|---|---|
| 产品原则 / 快捷键 / 数据模型 | [PROJECT.md](PROJECT.md) |
| 勾选执行 | [TASKS.md](TASKS.md) |
| 为什么某设计存在（亮点笔记） | [docs/archive/REVIEW-full-20260610.md](docs/archive/REVIEW-full-20260610.md) |
| 用户可见变更 | [CHANGELOG.md](CHANGELOG.md) |

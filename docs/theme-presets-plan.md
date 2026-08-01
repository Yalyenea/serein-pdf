# 多主题预设计划（Theme Presets Plan）

> 状态：**规划中**（未开工）  
> 范围：Serein 原生 PDF 阅读器的外观主题扩展  
> 对照：Rosewash 扩展已落地的 Codex 对齐预设体系  
> 相关代码：`Features/Theme/`、`Core/AppConfiguration.swift`、`Features/Annotations/HighlightColor.swift`、`App/SettingsWindowController.swift`

---

## 1. 目标

在**不破坏**现有 `Mode + Light Theme + Dark Theme` 产品模型的前提下，把主题从「Normal + Rose Pine 两套硬编码」扩展为**可注册、可批量增加**的 curated 预设表，覆盖常见编辑器/终端主题家族（与 Rosewash / Codex 桌面端同类名单对齐，可分批引入）。

### 1.1 成功标准

| 标准 | 说明 |
| --- | --- |
| 行为兼容 | 默认仍为 `system + normal + rose_pine_moon`；旧 `config.toml` 可读 |
| 扩展方式 | 新增主题 = 注册表加一项（tokens + 策略），**不**在 `process`/UI 里再开 `switch` 分叉 |
| PDF 观感 | Light：白纸映射为主题纸色并尽量保留原文档彩色；Dark：纸面/正文端点重映射，彩图色相可辨 |
| 壳层一致 | 侧栏 / 分割 / 选中 / 描边与 PDF 纸面同一家族 |
| 高亮可读 | 粉 / 黄 / 绿在各主题下低饱和、可辨、不过刺眼 |
| 快捷键 | `i` 仍切 mode；`Cmd+K` `Cmd+T` 在**当前 mode 侧**的主题列表中循环（不再写死二值 `toggled`） |

### 1.2 非目标（本计划不做）

- 用户自定义任意 hex 主题编辑器
- 按 PDF / 窗口绑定不同主题
- 导入社区 `.tmTheme` / VS Code theme JSON 的通用解析器
- 网站 `Website/` 的主题体系（独立静态页，另议）
- 与 Rosewash 实时同步配置文件

---

## 2. 现状摘要

### 2.1 产品配置

```toml
[appearance]
mode = "system"                 # system | light | dark
light_theme = "normal"          # 当前: normal | rose_pine_dawn
dark_theme = "rose_pine_moon"   # 当前: normal | rose_pine_moon
```

- Light / Dark 主题**独立记忆**（可混搭，例如 Normal 亮 + Moon 暗）。
- Settings General：`Mode` / `Light Theme` / `Dark Theme` 三个 `NSPopUpButton`，由 `CaseIterable` 填充。
- `i`：切 light/dark mode，不改两侧已选 theme。
- `Cmd+K` → `Cmd+T`：调用当前侧 theme 的 `.toggled`（**仅在两个 case 间互切**）。

### 2.2 代码结构

| 位置 | 职责 |
| --- | --- |
| `Core/AppConfiguration.swift` | `AppearanceMode`、`LightTheme`、`DarkTheme` 枚举与 TOML 读写 |
| `Features/Theme/NightModeStyle.swift` | 真正的主题引擎：`ThemeDescriptor`、`PDFStyle`、CIColorMatrix、dynamic colors |
| `Features/Theme/ThemeManager.swift` | 薄包装（阅读状态相关） |
| `Features/Annotations/HighlightColor.swift` | `HighlightPalette` × 粉黄绿 手写 sRGB |
| `App/SettingsWindowController.swift` | 主题 popup UI |
| `App/AppDelegate.swift` | `switchCurrentTheme`、菜单 |

### 2.3 `ThemeDescriptor` 字段（每主题必须齐）

```text
pageBackground / pageForeground
primaryText / secondaryText / tertiaryText
readerBackdrop / splitBackground / paneBackground
chromeDivider / selectedChromeBackground / chromeStroke
usesOpaqueSidebar / prefersFlatPDFChrome
highlightPalette
pdfStyle
```

### 2.4 `PDFStyle` 策略（PDF 滤镜路径）

| 策略 | 用途 | 典型主题 |
| --- | --- | --- |
| `.none` | 不滤镜 | Light `Normal` |
| `.classicInvert` | 经典反色（历史路径） | 视需要 |
| `.paper(background)` | 只替白纸，保留正文/彩图色 | Rose Pine Dawn |
| `.darkPaper(bg, fg, accentPreservation)` | 暗纸端点映射 | Rose Pine Moon |
| `.remap(bg, fg, accentPreservation, backgroundLuminance)` | 更通用的亮度轴重映射 | Dark `Normal` |

**结论：** 多主题的难点不在菜单，而在为每个 variant 选对 `PDFStyle` 并调好端点色与 `accentPreservation`。

### 2.5 与 Rosewash 的对比

| | Rosewash（浏览器页） | Serein（本项目） |
| --- | --- | --- |
| 覆盖面 | DOM 表面 + 文本 + 边框 | PDF 像素滤镜 + AppKit 壳 |
| 最小 token | 6 色（base/surface/overlay/muted/text/link） | 6 色 **不够直接**，需映射到完整 `ThemeDescriptor` |
| 扩展成本 | 注册表加 hex | 注册表 + PDF 策略 + 高亮 + 回归 PDF |
| 已有拆分 | `preset + appearance` | **已有** `mode + light_theme + dark_theme`（更贴近产品） |
| 难易 | 高易 | **中等** |

---

## 3. 目标架构

### 3.1 统一注册表

将 `LightTheme` / `DarkTheme` 的「手写 enum case + 巨型 switch」收敛为：

```text
ThemeRegistry
  └── ThemeFamily (id, label)
        ├── light: ThemeVariant?   // tokens + pdf policy + optional chrome overrides
        └── dark:  ThemeVariant?
```

配置层仍可保留两个「当前选择」字段（兼容现有语义）：

```toml
[appearance]
mode = "system"
light_theme = "catppuccin"      # family id；解析为该 family 的 light variant
dark_theme = "tokyo-night"      # family id；解析为该 family 的 dark variant
```

或更显式（可选，二期）：

```toml
light_theme = "catppuccin-latte"
dark_theme = "tokyo-night"
```

**推荐一期：** family id + 自动取 light/dark 子 variant（与 Rosewash `preset` 类似）；`normal` 作为特殊 family，仅含系统风格 light/dark。

### 3.2 最小 Token 集（与 Rosewash 可对齐）

每个 **variant** 至少声明：

| Token | 用途 |
| --- | --- |
| `base` | 侧栏 / reader 外缘最深（或最浅）底 |
| `surface` | PDF 纸面、主阅读面 |
| `overlay` | 分割线、选中块、略抬升面 |
| `muted` | 三级文字、弱描边 |
| `subtle` | 二级文字（可与 muted 合并推导，建议保留） |
| `text` | 主文字 / PDF 暗端（dark）或正文色（chrome） |
| `link` | 强调 / 链接感（高亮与选中可参考） |

Rosewash / Codex 已有的 6 色表可直接作为 `base/surface/overlay/muted/text/link` 来源；`subtle` 可用 `text` 与 `muted` 插值。

### 3.3 Token → `ThemeDescriptor` 推导规则（默认）

**Light curated（非 Normal）：**

| Descriptor 字段 | 推导 |
| --- | --- |
| pageBackground | `surface` |
| pageForeground | `text` |
| primaryText | `text` |
| secondaryText | `subtle` 或 `muted` 偏深 |
| tertiaryText | `muted` |
| readerBackdrop / split / pane | `base` |
| chromeDivider | `overlay` 或略深 UI 色 |
| selectedChromeBackground | `overlay` @ 0.4–0.6 alpha 或实色 overlay |
| chromeStroke | 介于 overlay 与 muted |
| usesOpaqueSidebar | `true` |
| prefersFlatPDFChrome | `true` |
| pdfStyle | `.paper(background: surface)` |

**Dark curated（非 Normal）：**

| Descriptor 字段 | 推导 |
| --- | --- |
| pageBackground | `surface` |
| pageForeground | `text` |
| 壳层底 | `base` |
| chromeDivider / selected | `overlay` |
| chromeStroke | `muted` |
| usesOpaqueSidebar | `true` |
| prefersFlatPDFChrome | `true` |
| pdfStyle | `.darkPaper(bg: surface, fg: text, accentPreservation: 0.75–0.90)` 或 `.remap(...)`（按观感二选一，默认 darkPaper） |

**Normal：** 保持现有手写 descriptor（系统 label 色、light `.none`、dark `.remap`），不走 token 推导。

允许 variant 级 **optional override**（仅当推导不达标时手写个别字段），避免每个主题整份 descriptor 拷贝。

### 3.4 高亮策略

现状：`HighlightPalette` 对每个主题 `switch` 三色 —— 主题数 × 3 会失控。

**目标：**

1. **默认公式**（由 token 生成粉/黄/绿）：固定 hue 族 + 按 theme 的 surface/text 调整亮度与 alpha（暗色 alpha 更低）。
2. **可选 override 表**：仅 Rose Pine / 极少数主题保留手调值（迁移现有 sRGB）。
3. 重开 PDF 时的「语义色最近邻」逻辑（`HighlightColor` 已有跨调色板分类）继续使用，并随 palette 列表扩展测试。

### 3.5 快捷键与循环

- 删除 `LightTheme.toggled` / `DarkTheme.toggled` 的二值语义。
- `switchCurrentTheme`：
  - 若当前为 light appearance → 在 **具有 light variant** 的 family 列表中取下一 id；
  - 若当前为 dark → 在 **具有 dark variant** 的列表中循环。
- 列表顺序：`normal` 固定首位，其余按 label 字母序（或显式 `order` 字段）。

### 3.6 UI

**一期（最小）：** 保持 Settings 两个 popup；`allCases` / registry 自动灌项即可。

**二期（可选）：** 与 Rosewash Settings 类似，Light / Dark 各用卡片网格（色板 swatch + 名称）点选；仍保持极简扁平。

---

## 4. 建议预设清单（分批）

名单对齐常见 Codex / 编辑器主题；**不必一次上齐**。每批都要过真实 PDF 抽检。

### 4.1 第 0 批（行为冻结 / 重构）

| Family | Light | Dark | 备注 |
| --- | --- | --- | --- |
| `normal` | ✓ | ✓ | 现网默认 light 侧 |
| `rose-pine` | Dawn | Moon | 现网默认 dark 侧；token 与现常量一致 |

验收：重构后像素级行为与现版一致（配置默认值不变）。

### 4.2 第 1 批（验证 registry 路径，~5 family）

| Family | Light | Dark | 重点验证 |
| --- | --- | --- | --- |
| `catppuccin` | Latte | Mocha | 冷灰纸 vs 暖 Dawn |
| `solarized` | Light | Dark | 经典学术 PDF |
| `gruvbox` | Light | Dark | 暖纸 dark remap |
| `nord` | — | Polar Night | 仅 dark |
| `one` | Light | Dark | 中性灰 |

### 4.3 第 2 批（扩展常见套）

`tokyo-night`（dark）、`dracula`（dark）、`github`（light/dark）、`everforest`、`monokai`（dark）、`night-owl`（dark）、`material`（dark）…

### 4.4 第 3 批（可选 / 品牌向）

`linear`、`raycast`、`vercel`、`notion`、`xcode`、`vscode-plus`、`ayu`、`matrix`…  
仅在 1–2 批稳定后考虑；品牌主题可只做 dark 或只做 light。

Token 源可参考 Rosewash `PRESETS` 与 Codex app 内置 code theme 的 surface/ink 色，但 **Serein 必须单独过 PDF 矩阵**，不能假设 hex 相同即观感相同。

---

## 5. 实施阶段

### Phase A — Registry 骨架（不增加用户可见主题）

1. 新增 `ThemeRegistry` / `ThemeFamily` / `ThemeVariant`（建议 `Features/Theme/ThemeRegistry.swift`）。
2. 将现有 Dawn/Moon RGB 常量与 Normal 描述迁入 registry；`NightModeStyle` 只读 registry。
3. `LightTheme` / `DarkTheme`：
   - **方案 A1（推荐短期）：** 枚举 case 仍存在，但 `descriptor` 查表；
   - **方案 A2（干净）：** 配置改为 `String` id + 校验，enum 仅作已知 id 的 typed wrapper。
4. 测试：现有 `NightModeStyleTests` / `AppConfigurationTests` / 窗口主题刷新测试全绿；默认配置字符串不变。

**预估：** 0.5–1 人日。

### Phase B — 推导器 + 高亮公式

1. 实现 `ThemeVariant.tokens → ThemeDescriptor` 默认推导。
2. 高亮默认公式 + Rose Pine override 迁入。
3. 单测：token 快照、矩阵在 CPU 路径上的端点映射（白→surface、黑→text）与现 Dawn/Moon 对齐。

**预估：** 0.5–1 人日。

### Phase C — 第 1 批主题 + 循环快捷键

1. 注册 4.2 各 family 的 light/dark tokens（可从 Rosewash 拷 hex，再微调）。
2. Settings popup 自动列出；`switchCurrentTheme` 列表循环。
3. `config.toml` 读写接受新 id；未知 id → 回退 `normal` / 默认 dark（**明确策略，不做静默乱猜**；产品规则禁止冗长兼容层，但非法配置回退到 default 是必要校验）。
4. 真机 PDF 清单抽检（见 §6）。

**预估：** 1.5–3 人日（含调色）。

### Phase D — 扩表与 UI 抛光（可选）

1. 第 2 批主题。
2. Settings 卡片网格（若 popup 过长）。
3. CHANGELOG / README / TASKS 同步；可选 Website 截图。

**预估：** 每增一批 1–2 人日。

---

## 6. 验证计划

### 6.1 自动化

| 测试 | 断言 |
| --- | --- |
| `AppConfiguration` 解析 | 新旧 id 往返；非法 id 错误或回退策略符合文档 |
| `NightModeStyle` / 矩阵 | 白/黑端点映射到 surface/text；Dawn/Moon 回归基准 |
| `HighlightColor` 分类 | 各 palette 写入后再识别为 pink/yellow/green |
| 快捷键 | `switchCurrentTheme` 在 ≥3 主题时循环顺序正确 |

### 6.2 手工 PDF（优先 `~/Downloads` 真实文件）

每个 **新 dark variant** 至少：

- 白底学术 PDF（正文黑字 + 蓝链）
- 含彩图 / 代码高亮截图的 PDF
- 已有粉/黄/绿高亮的标注文档（主题切换后语义色仍正确）

每个 **新 light variant** 至少：

- 纯白纸论文：纸面色正确、正文不被强行染色（paper 策略）
- 侧栏与纸面层次可分

### 6.3 回归清单（每次合入）

- [ ] 默认启动外观与现版一致  
- [ ] `i` 切换 mode 保留两侧选择  
- [ ] `Cmd+K` `Cmd+T` 只动当前侧  
- [ ] Settings 改主题即时刷新已开 PDF  
- [ ] 分屏双 reader 同步主题  
- [ ] 不透明侧栏主题下原生 material 不「透出系统灰」  

---

## 7. 主要改动文件地图

| 文件 | 改动 |
| --- | --- |
| `Features/Theme/ThemeRegistry.swift` | **新建** 注册表与 token 定义 |
| `Features/Theme/NightModeStyle.swift` | 去掉巨型 switch；查表 + 推导；保留滤镜数学 |
| `Features/Theme/ThemeManager.swift` | 若需，转发 registry 列表 |
| `Features/Annotations/HighlightColor.swift` | palette 公式化 / override 表 |
| `Core/AppConfiguration.swift` | theme id 集合、序列化、校验 |
| `App/SettingsWindowController.swift` | 列表数据源改 registry |
| `App/AppDelegate.swift` | `switchCurrentTheme` 循环 |
| `Tests/SereinTests/*` | 配置 + 主题 + 高亮 + 快捷键 |
| `README.md` / `CHANGELOG.md` / `TASKS.md` | 用户可见说明与任务勾选 |

临时色板对照、截图放入 `.tmp/`，不进发布产物。

---

## 8. 风险与对策

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| 推导 chrome 层次扁平 | 侧栏与纸面糊成一块 | variant override；暗色 base 必须深于 surface |
| `accentPreservation` 不当 | 彩图发灰或荧光 | 分 light paper / darkPaper 默认值；第 1 批逐主题微调 |
| 高亮公式偏色 | 打印/投影难看 | Rose Pine 级手调作黄金样本；公式跟 surface 亮度挂钩 |
| 主题过多菜单难扫 | 设置页变长 | Phase D 网格；或分组（Default / Popular / Dark-only） |
| 配置 id 变更 | 用户 toml 失效 | 保留 `rose_pine_dawn` / `rose_pine_moon` 字符串；新 id 稳定 kebab-case |
| 并发：`nonisolated(unsafe)` 静态主题 | 数据竞争 | 与 REVIEW C4 一并：收进 `@MainActor` Theme 状态（可并行里程碑） |

---

## 9. 工作量总览

| 范围 | 难度 | 量级 |
| --- | --- | --- |
| Phase A 仅 registry 重构 | ★★ | 0.5–1 日 |
| Phase B 推导 + 高亮 | ★★ | 0.5–1 日 |
| Phase C 第 1 批 + 快捷键 | ★★☆ | 1.5–3 日 |
| 扩到 ~15–25 family | ★★★ | 累计约 3–6 日（含 PDF 调校） |
| 自定义主题编辑器 | ★★★★ | 不在本计划 |

**总评：** 可行性高；容易性中等。比 Rosewash「加 hex 即用」重，但现有 `Mode / Light / Dark` 与 `ThemeDescriptor` 已铺好路。关键路径是 **Registry + Token 推导 + 分批 PDF 验收**，而不是一次性枚举 28 个完整手写 descriptor。

---

## 10. 建议的首个 PR 切片

1. **PR1：** Phase A — registry + Dawn/Moon/Normal 迁入，无新主题，测试全绿。  
2. **PR2：** Phase B — 推导器与高亮公式，行为仍对齐。  
3. **PR3：** 仅加入 `catppuccin` light/dark + 循环快捷键，验证扩展路径。  
4. 其后每个 PR 加 2–4 个 family，附手工 PDF 检查记录（可写在 PR 描述或 `.tmp/theme-qa/`）。

---

## 11. 参考

- 本仓库：`Features/Theme/NightModeStyle.swift`、`Core/AppConfiguration.swift`  
- 架构评审：`REVIEW.md`（主题并发 C4、ThemeManager 贫血 S5）  
- Rosewash：`src/content/core.js` 中 `PRESETS` 与 `preset + appearance` 设置模型  
- Codex 桌面：内置 code theme id 列表（Ayu、Catppuccin、Dracula、Everforest、GitHub、Gruvbox、Nord、One、Solarized、Tokyo Night…）

---

## 12. 决策记录（待开工时勾选）

- [ ] 配置 id 用 **family**（`catppuccin`）还是 **variant**（`catppuccin-mocha`）  
- [ ] 非法 theme id：硬错误 vs 回退 default  
- [ ] Dark 默认 `pdfStyle`：统一 `darkPaper` 还是允许 per-theme `remap`  
- [ ] Settings UI：一期 popup 是否足够  
- [ ] 是否与 Rosewash 维护「共享 token JSON」（可选工具链，非运行时依赖）

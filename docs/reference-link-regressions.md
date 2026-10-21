# 引用预览与跳转回归记录

相同的“双栏预览”或“跳回第一页”现象，可能来自链接坐标、栏识别或滚动定位。排查时先确认失败发生在哪一层，再与已有修复对比。

## 历次修复

| 修复 | 触发条件 | 处理位置 | 本次暴露的覆盖缺口 |
|---|---|---|---|
| `5df6fd2`：目标栏预览 | 链接有明确坐标，页面为双栏 | `ReferencePreviewColumnLayout`、预览控制器 | 未指定坐标会跳过栏识别；合成测试提供了有效坐标 |
| `d2edb89`：公式与错行双栏 | 两栏基线不齐，公式、上下标与编号稀疏 | `ReferencePreviewColumnLayout` | 短行产生的候选空白可能比真实栏间空白更宽，右栏编号因此被排除 |
| `48d5ec4`：目录跳转 | 目录目标使用 `kPDFDestinationUnspecifiedValue` | `OutlineExtractor.readingPosition` | 正文内链和分屏直接使用 `destination.point`，没有经过目录的坐标处理 |
| 2026-10-21：整页文献链接 | 文献链接仅指向整页，正文引用编号可识别 | `ReferenceLinkDestination`、两处链接入口、栏布局 | 补充编号定位、导航坐标处理、短行栏界和末页单栏验证 |

上次目录修复没有覆盖正文内链入口，这是相同坐标问题再次出现的原因。双栏预览还依赖有效的目标坐标；仅改栏检测无法解决整页文献链接。

查看旧实现与当前实现：

```sh
git show 48d5ec4 -- Core/OutlineExtractor.swift
git diff d2edb89 HEAD -- UI/CenterReader/ReferencePreviewColumnLayout.swift
git log -p -- UI/CenterReader/ReferenceLinkDestination.swift
```

## 2026-10-21 样本

- 文件：`1687-6180-2014-120.pdf`，17 页。
- SHA-256：`8228e823bf40deadeaa86d2ad3571c44e56adbc230a0dfc4c98f7bba6434bd92`。
- 文献链接使用命名目标，如 `link_CR1`、`link_CR9`；指向第 16 页的这些目标均为整页 `/FitR`：`[page /FitR 0 794 596 0]`。
- PDFKit 返回的 x、y 均为 `kPDFDestinationUnspecifiedValue`。该值有限，单独检查 `isFinite` 不能发现它。
- 第 16 页为双栏，编号悬挂在条目正文左侧；第 17 页只有左侧文献正文，页眉和远处广告会扩大整页文字范围。

## 当前处理范围

1. 显式目标坐标直接保留。两个坐标均未指定时，检查源链接是否位于 `[1]`、`[1,2]`、`[3-7]` 等方括号引用中。
2. 只在链接指定的目标页查找 `1.` 或 `[1]` 形式的条目。编号必须唯一，且至少三个不同编号的左边缘对齐；匹配失败时保留原目标页。
3. 正文与预览内链接共用编号定位。当前阅读区导航和分屏将未指定轴解析为目标页边缘，避免把特殊值转换成滚动坐标。
4. 用支持双栏的多行文字收紧候选栏间空白，保留悬挂编号。局部只剩一栏时，按该栏正文适配；目标处的跨栏标题保持完整。

非方括号引用、重复编号、无文本层和仅有页码的普通链接不做条目推断。目录入口仍由 `OutlineExtractor` 处理；修改坐标语义时应同时核对两处。

## 回归覆盖

| 层次 | 自动化覆盖 |
|---|---|
| 编号定位 | 合成 PDF 验证左右栏、成组引用、显式坐标保留、无方括号和重复编号拒绝推断 |
| 栏几何 | 双栏、窄栏间距、错行、公式、悬挂编号、末页单栏、跨栏标题、偏移页面框 |
| 导航坐标 | 两轴未指定、单轴未指定、偏移裁切框 |
| 真实样本 | 73 个引用链接的单栏缩放与目标可见性；首个引用的完整阅读器 ⌘+点击、返回历史；整页链接停在第 16 页 |

真实样本测试由环境变量启用，默认测试会跳过这一项。合成测试随代码保存；样本 PDF 留在本机。未提供样本时，不能把测试通过表述为已复测该 PDF。

```sh
SEREIN_REFERENCE_TEST_PDF="$HOME/Downloads/1687-6180-2014-120.pdf" \
swift test --build-system native --disable-sandbox --no-parallel \
  --disable-swift-testing \
  --filter 'Reference(LinkDestination|Preview)|NavigationHistoryTests'
```

后续出现类似问题时，记录文件校验值、源链接文字、原始目标类型、目标页与坐标，再验证普通点击、⌘+点击、分屏和返回历史。新增样本应注明它补充了哪一种触发条件，并将可复现的几何或状态条件加入合成测试。

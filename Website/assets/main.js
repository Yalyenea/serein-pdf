/* ============================================================
 * Theme · language · scroll reveal · path copy
 * ============================================================ */
(function () {
  const THEME_KEY = "serein-site-theme";
  const LANG_KEY = "serein-site-lang";

  const strings = {
    en: {
      "hero.badge": "Serein · macOS PDF Reader",
      "hero.title": "Read papers with<br>calm <em>focus</em>",
      "hero.sub":
        "A native PDF reader for research — tabs, outline, highlights, and a keyboard flow that stays out of the way.",
      "hero.note": "Swift · AppKit · PDFKit",
      "hero.shotAlt":
        "Serein reader window with vertical tabs, PDF pages, and right sidebar",

      "layout.kicker": "Three-pane layout",
      "layout.title": "Three panes, one job each",
      "layout.desc":
        "Left tabs answer what is open. Center stays for reading. Right holds outline, pages, search, and annotations — quiet even when the workflow is dense.",

      "tabs.kicker": "Tabs that adapt",
      "tabs.title": "Vertical rail or titlebar strip",
      "tabs.desc":
        "Switch between a left tab rail and macOS titlebar tabs without changing the document model. Same sessions, same shortcuts, different chrome.",
      "tabs.card": "verticalSidebar · horizontalTitlebar",

      "note.kicker": "Pink-first highlights",
      "note.title": "Keep thinking on the page",
      "note.desc":
        "Press A to highlight a selection or enter highlight mode. Add comments in the right sidebar, undo up to 50 steps, export Markdown grouped by page.",
      "note.card": "pink · yellow · green · comments · Markdown",

      "search.kicker": "Search that stays aside",
      "search.title": "Results never crowd the page",
      "search.desc":
        "Find in this document or across every open PDF. The find bar stays thin; previews and hit lists live in the right pane so reading space stays clean.",
      "search.card": "This Document · All Open",

      "split.kicker": "Compare split",
      "split.title": "Two views, one screen",
      "split.desc":
        "Open a second reader for the same PDF or another tab, then arrange the pair side by side or stacked. Each pane keeps its own page and zoom.",
      "split.card": "side by side · stacked · independent state",

      "flow.kicker": "Continuous reading",
      "flow.title": "Many PDFs, one ordered flow",
      "flow.desc":
        "Group selected tabs into a continuous reading set. Page turns cross document boundaries; the outline lists every PDF together without stitching a fake file.",
      "flow.card": "tab context menu · ordered groups",

      "reload.kicker": "Hot reload",
      "reload.title": "Recompile without reopening",
      "reload.desc":
        "When LaTeX, Typst, or another toolchain rewrites an open clean PDF, Serein reloads it in place and returns to the live page. Sessions with unsaved annotations stay untouched.",
      "reload.card": "LaTeX · Typst · keep your page",

      "keys.kicker": "Keyboard-first",
      "keys.title": "Built for hands on the home row",
      "keys.desc":
        "Vim-style page turns, half-page scroll, jump to edges, find, overview, and immersive chrome — all configurable in Settings, none of them shouting for attention.",
      "keys.card": "config.toml · capture · conflict-aware",

      "overview.kicker": "Overview grid",
      "overview.title": "Every page at a glance",
      "overview.desc":
        "A seamless page grid that shares the reader surface — no nested panels. Zoom for denser tiles, click a page to jump and exit.",
      "overview.card": "viewport-fit · click to jump",

      "details.title": "And the quiet details",
      "d.theme.title": "Rose Pine themes",
      "d.theme.desc":
        "Mode plus light and dark themes. Rose Pine Dawn warms the page itself; Rose Pine Moon keeps margins with the dark surface.",
      "d.library.title": "PDF Library",
      "d.library.desc":
        "Point Settings at folder roots. Index, search, and open from a two-pane library browser without building a file tree in the sidebar.",
      "d.export.title": "Share and clean copy",
      "d.export.desc":
        "Share the original, a clean PDF with user marks removed, or highlights as Markdown — page-grouped snippet and comment for note-taking.",

      "dl.title": "Get <em>Serein</em>",
      "dl.sub":
        "Download the latest DMG from GitHub Releases. Locally signed for this project — first launch may need the macOS right-click Open flow.",
      "dl.mac": "Download for macOS",
      "dl.mac.meta": "GitHub Releases",
      "dl.source": "View source",
      "dl.req": "macOS 14+",

      "docs.kicker": "Essentials",
      "docs.title": "Compact notes",
      "docs.req.title": "Requirements",
      "docs.req.1": "macOS 14 or newer",
      "docs.req.2": "Swift 6.1 toolchain for development builds",
      "docs.req.3": "just for the local task runner",
      "docs.keys.title": "Core shortcuts",
      "docs.keys.focus": "Toggle cursor reading focus",
      "docs.keys.a": "Highlight or enter highlight mode",
      "docs.keys.c": "Toggle single-page continuous",
      "docs.keys.f": "Find in current document",
      "docs.keys.split": "Toggle compare split",
      "docs.cfg.title": "Configuration",
      "docs.cfg.desc": "Runtime settings live in:",

      "contact.title": "Open source",
      "contact.note":
        "Personal, non-commercial use. Redistribution and commercial use remain restricted without written permission.",
      "footer.rights": "© Serein · Native macOS PDF reader",

      "lang.toggle": "中文",
      "theme.toLight": "Switch to light theme",
      "theme.toDark": "Switch to dark theme",
    },
    zh: {
      "hero.badge": "Serein · macOS PDF 阅读器",
      "hero.title": "以沉静的方式<br>读完每一篇 <em>论文</em>",
      "hero.sub":
        "原生 macOS PDF 阅读器——标签、目录、高亮与键盘流线，为深度阅读而生。",
      "hero.note": "Swift · AppKit · PDFKit",
      "hero.shotAlt": "Serein 阅读窗口：左侧标签、中间 PDF、右侧侧栏",

      "layout.kicker": "三栏布局",
      "layout.title": "三栏各司其职",
      "layout.desc":
        "左栏回答打开了哪些文档，中栏只留给阅读，右栏承载目录、页面、搜索与批注——工作再密，界面也保持安静。",

      "tabs.kicker": "可切换的标签",
      "tabs.title": "左侧竖栏或标题栏横条",
      "tabs.desc":
        "在左侧标签轨与 macOS 标题栏标签之间切换，文档模型不变。同一会话、同一快捷键，只是外壳不同。",
      "tabs.card": "verticalSidebar · horizontalTitlebar",

      "note.kicker": "粉色优先的高亮",
      "note.title": "把思考留在页上",
      "note.desc":
        "按 A 高亮选区或进入高亮模式。右侧栏写评论，撤销最多 50 步，按页导出 Markdown 笔记。",
      "note.card": "粉 · 黄 · 绿 · 评论 · Markdown",

      "search.kicker": "不抢阅读区的搜索",
      "search.title": "结果从不挤占正文",
      "search.desc":
        "搜当前文档或所有已打开 PDF。Find 条保持轻薄，预览与命中列表在右侧栏，阅读空间保持干净。",
      "search.card": "当前文档 · 全部打开",

      "split.kicker": "对照分屏",
      "split.title": "两个视图，同一屏幕",
      "split.desc":
        "为同一 PDF 或其他标签打开第二个阅读区，再按左右或上下排列。两个 pane 各自保留页码与缩放。",
      "split.card": "左右 · 上下 · 独立阅读状态",

      "flow.kicker": "连续阅读",
      "flow.title": "多份 PDF，一条有序流",
      "flow.desc":
        "将选中标签组成连续阅读组。翻页跨文档边界；目录按 PDF 分组连在一起，不伪造合成文件。",
      "flow.card": "标签右键菜单 · 有序分组",

      "reload.kicker": "热重载",
      "reload.title": "重新编译，不必重开",
      "reload.desc":
        "当 LaTeX、Typst 或其他工具链改写已打开的干净 PDF 时，Serein 就地重载并回到实时页码。带未保存批注的会话保持不动。",
      "reload.card": "LaTeX · Typst · 保留页码",

      "keys.kicker": "键盘优先",
      "keys.title": "为指尖留在主键位而生",
      "keys.desc":
        "Vim 式翻页、半页滚动、跳转首尾、查找、全览与沉浸外壳——均可在设置中配置，从不喧哗。",
      "keys.card": "config.toml · 捕获 · 冲突检测",

      "overview.kicker": "全览网格",
      "overview.title": "一眼看见每一页",
      "overview.desc":
        "与阅读区同色的无缝页网格，没有嵌套面板。缩放加密铺排，点击页面跳转并退出。",
      "overview.card": "视口适配 · 点击跳转",

      "details.title": "还有这些安静的细节",
      "d.theme.title": "Rose Pine 主题",
      "d.theme.desc":
        "外观模式加亮色/暗色主题。Rose Pine Dawn 把纸面本身染暖；Rose Pine Moon 让页边与深色表面一致。",
      "d.library.title": "PDF 库",
      "d.library.desc":
        "在设置中指定库文件夹。双栏库浏览器索引、搜索并打开 PDF，侧栏不做文件树。",
      "d.export.title": "分享与干净副本",
      "d.export.desc":
        "分享原件、去掉用户批注的干净 PDF，或以 Markdown 导出高亮——按页分组的摘录与评论，方便做笔记。",

      "dl.title": "获取 <em>Serein</em>",
      "dl.sub":
        "从 GitHub Releases 下载最新 DMG。本项目使用本地签名——首次启动可能需要 macOS 右键打开流程。",
      "dl.mac": "下载 macOS 版",
      "dl.mac.meta": "GitHub Releases",
      "dl.source": "查看源码",
      "dl.req": "macOS 14+",

      "docs.kicker": "要点",
      "docs.title": "精简说明",
      "docs.req.title": "运行要求",
      "docs.req.1": "macOS 14 或更新",
      "docs.req.2": "开发构建需要 Swift 6.1 工具链",
      "docs.req.3": "本地任务使用 just",
      "docs.keys.title": "核心快捷键",
      "docs.keys.focus": "开启或关闭鼠标跟随阅读聚焦",
      "docs.keys.a": "高亮选区或进入高亮模式",
      "docs.keys.c": "切换单页连续阅读",
      "docs.keys.f": "在当前文档中查找",
      "docs.keys.split": "切换对照分屏",
      "docs.cfg.title": "配置",
      "docs.cfg.desc": "运行时设置位于：",

      "contact.title": "开源仓库",
      "contact.note":
        "个人非商业使用。未经书面许可，不得再分发或用于商业用途。",
      "footer.rights": "© Serein · 原生 macOS PDF 阅读器",

      "lang.toggle": "EN",
      "theme.toLight": "切换到浅色主题",
      "theme.toDark": "切换到深色主题",
    },
  };

  const themeMedia = window.matchMedia
    ? window.matchMedia("(prefers-color-scheme: dark)")
    : null;

  function getSavedTheme() {
    const saved = localStorage.getItem(THEME_KEY);
    return saved === "light" || saved === "dark" ? saved : null;
  }

  function detectSystemTheme() {
    return themeMedia && themeMedia.matches ? "dark" : "light";
  }

  function detectTheme() {
    return getSavedTheme() || detectSystemTheme();
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    const btn = document.querySelector("[data-theme-toggle]");
    if (!btn) return;
    btn.textContent = theme === "dark" ? "☀" : "☾";
    const lang = document.documentElement.lang === "zh-CN" ? "zh" : "en";
    const key = theme === "dark" ? "theme.toLight" : "theme.toDark";
    btn.setAttribute("aria-label", strings[lang][key]);
  }

  function getSavedLang() {
    const saved = localStorage.getItem(LANG_KEY);
    return saved === "zh" || saved === "en" ? saved : null;
  }

  function detectLang() {
    if (getSavedLang()) return getSavedLang();
    const nav = (navigator.language || "en").toLowerCase();
    return nav.startsWith("zh") ? "zh" : "en";
  }

  function applyLang(lang) {
    const table = strings[lang] || strings.en;
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (key && table[key] != null) el.textContent = table[key];
    });

    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      const key = el.getAttribute("data-i18n-html");
      if (key && table[key] != null) el.innerHTML = table[key];
    });

    document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
      const spec = el.getAttribute("data-i18n-attr");
      if (!spec) return;
      const [attr, key] = spec.split(":");
      if (attr && key && table[key] != null) el.setAttribute(attr, table[key]);
    });

    const langBtn = document.querySelector("[data-lang-toggle]");
    if (langBtn) langBtn.textContent = table["lang.toggle"];

    // Refresh theme button label for current language
    applyTheme(document.documentElement.getAttribute("data-theme") || detectTheme());
  }

  function setupReveal() {
    const reveals = Array.from(document.querySelectorAll(".reveal"));
    if (!reveals.length) return;

    const markIn = (el) => el.classList.add("is-in");

    // First paint: show anything already in or near the viewport.
    const nearFold = window.innerHeight * 0.92;
    reveals.forEach((el) => {
      if (el.getBoundingClientRect().top < nearFold) markIn(el);
    });

    if (!("IntersectionObserver" in window)) {
      reveals.forEach(markIn);
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          markIn(entry.target);
          io.unobserve(entry.target);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );

    reveals.forEach((el) => {
      if (!el.classList.contains("is-in")) io.observe(el);
    });
  }

  function setupCopy() {
    document.querySelectorAll("[data-copy]").forEach((button) => {
      button.addEventListener("click", async () => {
        const text = button.getAttribute("data-copy");
        if (!text || !navigator.clipboard) return;
        await navigator.clipboard.writeText(text);
        button.classList.add("is-copied");
        window.setTimeout(() => button.classList.remove("is-copied"), 1400);
      });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    let theme = detectTheme();
    applyTheme(theme);

    const themeBtn = document.querySelector("[data-theme-toggle]");
    if (themeBtn) {
      themeBtn.addEventListener("click", () => {
        theme = theme === "dark" ? "light" : "dark";
        localStorage.setItem(THEME_KEY, theme);
        applyTheme(theme);
      });
    }

    if (themeMedia) {
      const sync = (event) => {
        if (getSavedTheme()) return;
        theme = event.matches ? "dark" : "light";
        applyTheme(theme);
      };
      if (themeMedia.addEventListener) themeMedia.addEventListener("change", sync);
      else if (themeMedia.addListener) themeMedia.addListener(sync);
    }

    let lang = detectLang();
    applyLang(lang);
    document.querySelectorAll("[data-lang-toggle]").forEach((btn) => {
      btn.addEventListener("click", () => {
        lang = lang === "zh" ? "en" : "zh";
        localStorage.setItem(LANG_KEY, lang);
        applyLang(lang);
      });
    });

    setupReveal();
    setupCopy();
  });
})();

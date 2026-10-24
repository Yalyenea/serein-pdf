(() => {
  const strings = {
    en: {
      "nav.skip": "Skip to content",
      "nav.label": "Main navigation",
      "nav.features": "Features",
      "nav.questions": "Questions",
      "hero.eyebrow": "A PDF reader for Mac",
      "hero.title": "Room to <em>read.</em>",
      "hero.intro": "A thoughtful place for your papers and books. Read, annotate, and follow an idea across documents.",
      "hero.image": "Serein showing a paper with page thumbnails in the sidebar",
      "hero.caption": "Your page, with room to think.",
      "hero.appearance": "Find your reading light ↓",
      "features.eyebrow": "For the way you read",
      "features.title": "Stay with the thought.",
      "feature.read.title": "Find your way.",
      "feature.read.body": "Browse the outline, search your open PDFs, and preview a reference while keeping your place.",
      "feature.mark.title": "Make it yours.",
      "feature.mark.body": "Highlight a line. Add a thought beside it. Keep annotations in the PDF and export your notes as Markdown.",
      "feature.connect.title": "Read things together.",
      "feature.connect.body": "Keep related PDFs in spaces. Split your view to compare pages, each with its own position and zoom.",
      "annotations.eyebrow": "A note in the margin",
      "annotations.title": "Keep what clicks.",
      "annotations.body": "A useful sentence. A question for later. Mark the passage and leave a comment right beside it.",
      "annotations.image": "A pink highlight in a paper, with a comment in Serein’s annotation sidebar",
      "annotations.highlight": "Highlight",
      "annotations.comment": "Comment",
      "annotations.shortcuts": "See the shortcuts",
      "appearance.eyebrow": "From morning to midnight",
      "appearance.title": "Read in your own light.",
      "appearance.body": "Choose light and dark themes, then make the paper and window colors your own.",
      "appearance.light": "A lighter page.",
      "appearance.dark": "A softer evening.",
      "appearance.lightAlt": "Serein’s light reading appearance",
      "appearance.darkAlt": "Serein’s dark reading appearance",
      "extras.title": "Small things, well considered.",
      "extras.mac.title": "At home on your Mac",
      "extras.mac.body": "Native windows, familiar controls, and your local files. Open a PDF and start reading.",
      "extras.keys.title": "A few keys away",
      "extras.keys.body": "Turn pages with J and K. Find a command with ⌘K. Set your own shortcuts.",
      "extras.reload.title": "Keep up with your work",
      "extras.reload.body": "Compile in LaTeX or Typst. Your PDF updates in place and keeps your reading position.",
      "questions.title": "A few practical things.",
      "faq.requirements.question": "Will it run on my Mac?",
      "faq.requirements.answer": "Serein requires an Apple silicon Mac with macOS 14 or later. Selection translation uses Apple’s translation service and requires macOS 15 or later.",
      "faq.install.question": "How do I install it?",
      "faq.install.answer": "Open the downloaded DMG and drag Serein into Applications. This build is not notarized. If macOS blocks the first launch, use System Settings → Privacy & Security → Open Anyway.",
      "faq.install.help": "Apple’s installation guide",
      "faq.price.question": "Is Serein free?",
      "faq.price.answer": "Yes. Serein is free and open source under the GPL-3.0 license. You can browse the code, report a bug, or contribute on GitHub.",
      "faq.files.question": "Where do my notes go?",
      "faq.files.answer": "Saved highlights and comments are written to your PDF. You can also export annotations as Markdown, plain text, or JSON, or export a clean PDF copy.",
      "download.title": "Your next good read.",
      "download.body": "Open a PDF. Settle in.",
      "download.label": "Download for Mac",
      "download.requirements": "Free & open source · macOS 14+ · Apple silicon",
      "download.releases": "Release notes & other downloads",
      "footer.source": "Source",
      "footer.feedback": "Feedback",
      "theme.light": "Switch to light theme",
      "theme.dark": "Switch to dark theme",
      "meta.title": "Serein · A PDF reader for Mac",
      "meta.description": "A focused PDF reader for Mac. Read, annotate, and work across documents with native tabs, split views, and light and dark themes. Free and open source.",
    },
    zh: {
      "nav.skip": "跳至正文",
      "nav.label": "主导航",
      "nav.features": "功能",
      "nav.questions": "常见问题",
      "hero.eyebrow": "Mac 上的 PDF 阅读器",
      "hero.title": "专心<em>读下去。</em>",
      "hero.intro": "给论文和书籍一个舒适的位置。阅读、批注，在多份文档之间接着思考。",
      "hero.image": "Serein 中的论文阅读界面，侧栏显示页面缩略图",
      "hero.caption": "页面清爽，思路连贯。",
      "hero.appearance": "找到舒服的阅读颜色 ↓",
      "features.eyebrow": "顺着你的阅读习惯",
      "features.title": "让思路连起来。",
      "feature.read.title": "想找的，随手就到。",
      "feature.read.body": "沿目录浏览，搜索已打开的 PDF，就地预览引用，随时回到刚才读到的地方。",
      "feature.mark.title": "把想法留在页边。",
      "feature.mark.body": "高亮一句话，写下当时的想法。批注保存在 PDF 中，也能导出为 Markdown 笔记。",
      "feature.connect.title": "放在一起，读得更明白。",
      "feature.connect.body": "用工作区收好相关文档，分屏对照不同页面。每个阅读区各自保留位置和缩放。",
      "annotations.eyebrow": "读到有感触的地方",
      "annotations.title": "记下来，接着读。",
      "annotations.body": "一句有用的话，一个留待解答的问题。标记原文，在旁边写下评论。",
      "annotations.image": "论文中的粉色高亮，以及 Serein 批注侧栏中的评论",
      "annotations.highlight": "高亮",
      "annotations.comment": "评论",
      "annotations.shortcuts": "查看快捷键",
      "appearance.eyebrow": "从清晨，到深夜",
      "appearance.title": "调成你舒服的颜色。",
      "appearance.body": "分别选择浅色与深色主题，再按喜好调整纸面和窗口颜色。",
      "appearance.light": "明亮的纸面。",
      "appearance.dark": "柔和的夜色。",
      "appearance.lightAlt": "Serein 的浅色阅读界面",
      "appearance.darkAlt": "Serein 的深色阅读界面",
      "extras.title": "顺手，藏在细节里。",
      "extras.mac.title": "熟悉的 Mac 体验",
      "extras.mac.body": "原生窗口，熟悉的操作，自己的本地文件。打开 PDF 就能开始阅读。",
      "extras.keys.title": "常用操作，几下按键",
      "extras.keys.body": "J 和 K 翻页，⌘K 查找命令。也可以设置自己的快捷键。",
      "extras.reload.title": "文档更新，阅读继续",
      "extras.reload.body": "用 LaTeX 或 Typst 编译时，PDF 自动更新，并保留当前阅读位置。",
      "questions.title": "开始之前，你可能想知道。",
      "faq.requirements.question": "我的 Mac 能用吗？",
      "faq.requirements.answer": "需要搭载 Apple 芯片、运行 macOS 14 或更新系统的 Mac。选区翻译使用 Apple 翻译服务，需要 macOS 15 或更新系统。",
      "faq.install.question": "如何安装？",
      "faq.install.answer": "打开下载的 DMG，把 Serein 拖入「应用程序」。当前版本尚未公证。首次打开若被 macOS 拦截，请前往「系统设置 → 隐私与安全性 → 仍要打开」。",
      "faq.install.help": "查看 Apple 安装说明",
      "faq.price.question": "Serein 免费吗？",
      "faq.price.answer": "免费，基于 GPL-3.0 协议开源。你可以在 GitHub 查看代码、反馈问题或参与开发。",
      "faq.files.question": "批注保存在哪里？",
      "faq.files.answer": "保存后，高亮和评论会写入 PDF。也可以将批注导出为 Markdown、纯文本或 JSON，或导出一份干净的 PDF 副本。",
      "download.title": "打开下一篇，慢慢读。",
      "download.body": "从一份 PDF 开始。",
      "download.label": "下载 Mac 版",
      "download.requirements": "免费开源 · macOS 14+ · Apple 芯片",
      "download.releases": "更新记录与其他下载",
      "footer.source": "源代码",
      "footer.feedback": "反馈问题",
      "theme.light": "切换到浅色主题",
      "theme.dark": "切换到深色主题",
      "meta.title": "Serein · Mac 上的 PDF 阅读器",
      "meta.description": "专心读下去。Mac 原生 PDF 阅读器，支持批注、工作区、分屏和明暗主题。免费开源。",
    },
  };
  const root = document.documentElement;
  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  const languageButton = document.querySelector("[data-lang-toggle]");
  const themeButton = document.querySelector("[data-theme-toggle]");
  let language = localStorage.getItem("serein-site-lang")
    || (navigator.language.startsWith("zh") ? "zh" : "en");
  let theme = localStorage.getItem("serein-site-theme");

  function renderTheme() {
    const dark = theme ? theme === "dark" : systemTheme.matches;
    root.dataset.theme = dark ? "dark" : "light";
    themeButton.setAttribute("aria-label", strings[language][dark ? "theme.light" : "theme.dark"]);
    themeButton.setAttribute("aria-pressed", String(dark));
    document.querySelector("meta[name='theme-color']").content = dark ? "#1d1c22" : "#f8f7f4";
    document.querySelectorAll("[data-dark-screenshot]").forEach((source) => {
      source.media = dark ? "all" : "not all";
    });
  }
  function renderLanguage() {
    root.lang = language;
    const copy = strings[language];
    document.querySelectorAll("[data-i18n]").forEach((element) => {
      element.textContent = copy[element.dataset.i18n];
    });
    // Only our own title strings contain markup; other copy stays plain text.
    document.querySelectorAll("[data-i18n-html]").forEach((element) => {
      element.innerHTML = copy[element.dataset.i18nHtml];
    });
    document.querySelectorAll("[data-i18n-attr]").forEach((element) => {
      const [attribute, key] = element.dataset.i18nAttr.split(":");
      element.setAttribute(attribute, copy[key]);
    });
    languageButton.textContent = language === "en" ? "中文" : "EN";
    languageButton.lang = language === "en" ? "zh" : "en";
    languageButton.setAttribute("aria-label", language === "en" ? "切换到中文" : "Switch to English");
    document.title = copy["meta.title"];
    document.querySelector("meta[name='description']").content = copy["meta.description"];
    renderTheme();
  }
  languageButton.addEventListener("click", () => {
    language = language === "en" ? "zh" : "en";
    localStorage.setItem("serein-site-lang", language);
    renderLanguage();
  });
  themeButton.addEventListener("click", () => {
    theme = root.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem("serein-site-theme", theme);
    renderTheme();
  });
  systemTheme.addEventListener("change", () => {
    if (!theme) renderTheme();
  });
  renderLanguage();
})();

(() => {
  const root = document.documentElement;
  const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
  const languageButton = document.querySelector("[data-lang-toggle]");
  const themeButton = document.querySelector("[data-theme-toggle]");
  const savedLanguage = localStorage.getItem("serein-site-lang");
  const savedTheme = localStorage.getItem("serein-site-theme");
  let language = savedLanguage === "en" || savedLanguage === "zh"
    ? savedLanguage : (navigator.language.startsWith("zh") ? "zh" : "en");
  let followsSystem = savedTheme !== "light" && savedTheme !== "dark";
  let theme = followsSystem ? (systemTheme.matches ? "dark" : "light") : savedTheme;

  function applyTheme() {
    root.dataset.theme = theme;
    themeButton.textContent = theme === "dark" ? "☼" : "◐";
    themeButton.setAttribute("aria-label", language === "en"
      ? `Switch to ${theme === "dark" ? "light" : "dark"} theme`
      : `切换到${theme === "dark" ? "浅" : "深"}色主题`);
    document.querySelector('meta[name="theme-color"]').content = theme === "dark" ? "#23212c" : "#f8f6f1";
  }

  function applyLanguage() {
    root.lang = language === "zh" ? "zh-CN" : "en";
    document.querySelectorAll("[data-en][data-zh]").forEach(element => {
      element.textContent = element.dataset[language];
    });
    document.querySelectorAll("[data-en-aria][data-zh-aria]").forEach(element => {
      element.setAttribute("aria-label", element.dataset[`${language}Aria`]);
    });
    languageButton.textContent = language === "en" ? "中文" : "EN";
    languageButton.setAttribute("aria-label", language === "en" ? "切换到中文" : "Switch to English");
    applyTheme();
  }

  languageButton.addEventListener("click", () => {
    language = language === "en" ? "zh" : "en";
    localStorage.setItem("serein-site-lang", language);
    applyLanguage();
  });
  themeButton.addEventListener("click", () => {
    followsSystem = false;
    theme = theme === "light" ? "dark" : "light";
    localStorage.setItem("serein-site-theme", theme);
    applyTheme();
  });
  systemTheme.addEventListener("change", event => {
    if (followsSystem) {
      theme = event.matches ? "dark" : "light";
      applyTheme();
    }
  });
  applyLanguage();
})();

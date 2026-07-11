// theme.js — stamp the saved theme on <html> before first paint.
// Loaded as a plain (blocking) script in <head> so there is no flash of the
// wrong theme. The header's toggle button (components.js) writes the choice
// to localStorage; with nothing saved, the system preference applies via
// the prefers-color-scheme media query in site.css.
(function () {
  var t = null;
  try { t = localStorage.getItem("theme"); } catch (e) { /* storage blocked */ }
  if (t === "light" || t === "dark") document.documentElement.dataset.theme = t;
})();

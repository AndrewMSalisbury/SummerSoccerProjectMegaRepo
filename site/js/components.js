// components.js — shared header, search, fallback badges, tables, tooltip.

import { loadJSON, el, svgEl, clear, append, fmtSeason } from "./data.js";

// ---------- header + search ----------

export async function initHeader() {
  const host = document.getElementById("site-header");
  if (!host) return;
  host.className = "site-header";

  const menu = el("div", { class: "dropdown-menu" });
  const dropdown = el("div", { class: "dropdown" },
    el("button", {
      type: "button",
      onclick: e => {
        e.stopPropagation();
        dropdown.classList.toggle("open");
      },
    }, "Leagues ▾"),
    menu);
  document.addEventListener("click", () => dropdown.classList.remove("open"));

  const input = el("input", {
    type: "search", placeholder: "Search coaches, teams…",
    autocomplete: "off", "aria-label": "Search",
  });
  const results = el("div", { class: "search-results" });

  host.append(el("div", { class: "container" },
    el("a", { class: "site-title", href: "index.html" }, "Coach Valuation"),
    el("nav", { class: "nav-links" },
      el("a", { href: "index.html" }, "Home"),
      dropdown,
      el("a", { href: "players.html" }, "Player growth"),
      el("a", { href: "builder.html" }, "Team builder"),
      el("a", { href: "validation.html" }, "Does it work?"),
      el("a", { href: "writeup.html" }, "Writeup")),
    el("div", { class: "search-box" }, input, results),
    themeToggle()));

  initSearch(input, results);

  try {
    const meta = await loadJSON("data/meta.json");
    for (const [slug, name] of Object.entries(meta.league_names)) {
      menu.append(el("a", { href: `league.html?id=${encodeURIComponent(slug)}` }, name));
    }
  } catch {
    menu.append(el("a", { href: "index.html" }, "(league list unavailable)"));
  }
}

// ---------- theme toggle ----------

// js/theme.js stamps any saved choice on <html> before first paint; this
// button flips the effective theme and persists it.
function effectiveTheme() {
  return document.documentElement.dataset.theme ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
}

function themeIcon(mode) {
  // shows the mode a click switches TO: moon while light, sun while dark
  const s = svgEl("svg", { viewBox: "0 0 24 24", fill: "none",
    stroke: "currentColor", "stroke-width": "2", "stroke-linecap": "round" });
  if (mode === "dark") {
    s.append(svgEl("path", {
      d: "M20.4 14.2A8.5 8.5 0 0 1 9.8 3.6 8.5 8.5 0 1 0 20.4 14.2Z",
      fill: "currentColor", stroke: "none" }));
  } else {
    s.append(svgEl("circle", { cx: 12, cy: 12, r: 4.2, fill: "currentColor",
      stroke: "none" }));
    for (const [x1, y1, x2, y2] of [
      [12, 2, 12, 4.5], [12, 19.5, 12, 22], [2, 12, 4.5, 12], [19.5, 12, 22, 12],
      [4.9, 4.9, 6.7, 6.7], [17.3, 17.3, 19.1, 19.1],
      [4.9, 19.1, 6.7, 17.3], [17.3, 6.7, 19.1, 4.9],
    ]) s.append(svgEl("line", { x1, y1, x2, y2 }));
  }
  return s;
}

function themeToggle() {
  const btn = el("button", { class: "theme-toggle", type: "button" });
  function refresh() {
    const next = effectiveTheme() === "dark" ? "light" : "dark";
    btn.setAttribute("aria-label", `Switch to ${next} mode`);
    btn.title = `Switch to ${next} mode`;
    clear(btn).append(themeIcon(next));
  }
  btn.addEventListener("click", () => {
    const next = effectiveTheme() === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("theme", next); } catch { /* storage blocked */ }
    refresh();
  });
  refresh();
  return btn;
}

function initSearch(input, results) {
  let index = null;
  let items = [];   // rendered anchor elements
  let active = -1;

  const typeLabel = { c: "Coaches", t: "Teams", l: "Leagues" };
  const typePage = { c: "coach.html", t: "team.html", l: "league.html" };

  async function ensureIndex() {
    if (!index) index = await loadJSON("data/search_index.json").catch(() => []);
    return index;
  }

  function render(q) {
    clear(results);
    items = [];
    active = -1;
    if (!q) { results.classList.remove("open"); return; }
    const ql = q.toLowerCase();
    const matches = index.filter(x => x.n.toLowerCase().includes(ql)).slice(0, 24);
    if (!matches.length) {
      results.append(el("div", { class: "empty" }, "No matches"));
      results.classList.add("open");
      return;
    }
    for (const t of ["l", "c", "t"]) {
      const group = matches.filter(m => m.t === t);
      if (!group.length) continue;
      results.append(el("div", { class: "group-label" }, typeLabel[t]));
      for (const m of group) {
        const a = el("a", { href: `${typePage[m.t]}?id=${encodeURIComponent(m.id)}` });
        // highlight the matched substring (textContent-built, not innerHTML)
        const i = m.n.toLowerCase().indexOf(ql);
        a.append(m.n.slice(0, i), el("mark", {}, m.n.slice(i, i + q.length)),
                 m.n.slice(i + q.length));
        results.append(a);
        items.push(a);
      }
    }
    results.classList.add("open");
  }

  input.addEventListener("focus", ensureIndex);
  input.addEventListener("input", async () => {
    await ensureIndex();
    render(input.value.trim());
  });
  input.addEventListener("keydown", e => {
    if (!items.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      active = (active + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items.forEach((a, i) => a.classList.toggle("active", i === active));
      items[active].scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter" && active >= 0) {
      e.preventDefault();
      window.location.href = items[active].getAttribute("href");
    } else if (e.key === "Escape") {
      results.classList.remove("open");
    }
  });
  document.addEventListener("click", e => {
    if (!results.contains(e.target) && e.target !== input) {
      results.classList.remove("open");
    }
  });
}

// ---------- fallback badges & photos ----------

// categorical hues (reference palette, light steps) for deterministic badges
const BADGE_HUES = ["#2a78d6", "#1baf7a", "#eda100", "#008300",
                    "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"];

function nameHash(name) {
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return h;
}

// Each league has its own fixed accent color (the one place the site uses a
// wide categorical range; everything else sticks to blue/aqua + the
// green↔red grade/residual polarity). Keyed by league slug.
const LEAGUE_HUES = {
  "premier-league":     "#4a3aa7",  // violet
  "laliga":             "#e34948",  // red
  "laliga2":            "#e87ba4",  // magenta
  "serie-a":            "#2a78d6",  // blue
  "bundesliga":         "#d95926",  // deep orange-red
  "ligue-1":            "#0d366b",  // navy
  "championship":       "#199e70",  // deep aqua
  "liga-portugal":      "#008300",  // green
  "jupiler-pro-league": "#c98500",  // amber
  "eredivisie":         "#eb6834",  // orange
  "superliga":          "#d55181",  // dark magenta
  "ekstraklasa":        "#86b6ef",  // light blue
  "1-hnl":              "#1baf7a",  // aqua
  "super-lig":          "#eda100",  // yellow
};

export function leagueHue(slug) {
  return LEAGUE_HUES[slug] || "#2a78d6";
}

export function teamAbbr(name) {
  const stop = new Set(["fc", "cf", "afc", "ac", "as", "ss", "sc", "cd", "rc",
                        "de", "the", "1", "b"]);
  const words = name.split(/[\s.-]+/).filter(w => w && !stop.has(w.toLowerCase()));
  if (!words.length) return name.slice(0, 3).toUpperCase();
  if (words.length === 1) return words[0].slice(0, 3).toUpperCase();
  return words.slice(0, 3).map(w => w[0]).join("").toUpperCase();
}

// SVG group for a club badge fallback: colored circle + initials.
// cx/cy/r position it inside an existing chart svg.
export function badgeGroup(name, cx, cy, r) {
  const hue = BADGE_HUES[nameHash(name) % BADGE_HUES.length];
  const g = svgEl("g", {});
  g.append(
    svgEl("circle", { cx, cy, r, fill: hue }),
    svgEl("text", {
      x: cx, y: cy, "text-anchor": "middle", "dominant-baseline": "central",
      fill: "#ffffff", "font-size": r * 0.85, "font-weight": "700",
      "font-family": "system-ui, sans-serif",
    }, teamAbbr(name)));
  return g;
}

// <img> for a crest with badge fallback, or the badge directly if no crest.
export function crestImg(crest, name, cls = "mini") {
  if (crest) {
    const img = el("img", { class: cls, src: crest, alt: `${name} crest`, loading: "lazy" });
    img.addEventListener("error", () => img.replaceWith(badgeSvg(name, cls)));
    return img;
  }
  return badgeSvg(name, cls);
}

export function badgeSvg(name, cls = "mini") {
  const s = svgEl("svg", { viewBox: "0 0 24 24", class: cls, role: "img" });
  s.append(badgeGroup(name, 12, 12, 11));
  return s;
}

// coach photo with neutral silhouette fallback
export function coachImg(img, name, cls = "mini face") {
  if (img) {
    const node = el("img", { class: cls, src: img, alt: name, loading: "lazy" });
    node.addEventListener("error", () => node.replaceWith(silhouetteSvg(cls)));
    return node;
  }
  return silhouetteSvg(cls);
}

export function silhouetteSvg(cls = "mini face") {
  const s = svgEl("svg", { viewBox: "0 0 24 24", class: cls, role: "img",
                           "aria-label": "no photo" });
  s.append(
    svgEl("rect", { x: 0, y: 0, width: 24, height: 24, fill: "#c3c2b7" }),
    svgEl("circle", { cx: 12, cy: 9, r: 4.2, fill: "#898781" }),
    svgEl("path", { d: "M 4 24 Q 4 15.5 12 15.5 Q 20 15.5 20 24 Z", fill: "#898781" }));
  return s;
}

// ---------- grade chip (never rendered without its cut label) ----------

// tier classes tint the chip/letter by grade band (A → F); the letter itself
// stays in ink so readability never depends on the hue
export function gradeTier(letter) {
  const t = (letter || "").charAt(0).toLowerCase();
  return "abcdf".includes(t) ? ` graded grade-${t}` : "";
}

export function gradeChip(grade) {
  if (!grade) return el("span", { class: "muted" }, "Unranked");
  return el("span", { title: `Rank ${grade.rank} of ${grade.n_ranked} — ${grade.cut_label}` },
    el("span", { class: "grade-chip" + gradeTier(grade.letter) }, grade.letter),
    " ",
    el("span", { class: "muted" }, `#${grade.rank} · ${grade.cut_label}`));
}

// ---------- sortable table ----------

// cols: [{label, cls, render(row) -> node/string}]
// sorts: {key: {label, fn(a,b)}}; toggle buttons switch between them.
export function sortableTable(host, rows, cols, sorts, defaultSort) {
  const controls = el("div", { class: "chart-controls" });
  const toggle = el("div", { class: "seg-toggle", role: "group" });
  const wrap = el("div", { class: "table-wrap" });
  let current = defaultSort;

  function render() {
    clear(toggle);
    for (const [key, s] of Object.entries(sorts)) {
      toggle.append(el("button", {
        type: "button",
        class: key === current ? "active" : "",
        onclick: () => { current = key; render(); },
      }, s.label));
    }
    const sorted = [...rows].sort(sorts[current].fn);
    const table = el("table", { class: "data" },
      el("thead", {}, el("tr", {},
        cols.map(c => el("th", { class: c.cls || "" }, c.label)))),
      el("tbody", {},
        sorted.map(r => {
          const tr = el("tr", {}, cols.map(c =>
            el("td", { class: c.cls || "" }, c.render(r))));
          tr.dataset.key = r.__key ?? "";
          return tr;
        })));
    clear(wrap).append(table);
  }

  controls.append(toggle);
  host.append(controls, wrap);
  render();
  return { rerender: render, wrap };
}

// ---------- shared tooltip ----------

let tooltipNode = null;

export function tooltip() {
  if (!tooltipNode) {
    tooltipNode = el("div", { class: "viz-tooltip", role: "status" });
    document.body.append(tooltipNode);
  }
  return {
    show(evt, title, rows) {
      clear(tooltipNode);
      if (title) tooltipNode.append(el("div", { class: "tt-title" }, title));
      for (const r of rows) {
        const line = el("div", { class: "tt-row" });
        if (r.color) {
          line.append(el("span", {
            class: "key-line" + (r.dashed ? " dashed" : ""),
            style: `border-top-color:${r.color}`,
          }));
        }
        line.append(r.label, el("strong", {}, r.value));
        tooltipNode.append(line);
      }
      tooltipNode.style.display = "block";
      this.move(evt);
    },
    move(evt) {
      const pad = 14;
      const w = tooltipNode.offsetWidth, h = tooltipNode.offsetHeight;
      let x = evt.clientX + pad, y = evt.clientY + pad;
      if (x + w > window.innerWidth - 8) x = evt.clientX - w - pad;
      if (y + h > window.innerHeight - 8) y = evt.clientY - h - pad;
      tooltipNode.style.left = `${x}px`;
      tooltipNode.style.top = `${y}px`;
    },
    hide() { tooltipNode.style.display = "none"; },
  };
}

// ---------- misc ----------

export function seasonSpan(first, last) {
  return `${fmtSeason(first)} – ${fmtSeason(last)}`;
}

export function statTile(label, value, hint) {
  return el("div", { class: "stat-tile" },
    el("div", { class: "label" }, label),
    el("div", { class: "value" }, value),
    hint ? el("div", { class: "hint" }, hint) : null);
}

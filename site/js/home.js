// home.js — hero, dataset stat tiles, top-coach leaderboard, league tiles.

import { loadJSON, el, clear, fmtSigned } from "./data.js";
import { initHeader, coachImg, statTile, gradeTier, leagueHue } from "./components.js";

initHeader();
init();

async function init() {
  const main = document.querySelector("main");
  clear(main);

  let meta, lb;
  try {
    [meta, lb] = await Promise.all([
      loadJSON("data/meta.json"),
      loadJSON("data/leaderboard.json"),
    ]);
  } catch {
    main.append(el("div", { class: "error-panel" },
      "Could not load site data. If you opened this file directly, serve the ",
      el("code", {}, "site/"), " folder instead: ",
      el("code", {}, "python -m http.server"), "."));
    return;
  }

  const d = meta.dataset;
  main.append(
    el("div", { class: "hero" },
      el("h1", {}, "Coach Rankings"),
      el("p", { class: "hero-link" },
        el("a", { href: "writeup.html" }, "How the model works — read the guide →"))),
    el("div", { class: "stat-row" },
      statTile("Leagues", String(d.leagues)),
      statTile("Seasons", `${d.last_season - d.first_season + 1}`,
        `${d.first_season}–${d.last_season}`),
      statTile("Team-seasons", d.team_seasons.toLocaleString()),
      statTile("Coaches", d.coaches.toLocaleString()),
      statTile("Graded coaches", `${d.n_graded_top5}`,
        `top-5 cut · ${d.n_graded_14league} all leagues`)));

  main.append(el("h2", {}, "Top coaches — performance above squad-value expectation"),
    ...renderLeaderboard(lb));

  main.append(el("h2", {}, "Leagues"));
  const grid = el("div", { class: "tile-grid" });
  for (const [slug, name] of Object.entries(meta.league_names)) {
    grid.append(el("a", {
      class: "league-tile", href: `league.html?id=${encodeURIComponent(slug)}`,
      style: `--tile-accent: ${leagueHue(slug)}`,
    }, name));
  }
  main.append(grid);

  main.append(el("p", { class: "footnote", style: "margin-top:28px" },
    `Data: Transfermarkt squad values and results, ${d.first_season}–${d.last_season}; ` +
    `player-type analysis: SofaScore (big-5 leagues, 2015/16–2024/25). Generated ${meta.generated}.`));
}

// Returns [subtitle, card]; the subtitle names the active cut, so grades in the
// table are never shown without their cut label (the two cuts use separate
// grading curves).
function renderLeaderboard(lb) {
  const cuts = { top5: lb.top5, all14: lb.all14 };
  let cutKey = "top5";
  let expanded = false;

  const subtitle = el("p", { class: "subtitle" });
  const card = el("div", { class: "chart-card" });
  const toggle = el("div", { class: "seg-toggle" });
  const wrap = el("div", { class: "table-wrap" });
  const btn = el("button", { class: "show-more", type: "button",
    onclick: () => { expanded = !expanded; render(); } });
  card.append(el("div", { class: "chart-controls" }, toggle), wrap, btn);

  function render() {
    const cut = cuts[cutKey];
    subtitle.textContent =
      `${cut.cut_label} cut, ranked by BLUP (shrunk toward zero when data is sparse). ` +
      "Grades are a bell curve over ranked coaches. " +
      "Stints, clubs, and games are full-career totals across all 14 leagues.";
    clear(toggle).append(...Object.entries(cuts).map(([k, c]) =>
      el("button", {
        type: "button",
        class: k === cutKey ? "active" : "",
        onclick: () => {
          if (k === cutKey) return;
          cutKey = k;
          expanded = false;
          render();
        },
      }, c.cut_label)));
    const rows = expanded ? cut.coaches : cut.coaches.slice(0, 25);
    const table = el("table", { class: "data" },
      el("thead", {}, el("tr", {},
        el("th", { class: "num" }, "#"),
        el("th", {}, "Coach"),
        el("th", {}, "Grade"),
        el("th", { class: "num" }, "Score"),
        el("th", { class: "num" }, "BLUP"),
        el("th", { class: "num" }, "Stints"),
        el("th", { class: "num" }, "Clubs"),
        el("th", { class: "num" }, "Games"),
        el("th", { class: "num" }, "Mean residual"))),
      el("tbody", {}, rows.map(c => el("tr", {},
        el("td", { class: "num muted" }, String(c.rank)),
        el("td", {}, el("a", { class: "cell-entity", href: `coach.html?id=${c.id}` },
          coachImg(c.img, c.name), c.name,
          c.significant ? el("span", {
            class: "grade-chip", title: "statistically significant after FDR correction",
          }, "sig") : null)),
        el("td", {}, el("span", { class: "grade-chip" + gradeTier(c.letter_grade) },
          c.letter_grade)),
        el("td", { class: "num" }, c.numeric_grade.toFixed(1)),
        el("td", { class: "num" }, fmtSigned(c.blup, 3)),
        el("td", { class: "num" }, String(c.n_stints)),
        el("td", { class: "num" }, String(c.n_clubs)),
        el("td", { class: "num" }, String(c.total_games)),
        el("td", { class: "num" }, c.mean_residual == null ? "—"
          : el("span", { class: c.mean_residual >= 0 ? "delta-pos" : "delta-neg" },
              fmtSigned(c.mean_residual)))))));
    clear(wrap).append(table);
    btn.textContent = expanded
      ? "Show top 25"
      : `Show all ${cut.coaches.length} ranked coaches`;
  }

  render();
  return [subtitle, card];
}

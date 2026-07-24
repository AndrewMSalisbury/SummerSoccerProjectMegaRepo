// players.js — player value-growth leaderboard (Part 12). Ranks the clean
// player-development residual: market-value growth above a player's own
// age/price/position/momentum baseline. Describes PLAYERS, not coaches.

import { loadJSON, el, clear, showError, fmtSeason } from "./data.js";
import { initHeader, statTile } from "./components.js";
import { growthCurves, CAT4 } from "./charts.js";

const POS_LABEL = { GK: "Goalkeepers", DEF: "Defenders", MID: "Midfielders", FWD: "Forwards" };
// Fixed categorical assignment, in the palette's validated slot order — the
// order is the CVD-safety mechanism, so it never follows the data (a filter
// must not repaint the survivors).
const POS_ORDER = ["FWD", "MID", "DEF", "GK"];
const PAGE = 25;   // players shown before "show all"

initHeader();
init();

async function init() {
  let D;
  try {
    D = await loadJSON("data/players.json");
  } catch {
    return showError("Player growth data not available. Run the site export.");
  }
  document.title = "Player value growth — Coach Valuation";
  const main = document.querySelector("main");
  clear(main);

  main.append(
    el("h1", {}, "Player value growth"),
    el("p", { class: "subtitle" },
      "Who appreciated in market value fastest — above their own age, price and position curve"));

  main.append(el("div", { class: "card" },
    el("p", { style: "margin:0 0 8px" },
      "The model expects every player's market value to follow a trajectory set by age, " +
      "starting value, position and recent momentum. This ranks the players who beat that " +
      "expectation by the widest margin — genuine breakouts, not just expensive teenagers " +
      "getting more expensive."),
    el("p", { class: "footnote", style: "margin:0" },
      "This is a player descriptor, not a coach one. The project's Coach Development " +
      "Effect analysis found that the coach's share of value growth does " +
      "not repeat across his career, so no coaching credit is drawn from this list.")));

  const chart = renderGrowth(main, D.growth);

  main.append(el("div", { class: "stat-row" },
    statTile("Players ranked", String(D.meta.n_pool.toLocaleString()),
      `min ${D.meta.min_minutes} minutes · ≥ €${D.meta.min_value_m}m`),
    statTile("Shown here", `Top ${D.meta.shown}`, "by development residual"),
    statTile("Most upside by role",
      POS_LABEL[D.by_position[0].pos] ?? D.by_position[0].pos,
      "highest mean over-appreciation")));

  // filters
  const controls = el("div", { class: "chart-controls" });
  const posSel = el("select", { "aria-label": "Position" },
    el("option", { value: "" }, "All positions"),
    ...D.positions.map(p => el("option", { value: p }, POS_LABEL[p] ?? p)));
  const lgSel = el("select", { "aria-label": "League" },
    el("option", { value: "" }, "All leagues"),
    ...D.leagues.map(l => el("option", { value: l }, leagueName(l))));
  const eraSel = el("select", { "aria-label": "Era" },
    el("option", { value: "0" }, "All seasons"),
    el("option", { value: "2020" }, "2020/21 onwards"),
    el("option", { value: "2015" }, "2015/16 onwards"));
  controls.append(el("span", { class: "muted" }, "Filter"), posSel, lgSel, eraSel);
  main.append(controls);

  const tableCard = el("div", { class: "chart-card" });
  const title = el("div", { class: "chart-title" });
  const wrap = el("div", { class: "table-wrap" });
  const btn = el("button", { class: "show-more", type: "button",
    onclick: () => { expanded = !expanded; render(); } });
  tableCard.append(title, wrap, btn);
  main.append(tableCard);

  let expanded = false;
  function render() {
    const pos = posSel.value, lg = lgSel.value, era = Number(eraSel.value);
    const rows = D.players.filter(p =>
      (!pos || p.pos === pos) && (!lg || p.league === lg) && p.season >= era);
    title.textContent = `${rows.length} player-season${rows.length === 1 ? "" : "s"}` +
      (rows.length > PAGE && !expanded ? ` · showing top ${PAGE}` : "");
    if (!rows.length) {
      clear(wrap).append(el("p", { class: "muted" }, "No players match these filters."));
      btn.style.display = "none";
      return;
    }
    const shown = expanded ? rows : rows.slice(0, PAGE);
    const table = el("table", { class: "data" },
      el("thead", {}, el("tr", {},
        el("th", {}, "#"), el("th", {}, "Player"),
        el("th", {}, "Pos"), el("th", { class: "num" }, "Age"),
        el("th", {}, "Club"), el("th", {}, "Season"),
        el("th", { class: "num" }, "Value"),
        el("th", { class: "num" }, "×"),
        el("th", { class: "num" }, "Over-exp."))),
      el("tbody", {}, shown.map((p, i) => el("tr", {},
        el("td", { class: "num muted" }, String(i + 1)),
        el("td", {}, el("strong", {}, p.name)),
        el("td", {}, el("span", { class: "muted" }, p.pos)),
        el("td", { class: "num" }, String(p.age)),
        el("td", {}, p.club),
        el("td", { class: "muted" }, fmtSeason(p.season)),
        el("td", { class: "num" }, `€${p.v0}m → €${p.v1}m`),
        el("td", { class: "num" }, el("strong", {}, `${p.mult}×`)),
        el("td", { class: "num delta-pos" }, `+${p.dev.toFixed(2)}`)))));
    clear(wrap).append(table);
    btn.style.display = rows.length > PAGE ? "" : "none";
    btn.textContent = expanded ? `Show top ${PAGE}` : `Show all ${rows.length} players`;
  }
  posSel.onchange = lgSel.onchange = eraSel.onchange = () => {
    expanded = false;
    render();
    chart?.setHighlight(posSel.value);   // the curve follows the position filter
  };
  render();

  // by-position footer
  const lists = el("div", { style:
    "display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px; margin-top:20px" });
  const posCard = el("div", { class: "card" },
    el("h3", { style: "margin-top:0" }, "Over-appreciation by position"),
    el("p", { class: "footnote", style: "margin:0 0 10px" },
      "Mean development residual across all ranked players in each role."));
  for (const b of D.by_position) {
    posCard.append(el("div", { style: "display:flex; gap:8px; padding:3px 0" },
      el("span", { style: "flex:1" }, POS_LABEL[b.pos] ?? b.pos),
      el("span", { class: b.mean_dev >= 0 ? "delta-pos" : "delta-neg" },
        (b.mean_dev >= 0 ? "+" : "") + b.mean_dev.toFixed(3))));
  }
  lists.append(posCard);
  main.append(lists);
}

// The expectation curve itself: what the model predicts a player gains in market
// value over the next season, by age and position. This is the baseline the
// leaderboard's "over-expectation" column is measured against.
function renderGrowth(main, G) {
  if (!G || !G.series || !G.series.length) return null;
  const byPos = new Map(G.series.map(s => [s.pos, s]));
  const series = POS_ORDER.filter(p => byPos.has(p)).map((p, i) => ({
    key: p,
    label: POS_LABEL[p] ?? p,
    color: CAT4[i],
    points: byPos.get(p).points,
  }));

  const host = el("div", {});
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Expected value growth by age and position"),
    el("div", { class: "chart-sub" },
      "Model-predicted change in market value over the following season — the baseline " +
      "every player on this page is scored against"),
    host,
    el("div", { class: "chart-legend" },
      ...series.map(s => el("span", { class: "key" },
        el("span", { class: "key-line", style: `border-top-color: ${s.color}` }),
        s.label))),
    el("p", { class: "footnote", style: "margin:10px 0 0" },
      `Fitted on ${G.meta.n_rows.toLocaleString()} player-seasons ` +
      `(${G.meta.n_players.toLocaleString()} players, ${fmtSeason(G.meta.first_season)}–` +
      `${fmtSeason(G.meta.last_season)}, 14 leagues). Each curve holds starting value, ` +
      "league and season fixed, so the gaps between positions are age-and-role effects " +
      "rather than price differences — real teenagers gain more than the curve shows " +
      "because they also start cheaper. Ages are plotted where at least " +
      `${G.meta.min_n} player-seasons support them.`));
  main.append(card);
  return growthCurves(host, series);
}

function leagueName(slug) {
  return slug.split("-").map(w => w[0].toUpperCase() + w.slice(1)).join(" ")
    .replace("Laliga2", "LaLiga 2").replace("Laliga", "LaLiga").replace("1 Hnl", "HNL");
}

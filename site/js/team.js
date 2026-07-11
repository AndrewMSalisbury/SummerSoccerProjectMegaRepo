// team.js — team page: coach history (sortable), season dumbbell chart,
// squad value trend, edge-state footnotes.

import { loadJSON, getParam, el, clear, showError, fmtSeason, fmtPpg,
         fmtSigned, fmtPoints, fmtMoney } from "./data.js";
import { initHeader, crestImg, coachImg, statTile, seasonSpan,
         sortableTable, gradeTier } from "./components.js";
import { dumbbellChart, lineChart } from "./charts.js";

initHeader();
init();

async function init() {
  const id = getParam("id");
  if (!id || !/^\d+$/.test(id)) return showError("No team id in the URL.");

  let t;
  try {
    t = await loadJSON(`data/teams/${id}.json`);
  } catch {
    return showError(`No team with id ${id}.`);
  }

  document.title = `${t.name} — Coach Valuation`;
  const main = document.querySelector("main");
  clear(main);

  main.append(renderHeader(t));
  main.append(renderSeasonChart(t));
  main.append(renderCoachHistory(t));
  main.append(renderValueTrends(t));
}

function renderHeader(t) {
  const a = t.aggregate;
  const head = el("div", { class: "entity-header" },
    crestImg(t.crest, t.name, "entity-photo crest"),
    el("div", { class: "entity-main" },
      el("h1", {}, t.name, t.is_b_team ? " " : null,
        t.is_b_team ? el("span", { class: "grade-chip", title:
          "Reserve side of a bigger club; the model includes a B-team adjustment" },
          "B team") : null),
      el("p", { class: "subtitle", style: "margin-bottom:4px" },
        `${t.leagues.join(" · ")} · ${a.n_seasons} seasons · ` +
        seasonSpan(a.first_season, a.last_season)),
      el("div", { class: "stat-row" },
        statTile("Mean residual", a.mean_residual != null
          ? `${fmtSigned(a.mean_residual)} PPG` : "—", "per season vs squad-value model"),
        a.best ? statTile("Best season", fmtSeason(a.best.season),
          `${fmtSigned(a.best.residual_points, 1)} pts vs expected`) : null,
        a.worst ? statTile("Toughest season", fmtSeason(a.worst.season),
          `${fmtSigned(a.worst.residual_points, 1)} pts vs expected`) : null)));
  return head;
}

let highlightSeason = null;

function renderSeasonChart(t) {
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Seasons: actual vs expected points"),
    el("div", { class: "chart-sub" },
      "Gray dot = points the squad-value model expected; colored dot = actual. " +
      "Click a season to highlight its coaches below."));
  const host = el("div", {});
  card.append(host, el("div", { class: "chart-legend" },
    el("span", { class: "key" },
      el("span", { class: "key-swatch", style: "background: var(--pos)" }),
      "finished above expectation"),
    el("span", { class: "key" },
      el("span", { class: "key-swatch", style: "background: var(--neg)" }),
      "below expectation"),
    el("span", { class: "key" },
      el("span", { class: "key-swatch", style: "background: var(--muted)" }),
      "expected points")));

  dumbbellChart(host, t.seasons, {
    onSelect: season => {
      highlightSeason = season;
      document.querySelectorAll("table.data tr[data-season]").forEach(tr => {
        tr.classList.toggle("highlight",
          season != null && Number(tr.dataset.season) === season);
      });
    },
  });

  const naSeasons = t.seasons.filter(s => s.residual_note);
  if (naSeasons.length) {
    card.append(el("p", { class: "footnote" },
      `${naSeasons.map(s => fmtSeason(s.season)).join(", ")}: no residual — ` +
      "insufficient market value data on Transfermarkt for that season."));
  }
  return card;
}

function renderCoachHistory(t) {
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Coach history"),
    el("div", { class: "chart-sub" },
      "Every stint in the dataset, with each coach's overall grade."));

  const rows = t.coach_history.map(r => ({ ...r }));

  const cols = [
    { label: "Season", render: r => fmtSeason(r.season) },
    { label: "Coach", render: r => r.coach
        ? el("a", { class: "cell-entity", href: `coach.html?id=${r.coach_id}` },
            coachImg(r.img, r.coach), r.coach)
        : el("span", { class: "muted" }, r.note || "unknown") },
    { label: "Grade", render: r => r.grade
        ? el("span", { title: `${r.grade.cut_label} cut` },
            el("span", { class: "grade-chip" + gradeTier(r.grade.letter) },
              r.grade.letter),
            el("span", { class: "muted" },
              ` #${r.grade.rank}·${r.grade.cut_label === "Top-5 leagues" ? "T5" : "All"}`))
        : el("span", { class: "muted" }, r.coach ? "unranked" : "") },
    { label: "From", render: r => r.date_from ?? "—" },
    { label: "Games", cls: "num", render: r => r.n_games ?? "—" },
    { label: "PPG", cls: "num", render: r => fmtPpg(r.actual_ppg) },
    { label: "Expected", cls: "num", render: r => fmtPpg(r.predicted_ppg) },
    { label: "Residual", cls: "num", render: r => r.residual_ppg == null
        ? el("span", { class: "muted" }, "—")
        : el("span", { class: r.residual_ppg >= 0 ? "delta-pos" : "delta-neg" },
            fmtSigned(r.residual_ppg)) },
  ];

  const host = el("div", {});
  card.append(host);
  const table = sortableTable(host, rows, cols, {
    chrono: { label: "Chronological",
      fn: (a, b) => a.season - b.season ||
        String(a.date_from ?? "").localeCompare(String(b.date_from ?? "")) },
    best: { label: "Best → worst",
      fn: (a, b) => (b.residual_ppg ?? -99) - (a.residual_ppg ?? -99) },
  }, "chrono");

  // rows carry data-season so chart clicks can highlight them
  observeSeasonTags(table.wrap);

  return card;
}

// Re-applies data-season attributes after every table (re)render, reading the
// season back off each row's first cell.
function observeSeasonTags(wrap) {
  const apply = () => {
    wrap.querySelectorAll("tbody tr").forEach(tr => {
      const seasonText = tr.querySelector("td")?.textContent ?? "";
      const y = Number(seasonText.slice(0, 4));
      if (y) tr.dataset.season = y;
      if (highlightSeason != null && y === highlightSeason) {
        tr.classList.add("highlight");
      }
    });
  };
  apply();
  new MutationObserver(apply).observe(wrap, { childList: true });
}

function renderValueTrends(t) {
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Squad value over time"),
    el("div", { class: "chart-sub" },
      "Two scales, two panels — total market value in euros, and the " +
      "minutes-weighted squad strength relative to the league average that season."));

  const grid = el("div", { style:
    "display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:16px" });

  const p1 = el("div", {},
    el("h3", { style: "margin-top:0" }, "Total squad value"));
  const h1 = el("div", {});
  p1.append(h1);
  lineChart(h1, t.seasons.map(s => ({ season: s.season, v: s.squad_value })),
    { fmt: fmtMoney, color: "var(--series-1)" });

  const p2 = el("div", {},
    el("h3", { style: "margin-top:0" }, "Weighted strength (× league average)"));
  const h2 = el("div", {});
  p2.append(h2);
  lineChart(h2, t.seasons.map(s => ({ season: s.season, v: s.norm_weighted })),
    { fmt: v => `${v.toFixed(2)}×`, color: "var(--series-2)" });

  grid.append(p1, p2);
  card.append(grid);
  return card;
}

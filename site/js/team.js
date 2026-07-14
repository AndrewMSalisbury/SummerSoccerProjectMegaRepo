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
  main.append(t.suggestions ? renderSuggestions(t) : renderSuggestionsNote());
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

// ---------- suggested coaches (recommender) ----------

function renderSuggestionsNote() {
  return el("div", { class: "chart-card suggest-card" },
    el("div", { class: "chart-title" }, "Suggested coaches"),
    el("p", { class: "chart-sub", style: "margin-bottom:0" },
      "Team-specific coach suggestions need SofaScore player-style data, " +
      "which covers the five major leagues from 2015/16 — this club has no " +
      "scored squad in the latest season. The overall coach ranking is on ",
      el("a", { href: "index.html" }, "the leaderboard"),
      "."));
}

function renderSuggestions(t) {
  const s = t.suggestions;
  const games = (t.seasons.find(x => x.season === s.season) || {}).games || 38;

  const card = el("div", { class: "chart-card suggest-card" },
    el("div", { class: "chart-title" },
      `Suggested coaches — ${fmtSeason(s.season)} squad`),
    el("div", { class: "chart-sub" },
      "Coaches who excelled with squads like this one, matched on the " +
      "player-type mix of their overperforming stints (descriptive). The full " +
      "candidate table, ranked by the validated quality score, follows below."));

  // ----- headline graphic: coaches who thrived with similar squads
  const grid = el("div", { class: "sim-grid" });
  const simMax = Math.max(...s.similar.map(m => m.similarity));
  const simMin = Math.min(...s.similar.map(m => m.similarity));
  s.similar.forEach((m, i) => {
    const span = Math.max(simMax - simMin, 0.001);
    const width = 25 + 75 * (m.similarity - simMin) / span;   // rank-scaled meter
    grid.append(el("a", { class: "sim-card-lg", href: `coach.html?id=${m.id}` },
      el("span", { class: "sim-rank" }, String(i + 1)),
      coachImg(m.img, m.name, "sim-photo"),
      el("div", { class: "sim-body" },
        el("div", { class: "sim-name" }, m.name,
          m.grade ? el("span", { title: `${m.grade.cut_label} cut` },
            el("span", {
              class: "grade-chip" + gradeTier(m.grade.letter),
              style: "margin-left:6px",
            }, m.grade.letter),
            el("span", { class: "muted", style: "font-weight:400" },
              ` ${m.grade.cut_label === "Top-5 leagues" ? "T5" : "All"}`)) : null),
        el("div", { class: "sim-meter", title:
          `${Math.round(m.similarity * 100)}% squad-mix similarity` },
          el("span", { style: `width:${width}%` })),
        el("div", { class: "muted" },
          `${Math.round(m.similarity * 100)}% match · ` +
          `${fmtSigned(m.mean_residual)} PPG over ${m.n_stints} big-5 stints`))));
  });
  card.append(grid);

  card.append(el("h3", { style: "margin:20px 0 4px" },
    "All candidates by validated quality"),
    el("p", { class: "chart-sub" },
      "Each coach's shrinkage-adjusted career overperformance (points per game " +
      "above squad-value expectation, vs a league-average coach). Fit and shape " +
      "columns are exploratory — they describe this squad specifically but did " +
      "not improve out-of-sample forecasts. Use the chips to filter by career " +
      "plausibility."));

  // ----- filter chips
  const filters = {
    league:   { label: "Has coached in this league",  on: false, test: c => c.this_league },
    country:  { label: "This country",                on: false, test: c => c.this_country },
    big5:     { label: "Big-5 proven",                on: false, test: c => c.big5 },
    level:    { label: `Similar level (±${s.level_band})`, on: false,
                test: c => c.club_level != null &&
                  Math.abs(c.club_level - s.team_level) <= s.level_band },
    active:   { label: "Recently active",             on: false,
                test: c => c.last_season >= s.active_since },
    domestic: { label: "Domestic coach",              on: false, test: c => c.domestic },
  };
  const chipRow = el("div", { class: "chip-row" });
  for (const [key, f] of Object.entries(filters)) {
    const chip = el("button", { class: "filter-chip", type: "button",
      onclick: () => { f.on = !f.on; chip.classList.toggle("on", f.on); draw(); },
    }, f.label);
    chipRow.append(chip);
  }
  card.append(chipRow);

  // ----- table
  const host = el("div", { class: "suggest-wrap" });
  card.append(host);

  const pts = v => `${fmtSigned(v * games, 1)} pts`;
  const explCell = v => el("span", { class: "muted" },
    v === 0 ? "—" : `${fmtSigned(v)} (${fmtSigned(v * games, 1)})`);

  const cols = [
    { label: "Coach", render: c => el("a", { class: "cell-entity",
        href: `coach.html?id=${c.id}` }, coachImg(c.img, c.name), c.name) },
    { label: "Grade", render: c => el("span",
        { title: `Rank ${c.grade.rank} — ${c.grade.cut_label} cut` },
        el("span", { class: "grade-chip" + gradeTier(c.grade.letter) },
          c.grade.letter),
        el("span", { class: "muted" },
          ` ${c.grade.cut_label === "Top-5 leagues" ? "T5" : "All"}`)) },
    { label: "Quality (validated)", cls: "num", render: c =>
        el("span", { class: c.quality >= 0 ? "delta-pos" : "delta-neg",
          title: `${fmtSigned(c.quality)} PPG vs an average coach; 95% interval ` +
                 `${fmtSigned(c.lo)} to ${fmtSigned(c.hi)} PPG on the full score` },
          pts(c.quality)) },
    { label: "Fit (exploratory)", cls: "num", render: c =>
        c.tier === "full" ? explCell(c.fit) : el("span", { class: "muted" }, "n/a") },
    { label: "Shape (exploratory)", cls: "num", render: c =>
        c.tier === "full" ? explCell(c.deployment) : el("span", { class: "muted" }, "n/a") },
    { label: "Career", render: c => badgeCell(c, s) },
  ];

  function draw() {
    clear(host);
    const rows = s.coaches.filter(c =>
      Object.values(filters).every(f => !f.on || f.test(c)));
    if (!rows.length) {
      host.append(el("p", { class: "footnote" },
        "No suggested coaches match the active filters."));
      return;
    }
    sortableTable(host, rows, cols, {
      validated: { label: "Validated (quality)",
        fn: (a, b) => b.quality - a.quality },
      exploratory: { label: "Exploratory (quality + fit + shape)",
        fn: (a, b) => b.exploratory_total - a.exploratory_total },
    }, "validated");
  }
  draw();

  card.append(el("p", { class: "footnote" },
    "The headline cards are descriptive: coaches with ≥4 big-5 stints and a " +
    "positive career residual, matched on player-type mix — a judgment aid, " +
    "not a prediction. The quality score is validated out-of-sample on " +
    "historical appointments; fit (player-type match) and shape (formation vs " +
    "squad value) are exploratory layers that did not improve those forecasts. " +
    "Availability, wages, and contracts are not modeled (yes, this page will " +
    "happily suggest hiring Guardiola). See the writeup."));

  return card;
}

function badgeCell(c, s) {
  const wrap = el("span", { class: "badge-cell" });
  const badge = (txt, title) =>
    el("span", { class: "badge-mini", title }, txt);
  if (c.this_league) wrap.append(badge("league", "Has coached in this league"));
  else if (c.this_country) wrap.append(badge("country", "Has coached in this country"));
  if (c.big5) wrap.append(badge("big-5", "30+ games in the five major leagues"));
  if (c.domestic) wrap.append(badge("domestic", "Same nationality as this club's country"));
  if (c.club_level != null) {
    wrap.append(el("span", { class: "muted",
      title: "Career club level: squad-value percentile of the clubs coached " +
             `(this club: ${s.team_level})` }, `lvl ${Math.round(c.club_level)}`));
  }
  if (c.last_season < s.active_since) {
    wrap.append(el("span", { class: "badge-mini stale",
      title: "Not seen in the dataset since this season" },
      `last ${fmtSeason(c.last_season)}`));
  }
  return wrap;
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

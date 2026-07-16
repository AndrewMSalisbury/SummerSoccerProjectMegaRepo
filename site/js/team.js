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

  const card = el("div", { class: "chart-card suggest-card" },
    el("div", { class: "chart-title" },
      `Suggested coaches — ${fmtSeason(s.season)} squad`),
    el("div", { class: "chart-sub" },
      "Coaches who excelled with squads like this one — matched on the " +
      "player-type mix of their overperforming big-5 stints, with a tilt " +
      "toward overall coach quality (descriptive: a judgment aid, not a " +
      "prediction). Use the chips to filter by career plausibility."));

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

  // ----- similarity grid (the card's content; redrawn on every chip toggle)
  const gridHost = el("div", {});
  card.append(gridHost);
  const MAX_CARDS = 9;

  // ----- squad-fit pop-up drawer (built once; slides in from the right when a
  // card is clicked). Keeps the cards clean; detail lives here.
  const sfBody = el("div", { class: "sf-drawer-body" });
  const sfClose = el("button", { class: "sf-close", type: "button",
    "aria-label": "Close", onclick: () => closeDrawer() }, "×");
  const sfDrawer = el("aside", { class: "sf-drawer" }, sfClose, sfBody);
  const sfBackdrop = el("div", { class: "sf-backdrop", onclick: () => closeDrawer() });
  document.body.append(sfBackdrop, sfDrawer);

  function onKey(e) { if (e.key === "Escape") closeDrawer(); }
  function closeDrawer() {
    sfDrawer.classList.remove("open");
    sfBackdrop.classList.remove("open");
    document.removeEventListener("keydown", onKey);
  }
  function openDrawer(m) {
    clear(sfBody);
    sfBody.append(drawerContent(m, s));
    sfDrawer.classList.add("open");
    sfBackdrop.classList.add("open");
    document.addEventListener("keydown", onKey);
  }

  function draw() {
    clear(gridHost);
    const rows = s.similar.filter(c =>
      Object.values(filters).every(f => !f.on || f.test(c)));
    if (!rows.length) {
      gridHost.append(el("p", { class: "footnote" },
        "No coaches match the active filters."));
      return;
    }
    const shown = rows.slice(0, MAX_CARDS);
    const simMax = Math.max(...shown.map(m => m.similarity));
    const simMin = Math.min(...shown.map(m => m.similarity));
    const span = Math.max(simMax - simMin, 0.001);
    const grid = el("div", { class: "sim-grid" });
    shown.forEach(m => {
      const width = 25 + 75 * (m.similarity - simMin) / span; // rank-scaled meter
      grid.append(el("a", { class: "sim-card-lg", href: `coach.html?id=${m.id}`,
        title: "Click for squad fit · ctrl/⌘-click for full profile",
        onclick: (e) => {
          // normal click pops the squad-fit drawer; let power-users
          // ctrl/⌘/middle-click through to the coach profile (the href)
          if (e.metaKey || e.ctrlKey || e.shiftKey || e.button === 1) return;
          e.preventDefault();
          openDrawer(m);
        } },
        // rank in the unfiltered ordering — stable under filters
        el("span", { class: "sim-rank" }, String(m.rank)),
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
            `${fmtSigned(m.mean_residual)} PPG over ${m.n_stints} big-5 stints`),
          badgeCell(m, s))));
    });
    gridHost.append(grid);
    if (rows.length > MAX_CARDS) {
      gridHost.append(el("p", { class: "footnote" },
        `Showing the ${MAX_CARDS} closest matches of the ${rows.length} ` +
        "coaches that pass the filters."));
    }
  }
  draw();

  // The validated-quality candidate table is intentionally not rendered
  // (2026-07-13, second revision — Andrew wasn't convinced it adds much on a
  // team page, since its order is team-independent). The data still ships in
  // t.suggestions.coaches, so restoring it is a frontend-only change.

  card.append(el("p", { class: "footnote" },
    "Descriptive, not a validated prediction: coaches with ≥4 big-5 stints " +
    "and a positive career residual, ordered by squad-mix similarity blended " +
    "with a small weight on overall coach quality (85/15) — so a slightly " +
    "less similar but stronger coach can rank above a close match. Card " +
    "numbers are each coach's rank in the full ordering and don't change " +
    "when filters are applied. The model's out-of-sample-tested quality " +
    "ranking is on the leaderboard. Availability, wages, and contracts are " +
    "not modeled (yes, this page will happily suggest hiring Guardiola). " +
    "See the writeup."));

  return card;
}

// Contents of the coach pop-up drawer for one similar coach: an at-a-glance
// dossier (career span, preferred formations, clubs coached, leagues) plus the
// squad-fit diagnostic (Squad_Fit_Gap_Design.md) — which of the squad's value
// his usual shapes leave idle / where they are thin, in € and slots, never in
// points (the deployment layer is exploratory, not a validated hiring signal).
function drawerContent(m, s) {
  const wrap = el("div", {});
  const c = m.career;

  // ----- header
  wrap.append(el("div", { class: "sf-drawer-head" },
    coachImg(m.img, m.name, "sf-drawer-photo"),
    el("div", { style: "min-width:0" },
      el("div", { class: "sf-drawer-name" }, m.name,
        m.grade ? el("span", { title: `${m.grade.cut_label} cut`,
          class: "grade-chip" + gradeTier(m.grade.letter),
          style: "margin-left:8px" }, m.grade.letter) : null),
      m.grade ? el("div", { class: "muted", style: "font-size:11.5px;margin-top:3px" },
        `Overall grade · ${m.grade.cut_label} cut`) : null)));

  // ----- headline stat tiles
  const tiles = el("div", { class: "sf-stats" },
    sfStat(`${Math.round(m.similarity * 100)}%`, "squad-mix match"),
    sfStat(fmtSigned(m.mean_residual), `PPG over ${m.n_stints} big-5 stints`));
  if (c) tiles.append(sfStat(
    c.first_season === c.last_season ? `${c.first_season}`
      : `${c.first_season}–${String(c.last_season).slice(2)}`,
    `${c.n_teams} club${c.n_teams === 1 ? "" : "s"} · ${c.total_games} games`));
  wrap.append(tiles);

  wrap.append(badgeCell(m, s));

  // ----- preferred formations
  if (c && c.formations && c.formations.length) {
    wrap.append(el("div", { class: "sf-section-title" }, "Preferred formations"));
    const list = el("div", { class: "sf-forms" });
    c.formations.forEach(f => {
      list.append(el("div", { class: "sf-form-row" },
        el("span", { class: "sf-form-name" }, f.formation),
        el("span", { class: "sf-form-bar" },
          el("span", { style: `width:${f.pct}%` })),
        el("span", { class: "sf-form-pct muted" }, `${f.pct}%`)));
    });
    wrap.append(list);
    wrap.append(el("div", { class: "sf-rigid muted" }, rigidityLabel(c.rigidity)));
  }

  // ----- clubs coached
  if (c && c.teams && c.teams.length) {
    wrap.append(el("div", { class: "sf-section-title" }, "Clubs coached"));
    const chips = el("div", { class: "sf-clubs" });
    c.teams.forEach(t => {
      chips.append(el("span", { class: "sf-club",
        title: `${t.games} games` },
        t.name, el("span", { class: "sf-club-span" }, t.span)));
    });
    wrap.append(chips);
    if (c.n_teams > c.teams.length) {
      chips.append(el("span", { class: "sf-club sf-club-more" },
        `+${c.n_teams - c.teams.length} more`));
    }
    if (c.leagues && c.leagues.length) {
      wrap.append(el("div", { class: "sf-rigid muted" },
        `Leagues: ${c.leagues.join(" · ")}`));
    }
  }

  // ----- squad fit
  wrap.append(el("div", { class: "sf-section-title" }, `Squad fit at ${s_teamName()}`));
  const detail = el("div", { class: "sf-detail" });
  const sf = m.squad_fit;
  if (!sf) {
    detail.append(el("div", { class: "sf-line" },
      "No squad-fit detail available for this coach."));
  } else {
    const strand = sf.strand || [], gaps = sf.gaps || [];
    if (strand.length) {
      detail.append(el("div", { class: "sf-sub" }, "Squad value his shapes underuse"));
      const max = Math.max(...strand.map(x => x.eur_m), 1);
      const bars = el("div", { class: "sf-bars" });
      strand.forEach(x => {
        bars.append(el("div", { class: "sf-bar-row" },
          el("span", { class: "sf-bar-label" }, x.label),
          el("span", { class: "sf-bar-track" },
            el("span", { class: "sf-bar-fill",
              style: `width:${Math.max(6, 100 * x.eur_m / max)}%` })),
          el("span", { class: "sf-bar-val" }, `€${x.eur_m}m`)));
      });
      detail.append(bars);
    }
    if (gaps.length) {
      detail.append(el("div", { class: "sf-sub" }, "Positions his shapes fill only with a stretch"));
      const chips = el("div", { class: "sf-gap-chips" });
      gaps.forEach(g => chips.append(el("span", { class: "sf-gap-chip" }, g.label)));
      detail.append(chips);
    }
    if (!strand.length && !gaps.length) detail.append(el("div", { class: "sf-line" },
      "Natural fits across the pitch — his usual shapes leave little squad " +
      "value out of position."));
  }
  detail.append(el("div", { class: "sf-note" },
    "Which of the squad's value his usual formations tend to leave out — a " +
    "descriptive shape fit, not a points forecast."));
  wrap.append(detail);

  wrap.append(el("a", { class: "sf-profile-link", href: `coach.html?id=${m.id}` },
    "View full coach profile →"));
  return wrap;
}

function sfStat(value, label) {
  return el("div", { class: "sf-stat" },
    el("div", { class: "sf-stat-val" }, value),
    el("div", { class: "sf-stat-lbl muted" }, label));
}

// The suggestions block doesn't carry the team name, but the page <h1> does.
function s_teamName() {
  const h1 = document.querySelector("h1");
  return h1 ? h1.childNodes[0].textContent.trim() : "this squad";
}

// rigidity in [0,1]: higher = more fixed a shape (cr_rigidity).
function rigidityLabel(r) {
  if (r == null) return "";
  if (r >= 0.66) return "Sticks tightly to his usual shape";
  if (r >= 0.48) return "Fairly consistent shape across squads";
  if (r >= 0.32) return "Adapts his shape to the squad";
  return "Highly flexible — reshapes often";
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

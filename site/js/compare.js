// compare.js — side-by-side comparison of two graded coaches.
//
// Restricted to the graded coaches: everyone else has no BLUP, no interval
// and no attack/defence split, so a comparison of two of them would be an empty
// page. Every number on the page is read from ONE cut (the two cuts use
// separate grading curves, so mixing them would be meaningless) — the toggle
// picks it, and every grade renders with its cut label.

import { loadJSON, getParam, el, clear, showError, fmtSeason, fmtPpg,
         fmtSigned, fmtPoints } from "./data.js";
import { initHeader, coachImg, crestImg, gradeTier, statTile,
         siteMeta } from "./components.js";
import { careerChart, compareCI, strengthBarsPair, compareStyle, spectrumBar,
         COMPARE_COLORS } from "./charts.js";

const SIDES = ["a", "b"];

const state = {
  index: [],          // graded coaches from leaderboard.json (all-leagues list)
  byId: new Map(),
  coach: { a: null, b: null },
  cut: null,          // "top5" | "14league"
};

// One document-level click handler for "close the open dropdown", rather than
// one per combobox: render() rebuilds the pickers on every interaction, so
// per-instance listeners would pile up against detached nodes.
const outsideClick = [];
document.addEventListener("click", e => {
  for (const fn of outsideClick) fn(e);
});

initHeader();
init().catch(e => showError(`Could not load the comparison: ${e.message}`));

async function init() {
  let lb;
  try {
    lb = await loadJSON("data/leaderboard.json");
    state.ssSpan = (await siteMeta().catch(() => null))?.dataset?.sofascore_span ?? null;
  } catch {
    return showError("Could not load site data. If you opened this file " +
      "directly, serve the site/ folder instead: python -m http.server.");
  }
  // the all-leagues cut ranks every graded coach; the top-5 cut is a subset
  state.index = lb.all14.coaches;
  state.nCoaches = lb.n_coaches;
  for (const c of state.index) state.byId.set(String(c.id), c);

  await Promise.all(SIDES.map(async side => {
    const id = getParam(side);
    if (id && state.byId.has(id)) state.coach[side] = await fetchCoach(id);
  }));

  render();
}

async function fetchCoach(id) {
  try {
    return await loadJSON(`data/coaches/${id}.json`);
  } catch {
    return null;
  }
}

// ---------- cut handling ----------

// A coach JSON carries its headline rating plus the other cut where it exists.
function ratingFor(c, cut) {
  if (!c || !c.rating) return null;
  if (c.rating.cut === cut) return c.rating;
  const o = c.rating.other_cut;
  return o && o.cut === cut ? o : null;
}

// Every top-5-graded coach is also graded on all 14 leagues, so the all-leagues
// cut is always common ground; top-5 is offered when both coaches are in it.
function availableCuts() {
  const { a, b } = state.coach;
  if (!a || !b) return [];
  const cuts = [];
  if (ratingFor(a, "top5") && ratingFor(b, "top5")) cuts.push("top5");
  if (ratingFor(a, "14league") && ratingFor(b, "14league")) cuts.push("14league");
  return cuts;
}

function cutLabel(cut) {
  return cut === "top5" ? "Top-5 leagues" : "All leagues";
}

// strengths ship for the headline cut plus an always-14-league copy, so the
// split can follow whichever cut the page is showing
function strengthsFor(c, cut) {
  if (!c) return null;
  if (c.strengths && c.strengths.cut === cut) return c.strengths;
  if (cut === "14league" && c.strengths_all14) return c.strengths_all14;
  return null;
}

function setParam(side, id) {
  const q = new URLSearchParams(window.location.search);
  if (id) q.set(side, id); else q.delete(side);
  history.replaceState(null, "", `?${q.toString()}`);
}

async function pick(side, id) {
  setParam(side, id);
  state.coach[side] = id ? await fetchCoach(id) : null;
  state.cut = null;   // re-resolve: the new pair may not share the old cut
  render();
}

// ---------- page ----------

function render() {
  const main = document.querySelector("main");
  clear(main);
  outsideClick.length = 0;   // the pickers about to be rebuilt re-register

  const { a, b } = state.coach;
  const cuts = availableCuts();
  if (!state.cut || !cuts.includes(state.cut)) state.cut = cuts[0] || null;

  document.title = a && b
    ? `${a.name} vs ${b.name} — Coach Valuation`
    : "Compare coaches — Coach Valuation";

  main.append(
    el("h1", {}, "Compare coaches"),
    el("p", { class: "subtitle" },
      "Two coaches side by side, on the same grading curve — and an honest " +
      "answer on whether the gap between them is one this data can actually see."));

  main.append(pickerRow());

  if (!a || !b) {
    main.append(emptyState());
    return;
  }

  main.append(cutRow(cuts));
  main.append(verdictCard());
  main.append(factsCard());
  main.append(careersCard());

  const st = renderStrengths();
  if (st) main.append(st);
  const sy = renderStyle();
  if (sy) main.append(sy);
  const fm = renderFormations();
  if (fm) main.append(fm);
  const hh = renderSharedClubs();
  if (hh) main.append(hh);

  main.append(el("p", { class: "footnote" },
    "Both coaches are shown on the ", el("strong", {}, cutLabel(state.cut)),
    " cut. The two cuts are separate grading curves fitted on different sets of " +
    "league-seasons, so a grade from one is not comparable with a grade from " +
    "the other — which is why this page never mixes them. See ",
    el("a", { href: "writeup.html#the-two-cuts" }, "how it works"), "."));
}

// ---------- pickers ----------

function pickerRow() {
  const row = el("div", { class: "cmp-picker-row" });
  SIDES.forEach((side, i) => {
    row.append(pickerSlot(side, COMPARE_COLORS[i]));
    if (i === 0) row.append(el("div", { class: "cmp-vs" }, "vs"));
  });
  return row;
}

function pickerSlot(side, color) {
  const c = state.coach[side];
  const slot = el("div", { class: "cmp-slot", style: `--cmp-hue: ${color}` });

  if (c) {
    const r = c.rating;
    slot.append(el("div", { class: "cmp-slot-filled" },
      coachImg(c.img, c.name, "cmp-photo"),
      el("div", { style: "min-width:0" },
        el("div", { class: "cmp-slot-name" },
          el("a", { href: `coach.html?id=${c.id}` }, c.name)),
        el("div", { class: "muted" },
          `${c.career.n_stints} stints · ${c.career.total_games} games · ` +
          `${fmtSeason(c.career.first_season)}–${fmtSeason(c.career.last_season)}`)),
      el("button", { class: "cmp-clear", type: "button", "aria-label": "Change coach",
        onclick: () => pick(side, null) }, "×")));
    return slot;
  }

  slot.append(el("div", { class: "cmp-slot-empty" },
    el("div", { class: "cmp-slot-label" },
      side === "a" ? "First coach" : "Second coach"),
    combobox(side)));
  return slot;
}

// Text input + filtered list, same idiom as the header search. Restricted to
// graded coaches, ordered by rank so typing nothing still shows the best.
function combobox(side) {
  const input = el("input", { type: "search", autocomplete: "off",
    placeholder: `Search ${state.index.length.toLocaleString()} graded coaches…`,
    "aria-label": "Search coaches" });
  const results = el("div", { class: "search-results" });
  const wrap = el("div", { class: "cmp-combo search-box" }, input, results);

  const other = side === "a" ? "b" : "a";
  let items = [], active = -1;

  function draw() {
    const q = input.value.trim().toLowerCase();
    const taken = state.coach[other] ? String(state.coach[other].id) : null;
    const rows = state.index
      .filter(c => String(c.id) !== taken)
      .filter(c => !q || c.name.toLowerCase().includes(q))
      .slice(0, 40);
    clear(results);
    items = [];
    active = -1;
    if (!rows.length) {
      results.append(el("div", { class: "empty" }, "No graded coach matches"));
      results.classList.add("open");
      return;
    }
    for (const c of rows) {
      const a = el("a", { href: "#", class: "cmp-option",
        onclick: e => { e.preventDefault(); pick(side, String(c.id)); } },
        coachImg(c.img, c.name, "mini face"),
        el("span", { style: "flex:1; min-width:0" }, c.name),
        el("span", { class: "grade-chip" + gradeTier(c.letter_grade) },
          c.letter_grade),
        el("span", { class: "muted" }, `#${c.rank}`));
      results.append(a);
      items.push(a);
    }
    results.classList.add("open");
  }

  input.addEventListener("focus", draw);
  input.addEventListener("input", draw);
  input.addEventListener("keydown", e => {
    if (!items.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      active = (active + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items.forEach((a, i) => a.classList.toggle("active", i === active));
      items[active].scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter" && active >= 0) {
      e.preventDefault();
      items[active].click();
    } else if (e.key === "Escape") {
      results.classList.remove("open");
    }
  });
  outsideClick.push(e => {
    if (!wrap.contains(e.target)) results.classList.remove("open");
  });
  return wrap;
}

function emptyState() {
  const card = el("div", { class: "card" },
    el("p", { style: "margin-top:0" },
      "Pick two coaches above. Both must be graded — a coach needs at least " +
      "three stints and 109 league games in the graded seasons before the model " +
      `will put a number on him, which leaves ${state.index.length.toLocaleString()} ` +
      `of the ${state.nCoaches.toLocaleString()} in the data.`));

  const top = state.index;
  const quick = [];
  if (top.length >= 4) {
    quick.push([top[0], top[1]], [top[2], top[3]]);
  }
  if (top.length >= 2) {
    const pool = top.slice(0, Math.min(60, top.length));
    const i = Math.floor(Math.random() * pool.length);
    let j = Math.floor(Math.random() * pool.length);
    if (j === i) j = (j + 1) % pool.length;
    quick.push([pool[i], pool[j]]);
  }
  if (quick.length) {
    card.append(el("div", { class: "cmp-quick" },
      el("span", { class: "muted" }, "Try:"),
      ...quick.map(([x, y]) => el("a", {
        class: "filter-chip", href: `compare.html?a=${x.id}&b=${y.id}` },
        `${x.name} vs ${y.name}`))));
  }
  return card;
}

function cutRow(cuts) {
  const row = el("div", { class: "chart-controls" },
    el("span", { class: "muted" }, "Grading curve"));
  const toggle = el("div", { class: "seg-toggle", role: "group" });
  for (const cut of cuts) {
    toggle.append(el("button", { type: "button",
      class: cut === state.cut ? "active" : "",
      onclick: () => { state.cut = cut; render(); } }, cutLabel(cut)));
  }
  row.append(toggle);
  if (cuts.length === 1) {
    row.append(el("span", { class: "muted" },
      "only one of these two is graded in the top-5 cut, so the comparison " +
      "runs on all 14 leagues"));
  }
  return row;
}

// ---------- verdict ----------

function series() {
  return SIDES.map((side, i) => ({
    side,
    coach: state.coach[side],
    name: state.coach[side].name,
    color: COMPARE_COLORS[i],
    rating: ratingFor(state.coach[side], state.cut),
  }));
}

function overlaps(x, y) {
  if (!x || !y) return null;
  return !(x[1] < y[0] || y[1] < x[0]);
}

function verdictCard() {
  const [A, B] = series();
  const card = el("div", { class: "chart-card cmp-verdict" });

  const lead = A.rating.blup >= B.rating.blup ? A : B;
  const trail = lead === A ? B : A;
  const gap = lead.rating.blup - trail.rating.blup;
  const perSeason = gap * 38;

  card.append(el("div", { class: "cmp-verdict-line" },
    el("strong", {}, lead.name), " grades ahead of ", el("strong", {}, trail.name)));
  card.append(el("div", { class: "cmp-verdict-num" },
    `${fmtSigned(gap, 3)} PPG`,
    el("span", { class: "muted" },
      ` · about ${perSeason.toFixed(1)} points over a 38-game season`)));

  const ov = overlaps(lead.rating.ci, trail.rating.ci);
  if (ov === null) {
    card.append(el("p", { class: "cmp-caveat" },
      "One of these two has no confidence interval in the data, so there is no " +
      "call to make on whether the gap is real."));
  } else if (ov) {
    card.append(el("p", { class: "cmp-caveat warn" },
      el("strong", {}, "This gap is not one the data can separate. "),
      "Over the stints they actually coached, their 95% intervals overlap — " +
      `${lead.name} averaged ${fmtSigned(lead.rating.mean_residual)} PPG above ` +
      `expectation (${fmtSigned(lead.rating.ci[0])} to ${fmtSigned(lead.rating.ci[1])}) ` +
      `and ${trail.name} ${fmtSigned(trail.rating.mean_residual)} ` +
      `(${fmtSigned(trail.rating.ci[0])} to ${fmtSigned(trail.rating.ci[1])}). ` +
      "Read the ordering as a best guess, not a finding."));
  } else {
    card.append(el("p", { class: "cmp-caveat ok" },
      el("strong", {}, "This gap holds up. "),
      "Their 95% intervals do not overlap: even at the pessimistic end of " +
      `${lead.name}'s record and the optimistic end of ${trail.name}'s, the ` +
      "ordering is the same."));
  }

  const host = el("div", {});
  card.append(host);
  compareCI(host, [A, B].map(s => ({
    name: s.name, blup: s.rating.mean_residual, ci: s.rating.ci, color: s.color,
  })));

  card.append(el("p", { class: "footnote" },
    "The bars are each coach's ", el("strong", {}, "raw career average"),
    " above squad-value expectation, with its 95% interval — the quantity the " +
    "uncertainty is measured on. The grade above them is the ",
    el("em", {}, "shrunk"), " version of the same thing: thin records are pulled " +
    "toward the middle, so a coach with a spectacular handful of seasons grades " +
    "below his raw average. That is why the two numbers differ, and why the " +
    "ordering by grade can differ from the ordering by raw average."));
  return card;
}

// ---------- facts table ----------

function factsCard() {
  const [A, B] = series();
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "The two records"),
    el("div", { class: "chart-sub" },
      `Grades and ranks on the ${cutLabel(state.cut)} cut; stints, clubs and ` +
      "games are full-career totals across all 14 leagues."));

  const rows = [
    ["Grade", s => el("span", { class: "grade-chip" + gradeTier(s.rating.letter_grade) },
      s.rating.letter_grade)],
    ["Rank", s => `${s.rating.rank} of ${s.rating.n_ranked}`],
    ["Grade (BLUP)", s => `${fmtSigned(s.rating.blup, 3)} PPG`],
    ["Career mean residual", s => el("span",
      { class: s.rating.mean_residual >= 0 ? "delta-pos" : "delta-neg" },
      `${fmtSigned(s.rating.mean_residual)} PPG`)],
    ["95% interval", s => s.rating.ci
      ? `${fmtSigned(s.rating.ci[0])} to ${fmtSigned(s.rating.ci[1])}` : "—"],
    ["Significant after FDR", s => s.rating.significant ? "Yes" : "No"],
    ["Stints", s => String(s.coach.career.n_stints)],
    ["Clubs", s => String(s.coach.career.n_clubs)],
    ["Games", s => String(s.coach.career.total_games)],
    ["Seasons", s => `${fmtSeason(s.coach.career.first_season)}–` +
      `${fmtSeason(s.coach.career.last_season)}`],
    ["Leagues", s => s.coach.career.leagues.join(", ")],
  ];

  const table = el("table", { class: "data cmp-table" },
    el("thead", {}, el("tr", {},
      el("th", {}, ""),
      ...[A, B].map(s => el("th", {},
        el("span", { class: "cmp-key", style: `background:${s.color}` }), s.name)))),
    el("tbody", {}, rows.map(([label, fn]) => el("tr", {},
      el("td", { class: "muted" }, label),
      ...[A, B].map(s => el("td", {}, fn(s)))))));
  card.append(el("div", { class: "table-wrap" }, table));
  return card;
}

// ---------- careers ----------

function careersCard() {
  const [A, B] = series();
  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Career points per game"),
    el("div", { class: "chart-sub" },
      "Each crest is one stint; the dashed line is the squad-value model's " +
      "expected PPG. Both charts share one vertical axis, so the height of a " +
      "point means the same thing on either side."));

  // one domain across both careers: separate axes would make a modest record
  // look like a strong one
  const vals = [...A.coach.stints, ...B.coach.stints]
    .flatMap(s => [s.actual_ppg, s.predicted_ppg]).filter(v => v != null);
  const yDomain = [Math.max(0, Math.floor(Math.min(...vals) * 4) / 4 - 0.25),
                   Math.ceil(Math.max(...vals) * 4) / 4 + 0.25];

  const grid = el("div", { class: "cmp-grid" });
  for (const s of [A, B]) {
    const host = el("div", {});
    grid.append(el("div", {},
      el("h3", { class: "cmp-col-title" },
        el("span", { class: "cmp-key", style: `background:${s.color}` }), s.name),
      host));
    careerChart(host, s.coach.stints, { mode: "chrono", yDomain });
  }
  card.append(grid);
  return card;
}

// ---------- attack / defence ----------

function renderStrengths() {
  const [A, B] = series();
  const sa = strengthsFor(A.coach, state.cut), sb = strengthsFor(B.coach, state.cut);
  if (!sa || !sb) return null;

  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Where the edge comes from"),
    el("div", { class: "chart-sub" },
      "The same overperformance the grades are built on, split into goals " +
      "scored above what the squad's value predicts and goals conceded below " +
      `it. Positive is better on both rows. ${cutLabel(state.cut)} cut.`));

  const host = el("div", {});
  card.append(host);
  strengthBarsPair(host, [
    { name: A.name, color: A.color, s: sa },
    { name: B.name, color: B.color, s: sb },
  ]);

  card.append(el("p", { class: "footnote" },
    "The scale is fixed across every coach on the site, which is why the " +
    "defence row is the shorter one for almost everyone: the coach effect " +
    "really is larger on goals scored than on goals conceded. This re-cuts a " +
    "number the project already trusts rather than making a new claim. See ",
    el("a", { href: "writeup.html#step-3-the-residual" }, "how it works"), "."));
  return card;
}

// ---------- style ----------

function renderStyle() {
  const [A, B] = series();
  const A_ = A.coach.style, B_ = B.coach.style;
  if (!A_ || !B_) {
    const missing = [!A_ ? A.name : null, !B_ ? B.name : null].filter(Boolean);
    return el("div", { class: "chart-card" },
      el("div", { class: "chart-title" }, "Style of the teams they coached"),
      el("p", { class: "muted", style: "margin-bottom:0" },
        `Not available for ${missing.join(" or ")} — the style data covers the ` +
        "big-5 leagues from 2015/16, and only coaches with at least 38 games " +
        "of it are profiled."));
  }

  const byKey = new Map(B_.axes.map(a => [a.key, a]));
  const axes = A_.axes
    .filter(a => byKey.has(a.key))
    .map(a => ({ key: a.key, label: a.label, coach_owned: a.coach_owned,
                 a: a.pct, b: byKey.get(a.key).pct }));

  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Style of the teams they coached"),
    el("div", { class: "chart-sub" },
      "What their teams actually did on the pitch, as a percentile among the " +
      `${A_.n_pool} coaches with big-5 style data ` +
      `(${fmtSeason(A_.seasons[0])}–${fmtSeason(A_.seasons[1])}).`));

  const host = el("div", {});
  card.append(host);
  compareStyle(host, axes, [
    { name: A.name, color: A.color }, { name: B.name, color: B.color }]);

  card.append(el("div", { class: "chart-legend" },
    el("span", { class: "key" },
      el("span", { class: "key-dot" }),
      "the two axes the coach owns more than the club does")));

  const ph = el("div", { class: "ph-block" },
    el("div", { class: "ph-title" }, "Where the ball is won back"));
  const phHost = el("div", {});
  ph.append(phHost);
  spectrumBar(phHost, {
    leftLabel: "Deep block",
    rightLabel: "High press",
    markers: [
      { pct: A_.pressing_height.pct, color: A.color, name: A.name },
      { pct: B_.pressing_height.pct, color: B.color, name: B.name },
    ],
  });
  const blended = [A_.pressing_height.blended ? A.name : null,
                   B_.pressing_height.blended ? B.name : null].filter(Boolean);
  ph.append(el("p", { class: "footnote", style: "margin-top:2px" },
    "Measured per season rather than per match." +
    (blended.length
      ? ` Most of ${blended.join(" and ")}'s seasons shared a club with another ` +
        "coach, so that figure is substantially the club's."
      : "")));
  card.append(ph);

  card.append(el("p", { class: "footnote" },
    "This is the style of their ", el("em", {}, "teams"), ", not their styles in " +
    "the abstract: it is co-produced with the squads they were given. On seven " +
    "of these nine axes the club explains more of the variation than the coach " +
    "does. Descriptive only — none of these axes predicts coaching quality once " +
    "club size is accounted for, so a difference here is not a reason to prefer " +
    "either man. See ",
    el("a", { href: "writeup.html#coach-page" }, "how it works"), "."));
  return card;
}

// ---------- formations ----------

function renderFormations() {
  const [A, B] = series();
  if (!A.coach.formations || !B.coach.formations) return null;

  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Preferred formations"),
    el("div", { class: "chart-sub" },
      "How their matches split across formations, weighted toward recent " +
      `seasons (SofaScore big-5 data, ${state.ssSpan ?? "the big-5 seasons"}).`));

  const grid = el("div", { class: "cmp-grid" });
  for (const s of [A, B]) {
    const f = s.coach.formations;
    const col = el("div", {},
      el("h3", { class: "cmp-col-title" },
        el("span", { class: "cmp-key", style: `background:${s.color}` }), s.name));
    const list = el("div", { class: "sf-forms" });
    const shapes = f.shapes.filter(x => x.pct >= 1);
    (shapes.length ? shapes : f.shapes.slice(0, 1)).forEach(x => {
      list.append(el("div", { class: "sf-form-row" },
        el("span", { class: "sf-form-name" }, x.formation),
        el("span", { class: "sf-form-bar" },
          el("span", { style: `width:${x.pct}%; background:${s.color}` })),
        el("span", { class: "sf-form-pct muted" }, `${x.pct}%`)));
    });
    col.append(list, el("div", { class: "sf-rigid muted", style: "margin-top:8px" },
      rigidityLabel(f.rigidity)));
    grid.append(col);
  }
  card.append(grid);
  return card;
}

// rigidity in [0,1]: higher = more fixed a shape (cr_rigidity).
function rigidityLabel(r) {
  if (r == null) return "";
  if (r >= 0.66) return "Sticks tightly to his usual shape.";
  if (r >= 0.48) return "Fairly consistent shape across squads.";
  if (r >= 0.32) return "Adapts his shape to the squad.";
  return "Highly flexible — reshapes often.";
}

// ---------- same club, different manager ----------

// The cleanest comparison available, and the rarest: only about 5% of pairs
// ever worked at the same club, so this section is usually absent.
function renderSharedClubs() {
  const [A, B] = series();
  const byClub = s => {
    const m = new Map();
    for (const st of s.coach.stints) {
      if (st.residual_ppg == null) continue;
      const cur = m.get(st.team_id) || { team: st.team, crest: st.crest,
        games: 0, pts: 0, exp: 0, seasons: [] };
      cur.games += st.n_games;
      cur.pts += st.actual_ppg * st.n_games;
      cur.exp += st.predicted_ppg * st.n_games;
      cur.seasons.push(st.season);
      m.set(st.team_id, cur);
    }
    return m;
  };
  const ma = byClub(A), mb = byClub(B);
  const shared = [...ma.keys()].filter(k => mb.has(k));
  if (!shared.length) return null;

  const card = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "Same club, different manager"),
    el("div", { class: "chart-sub" },
      "Both of them worked at these clubs. Not the same squad — years apart, " +
      "different players — but the closest thing to a like-for-like the data holds."));

  const table = el("table", { class: "data" },
    el("thead", {}, el("tr", {},
      el("th", {}, "Club"), el("th", {}, "Coach"),
      el("th", {}, "Seasons"), el("th", { class: "num" }, "Games"),
      el("th", { class: "num" }, "PPG"), el("th", { class: "num" }, "Expected"),
      el("th", { class: "num" }, "Residual"))));
  const body = el("tbody", {});
  for (const id of shared) {
    [[ma.get(id), A], [mb.get(id), B]].forEach(([v, s], i) => {
      const ppg = v.pts / v.games, exp = v.exp / v.games;
      const yrs = [...new Set(v.seasons)].sort((x, y) => x - y);
      body.append(el("tr", {},
        el("td", {}, i === 0
          ? el("a", { class: "cell-entity", href: `team.html?id=${id}` },
              crestImg(v.crest, v.team), v.team)
          : ""),
        el("td", {},
          el("span", { class: "cmp-key", style: `background:${s.color}` }), s.name),
        el("td", { class: "muted" }, yrs.length === 1
          ? fmtSeason(yrs[0])
          : `${fmtSeason(yrs[0])}–${fmtSeason(yrs[yrs.length - 1])}`),
        el("td", { class: "num" }, String(v.games)),
        el("td", { class: "num" }, fmtPpg(ppg)),
        el("td", { class: "num" }, fmtPpg(exp)),
        el("td", { class: "num" }, el("span",
          { class: ppg - exp >= 0 ? "delta-pos" : "delta-neg" },
          fmtSigned(ppg - exp)))));
    });
  }
  table.append(body);
  card.append(el("div", { class: "table-wrap" }, table));
  card.append(el("p", { class: "footnote" },
    "Expected PPG already accounts for how good each squad was at the time, so " +
    "the residual is comparable even when one of them inherited a much better " +
    "team. A single spell is still a small sample."));
  return card;
}

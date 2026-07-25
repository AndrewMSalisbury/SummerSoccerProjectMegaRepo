// builder.js — the team-builder page (Docs/Team_Builder_Design.md).
//
// Build an XI on a drawn pitch: pick any of the 22 observed formations, click
// a slot to choose a player-season from the big-5 pool (2015/16–2024/25),
// then get the same descriptive coach-similarity grid the team pages show —
// computed here in the browser against the user's XI (cosine similarity on
// archetype shares, 85/15 similarity/quality blend, identical to
// se_suggestions() in site_export.R).

import {
  loadJSON, el, svgEl, clear, fmtSeason, fmtMoney, fmtSigned, showError,
} from "./data.js";
import {
  initHeader, coachImg, crestImg, gradeTier, silhouetteSvg,
} from "./components.js";

initHeader();

// mirrors se_league_countries for the five builder-relevant leagues
const LEAGUE_COUNTRY = {
  "premier-league": "England", "laliga": "Spain", "serie-a": "Italy",
  "bundesliga": "Germany", "ligue-1": "France",
};
const LEAGUE_NAMES = {
  "premier-league": "Premier League", "laliga": "La Liga",
  "serie-a": "Serie A", "bundesliga": "Bundesliga", "ligue-1": "Ligue 1",
};

// unknown TM position label -> weakly playable anywhere (0.9 × 0.35, the
// same default as cr_tm_position_slot in coach_recommender.R)
const UNKNOWN_POS_ELIG = 0.315;

const state = {
  meta: null,
  players: null,          // raw array
  playersById: new Map(),
  coaches: null,
  formation: "4-3-3",
  // one entry per slot index (0 = GK): {pid, y} or null
  picks: [],
  bench: [],              // displaced picks: {pid, y}
  leagueContext: null,    // slug or null
  benchReason: null,      // label above the bench strip
  loaded: null,           // "Club · 2024/25" when started from a real squad
};

main().catch(e => showError(`Failed to load the team builder: ${e.message}`));

async function main() {
  const [meta, players, coaches] = await Promise.all([
    loadJSON("data/builder/meta.json"),
    loadJSON("data/builder/players.json"),
    loadJSON("data/builder/coaches.json"),
  ]);
  state.meta = meta;
  state.players = players;
  state.coaches = coaches;
  for (const p of players) state.playersById.set(p.id, p);

  state.formation = meta.formations.some(f => f.name === "4-3-3")
    ? "4-3-3" : meta.formations[0].name;
  state.picks = formationOf(state.formation).slots.map(() => null);

  readHash();
  render();
}

// ---------- data helpers ----------

function formationOf(name) {
  return state.meta.formations.find(f => f.name === name);
}

function seasonOf(pick) {
  const p = state.playersById.get(pick.pid);
  return p ? p.seasons.find(s => s.y === pick.y) : null;
}

// eligibility of one player-season for one slot type (0..1)
function eligibility(player, season, slotType) {
  if (season.pos === "Goalkeeper") return slotType === "GK" ? 1 : 0;
  if (slotType === "GK") return 0;
  if (season.arch) {
    const row = state.meta.eligibility[season.arch];
    return row ? (row[slotType] ?? 0) : 0;
  }
  const row = state.meta.tm_position_eligibility[season.pos];
  return row ? (row[slotType] ?? 0) : UNKNOWN_POS_ELIG;
}

function pickedIds() {
  const ids = new Set();
  for (const p of state.picks) if (p) ids.add(p.pid);
  for (const p of state.bench) ids.add(p.pid);
  return ids;
}

function xiValue() {
  let v = 0;
  for (const pick of state.picks) {
    const s = pick && seasonOf(pick);
    if (s && s.v != null) v += s.v;
  }
  return v;
}

function filledCount() {
  return state.picks.filter(Boolean).length;
}

// the archetype mix is built from outfielders only, so that is what the
// suggestions threshold counts
const MIN_OUTFIELD_FOR_SUGGESTIONS = 7;

function outfieldCount() {
  const f = formationOf(state.formation);
  return state.picks.filter((p, i) => p && f.slots[i].type !== "GK").length;
}

// share vector over the 10 outfield picks, equal-weighted (the builder analog
// of the minutes-weighted stint shares the coach profiles are built from)
function xiShares() {
  const shares = {};
  const f = formationOf(state.formation);
  let n = 0;
  state.picks.forEach((pick, i) => {
    if (!pick || f.slots[i].type === "GK") return;
    const s = seasonOf(pick);
    if (!s) return;
    n += 1;
    if (s.arch) shares[s.arch] = (shares[s.arch] || 0) + 1;
  });
  if (n === 0) return null;
  for (const k of Object.keys(shares)) shares[k] /= n;
  return shares;
}

// percentile of the XI value within the exported per-club best-XI values
function xiLevel() {
  const key = state.leagueContext || "big5";
  const dist = state.meta.xi_values[key] || state.meta.xi_values.big5;
  if (!dist || !dist.length) return null;
  const v = xiValue() / 1e6;
  let below = 0;
  for (const d of dist) if (d < v) below += 1;
  return Math.round(100 * below / dist.length);
}

// ---------- URL hash persistence ----------

function writeHash() {
  const parts = state.picks.map(p => (p ? `${p.pid}.${p.y}` : "")).join(",");
  const h = `#f=${encodeURIComponent(state.formation)}&s=${parts}`;
  history.replaceState(null, "", h);
}

function readHash() {
  const h = window.location.hash.replace(/^#/, "");
  if (!h) return;
  const q = new URLSearchParams(h);
  const f = q.get("f");
  if (f && formationOf(f)) {
    state.formation = f;
    state.picks = formationOf(f).slots.map(() => null);
  }
  const s = q.get("s");
  if (!s) return;
  const slots = formationOf(state.formation).slots;
  s.split(",").forEach((tok, i) => {
    if (!tok || i >= slots.length) return;
    const [pid, y] = tok.split(".").map(Number);
    const player = state.playersById.get(pid);
    const season = player && player.seasons.find(se => se.y === y);
    if (!player || !season) return;
    if (eligibility(player, season, slots[i].type) < state.meta.eligibility_floor) return;
    if ([...Array(i).keys()].some(j => state.picks[j] && state.picks[j].pid === pid)) return;
    state.picks[i] = { pid, y };
  });
}

// ---------- formation switching (keep picks where eligible) ----------

// Seat a set of picks into a formation's slots. Two priorities, because the
// two callers are asking different questions:
//  - switching formation KEEPS an XI the user already chose, so the best-fitting
//    (pick, slot) pair wins each round — the GK reclaims the GK slot before a
//    stretch fit can steal anything.
//  - loading a real squad is CHOOSING an XI out of 14-28 players, so value leads
//    and fit only breaks ties; a first pass at natural/capable fit (>= 0.5)
//    stops an expensive forward occupying left-back while a real one sits out.
// Returns {seated, bench} and mutates nothing.
function assignToSlots(picks, slots, { byValue = false } = {}) {
  const seated = slots.map(() => null);
  const floor = state.meta.eligibility_floor;
  const seasonFor = pick => {
    const player = state.playersById.get(pick.pid);
    return player ? player.seasons.find(s => s.y === pick.y) : null;
  };

  if (byValue) {
    const byVal = (a, b) => (seasonFor(b)?.v ?? -1) - (seasonFor(a)?.v ?? -1);
    let remaining = [...picks].sort(byVal);
    for (const threshold of [0.5, floor]) {
      const left = [];
      for (const pick of remaining) {          // most valuable first
        const season = seasonFor(pick);
        if (!season) continue;                 // stale pick: drop it
        const player = state.playersById.get(pick.pid);
        let best = null;
        slots.forEach((slot, i) => {
          if (seated[i]) return;
          const e = eligibility(player, season, slot.type);
          if (e >= threshold && (!best || e > best.e)) best = { i, e };
        });
        if (best) seated[best.i] = pick; else left.push(pick);
      }
      remaining = left;
    }
    return { seated, bench: remaining };
  }

  const remaining = [...picks];
  while (remaining.length) {
    let best = null;
    for (const pick of remaining) {
      const season = seasonFor(pick);
      if (!season) continue;
      const player = state.playersById.get(pick.pid);
      slots.forEach((slot, i) => {
        if (seated[i]) return;
        const e = eligibility(player, season, slot.type);
        if (e >= floor && (!best || e > best.e)) best = { pick, i, e };
      });
    }
    if (!best) break;
    seated[best.i] = best.pick;
    remaining.splice(remaining.indexOf(best.pick), 1);
  }
  return { seated, bench: remaining };
}

function switchFormation(name) {
  const oldPicks = state.picks.filter(Boolean).concat(state.bench);
  state.formation = name;
  const { seated, bench } = assignToSlots(oldPicks, formationOf(name).slots);
  state.picks = seated;
  state.bench = bench;
}

// ---------- starting from a real squad ----------

// Every club-season present in the player pool, newest first. Built once.
let squadCache = null;
function squadIndex() {
  if (squadCache) return squadCache;
  const m = new Map();
  for (const p of state.players) {
    // 83 of the 18,638 exported player-seasons repeat the same (player, club,
    // season) row, so a squad would otherwise list a player twice
    const seen = new Set();
    for (const s of p.seasons) {
      const key = `${s.club_id}|${s.y}`;
      if (seen.has(key)) continue;
      seen.add(key);
      let e = m.get(key);
      if (!e) {
        e = { key, club: s.club, clubId: s.club_id, y: s.y, lg: s.lg, players: [] };
        m.set(key, e);
      }
      e.players.push({ pid: p.id, y: s.y });
    }
  }
  squadCache = [...m.values()]
    .sort((a, b) => b.y - a.y || a.club.localeCompare(b.club));
  return squadCache;
}

// Seat a real squad into the current shape. The pool behind this page is the
// players who actually played that season (a SofaScore archetype needs minutes,
// keepers need 600+), so this is that squad's regulars — not the club's literal
// team sheet, and the copy says so.
function loadSquad(entry) {
  const { seated, bench } = assignToSlots(
    entry.players.map(x => ({ pid: x.pid, y: x.y })),
    formationOf(state.formation).slots, { byValue: true });
  state.picks = seated;
  state.bench = bench;
  state.benchReason = `Rest of the ${entry.club} ${fmtSeason(entry.y)} squad`;
  state.loaded = `${entry.club} · ${fmtSeason(entry.y)}`;
  // the club's own league is the sensible default context for the filter chips
  state.leagueContext = entry.lg;
  closePicker();
  render();
}

function randomSquad() {
  const all = squadIndex();
  loadSquad(all[Math.floor(Math.random() * all.length)]);
}

function openSquadPicker() {
  closePicker();
  const all = squadIndex();
  const input = el("input", { type: "search", autocomplete: "off",
    placeholder: "Search clubs…", "aria-label": "Search clubs" });
  const listHost = el("div", { class: "picker-list" });
  const MAX_ROWS = 60;

  function draw() {
    clear(listHost);
    const q = input.value.trim().toLowerCase();
    const rows = q ? all.filter(e => e.club.toLowerCase().includes(q)) : all;
    if (!rows.length) {
      listHost.append(el("div", { class: "picker-empty" }, "No clubs match."));
      return;
    }
    for (const e of rows.slice(0, MAX_ROWS)) {
      listHost.append(el("div", { class: "picker-row",
        onclick: () => loadSquad(e) },
        crestImg(`assets/crests/${e.clubId}.png`, e.club, "picker-photo"),
        el("div", { class: "picker-main" },
          el("div", { class: "picker-name" }, e.club),
          el("div", { class: "picker-sub" },
            el("span", { class: "picker-arch" }, LEAGUE_NAMES[e.lg] ?? e.lg))),
        el("div", { class: "picker-right" },
          el("span", { class: "picker-value" }, fmtSeason(e.y)),
          el("span", { class: "picker-nseasons" },
            `${e.players.length} players`))));
    }
    if (rows.length > MAX_ROWS) {
      listHost.append(el("div", { class: "picker-empty" },
        `…and ${rows.length - MAX_ROWS} more — type a club name to narrow.`));
    }
  }
  input.addEventListener("input", draw);

  modalNode = el("div", { class: "builder-modal",
    onclick: e => { if (e.target === modalNode) closePicker(); } },
    el("div", { class: "modal-card", role: "dialog", "aria-modal": "true" },
      el("div", { class: "modal-head" },
        el("div", { class: "chart-title" }, "Start from a real squad"),
        el("button", { class: "modal-close", type: "button",
          onclick: closePicker }, "×")),
      el("div", { class: "modal-search" }, input),
      el("p", { class: "footnote", style: "margin:0 0 6px" },
        `${all.length} club-seasons across the big five leagues, ` +
        "2015/16–2024/25. The XI is that squad's most valuable players who fit " +
        "your current shape; everyone else goes to the bench."),
      listHost));
  document.body.append(modalNode);
  document.addEventListener("keydown", escClose);
  draw();
  input.focus();
}

// place a benched pick into the best empty eligible slot
function placeFromBench(pick) {
  const slots = formationOf(state.formation).slots;
  const player = state.playersById.get(pick.pid);
  const season = player.seasons.find(s => s.y === pick.y);
  let best = null;
  slots.forEach((slot, i) => {
    if (state.picks[i]) return;
    const e = eligibility(player, season, slot.type);
    if (e >= state.meta.eligibility_floor && (!best || e > best.e)) best = { i, e };
  });
  if (!best) return false;
  state.picks[best.i] = pick;
  state.bench = state.bench.filter(b => b !== pick);
  return true;
}

// ---------- page render ----------

function render() {
  writeHash();
  const main = document.querySelector("main");
  clear(main);

  main.append(
    el("h1", { class: "page-title" }, "Team builder"),
    el("p", { class: "subtitle" },
      "Build your own XI from every big-5 player-season since 2015/16, then " +
      "see which coaches thrived with squads shaped like yours. Click a " +
      "circle to fill a position — or start from a squad that really existed."),
    startRow());

  const layout = el("div", { class: "builder-layout" },
    el("div", {}, pitchCard(), benchStrip()),
    el("div", {}, readoutCard(), formationCard()));
  main.append(layout, suggestionsCard());
}

// An empty pitch asking for eleven clicks before it does anything is the page's
// worst moment; these two buttons make the first one produce a whole team.
function startRow() {
  return el("div", { class: "builder-start" },
    el("button", { class: "builder-start-btn", type: "button",
      onclick: openSquadPicker }, "Load a real squad"),
    el("button", { class: "builder-reset", type: "button",
      onclick: randomSquad }, "Surprise me"),
    el("span", { class: "muted" },
      "then swap anyone out — it stays your XI"));
}

function formationCard() {
  const card = el("div", { class: "chart-card formation-card" },
    el("div", { class: "chart-title" }, "Formation"));
  const groups = new Map();
  for (const f of state.meta.formations) {
    const label = f.family.startsWith("back3") ? "Back three / five" : "Back four";
    if (!groups.has(label)) groups.set(label, []);
    groups.get(label).push(f);
  }
  for (const [label, fs] of groups) {
    card.append(el("div", { class: "formation-group-label" }, label));
    const grid = el("div", { class: "formation-grid" });
    for (const f of fs) {
      grid.append(el("button", {
        class: "formation-chip" + (f.name === state.formation ? " on" : ""),
        type: "button",
        onclick: () => {
          if (f.name === state.formation) return;
          switchFormation(f.name);
          render();
        },
      }, f.name));
    }
    card.append(grid);
  }
  return card;
}

function resetButton() {
  return el("button", {
    class: "builder-reset", type: "button",
    onclick: () => {
      state.picks = formationOf(state.formation).slots.map(() => null);
      state.bench = [];
      state.benchReason = null;
      state.loaded = null;
      render();
    },
  }, "Clear team");
}

// writeHash() has always round-tripped the whole XI through the URL; nothing
// ever told anyone, so the button is the entire feature.
function shareButton() {
  const btn = el("button", { class: "builder-reset", type: "button" }, "Copy link");
  btn.addEventListener("click", async () => {
    const url = window.location.href;
    try {
      await navigator.clipboard.writeText(url);
      btn.textContent = "Link copied";
    } catch {
      // clipboard blocked (insecure origin, permissions): select it instead so
      // the reader can still copy by hand
      const box = el("input", { class: "share-fallback", value: url,
        readonly: "", "aria-label": "Shareable link" });
      btn.replaceWith(box);
      box.select();
      return;
    }
    setTimeout(() => { btn.textContent = "Copy link"; }, 1800);
  });
  return btn;
}

// ---------- pitch ----------

function pitchCard() {
  const f = formationOf(state.formation);
  const pitch = el("div", { class: "builder-pitch" }, pitchSvg());

  f.slots.forEach((slot, i) => {
    const pick = state.picks[i];
    const topPct = 92 - 0.85 * slot.y;
    const leftPct = 8 + 0.84 * slot.x;
    const pickTitle = pick ? (() => {
      const p = state.playersById.get(pick.pid);
      return `${p.name} — ${fmtSeason(pick.y)} (click to change)`;
    })() : `Pick a ${slotLabel(slot)}`;
    const btn = el("button", {
      class: "pitch-slot" + (pick ? " filled" : ""),
      type: "button",
      style: `top:${topPct}%;left:${leftPct}%`,
      title: pickTitle,
      onclick: () => openPicker(i),
    });

    if (pick) {
      const player = state.playersById.get(pick.pid);
      const season = seasonOf(pick);
      btn.append(playerFace(player, "slot-photo"));
      btn.append(el("span", { class: "slot-name" }, shortName(player.name)));
      // season as a small corner pill — the top-left of the circle is photo
      // background (contain leaves side gaps), so it never covers the face
      btn.append(el("span", { class: "slot-season" },
        fmtSeason(season.y).slice(2)));
      const x = el("span", {
        class: "slot-remove", role: "button", title: "Remove",
        onclick: e => {
          e.stopPropagation();
          state.picks[i] = null;
          render();
        },
      }, "×");
      btn.append(x);
    } else {
      btn.append(el("span", { class: "slot-empty" }, slotAbbr(slot)));
    }
    pitch.append(btn);
  });

  return el("div", { class: "chart-card builder-card" }, pitch);
}

function pitchSvg() {
  const s = svgEl("svg", { viewBox: "0 0 100 132", class: "pitch-lines",
                           "aria-hidden": "true" });
  const line = attrs => svgEl("rect", { fill: "none", ...attrs });
  s.append(
    line({ x: 2, y: 2, width: 96, height: 128, rx: 1.5 }),
    // halfway line + circle (own half is the bottom)
    svgEl("line", { x1: 2, y1: 66, x2: 98, y2: 66 }),
    svgEl("circle", { cx: 50, cy: 66, r: 9, fill: "none" }),
    // own box (bottom) and opponent box (top)
    line({ x: 26, y: 114, width: 48, height: 16 }),
    line({ x: 38, y: 124, width: 24, height: 6 }),
    line({ x: 26, y: 2, width: 48, height: 16 }),
    line({ x: 38, y: 2, width: 24, height: 6 }));
  return s;
}

const SLOT_LABELS = {
  GK: "goalkeeper", CB: "centre-back", FB: "fullback / wing-back",
  DM: "holding midfielder", CM: "central midfielder",
  AM: "attacking midfielder", W: "winger / wide forward", ST: "striker",
};

function slotLabel(slot) {
  const side = slot.side === "L" ? "left " : slot.side === "R" ? "right " : "";
  return side + SLOT_LABELS[slot.type];
}

function slotAbbr(slot) {
  return (slot.side && slot.type !== "CB" ? slot.side : "") + slot.type;
}

function shortName(name) {
  const parts = name.split(" ");
  if (parts.length === 1) return name;
  // keep surname particles: "Kevin De Bruyne" -> "De Bruyne", not "Bruyne"
  const particle = /^(de|del|der|den|di|da|dos|du|el|la|le|van|von|ter|ten|mac|st\.)$/i;
  let i = parts.length - 1;
  while (i > 0 && particle.test(parts[i - 1])) i -= 1;
  return parts.slice(Math.max(i, 1)).join(" ");
}

// player photo with initials fallback (players lack photos until the scrape
// completes; the circle never breaks)
function playerFace(player, cls) {
  if (player.photo) {
    const img = el("img", { class: cls, src: player.photo, alt: player.name,
                            loading: "lazy" });
    img.addEventListener("error", () => img.replaceWith(initialsFace(player.name, cls)));
    return img;
  }
  return initialsFace(player.name, cls);
}

function initialsFace(name, cls) {
  const initials = name.split(/[\s-]+/).filter(Boolean)
    .map(w => w[0]).slice(0, 2).join("").toUpperCase();
  return el("span", { class: `${cls} initials` }, initials);
}

// ---------- bench ----------

function benchStrip() {
  if (!state.bench.length) return null;
  const strip = el("div", { class: "builder-bench" },
    el("span", { class: "muted" },
      `${state.benchReason || "Displaced by the formation change"} — click to place: `));
  for (const pick of state.bench) {
    const player = state.playersById.get(pick.pid);
    strip.append(el("button", {
      class: "bench-chip", type: "button",
      title: "Place into the best empty slot",
      onclick: () => { if (placeFromBench(pick)) render(); },
    },
      playerFace(player, "bench-photo"),
      `${shortName(player.name)} ${fmtSeason(pick.y)}`,
      el("span", {
        class: "slot-remove", role: "button", title: "Remove",
        onclick: e => {
          e.stopPropagation();
          state.bench = state.bench.filter(b => b !== pick);
          render();
        },
      }, "×")));
  }
  return strip;
}

// ---------- team readout ----------

function readoutCard() {
  const filled = filledCount();
  const card = el("div", { class: "chart-card builder-readout" },
    el("div", { class: "readout-head" },
      el("div", {},
        el("div", { class: "chart-title" }, "Your team"),
        state.loaded
          ? el("div", { class: "muted", style: "font-size:12.5px" },
              `Started from ${state.loaded}`)
          : null),
      el("div", { class: "readout-actions" }, shareButton(), resetButton())));

  card.append(el("div", { class: "readout-stats" },
    stat("Players", `${filled} / 11`),
    stat("XI value", fmtMoney(xiValue())),
    stat("Value level", filled === 11 && xiLevel() != null
      ? `p${xiLevel()}`
      : "—",
      filled === 11
        ? `percentile vs ${state.leagueContext
            ? LEAGUE_NAMES[state.leagueContext] : "big-5"} best XIs, ${fmtSeason(state.meta.season)}`
        : "fill all 11 slots")));

  const shares = xiShares();
  if (shares) {
    card.append(el("div", { class: "chart-sub", style: "margin-top:10px" },
      "Player-type mix (outfield)"));
    const bar = el("div", { class: "arch-bar" });
    const order = Object.keys(state.meta.archetype_labels);
    for (const a of order) {
      if (!shares[a]) continue;
      bar.append(el("span", {
        class: `arch-seg arch-${a[0].toLowerCase()}`,
        style: `flex-grow:${shares[a]}`,
        title: `${state.meta.archetype_labels[a]} — ${Math.round(shares[a] * 100)}%`,
      }, shares[a] >= 0.15 ? a : ""));
    }
    card.append(bar);
    card.append(el("p", { class: "footnote" },
      "Values are nominal per season — a cross-era XI mixes transfer-market " +
      "inflation eras. Archetypes are each player's observed style in the " +
      "season you picked."));
  }
  return card;
}

function stat(label, value, hint) {
  return el("div", { class: "stat-tile" },
    el("div", { class: "label" }, label),
    el("div", { class: "value" }, value),
    hint ? el("div", { class: "hint" }, hint) : null);
}

// ---------- picker ----------

let modalNode = null;

function closePicker() {
  if (modalNode) { modalNode.remove(); modalNode = null; }
}

function openPicker(slotIdx, initialQuery = "") {
  closePicker();
  const f = formationOf(state.formation);
  const slot = f.slots[slotIdx];
  const floor = state.meta.eligibility_floor;
  const taken = pickedIds();
  const current = state.picks[slotIdx];
  if (current) taken.delete(current.pid);

  // One row per player, sorted by career-peak market value. The browse list
  // holds Natural/Capable players (eligibility >= 0.5); Stretch-only players
  // (>= floor) exist but surface only when a search query matches them.
  const rows = [];
  for (const p of state.players) {
    const seasons = p.seasons
      .map(s => ({ s, e: eligibility(p, s, slot.type) }))
      .filter(x => x.e >= floor);
    if (!seasons.length) continue;
    const main = seasons.filter(x => x.e >= 0.5);
    const group = main.length ? main : seasons;
    const peak = group.reduce((a, b) => ((b.s.v ?? -1) > (a.s.v ?? -1) ? b : a));
    const bestElig = Math.max(...group.map(x => x.e));
    rows.push({
      p, seasons, peak: peak.s,
      stretchOnly: !main.length,
      tier: bestElig >= 1 ? null : bestElig >= 0.5 ? "Capable" : "Stretch",
      taken: taken.has(p.id),
    });
  }
  rows.sort((a, b) => (b.peak.v ?? -1) - (a.peak.v ?? -1));
  const mainRows = rows.filter(r => !r.stretchOnly);
  const stretchRows = rows.filter(r => r.stretchOnly);

  const input = el("input", {
    type: "search", placeholder: "Search players…", autocomplete: "off",
    value: initialQuery, "aria-label": "Search players",
  });
  const listHost = el("div", { class: "picker-list" });
  const MAX_ROWS = 80;

  function draw() {
    clear(listHost);
    const q = input.value.trim().toLowerCase();
    const hit = r => r.p.name.toLowerCase().includes(q);
    const match = q ? mainRows.filter(hit) : mainRows;
    const stretch = q ? stretchRows.filter(hit) : [];
    if (!match.length && !stretch.length) {
      listHost.append(el("div", { class: "picker-empty" }, "No matches."));
      return;
    }
    for (const r of match.slice(0, MAX_ROWS)) {
      listHost.append(pickerRow(r, slotIdx, slot, () => input.value));
    }
    if (match.length > MAX_ROWS) {
      listHost.append(el("div", { class: "picker-empty" },
        `…and ${match.length - MAX_ROWS} more — type to narrow.`));
    }
    if (stretch.length) {
      listHost.append(el("div", { class: "picker-tier" },
        "Out of position (stretch)",
        el("span", { class: "muted" }, ` · ${stretch.length}`)));
      for (const r of stretch.slice(0, MAX_ROWS)) {
        listHost.append(pickerRow(r, slotIdx, slot, () => input.value));
      }
    }
  }

  input.addEventListener("input", draw);

  modalNode = el("div", { class: "builder-modal",
    onclick: e => { if (e.target === modalNode) closePicker(); } },
    el("div", { class: "modal-card", role: "dialog", "aria-modal": "true" },
      el("div", { class: "modal-head" },
        el("div", { class: "chart-title" }, `Pick a ${slotLabel(slot)}`),
        el("button", { class: "modal-close", type: "button",
          onclick: closePicker }, "×")),
      el("div", { class: "modal-search" }, input),
      listHost));
  document.body.append(modalNode);
  document.addEventListener("keydown", escClose);
  draw();
  input.focus();
}

function escClose(e) {
  if (e.key === "Escape") {
    closePicker();
    document.removeEventListener("keydown", escClose);
  }
}

function pickerRow(r, slotIdx, slot, getQuery) {
  const peak = r.peak;
  const row = el("div", {
    class: "picker-row" + (r.taken ? " taken" : ""),
    onclick: () => {
      if (r.taken) return;
      if (r.seasons.length === 1) {
        state.picks[slotIdx] = { pid: r.p.id, y: r.seasons[0].s.y };
        closePicker();
        render();
      } else {
        openSeasonChooser(slotIdx, slot, r, getQuery());
      }
    },
  },
    playerFace(r.p, "picker-photo"),
    el("div", { class: "picker-main" },
      el("div", { class: "picker-name" }, r.p.name,
        r.tier ? el("span", { class: "picker-arch picker-tag",
          title: r.tier === "Capable"
            ? "Playable here, but not the natural position"
            : "Well outside the natural position" }, r.tier) : null,
        r.taken ? el("span", { class: "muted" }, "  already in your XI") : null),
      el("div", { class: "picker-sub" },
        el("span", { class: "picker-club" },
          crestImg(`assets/crests/${peak.club_id}.png`, peak.club, "mini"),
          ` ${peak.club}`),
        el("span", { class: "picker-arch" },
          peak.arch ? state.meta.archetype_labels[peak.arch] : peak.pos))),
    el("div", { class: "picker-right" },
      el("span", { class: "picker-value",
        title: `career-peak value (${fmtSeason(peak.y)})` },
        peak.v != null ? fmtMoney(peak.v) : "—"),
      el("span", { class: "picker-nseasons" },
        r.seasons.length > 1
          ? `${r.seasons.length} seasons`
          : fmtSeason(r.seasons[0].s.y))));
  return row;
}

// second step of the picker: choose which season of the player to place
function openSeasonChooser(slotIdx, slot, r, backQuery) {
  closePicker();
  const listHost = el("div", { class: "picker-list" });
  for (const { s, e } of r.seasons) {   // ships newest-first
    listHost.append(el("div", { class: "picker-row",
      onclick: () => {
        state.picks[slotIdx] = { pid: r.p.id, y: s.y };
        closePicker();
        render();
      },
    },
      el("span", { class: "season-year" }, fmtSeason(s.y)),
      el("div", { class: "picker-main" },
        el("div", { class: "picker-sub" },
          el("span", { class: "picker-club" },
            crestImg(`assets/crests/${s.club_id}.png`, s.club, "mini"),
            ` ${s.club}`),
          el("span", { class: "picker-arch" },
            s.arch ? state.meta.archetype_labels[s.arch] : s.pos),
          e < 0.5 ? el("span", { class: "picker-arch picker-tag",
            title: "Well outside the natural position" }, "Stretch") : null)),
      el("div", { class: "picker-right" },
        el("span", { class: "picker-value" },
          s.v != null ? fmtMoney(s.v) : "—"))));
  }

  modalNode = el("div", { class: "builder-modal",
    onclick: e => { if (e.target === modalNode) closePicker(); } },
    el("div", { class: "modal-card", role: "dialog", "aria-modal": "true" },
      el("div", { class: "modal-head" },
        el("div", { class: "modal-head-player" },
          el("button", { class: "modal-back", type: "button",
            onclick: () => openPicker(slotIdx, backQuery) }, "‹ Back"),
          playerFace(r.p, "picker-photo"),
          el("div", { class: "chart-title" }, r.p.name)),
        el("button", { class: "modal-close", type: "button",
          onclick: closePicker }, "×")),
      el("div", { class: "chart-sub", style: "padding:0 16px 8px" },
        `Choose a season — ${slotLabel(slot)}`),
      listHost));
  document.body.append(modalNode);
  document.addEventListener("keydown", escClose);
}

// ---------- coach suggestions ----------

function suggestionsCard() {
  const card = el("div", { class: "chart-card suggest-card" },
    el("div", { class: "chart-title" }, "Coaches for this team"),
    el("div", { class: "chart-sub" },
      "Coaches who excelled with squads like yours — matched on the " +
      "player-type mix of their overperforming big-5 stints, with a tilt " +
      "toward overall coach quality (descriptive: a judgment aid, not a " +
      "prediction)."));

  // xiShares() already normalises over whatever outfield picks exist, so a
  // partial XI needs no different maths — only a warning that it will move.
  // Below seven outfielders the mix is too thin for the shares to mean much.
  const filled = filledCount();
  const outfield = outfieldCount();
  if (outfield < MIN_OUTFIELD_FOR_SUGGESTIONS) {
    card.append(el("p", { class: "footnote", style: "margin-top:4px" },
      `Pick ${MIN_OUTFIELD_FOR_SUGGESTIONS} outfield players to see suggestions ` +
      `(${outfield}/${MIN_OUTFIELD_FOR_SUGGESTIONS}) — or load a real squad above ` +
      "to fill the whole XI at once."));
    return card;
  }
  if (filled < 11) {
    card.append(el("p", { class: "builder-provisional" },
      el("strong", {}, "Provisional — "),
      `${filled} of 11 places filled. These are matched on the mix you have so ` +
      "far, and will move as you fill the rest."));
  }

  const shares = xiShares();
  const ranked = rankCoaches(shares);

  // league context enables the league/country/domestic chips
  const ctxSel = el("select", { class: "builder-select",
    "aria-label": "League context" },
    el("option", { value: "" }, "None (big-5 wide)"));
  for (const [slug, name] of Object.entries(LEAGUE_NAMES)) {
    ctxSel.append(el("option", {
      value: slug, selected: slug === state.leagueContext ? "" : null }, name));
  }
  ctxSel.addEventListener("change", () => {
    state.leagueContext = ctxSel.value || null;
    render();
  });
  card.append(el("div", { class: "builder-control", style: "margin-bottom:10px" },
    "League context ", ctxSel,
    el("span", { class: "muted", style: "margin-left:8px" },
      "sets which league the league / country / domestic filters mean")));

  const ctx = state.leagueContext;
  const country = ctx ? LEAGUE_COUNTRY[ctx] : null;
  const level = xiLevel();
  const band = state.meta.level_band;

  const filters = {
    league:  { label: "Has coached in this league", on: false, needsCtx: true,
               test: c => ctx && c.leagues.includes(ctx) },
    country: { label: "This country", on: false, needsCtx: true,
               test: c => country && c.countries.includes(country) },
    big5:    { label: "Big-5 proven", on: false, test: c => c.big5 },
    // an incomplete XI is worth less than a full one, so its value percentile
    // would quietly point this filter at the wrong tier of club
    level:   { label: `Similar level (±${band})`, on: false, needsFull: true,
               test: c => c.club_level != null && level != null &&
                 Math.abs(c.club_level - level) <= band },
    active:  { label: "Recently active", on: false,
               test: c => c.last_season >= state.meta.active_since },
    domestic: { label: "Domestic coach", on: false, needsCtx: true,
                test: c => country && c.nationality === country },
  };
  const chipRow = el("div", { class: "chip-row" });
  for (const [, fdef] of Object.entries(filters)) {
    const disabled = (fdef.needsCtx && !ctx) || (fdef.needsFull && filled < 11);
    const chip = el("button", {
      class: "filter-chip" + (disabled ? " disabled" : ""),
      type: "button",
      title: disabled
        ? (fdef.needsFull && filled < 11
            ? "Fill all 11 places — a partial XI has no meaningful value level"
            : "Pick a league context to use this filter")
        : null,
      onclick: () => {
        if (disabled) return;
        fdef.on = !fdef.on;
        chip.classList.toggle("on", fdef.on);
        draw();
      },
    }, fdef.label);
    if (disabled) fdef.on = false;
    chipRow.append(chip);
  }
  card.append(chipRow);

  const gridHost = el("div", {});
  card.append(gridHost);
  const MAX_CARDS = 9;

  function draw() {
    clear(gridHost);
    const rows = ranked.filter(c =>
      Object.values(filters).every(fdef => !fdef.on || fdef.test(c)));
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
    for (const m of shown) {
      const width = 25 + 75 * (m.similarity - simMin) / span;
      grid.append(el("a", { class: "sim-card-lg",
        href: `coach.html?id=${m.id}`,
        title: `#${m.rank} for this team` },
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
          badgeCell(m, ctx, country, level))));
    }
    gridHost.append(grid);
    if (rows.length > MAX_CARDS) {
      gridHost.append(el("p", { class: "footnote" },
        `Showing the top ${MAX_CARDS} of the ${rows.length} coaches that ` +
        "pass the filters."));
    }
  }
  draw();

  card.append(el("p", { class: "footnote" },
    "Descriptive, not a validated prediction: coaches with ≥4 big-5 stints " +
    "and a positive career residual, ordered by squad-mix similarity blended " +
    "with a small weight on overall coach quality (85/15). Your XI's mix is " +
    "equal-weighted; the coaches' profiles are minutes-weighted from their " +
    "real squads. The model's out-of-sample-tested quality ranking is on ",
    el("a", { href: "index.html" }, "the leaderboard"),
    ". Availability, wages, and contracts are not modeled."));
  return card;
}

// cosine similarity vs every pool coach + the 85/15 blend, ranks assigned
// once over the unfiltered pool (mirrors se_suggestions in site_export.R)
function rankCoaches(shares) {
  const [wSim, wQ] = state.meta.sim_quality_blend;
  const archIds = Object.keys(state.meta.archetype_labels);
  const v = archIds.map(a => shares[a] || 0);
  const vNorm = Math.sqrt(v.reduce((t, x) => t + x * x, 0));

  const rows = state.coaches.map(c => {
    const p = archIds.map(a => c.profile[a] || 0);
    const dot = p.reduce((t, x, i) => t + x * v[i], 0);
    const pNorm = Math.sqrt(p.reduce((t, x) => t + x * x, 0));
    const similarity = vNorm && pNorm ? dot / (vNorm * pNorm) : 0;
    return { ...c, similarity };
  });

  const z = xs => {
    const ok = xs.filter(x => x != null);
    const mean = ok.reduce((t, x) => t + x, 0) / ok.length;
    const sd = Math.sqrt(ok.reduce((t, x) => t + (x - mean) ** 2, 0) / (ok.length - 1));
    return xs.map(x => (x == null || !sd ? 0 : (x - mean) / sd));
  };
  const zSim = z(rows.map(r => r.similarity));
  const zQ = z(rows.map(r => (r.blup == null ? null : r.blup)));
  rows.forEach((r, i) => { r.score = wSim * zSim[i] + wQ * zQ[i]; });
  rows.sort((a, b) => b.score - a.score);
  rows.forEach((r, i) => { r.rank = i + 1; });
  return rows;
}

function badgeCell(c, ctx, country, level) {
  const wrap = el("span", { class: "badge-cell" });
  const badge = (txt, title) => el("span", { class: "badge-mini", title }, txt);
  if (ctx && c.leagues.includes(ctx)) {
    wrap.append(badge("league", "Has coached in this league"));
  } else if (country && c.countries.includes(country)) {
    wrap.append(badge("country", "Has coached in this country"));
  }
  if (c.big5) wrap.append(badge("big-5", "30+ games in the five major leagues"));
  if (country && c.nationality === country) {
    wrap.append(badge("domestic", "Same nationality as the league context"));
  }
  if (c.club_level != null) {
    wrap.append(el("span", { class: "muted",
      title: "Career club level: squad-value percentile of the clubs coached" +
        (level != null ? ` (your XI: p${level})` : "") },
      `lvl ${Math.round(c.club_level)}`));
  }
  return wrap;
}

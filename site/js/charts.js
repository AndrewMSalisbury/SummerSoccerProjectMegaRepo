// charts.js — hand-rolled SVG charts.
// Mark specs follow the dataviz skill: 2px lines, >=8px markers with a 2px
// surface ring, bars <=24px with 4px rounded data-ends (square at baseline),
// hairline solid gridlines, selective direct labels, hover tooltips with hit
// targets larger than the marks. Colors are CSS custom properties so light
// and dark modes swap without re-rendering.

import { svgEl, el, clear, fmtSeason, fmtPpg, fmtSigned, fmtPoints } from "./data.js";
import { badgeGroup, tooltip } from "./components.js";

const INK2 = "var(--ink-2)";
const MUTED = "var(--muted)";
const GRID = "var(--grid)";
const BASE = "var(--baseline)";
const S1 = "var(--series-1)";
const POS = "var(--pos)";
const NEG = "var(--neg)";
const SURF = "var(--surface)";

function scaleLinear([d0, d1], [r0, r1]) {
  const f = x => r0 + ((x - d0) / (d1 - d0 || 1)) * (r1 - r0);
  f.ticks = n => {
    const span = d1 - d0;
    const step = niceStep(span / Math.max(1, n));
    const t = [];
    for (let v = Math.ceil(d0 / step) * step; v <= d1 + 1e-9; v += step) {
      t.push(+v.toFixed(6));
    }
    return t;
  };
  return f;
}

// 1st, 2nd, 3rd, 4th … 21st, 22nd — "1th" and "22th" are what a bare "th" gives
function ordinal(n) {
  const teens = n % 100 >= 11 && n % 100 <= 13;   // 11th, 12th, 13th, not 11st
  if (teens) return `${n}th`;
  if (n % 10 === 1) return `${n}st`;
  if (n % 10 === 2) return `${n}nd`;
  if (n % 10 === 3) return `${n}rd`;
  return `${n}th`;
}

function niceStep(raw) {
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  for (const m of [1, 2, 2.5, 5, 10]) if (raw / mag <= m) return m * mag;
  return 10 * mag;
}

function chartSvg(w, h) {
  return svgEl("svg", { viewBox: `0 0 ${w} ${h}`, width: w, height: h,
                        role: "img" });
}

function yAxis(svg, y, x0, x1, fmt = v => String(v), n = 5) {
  for (const t of y.ticks(n)) {
    svg.append(
      svgEl("line", { x1: x0, x2: x1, y1: y(t), y2: y(t),
                      stroke: GRID, "stroke-width": 1 }),
      svgEl("text", { x: x0 - 8, y: y(t), "text-anchor": "end",
                      "dominant-baseline": "central", "font-size": 11,
                      fill: MUTED }, fmt(t)));
  }
}

function measuredWidth(host, min = 320, max = 1100) {
  return Math.max(min, Math.min(max, host.clientWidth || 720));
}

function onResize(host, fn) {
  let w = host.clientWidth;
  const ro = new ResizeObserver(() => {
    if (Math.abs(host.clientWidth - w) > 24) { w = host.clientWidth; fn(); }
  });
  ro.observe(host);
}

// ---------- coach career chart ----------

// stints: coach JSON stints array. opts: {mode: "chrono"|"best", onSelect(stint)}
// Y domain is computed once over both series and both modes so toggling the
// sort never rescales the axis.
export function careerChart(host, stints, opts = {}) {
  const tt = tooltip();
  let mode = opts.mode || "chrono";
  let selected = null;

  const vals = stints.flatMap(s => [s.actual_ppg, s.predicted_ppg])
    .filter(v => v != null);
  const yDom = [Math.max(0, Math.floor(Math.min(...vals) * 4) / 4 - 0.25),
                Math.ceil(Math.max(...vals) * 4) / 4 + 0.25];

  function render() {
    const W = measuredWidth(host);
    const H = 320;
    const m = { top: 16, right: 24, bottom: 44, left: 44 };
    const svg = chartSvg(W, H);
    const y = scaleLinear(yDom, [H - m.bottom, m.top]);

    let pts;   // [{s, x}]
    if (mode === "chrono") {
      const seasons = [...new Set(stints.map(s => s.season))].sort((a, b) => a - b);
      const x = scaleLinear([0, Math.max(1, seasons.length - 1)],
                            [m.left + 24, W - m.right - 24]);
      const seasonX = new Map(seasons.map((yr, i) => [yr, x(i)]));
      // jitter stints sharing a season
      const bySeason = new Map();
      for (const s of stints) {
        bySeason.set(s.season, (bySeason.get(s.season) || []).concat(s));
      }
      pts = [];
      for (const [yr, group] of bySeason) {
        group.forEach((s, i) => {
          const off = (i - (group.length - 1) / 2) * 24;
          pts.push({ s, x: seasonX.get(yr) + off });
        });
      }
      pts.sort((a, b) => a.x - b.x);

      // x axis labels: thin to fit
      const every = Math.ceil(seasons.length / Math.max(3, Math.floor((W - 80) / 64)));
      seasons.forEach((yr, i) => {
        if (i % every) return;
        svg.append(svgEl("text", { x: seasonX.get(yr), y: H - m.bottom + 18,
          "text-anchor": "middle", "font-size": 11, fill: MUTED }, fmtSeason(yr)));
      });
    } else {
      const order = [...stints].sort((a, b) =>
        (b.residual_ppg ?? -99) - (a.residual_ppg ?? -99));
      const x = scaleLinear([0, Math.max(1, order.length - 1)],
                            [m.left + 24, W - m.right - 24]);
      pts = order.map((s, i) => ({ s, x: x(i) }));
      svg.append(
        svgEl("text", { x: m.left + 24, y: H - m.bottom + 18, "font-size": 11,
                        fill: MUTED }, "best stint"),
        svgEl("text", { x: W - m.right - 24, y: H - m.bottom + 18,
                        "text-anchor": "end", "font-size": 11, fill: MUTED },
              "worst stint"));
    }

    yAxis(svg, y, m.left, W - m.right, v => v.toFixed(1));
    svg.append(svgEl("line", { x1: m.left, x2: W - m.right,
      y1: H - m.bottom, y2: H - m.bottom, stroke: BASE, "stroke-width": 1 }));

    // expected series: recessive dashed line + small gray dots
    const exp = pts.filter(p => p.s.predicted_ppg != null);
    if (mode === "chrono" && exp.length > 1) {
      svg.append(svgEl("path", {
        d: exp.map((p, i) =>
          `${i ? "L" : "M"}${p.x},${y(p.s.predicted_ppg)}`).join(""),
        fill: "none", stroke: MUTED, "stroke-width": 2,
        "stroke-dasharray": "5 4", "stroke-linecap": "round",
        "stroke-linejoin": "round", opacity: 0.85 }));
    }
    for (const p of exp) {
      svg.append(svgEl("circle", { cx: p.x, cy: y(p.s.predicted_ppg), r: 4,
        fill: MUTED, stroke: SURF, "stroke-width": 2 }));
    }

    // actual series: connecting line (chrono only), then crest marks
    const act = pts.filter(p => p.s.actual_ppg != null);
    if (mode === "chrono" && act.length > 1) {
      svg.append(svgEl("path", {
        d: act.map((p, i) => `${i ? "L" : "M"}${p.x},${y(p.s.actual_ppg)}`).join(""),
        fill: "none", stroke: S1, "stroke-width": 2,
        "stroke-linecap": "round", "stroke-linejoin": "round" }));
    }

    const R = 13;
    for (const p of act) {
      const cy = y(p.s.actual_ppg);
      const g = svgEl("g", { cursor: "pointer", tabindex: 0, role: "button" });
      g.append(svgEl("title", {}, `${p.s.team} ${fmtSeason(p.s.season)}`));
      g.append(svgEl("circle", { cx: p.x, cy, r: R + 2, fill: SURF,
        stroke: selected === p.s ? S1 : "var(--border)",
        "stroke-width": selected === p.s ? 2.5 : 1 }));
      if (p.s.crest) {
        g.append(svgEl("image", { href: p.s.crest, x: p.x - R + 1, y: cy - R + 1,
          width: 2 * R - 2, height: 2 * R - 2,
          preserveAspectRatio: "xMidYMid meet" }));
      } else {
        g.append(badgeGroup(p.s.team, p.x, cy, R - 1));
      }
      // hit target beyond the mark
      g.append(svgEl("circle", { cx: p.x, cy, r: R + 8, fill: "transparent" }));

      const rows = () => [
        { label: "Actual PPG", value: fmtPpg(p.s.actual_ppg), color: "#2a78d6" },
        { label: "Expected PPG", value: fmtPpg(p.s.predicted_ppg),
          color: "#898781", dashed: true },
        { label: "Residual", value: fmtSigned(p.s.residual_ppg), },
      ];
      g.addEventListener("pointermove", e =>
        tt.show(e, `${p.s.team} · ${fmtSeason(p.s.season)}`, rows()));
      g.addEventListener("pointerleave", () => tt.hide());
      const select = () => {
        selected = selected === p.s ? null : p.s;
        opts.onSelect?.(selected);
        render();
      };
      g.addEventListener("click", select);
      g.addEventListener("keydown", e => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(); }
      });
      svg.append(g);
    }

    clear(host).append(svg);
  }

  render();
  onResize(host, render);
  return {
    setMode(m2) { mode = m2; render(); },
    clearSelection() { selected = null; render(); },
  };
}

// ---------- team season dumbbell (expected -> actual points) ----------

export function dumbbellChart(host, seasons, opts = {}) {
  const tt = tooltip();
  let selected = null;
  const ok = seasons.filter(s => s.expected_points != null && s.points != null);

  function render() {
    const W = measuredWidth(host);
    const H = 300;
    const m = { top: 16, right: 20, bottom: 40, left: 44 };
    const svg = chartSvg(W, H);
    if (!ok.length) { clear(host).append(el("p", { class: "muted" }, "No data.")); return; }

    const vals = ok.flatMap(s => [s.points, s.expected_points]);
    const y = scaleLinear([Math.floor(Math.min(...vals) / 10) * 10 - 5,
                           Math.ceil(Math.max(...vals) / 10) * 10 + 5],
                          [H - m.bottom, m.top]);
    const x = scaleLinear([0, Math.max(1, ok.length - 1)],
                          [m.left + 20, W - m.right - 20]);

    yAxis(svg, y, m.left, W - m.right, v => String(Math.round(v)));
    svg.append(svgEl("line", { x1: m.left, x2: W - m.right, y1: H - m.bottom,
      y2: H - m.bottom, stroke: BASE, "stroke-width": 1 }));

    const every = Math.ceil(ok.length / Math.max(3, Math.floor((W - 80) / 64)));
    ok.forEach((s, i) => {
      const cx = x(i);
      if (i % every === 0) {
        svg.append(svgEl("text", { x: cx, y: H - m.bottom + 18,
          "text-anchor": "middle", "font-size": 11, fill: MUTED },
          fmtSeason(s.season)));
      }

      const yA = y(s.points), yE = y(s.expected_points);
      const over = s.points >= s.expected_points;
      const g = svgEl("g", { cursor: opts.onSelect ? "pointer" : "default" });
      g.append(
        svgEl("line", { x1: cx, x2: cx, y1: yE, y2: yA,
          stroke: over ? POS : NEG, "stroke-width": 2, opacity: 0.7 }),
        svgEl("circle", { cx, cy: yE, r: 4, fill: MUTED,
          stroke: SURF, "stroke-width": 2 }),
        svgEl("circle", { cx, cy: yA, r: 6, fill: over ? POS : NEG,
          stroke: selected === s.season ? "var(--ink)" : SURF,
          "stroke-width": 2 }),
        svgEl("rect", { x: cx - 12, y: m.top, width: 24, height: H - m.top - m.bottom,
          fill: "transparent" }));

      g.addEventListener("pointermove", e => tt.show(e,
        `${fmtSeason(s.season)} · ${s.league_name}`, [
          { label: "Points", value: fmtPoints(s.points), color: over ? "#2a78d6" : "#e34948" },
          { label: "Expected", value: fmtPoints(s.expected_points), color: "#898781" },
          { label: "Residual", value: fmtSigned(s.residual_points, 1) + " pts" },
        ]));
      g.addEventListener("pointerleave", () => tt.hide());
      if (opts.onSelect) {
        g.addEventListener("click", () => {
          selected = selected === s.season ? null : s.season;
          opts.onSelect(selected);
          render();
        });
      }
      svg.append(g);
    });

    clear(host).append(svg);
  }

  render();
  onResize(host, render);
}

// ---------- simple line chart (squad value trend) ----------

export function lineChart(host, points, { fmt = String, color = S1 } = {}) {
  function render() {
    const W = measuredWidth(host);
    const H = 180;
    const m = { top: 12, right: 16, bottom: 30, left: 56 };
    const svg = chartSvg(W, H);
    const ok = points.filter(p => p.v != null);
    if (ok.length < 2) { clear(host).append(el("p", { class: "muted" }, "No data.")); return; }

    const y = scaleLinear([0, Math.max(...ok.map(p => p.v)) * 1.08],
                          [H - m.bottom, m.top]);
    const x = scaleLinear([Math.min(...ok.map(p => p.season)),
                           Math.max(...ok.map(p => p.season))],
                          [m.left + 8, W - m.right - 8]);

    yAxis(svg, y, m.left, W - m.right, fmt);
    svg.append(svgEl("line", { x1: m.left, x2: W - m.right, y1: H - m.bottom,
      y2: H - m.bottom, stroke: BASE, "stroke-width": 1 }));

    const seasons = ok.map(p => p.season);
    const every = Math.ceil(seasons.length / Math.max(3, Math.floor((W - 90) / 64)));
    seasons.forEach((yr, i) => {
      if (i % every) return;
      svg.append(svgEl("text", { x: x(yr), y: H - m.bottom + 16,
        "text-anchor": "middle", "font-size": 10.5, fill: MUTED }, fmtSeason(yr)));
    });

    svg.append(svgEl("path", {
      d: ok.map((p, i) => `${i ? "L" : "M"}${x(p.season)},${y(p.v)}`).join(""),
      fill: "none", stroke: color, "stroke-width": 2,
      "stroke-linecap": "round", "stroke-linejoin": "round" }));

    const tt = tooltip();
    for (const p of ok) {
      const c = svgEl("circle", { cx: x(p.season), cy: y(p.v), r: 10,
        fill: "transparent", cursor: "default" });
      c.addEventListener("pointermove", e =>
        tt.show(e, fmtSeason(p.season), [{ label: "", value: fmt(p.v), color }]));
      c.addEventListener("pointerleave", () => tt.hide());
      svg.append(c);
    }
    // end dot + end label (selective direct label)
    const last = ok[ok.length - 1];
    svg.append(
      svgEl("circle", { cx: x(last.season), cy: y(last.v), r: 4, fill: color,
        stroke: SURF, "stroke-width": 2 }),
      svgEl("text", { x: x(last.season), y: y(last.v) - 10, "text-anchor": "end",
        "font-size": 11, fill: INK2 }, fmt(last.v)));

    clear(host).append(svg);
  }
  render();
  onResize(host, render);
}

// ---------- coach strengths: offence / defence split ----------

// Layer A of the descriptive profile: the coach's overperformance split into
// goals scored above squad-value expectation and goals conceded below it.
// The x domain is FIXED across coaches (and across both ranking cuts) so the
// bars mean the same thing on every page, and so the two rows share one scale.
// Defence bars are visibly shorter than attack bars for almost everyone: that
// is the real finding (the coach effect is stronger on goals scored than on
// goals conceded), not a scaling artifact — do not give the rows their own axes.
const STRENGTH_DOMAIN = 0.26;

export function strengthBars(host, s) {
  const tt = tooltip();
  const rows = [
    { label: "Attack", v: s.off, sig: s.off_significant,
      hint: "goals scored above expectation" },
    { label: "Defence", v: s.def, sig: s.def_significant,
      hint: "goals conceded below expectation" },
  ];

  function render() {
    const W = measuredWidth(host);
    const rowH = 44, barH = 20;
    const m = { top: 10, right: 60, bottom: 28, left: 84 };
    const H = m.top + rows.length * rowH + m.bottom;
    const svg = chartSvg(W, H);
    const x = scaleLinear([-STRENGTH_DOMAIN, STRENGTH_DOMAIN], [m.left, W - m.right]);

    svg.append(svgEl("line", { x1: x(0), x2: x(0), y1: m.top, y2: H - m.bottom,
      stroke: BASE, "stroke-width": 1 }));

    rows.forEach((r, i) => {
      const yTop = m.top + i * rowH + (rowH - barH) / 2;
      const cy = yTop + barH / 2;
      const over = r.v >= 0;
      const x0 = Math.min(x(0), x(r.v)), x1 = Math.max(x(0), x(r.v));
      const wBar = Math.max(1, x1 - x0);
      const rr = Math.min(4, wBar);
      const d = over
        ? `M${x0},${yTop} H${x1 - rr} Q${x1},${yTop} ${x1},${yTop + rr} V${yTop + barH - rr} Q${x1},${yTop + barH} ${x1 - rr},${yTop + barH} H${x0} Z`
        : `M${x1},${yTop} H${x0 + rr} Q${x0},${yTop} ${x0},${yTop + rr} V${yTop + barH - rr} Q${x0},${yTop + barH} ${x0 + rr},${yTop + barH} H${x1} Z`;
      svg.append(svgEl("path", { d, fill: over ? POS : NEG }));

      svg.append(svgEl("text", { x: m.left - 14, y: cy, "text-anchor": "end",
        "dominant-baseline": "central", "font-size": 12.5, fill: INK2 }, r.label));
      svg.append(svgEl("text", {
        x: over ? x1 + 8 : x0 - 8, y: cy, "text-anchor": over ? "start" : "end",
        "dominant-baseline": "central", "font-size": 11.5, fill: INK2,
      }, fmtSigned(r.v)));

      const hit = svgEl("rect", { x: 0, y: m.top + i * rowH, width: W,
        height: rowH, fill: "transparent" });
      hit.addEventListener("pointermove", e => tt.show(e, r.label, [
        { label: r.hint, value: `${fmtSigned(r.v)} per game`,
          color: over ? "#2a78d6" : "#e34948" },
        { label: "vs FDR", value: r.sig ? "significant" : "not significant" },
      ]));
      hit.addEventListener("pointerleave", () => tt.hide());
      svg.append(hit);
    });

    svg.append(svgEl("text", { x: x(0), y: H - 8, "text-anchor": "middle",
      "font-size": 11, fill: MUTED },
      "← below expectation  ·  goals per game  ·  above →"));

    clear(host).append(svg);
  }
  render();
  onResize(host, render);
}

// ---------- coach style fingerprint ----------

// Layer B: the style of the teams a coach ran, as a percentile among the
// profiled coaches (raw axis units are SDs of team-matches, where every coach
// mean compresses toward zero and every fingerprint looks flat).
// Deliberately ONE hue rather than the site's pos/neg pair: these axes have no
// good/bad polarity — more possession is not better — and coloring them with
// the above/below-expectation ramp would invent a verdict the layer does not
// make. The 50th-percentile midline carries the "more or less than typical"
// reading on its own.
export function styleBars(host, axes) {
  const tt = tooltip();

  function render() {
    const W = measuredWidth(host);
    const rowH = 30, barH = 14;
    const m = { top: 8, right: 44, bottom: 30, left: 148 };
    const H = m.top + axes.length * rowH + m.bottom;
    const svg = chartSvg(W, H);
    const x = scaleLinear([0, 100], [m.left, W - m.right]);

    axes.forEach((a, i) => {
      const yTop = m.top + i * rowH + (rowH - barH) / 2;
      const cy = yTop + barH / 2;

      // full-range track: gives the 0-100 scale without a tick axis
      svg.append(svgEl("rect", { x: x(0), y: yTop, width: x(100) - x(0),
        height: barH, rx: 3, fill: GRID }));

      const x0 = Math.min(x(50), x(a.pct)), x1 = Math.max(x(50), x(a.pct));
      svg.append(svgEl("rect", { x: x0, y: yTop, width: Math.max(2, x1 - x0),
        height: barH, rx: 3, fill: S1 }));

      // coach-owned axes (design sec. 5) get a dot; the legend names them
      if (a.coach_owned) {
        svg.append(svgEl("circle", { cx: m.left - 130, cy, r: 3.5, fill: S1 }));
      }
      svg.append(svgEl("text", { x: m.left - 120, y: cy, "font-size": 12,
        "dominant-baseline": "central", fill: INK2 }, a.label));
      svg.append(svgEl("text", { x: x(100) + 8, y: cy, "font-size": 11.5,
        "dominant-baseline": "central", fill: INK2 }, String(a.pct)));

      const hit = svgEl("rect", { x: 0, y: m.top + i * rowH, width: W,
        height: rowH, fill: "transparent" });
      hit.addEventListener("pointermove", e => tt.show(e, a.label, [
        { label: "percentile among coaches", value: String(a.pct), color: "#2a78d6" },
        { label: "raw", value: `${fmtSigned(a.sd, 2)} SD` },
      ]));
      hit.addEventListener("pointerleave", () => tt.hide());
      svg.append(hit);
    });

    // median line drawn over the bars so it stays readable
    svg.append(svgEl("line", { x1: x(50), x2: x(50), y1: m.top,
      y2: H - m.bottom, stroke: BASE, "stroke-width": 1 }));
    svg.append(svgEl("text", { x: x(50), y: H - 8, "text-anchor": "middle",
      "font-size": 11, fill: MUTED }, "← less  ·  typical coach  ·  more →"));

    clear(host).append(svg);
  }
  render();
  onResize(host, render);
}

// ---------- named-pole percentile spectrum ----------

// One percentile on a scale whose ends are named, for a measure whose axis
// label does not explain itself ("pressing height" reads as jargon; "deep
// block ... high press" reads as football).
// The marker rides a PERCENTILE scale, not a pitch: the underlying stat is the
// share of possession won in the attacking third, ranked against other
// coaches. Position along a drawn pitch would claim a physical location the
// data does not contain — 98th percentile is not "wins it 98% of the way
// upfield". Keep the poles as labels and the scale as rank.
export function spectrumBar(host, { pct, leftLabel, rightLabel, label }) {
  function render() {
    const W = measuredWidth(host);
    const H = 56;
    const m = { left: 92, right: 92 };
    const trackY = 16, trackH = 12;
    const svg = chartSvg(W, H);
    const x = scaleLinear([0, 100], [m.left, W - m.right]);

    svg.append(svgEl("rect", { x: x(0), y: trackY, width: x(100) - x(0),
      height: trackH, rx: 3, fill: GRID }));
    // quartile ticks: enough scale to read the marker against, no tick labels
    for (const q of [25, 50, 75]) {
      svg.append(svgEl("line", { x1: x(q), x2: x(q), y1: trackY,
        y2: trackY + trackH, stroke: BASE, "stroke-width": 1 }));
    }

    svg.append(svgEl("text", { x: x(0) - 10, y: trackY + trackH / 2,
      "text-anchor": "end", "dominant-baseline": "central", "font-size": 12,
      fill: MUTED }, leftLabel));
    svg.append(svgEl("text", { x: x(100) + 10, y: trackY + trackH / 2,
      "dominant-baseline": "central", "font-size": 12, fill: MUTED }, rightLabel));

    // marker: 2px surface ring so it reads against the track at any position
    svg.append(svgEl("circle", { cx: x(pct), cy: trackY + trackH / 2, r: 7,
      fill: S1, stroke: SURF, "stroke-width": 2 }));
    // keep the marker label inside the track's span at the poles
    const anchor = pct <= 4 ? "start" : pct >= 96 ? "end" : "middle";
    svg.append(svgEl("text", { x: x(pct), y: trackY + trackH + 18,
      "text-anchor": anchor, "font-size": 11.5, fill: INK2 },
      label ?? `${ordinal(pct)} percentile`));

    clear(host).append(svg);
  }
  render();
  onResize(host, render);
}

// ---------- league diverging residual bars ----------

// rows: standings rows for one season (with residual_points, team, crest).
export function divergingBars(host, rows) {
  const tt = tooltip();

  function render() {
    const W = measuredWidth(host);
    const ok = [...rows].filter(r => r.residual_points != null)
      .sort((a, b) => b.residual_points - a.residual_points);
    const rowH = 26, barH = 18;
    const m = { top: 8, right: 56, bottom: 26, left: 190 };
    const H = m.top + ok.length * rowH + m.bottom;
    const svg = chartSvg(W, H);
    if (!ok.length) { clear(host).append(el("p", { class: "muted" }, "No data.")); return; }

    const ext = Math.max(...ok.map(r => Math.abs(r.residual_points))) * 1.08;
    const x = scaleLinear([-ext, ext], [m.left, W - m.right]);

    // zero midline
    svg.append(svgEl("line", { x1: x(0), x2: x(0), y1: m.top,
      y2: H - m.bottom, stroke: BASE, "stroke-width": 1 }));

    ok.forEach((r, i) => {
      const yTop = m.top + i * rowH + (rowH - barH) / 2;
      const cy = yTop + barH / 2;
      const v = r.residual_points;
      const over = v >= 0;
      const x0 = Math.min(x(0), x(v)), x1 = Math.max(x(0), x(v));
      const wBar = Math.max(1, x1 - x0);
      const rr = Math.min(4, wBar);

      // 4px rounded at the data end only (square at the zero baseline)
      const d = over
        ? `M${x0},${yTop} H${x1 - rr} Q${x1},${yTop} ${x1},${yTop + rr} V${yTop + barH - rr} Q${x1},${yTop + barH} ${x1 - rr},${yTop + barH} H${x0} Z`
        : `M${x1},${yTop} H${x0 + rr} Q${x0},${yTop} ${x0},${yTop + rr} V${yTop + barH - rr} Q${x0},${yTop + barH} ${x0 + rr},${yTop + barH} H${x1} Z`;
      svg.append(svgEl("path", { d, fill: over ? POS : NEG }));

      // crest + name in the left gutter
      const label = svgEl("text", { x: m.left - 34, y: cy, "text-anchor": "end",
        "dominant-baseline": "central", "font-size": 11.5, fill: INK2 },
        r.team.length > 22 ? r.team.slice(0, 21) + "…" : r.team);
      svg.append(label);
      if (r.crest) {
        svg.append(svgEl("image", { href: r.crest, x: m.left - 28, y: cy - 9,
          width: 18, height: 18, preserveAspectRatio: "xMidYMid meet" }));
      } else {
        svg.append(badgeGroup(r.team, m.left - 19, cy, 9));
      }

      // direct labels on the extremes only; tooltip carries the rest
      if (i === 0 || i === ok.length - 1) {
        svg.append(svgEl("text", {
          x: over ? x1 + 6 : x0 - 6, y: cy,
          "text-anchor": over ? "start" : "end",
          "dominant-baseline": "central", "font-size": 11, fill: INK2,
        }, fmtSigned(v, 1)));
      }

      const hit = svgEl("rect", { x: 0, y: m.top + i * rowH, width: W,
        height: rowH, fill: "transparent", cursor: "pointer" });
      hit.addEventListener("pointermove", e => tt.show(e, r.team, [
        { label: "vs expectation", value: `${fmtSigned(v, 1)} pts`,
          color: over ? "#2a78d6" : "#e34948" },
        { label: "Points", value: fmtPoints(r.points) },
        { label: "Expected", value: fmtPoints(r.expected_points) },
      ]));
      hit.addEventListener("pointerleave", () => tt.hide());
      hit.addEventListener("click", () =>
        window.location.href = `team.html?id=${r.team_id}`);
      svg.append(hit);
    });

    svg.append(svgEl("text", { x: x(0), y: H - 8, "text-anchor": "middle",
      "font-size": 11, fill: MUTED }, "← under  ·  points vs expectation  ·  over →"));

    clear(host).append(svg);
  }
  render();
  onResize(host, render);
}

// ---------- player value-growth curves by position ----------

// Four categorical hues in the reference palette's validated slot order
// (blue -> orange -> aqua -> yellow). The ORDER is the colorblind-safety
// mechanism, not a preference: it is the assignment sequence the adjacent-pair
// gate was validated on (worst adjacent CVD ΔE 9.1 light / 8.4 dark). Series are
// assigned from the front of this list and never cycled or re-ordered, and the
// two light-mode steps below 3:1 contrast (aqua, yellow) are why every line also
// carries a direct end label.
export const CAT4 = ["var(--series-1)", "var(--series-3)",
                     "var(--series-2)", "var(--series-4)"];

// series: [{key, label, color, points: [{age, pct, obs, n}]}] — one curve per
// position group. opts.highlight dims every other curve (used by the page's
// position filter). Returns { setHighlight }.
export function growthCurves(host, series, opts = {}) {
  const tt = tooltip();
  let highlight = opts.highlight || null;

  const ok = series.filter(s => s.points.length > 1);
  const ages = [...new Set(ok.flatMap(s => s.points.map(p => p.age)))]
    .sort((a, b) => a - b);

  function render() {
    if (!ok.length || !ages.length) {
      clear(host).append(el("p", { class: "muted" }, "No data."));
      return;
    }
    const W = measuredWidth(host);
    const H = 380;
    // narrow viewports get short position codes so the label gutter can shrink
    const narrow = W < 560;
    const m = { top: 18, right: narrow ? 44 : 112, bottom: 46, left: 50 };
    const svg = chartSvg(W, H);

    const vals = ok.flatMap(s => s.points.map(p => p.pct));
    const lo = Math.min(0, Math.min(...vals)), hi = Math.max(0, Math.max(...vals));
    const pad = (hi - lo) * 0.08;
    const y = scaleLinear([lo - pad, hi + pad], [H - m.bottom, m.top]);
    const x = scaleLinear([ages[0], ages[ages.length - 1]],
                          [m.left + 10, W - m.right - 10]);

    yAxis(svg, y, m.left, W - m.right,
          v => `${v > 0 ? "+" : ""}${Math.round(v)}%`, 7);

    // the zero line is the story ("value stops growing here"), so it is drawn
    // heavier than the gridlines it sits among
    svg.append(
      svgEl("line", { x1: m.left, x2: W - m.right, y1: y(0), y2: y(0),
        stroke: BASE, "stroke-width": 1.5 }),
      svgEl("text", { x: m.left + 6, y: y(0) - 6, "font-size": 10.5, fill: MUTED },
        "no change"));

    // x axis: thin the age ticks to fit
    const every = Math.ceil(ages.length / Math.max(4, Math.floor((W - 140) / 42)));
    ages.forEach((a, i) => {
      if (i % every) return;
      svg.append(svgEl("text", { x: x(a), y: H - m.bottom + 18,
        "text-anchor": "middle", "font-size": 11, fill: MUTED }, String(a)));
    });
    svg.append(svgEl("text", { x: (m.left + W - m.right) / 2, y: H - 8,
      "text-anchor": "middle", "font-size": 11, fill: MUTED }, "Age"));

    const dim = s => highlight && s.key !== highlight;

    for (const s of ok) {
      svg.append(svgEl("path", {
        d: s.points.map((p, i) => `${i ? "L" : "M"}${x(p.age)},${y(p.pct)}`).join(""),
        fill: "none", stroke: s.color, "stroke-width": highlight === s.key ? 2.5 : 2,
        "stroke-linecap": "round", "stroke-linejoin": "round",
        opacity: dim(s) ? 0.22 : 1 }));
    }

    // Direct end labels, all parked in the right gutter and pushed apart where
    // the curves converge (they do, sharply, after 30) — with a hairline leader
    // back to each curve's own end, which sits at a different age per position.
    // Text wears the ink token; the colored dot and leader carry identity.
    const gutterX = W - m.right + 10;
    const ends = ok.map(s => {
      const last = s.points[s.points.length - 1];
      return { s, cx: x(last.age), cy: y(last.pct), ly: y(last.pct) };
    }).sort((a, b) => a.ly - b.ly);
    const gap = 15, top = m.top + 6, bot = H - m.bottom - 6;
    for (let i = 1; i < ends.length; i++) {
      ends[i].ly = Math.max(ends[i].ly, ends[i - 1].ly + gap);
    }
    const spill = ends[ends.length - 1].ly - bot;
    if (spill > 0) for (const e of ends) e.ly = Math.max(top, e.ly - spill);
    for (const e of ends) {
      const o = dim(e.s) ? 0.22 : 1;
      svg.append(
        svgEl("path", { d: `M${e.cx + 5},${e.cy} L${gutterX - 5},${e.ly}`,
          fill: "none", stroke: e.s.color, "stroke-width": 1, opacity: o * 0.55 }),
        svgEl("circle", { cx: e.cx, cy: e.cy, r: 4, fill: e.s.color, stroke: SURF,
          "stroke-width": 2, opacity: o }),
        svgEl("text", { x: gutterX, y: e.ly, "dominant-baseline": "central",
          "font-size": 11.5, fill: INK2, opacity: dim(e.s) ? 0.35 : 1 },
          narrow ? e.s.key : e.s.label));
    }

    // crosshair + one tooltip per age column, listing every position present
    const cross = svgEl("line", { x1: 0, x2: 0, y1: m.top, y2: H - m.bottom,
      stroke: MUTED, "stroke-width": 1, opacity: 0, "pointer-events": "none" });
    const dots = svgEl("g", { opacity: 0, "pointer-events": "none" });
    svg.append(cross, dots);

    const colW = (W - m.right - m.left) / Math.max(1, ages.length - 1);
    for (const a of ages) {
      const hit = svgEl("rect", { x: x(a) - colW / 2, y: m.top, width: colW,
        height: H - m.top - m.bottom, fill: "transparent" });
      hit.addEventListener("pointermove", e => {
        const here = ok.map(s => ({ s, p: s.points.find(q => q.age === a) }))
          .filter(d => d.p)
          .sort((d1, d2) => d2.p.pct - d1.p.pct);
        cross.setAttribute("x1", x(a)); cross.setAttribute("x2", x(a));
        cross.setAttribute("opacity", 0.5);
        clear(dots);
        for (const d of here) {
          dots.append(svgEl("circle", { cx: x(a), cy: y(d.p.pct), r: 4.5,
            fill: d.s.color, stroke: SURF, "stroke-width": 2 }));
        }
        dots.setAttribute("opacity", 1);
        tt.show(e, `Age ${a}`, here.map(d => ({
          label: d.s.label,
          value: `${d.p.pct > 0 ? "+" : ""}${d.p.pct.toFixed(1)}%`,
          color: d.s.color })));
      });
      hit.addEventListener("pointerleave", () => {
        cross.setAttribute("opacity", 0);
        dots.setAttribute("opacity", 0);
        tt.hide();
      });
      svg.append(hit);
    }

    clear(host).append(svg);
  }

  render();
  onResize(host, render);
  return {
    setHighlight(k) { highlight = k || null; render(); },
  };
}

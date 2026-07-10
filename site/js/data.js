// data.js — JSON loading, query params, formatting, DOM helpers.

const cache = new Map();

export async function loadJSON(path) {
  if (cache.has(path)) return cache.get(path);
  const p = fetch(path).then(r => {
    if (!r.ok) throw new Error(`${r.status} loading ${path}`);
    return r.json();
  });
  cache.set(path, p);
  try {
    return await p;
  } catch (e) {
    cache.delete(path);
    throw e;
  }
}

export function getParam(name) {
  return new URLSearchParams(window.location.search).get(name);
}

// "2015" -> "2015/16"
export function fmtSeason(y) {
  return `${y}/${String((y + 1) % 100).padStart(2, "0")}`;
}

export function fmtPpg(x) {
  return x == null ? "—" : x.toFixed(2);
}

export function fmtSigned(x, digits = 2) {
  if (x == null) return "—";
  const s = x.toFixed(digits);
  return x >= 0 ? `+${s}` : s;
}

export function fmtPoints(x) {
  return x == null ? "—" : (Number.isInteger(x) ? String(x) : x.toFixed(1));
}

export function fmtMoney(eur) {
  if (eur == null) return "—";
  if (eur >= 1e9) return `€${(eur / 1e9).toFixed(2)}bn`;
  if (eur >= 1e6) return `€${(eur / 1e6).toFixed(0)}m`;
  if (eur >= 1e3) return `€${(eur / 1e3).toFixed(0)}k`;
  return `€${eur}`;
}

// el("div", {class: "x", onclick: fn}, child, "text", …) — children are
// appended via textContent semantics (no innerHTML), so data strings are safe.
export function el(tag, attrs = {}, ...children) {
  const ns = tag === "svg" || attrs.svg ? "http://www.w3.org/2000/svg" : null;
  const node = ns ? document.createElementNS(ns, tag) : document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "svg") continue;
    if (k.startsWith("on") && typeof v === "function") {
      node.addEventListener(k.slice(2), v);
    } else if (v != null) {
      node.setAttribute(k === "class" ? "class" : k, v);
    }
  }
  append(node, ...children);
  return node;
}

export function svgEl(tag, attrs = {}, ...children) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k.startsWith("on") && typeof v === "function") {
      node.addEventListener(k.slice(2), v);
    } else if (v != null) {
      node.setAttribute(k, v);
    }
  }
  append(node, ...children);
  return node;
}

export function append(node, ...children) {
  for (const c of children.flat()) {
    if (c == null) continue;
    node.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return node;
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
  return node;
}

export function showError(msg) {
  const main = document.querySelector("main");
  clear(main).append(el("div", { class: "error-panel" }, msg));
}

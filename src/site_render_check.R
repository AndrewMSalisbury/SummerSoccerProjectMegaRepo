# site_render_check.R
#
# Post-export smoke test for the static site. Run after export_site_data():
#
#   # in a terminal, from site/:   python -m http.server 8899
#   source("site_render_check.R"); src_render_check()
#
# WHY THIS EXISTS. On 2026-07-26 a `const hold = ...` declaration was deleted
# from coach.js while a reference to it survived. The resulting ReferenceError
# threw inside renderChartCard(), so the coach page rendered its header,
# subtitle and stat tiles and then silently appended NOTHING else — no career
# chart, no strengths, no style, no formations, no player-type fit. It produced
# no console error (the throw is inside an unhandled async init()), `node
# --check` passed (a ReferenceError is a runtime error, not a syntax error),
# and the old smoke test passed too because its only assertion was
# "main.innerText is longer than 200 characters" — and 777 characters of
# half-rendered page clears that easily.
#
# So this checker asserts what actually matters:
#   - error handlers installed BEFORE page scripts run, catching window errors
#     AND unhandledrejection (which is how an async init() failure surfaces)
#   - a per-page MINIMUM CARD COUNT, so a page that stops halfway fails
#   - a per-page minimum text length, kept as a coarse backstop
#
# When a page gains a card, raise its min_cards. That is the point: the numbers
# are a contract, not a guess.

suppressMessages({ library(chromote); library(jsonlite) })

src_render_pages <- list(
  list(url = "index.html",                     min_cards = 1, min_len = 1200),
  list(url = "league.html?id=premier-league",  min_cards = 2, min_len = 2000),
  list(url = "team.html?id=281",               min_cards = 3, min_len = 3000),
  # a fully-populated coach: grade, career chart, strengths, style, formations, fit
  list(url = "coach.html?id=5672",             min_cards = 5, min_len = 3000),
  list(url = "coach.html?id=3517",             min_cards = 3, min_len = 1500),
  list(url = "compare.html?a=5672&b=3517",     min_cards = 2, min_len = 1500),
  list(url = "validation.html",                min_cards = 4, min_len = 6000),
  list(url = "players.html",                   min_cards = 2, min_len = 3000),
  list(url = "builder.html",                   min_cards = 1, min_len = 800)
)

src_render_check <- function(base = "http://localhost:8899",
                             pages = src_render_pages, wait = 4) {
  b <- ChromoteSession$new()
  on.exit(try(b$close(), silent = TRUE), add = TRUE)

  # must be registered before the document's own scripts evaluate, or an error
  # thrown during module init happens before any listener we add afterwards
  b$Page$addScriptToEvaluateOnNewDocument(source = "
    window.__errs = [];
    window.addEventListener('error', e => window.__errs.push('error: ' + e.message));
    window.addEventListener('unhandledrejection',
      e => window.__errs.push('unhandledrejection: ' +
        ((e.reason && e.reason.message) || e.reason)));
  ")

  probe <- "(() => { const m = document.querySelector('main');
     return JSON.stringify({
       len: m ? m.innerText.length : 0,
       cards: m ? m.querySelectorAll('.chart-card, .card, .val-card').length : 0,
       errPanel: !!document.querySelector('.error-panel'),
       errs: window.__errs || [] }); })()"

  fails <- 0
  for (p in pages) {
    invisible(b$Page$navigate(paste0(base, "/", p$url), wait_ = TRUE))
    Sys.sleep(wait)
    r <- fromJSON(b$Runtime$evaluate(probe, returnByValue = TRUE)$result$value)
    bad <- c(
      if (isTRUE(r$errPanel)) "error panel",
      if (length(r$errs))     paste("JS:", paste(r$errs, collapse = "; ")),
      if (r$len   < p$min_len)   sprintf("text %d < %d",  r$len,   p$min_len),
      if (r$cards < p$min_cards) sprintf("cards %d < %d", r$cards, p$min_cards))
    ok <- length(bad) == 0
    if (!ok) fails <- fails + 1
    cat(sprintf("%-34s %-4s len %5d cards %2d %s\n", p$url,
                if (ok) "ok" else "FAIL", r$len, r$cards,
                if (ok) "" else paste(bad, collapse = " | ")))
  }
  cat(sprintf("\n#### failures: %d of %d ####\n", fails, length(pages)))
  invisible(fails)
}

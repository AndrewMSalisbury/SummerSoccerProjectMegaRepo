# Coach Valuation — static site

Presentation site for the football coach valuation project. Design:
`Docs/Website_Design.md`; build plan: `Docs/Website_Implementation_Plan.md`.

## Running locally

The pages fetch JSON with ES modules, which most browsers block on `file://`.
Serve the folder instead:

```
cd site
python -m http.server 8000
```

then open <http://localhost:8000/>.

## Regenerating the data

Everything under `site/data/`, `site/assets/`, and `site/writeup.html` is
generated — do not edit by hand. To rebuild from the latest results:

```r
# in RStudio with working dir src/ (fbcoach.Rproj)
source("site_export.R")
export_site_data()
```

Hand-written files: `*.html` (except `writeup.html`), `css/`, `js/`.

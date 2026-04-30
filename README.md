# EveryAwesome

A single-page web app that aggregates entries from several
[awesome lists](https://github.com/sindresorhus/awesome) into one
searchable, fuzzy-filterable interface.

Live: <https://everyawesome.github.io/EveryAwesome/>


## What it does

- Fetches the readme of each list in [`lists.js`](./lists.js) at build time
- Parses every list-item into a structured entry
  (name, URL, description, category, subcategory, tags)
- Bundles the result into a static `entries.json`
- Serves an Elm SPA that lets you fuzzy-search across all of them
  and filter by source list, category, or tag


## Sources

`lists.js` currently registers 18 awesome lists:

- [`ad-si/awesome-3d-printing`](https://github.com/ad-si/awesome-3d-printing) — 3D Printing
- [`ad-si/awesome-command-line-tools`](https://github.com/ad-si/awesome-command-line-tools) — Command-Line Tools
- [`ad-si/awesome-e-commerce`](https://github.com/ad-si/awesome-e-commerce) — E-Commerce
- [`ad-si/awesome-electronics`](https://github.com/ad-si/awesome-electronics) — Electronics
- [`ad-si/awesome-fabrication`](https://github.com/ad-si/awesome-fabrication) — Fabrication
- [`ad-si/awesome-fp-jobs`](https://github.com/ad-si/awesome-fp-jobs) — FP Jobs
- [`ad-si/awesome-laser-cutting`](https://github.com/ad-si/awesome-laser-cutting) — Laser Cutting
- [`ad-si/awesome-lego`](https://github.com/ad-si/awesome-lego) — Lego
- [`ad-si/awesome-makefile`](https://github.com/ad-si/awesome-makefile) — Makefile
- [`ad-si/awesome-music-production`](https://github.com/ad-si/awesome-music-production) — Music Production
- [`ad-si/awesome-pencil`](https://github.com/ad-si/awesome-pencil) — Pencil
- [`ad-si/awesome-ray-tracing`](https://github.com/ad-si/awesome-ray-tracing) — Ray Tracing
- [`ad-si/awesome-scanning`](https://github.com/ad-si/awesome-scanning) — Scanning
- [`ad-si/awesome-sheet-music`](https://github.com/ad-si/awesome-sheet-music) — Sheet Music
- [`ad-si/awesome-soundfonts`](https://github.com/ad-si/awesome-soundfonts) — Soundfonts
- [`ad-si/awesome-utc`](https://github.com/ad-si/awesome-utc) — UTC
- [`ad-si/awesome-video-production`](https://github.com/ad-si/awesome-video-production) — Video Production
- [`ad-si/awesome-wolfram-language`](https://github.com/ad-si/awesome-wolfram-language) — Wolfram Language

To add another list, append an entry `{ id, name, repo }` to
[`lists.js`](./lists.js) and rerun `make build`.


## Architecture

```
lists.js                    registry of source repos
scripts/parse_awesome.js    markdown → entries.json (markdown-it)
data/raw/<id>.md            fetched readmes (build artifact)
data/entries.json           parsed dataset (build artifact)
webapp/                     elm.land SPA
  src/Pages/Home_.elm         search + filter UI
  src/Shared.elm              loads entries.json via flags
  src/main.css                Tailwind v4 entry
```


## Build & run

Prerequisites: `node`, `npm`, `make`, `curl`, `jq`.

```sh
make help     # list targets
make dev      # fetch + parse + build CSS + start dev server (http://localhost:1234)
make build    # full production build → webapp/dist/
make clean    # remove all build artifacts
```

The first run installs `markdown-it` (root) and Tailwind + elm-land
(in `webapp/`), then fetches every readme from GitHub.


## Search

Fuzzy subsequence matching, fzf-style:

- Each query character must appear in order in the haystack
- Consecutive matches and word-boundary matches score higher
- Name matches are weighted 2× over description matches
- Results sort by score descending; input is debounced by 150 ms

Categorical filters (lists / categories / tags) are intersected with
the search.


## Deployment

`.github/workflows/deploy.yml` runs on every push to `main`:

1. `make build`
2. Rewrites the absolute asset URLs elm-land emits to be document-relative
   (so the site works under a project-page subpath)
3. Copies `index.html` → `404.html` as an SPA fallback
4. Publishes `webapp/dist/` via the standard
   `actions/{configure,upload,deploy}-pages` chain

Hash routing (`useHashRouting: true` in `webapp/elm-land.json`) sidesteps
the SPA-on-subpath problem; URLs look like `/EveryAwesome/#/`.

To enable: in repo Settings → Pages, set **Source** to **GitHub Actions**.

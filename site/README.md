# PortPilot product site — local review

An independent product site, guide, CLI reference and sponsor page. The seven
browser interface studies remain under `docs/design/2026-10-ui-directions/`.

No packages, native app launches, credentials or external requests are needed.

```sh
node site/build.mjs
python3 -m http.server 4328 --bind 127.0.0.1 --directory site/dist
```

Open http://127.0.0.1:4328/. This preview deliberately uses `noindex` metadata
and a disallow-all robots file. Nothing here configures DNS or publishes a site.

The second visual version is at http://127.0.0.1:4328/v2/. The original design
remains at `/`; both share the clickable workspace previews. On desktop,
scrolling through the App / CLI / TUI rows selects the corresponding panel.
A click takes priority until the reader scrolls another fifth of a viewport
(at least 160 pixels). Inner workspace tabs retain keyboard focus and pause
scroll selection while focused. Mobile and reduced-motion readers use manual
tabs. Direct links such as `/v2/#tab-cli` select the requested panel.

`v2.mjs` creates the second set of pages with versioned navigation and search.
`assets/v2.css` and `assets/v2.js` contain its original point drawing of local
app surfaces, inspired by the Architecture and Norrvik references. The app
examples are illustrative, including the simulator's host service. Nothing
queries other devices. La Douceur informed the type pairing: Instrument Sans
and Cormorant Garamond italic, both self-hosted with their font licenses.
Animation pauses offscreen, when the page is hidden, for reduced motion, or
with the explicit pause button. No third-party animation library is required.

Edit `content.mjs` for the guide; `build.mjs` for page structure; and
`assets/site.css` / `assets/site.js` for appearance and interaction.
The build reads the source version from `../package.json` and the commit from
Git. It does not query a release API or label a source version as the latest
published release. Rebuilding after a version bump updates every page.

For the public `portpilot.srinivas.dev` artifact, set the explicit origin:

```sh
PORTPILOT_SITE_ORIGIN=https://portpilot.srinivas.dev \
PORTPILOT_SOURCE_COMMIT="$(git rev-parse HEAD)" \
node site/build.mjs
```

The public build promotes V2 to `/`, keeps the original direction at
`/classic/`, emits canonical URLs and a sitemap, and allows indexing. A build
without `PORTPILOT_SITE_ORIGIN` remains a private local preview. Cloudflare
Pages can build from this repository with root directory `site`, command
`node build.mjs`, output directory `dist`, and the origin environment variable
set to `https://portpilot.srinivas.dev`.

OpenAI Sites publication uses the repository-root `.openai/hosting.json` and
its top-level `dist` static directory so the hosting source preserves the
signed PortPilot Git history. The hosting build and validator set
`PORTPILOT_SITE_OUTPUT=../dist`; local builds omit it and continue to use
`site/dist`. Only those two output locations are accepted.

`PORTPILOT_SOURCE_COMMIT` is optional in the canonical Git checkout. Hosting
packagers must pass the exact signed canonical commit because their temporary
source repository may not have a commit yet; the builder accepts only a full
lowercase SHA.

The search index is built from the rendered guide headings and text. Search,
theme, copy buttons, the example listener map and reduced-motion controls run
locally. The map is synthetic; it never reads or controls real processes.

Installation and CLI examples are grounded in `README.md`, `Package.swift`,
`Sources/PortKillerCLI/CLI.swift`, and `AGENTS.md`. Sponsor URLs are reused from
the Runic and Tokmeter repositories. No native code or installed app is changed.

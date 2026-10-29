# PortPilot website handover

Prepared and updated 2026-10-29. V2 is reconciled with the current PortPilot
security source and prepared for `portpilot.srinivas.dev`. Keep the current
design and interactions. Publication is authorized for this subdomain; the
OpenAI Sites deployment succeeded, and only the custom-domain DNS/TLS gate is
still pending.

## Exact location

| Item | Location |
| --- | --- |
| Current V2 preview | http://127.0.0.1:4328/v2/ |
| Production-layout preview | http://127.0.0.1:4328/ after a public build |
| Original design for comparison | http://127.0.0.1:4328/classic/ after a public build |
| Website worktree | `/Users/srinivaspendela/Sriinnu/Personal/websites/.previews/2026-10-22/portpilot` |
| Editable website source | `/Users/srinivaspendela/Sriinnu/Personal/websites/.previews/2026-10-22/portpilot/site` |
| Generated V2 entry point | `/Users/srinivaspendela/Sriinnu/Personal/websites/.previews/2026-10-22/portpilot/site/dist/v2/index.html` |
| Sites project | `appgprj_6ae332df6edc81919bbd6324f8cc90e0` (`portpilot`) |
| Sites manifest | repository-root `.openai/hosting.json` (`dist`) |
| Generated Sites origin | https://portpilot.humbleboot1.chatgpt.site |
| Intended custom hostname | https://portpilot.srinivas.dev |
| Deployed source | `46be5dfcbfeade6dd979c4c26436fe8aa39e420f` |
| Saved version | `appgprj_6ae332df6edc81919bbd6324f8cc90e0~appgver_6fb2d9f000d8819182ebf995566c5647` |
| Deployment | `appgdep_6ae333e760688191a57fe3d237089222` (succeeded, public) |
| Custom-domain status | pending DNS validation and TLS; CNAME target `custom-domains.chatgpt.site.` |
| Canonical app repository with newer security work | `/Users/srinivaspendela/Sriinnu/Personal/ports` |
| This handover | `site/HANDOVER.md` in the website worktree |

This is an independent, static Node-built product website inside an isolated
PortPilot worktree. It is not an Astro route in the main Srinivas.dev repository.
Do not edit `dist/`; rebuild it from the files below.

## Source baseline

Verified after reconciliation:

| Checkout | Branch | HEAD | Working tree |
| --- | --- | --- | --- |
| Website preview | `codex/portpilot-site-local-20261029` | `a719754c079df89f0507244e3c78be4b084a7340` plus website changes | Website source ready to commit |
| Canonical app | `main` | `a719754c079df89f0507244e3c78be4b084a7340` | Clean |

The website worktree was fast-forwarded to the audited `main` revision before
the security copy was updated. Both checkouts report package version `3.5.7`.
The builder reads the version and Git commit from this worktree, so generated
source links pin to the exact checked-out revision.

Preserve `site/` and commit it before changing Git refs. `site/dist/` is ignored
and generated; the source, assets, font licenses, README, validator and this
handover are the valuable files.

## Build and preview

```sh
cd /Users/srinivaspendela/Sriinnu/Personal/websites/.previews/2026-10-22/portpilot
node site/build.mjs
```

This creates a private preview with the original at `/` and V2 at `/v2/`. For
the public layout, V2 is promoted to `/` and the original moves to `/classic/`:

```sh
PORTPILOT_SITE_ORIGIN=https://portpilot.srinivas.dev \
PORTPILOT_SOURCE_COMMIT="$(git rev-parse HEAD)" \
node site/build.mjs
node site/validate.mjs --public
```

There is no package install, bundler or framework server. Reuse the loopback
server on port 4328 while it is running. If needed, start it from this worktree:

```sh
python3 -m http.server 4328 --bind 127.0.0.1 --directory site/dist
```

Do not kill another listener or silently move the preview to a new port. Builds
without `PORTPILOT_SITE_ORIGIN` have `noindex, nofollow` and disallow-all robots;
the explicit public build emits canonical metadata, a sitemap and public robots.

## Files to edit

| File | Responsibility |
| --- | --- |
| `site/content.mjs` | Eight guide pages: overview, installation, CLI, app, security, privacy, development and FAQ. Start here for security documentation changes. |
| `site/build.mjs` | Shared header/footer, original homepage, sponsor page, guide rendering, search-index creation, source version/commit links and asset copying. Calls `buildV2(out)`. |
| `site/v2.mjs` | V2 hero and generation of the second set of pages. Rewrites navigation and search URLs to `/v2/`. |
| `site/assets/site.css` | Shared base styling and original design. |
| `site/assets/site.js` | Theme, favicon switching, sample previews, tabs, scroll selection, search, copy buttons and guide navigation. Shared by both versions. |
| `site/assets/v2.css` | V2 paper/ink/blue styling, dark palette, layout, typography, logo contrast and responsive rules. |
| `site/assets/v2.js` | Original Canvas drawing of apps/services, app selection/readout, inward observation markers, pointer response and pause/lifecycle controls. |
| `site/assets/favicon*.svg` | Original and V2 light/dark browser icons. |
| `site/README.md` | Build instructions and implementation notes. |

V2 shares content and base assets with V1, then layers its CSS/JS on top. A shared
change can affect both. The V2 builder replaces the original hero by matching
its markup and rewrites root-relative page links, while keeping `/assets/` and
`/studies/` shared. Check both versions if changing that structure.

The build currently creates 21 HTML files: ten authored pages per version and
the shared interface-study index. The seven older browser UI studies are copied
from `docs/design/2026-10-ui-directions/` to `/studies/`; they are separate from
the product site and do not prove those interfaces are wired into the native app.

## Design references and how they were used

The user supplied these references. Architecture, Norrvik and La Douceur are the
strongest influences on this PortPilot V2. Do not claim every supplied reference
was fully watched or implemented.

| Reference | Direction / review status |
| --- | --- |
| [Architecture / Elias Brandt](https://architecture-template.modulify.website/) | Directly reviewed in the browser. Paper background, fine drafting grid, detailed architectural line drawing, oversized type, blue hover emphasis and scroll-led process stages. The user particularly loved the Roman building and ink lines in the wider portfolio project. PortPilot translates this into a drawing of its own local app ecosystem. |
| [Norrvik](https://norrvik-template.modulify.website/) | Directly reviewed in the browser. Point-cloud architecture, technical annotations, measured grids, restrained blue highlights and an explicit motion pause. This informed the app drawing and observatory language. |
| [La Douceur](https://la-douceur-template.modulify.website/) | Directly reviewed in the browser and font metadata checked. Spacious composition, warmth, Instrument Sans with Cormorant Garamond. V2 uses self-hosted Instrument Sans and Cormorant Garamond italic; keep their licenses. |
| [Hardback](https://hardback-template.modulify.website/) | Supplied for conceptual inspiration; public source/styles inspected. No substantial, specific Hardback interaction was reproduced in this pass. |
| [Boat motion posters](https://recent.design/i/vr4ookj-boat-motion-posters) | Supplied for motion inspiration. Reference page/description inspected: particle textures, blue/black contrast and bold motion-poster composition. The full animation was not independently reviewed. |
| [Black Plus](https://blackplus-template.modulify.website/) | The user's explicit reference for **Tokmeter**. Public source/styles inspected, but this is not the primary direction for PortPilot. Avoid turning every subsite into the same dark SaaS layout. |
| [Vullnet Ademaj X video](https://x.com/VullnetAdemaj/status/2113877495904637022/video/1) | User-supplied motion reference. Fetch returned 403 and the video was not watched. Do not describe its contents as verified. |

Some reference URLs failed in the text web reader while loading in Chrome or
returning their public HTML successfully. That failure alone does not mean the
reference site is unavailable. Our artwork is original Canvas/vector code; no
template code, Roman drawing, or commercial reference assets were copied into
the site. No image-generation step is needed for the current artwork.

## User decisions to preserve

- Keep the current version locally available for comparison; continue V2.
- Use clear, visible line work. Earlier faint lines drew explicit criticism.
- The visual must reflect the product's real architecture and purpose.
- The user corrected the generic blocks: “the ports opened can be apps. ios
  app, macapp, tailsafe ..etc etc. not blocks :-)”. The hero now has a browser/dev
  window, an iOS simulator, a network-app icon, and a macOS window. Keep them
  recognizable. The network app remains generically labelled; do not infer a
  specific third-party integration from the user's spelling.
- The observation flow goes **toward PortPilot**. The product reads operating
  system observations. Ports do not emit telemetry to the app. The iOS example
  represents a local simulator/host service, not monitoring an arbitrary phone.
- Hero ports, processes, binds and projects are labelled illustrative data.
  Selecting one updates the sample readout; it does not inspect this machine.
- App / CLI / TUI rows are clickable and keyboard-operable. On desktop, natural
  scrolling selects the row crossing the viewport marker. Do not hijack wheel
  input. Manual selection wins until further scroll; focus inside the preview
  protects the inner tabs. Mobile and reduced-motion readers use manual tabs.
- Direct links such as `/v2/#tab-cli` select that view. The inner Listeners /
  Connections / Schedules tabs are also functional, with separate sample data
  and arrow/Home/End keyboard navigation.
- Motion has a pause/resume control and stops offscreen, when the page is hidden,
  and for reduced motion. Keep those controls.
- Header/footer logos and browser icons must follow the selected theme. This
  was the final requested fix. V2 uses an ink badge in light mode and a pale
  badge in dark mode; the blue slash uses a contrasting shade. The hero mark
  also follows the drawing palette. Preserve both light and dark variants.
- V2 theme preference is `portpilot-v2-theme` in localStorage. Original version
  uses `portpilot-site-theme`. Search and sample interactions run locally.
- Keep the full footer, sponsor details, wiki/field guide, developer instructions,
  installation paths and CLI reference.

Sponsor destinations already used in the site:

- https://github.com/sponsors/sriinnu
- https://buymeacoffee.com/sriinnu

The user's original wider project includes Srinivas.dev, Runic, Tokmeter and
other subdomains. This handover is specifically for PortPilot; do not alter the
other sites as a side effect of updating its security copy.

## Reconcile the newer security work

Read the **current canonical checkout**, starting with `AGENTS.md`, `mission.md`,
`ports-threat-model.md`, `README.md`, and these files added/updated by `a719754`:

- `docs/DAYBREAK_SECURITY_AUDIT_2026-10-29.md`
- `docs/wiki/Security-Measures.md`
- `docs/MENUBAR_REFRESH_REVIEW_2026-10-29.md`

Relevant changed implementation/tests include:

- `Sources/PortManagerLib/ThreatDetector.swift`
- `Sources/PortManagerLib/BlocklistStore.swift`
- `Sources/PortManagerLib/TCPProxyManager.swift`
- `Sources/PortManagerLib/PortManager+Connections.swift`
- `Sources/PortManagerLib/PortManager+CronDiscovery.swift`
- `Sources/PortPilot/Stores/ThreatMonitorStore.swift`
- `Sources/PortPilot/Stores/CronjobController.swift`
- `Sources/PortPilot/SecurityFAQView.swift`
- `Sources/PortKillerCLI/BlocklistCommand.swift` and `CLI.swift`
- `Tests/PortPilotTests/ThreatDetectorTests.swift`
- `Tests/PortPilotTests/BlocklistTests.swift`
- `Tests/PortPilotTests/CronPersistenceConcurrencyTests.swift`
- `scripts/release_policy.sh` and `scripts/release_scripts.test.cjs`

These paths were identified from the commit diff. Two independent read-only
reviews compared the website claims and hosting path with the current source.

Compare the new facts with `site/content.mjs`, homepage feature/limitations copy,
FAQ, privacy/local-state text, CLI help and installation/release guidance. Pin
claims to the correct source revision. Keep these distinctions unless newer
source explicitly and demonstrably changes them:

- Observations are periodic, permission-limited and heuristic. An alert or bind
  address alone does not prove malware, exposure, reachability, or device safety.
- The app runs as the ordinary user. Do not recommend `sudo` for visibility.
- A blocklist annotation is not firewall enforcement.
- App Quick Proxy is a raw TCP forwarder; the CLI proxy is an SSH SOCKS workflow.
- macOS app support and selected CLI/TUI portability do not imply Windows parity.
- Source/test success, installed/live acceptance and a published release are
  separate facts. Recheck current source guidance rather than copying old claims.
- The displayed `3.5.7` is a **source version** from package metadata, not a
  live “latest released version” lookup. No release API has been integrated.

Preserve the native app and operator state. Website validation does not require
launching the app, running Guard, signalling processes, changing cron/Docker,
starting proxies, installing or notarizing anything. Effectful CLI commands were
not run.

## Verification and acceptance

Current website checks:

- Node build and syntax checks passed.
- Preview: 21 generated HTML pages and 788 local references/anchors passed.
- Public layout: 31 generated HTML pages and 1,192 references/anchors passed.
- Public metadata checks cover V2 at `/`, original at `/classic/`, no-indexed
  aliases, canonical URLs, robots, sitemap, build provenance and security headers.
- Local HTTP endpoints for pages, search, scripts and fonts returned 200.
- Browser checks covered desktop tab clicks, scroll-to-TUI selection, inner
  Connections/Schedules content and a 390 × 844 responsive tab-bar/CLI click.
- Search for `proxy` returned links inside `/v2/guide/`, including section anchors.
- App selection updated the sample details, and pause/resume changed state.
- The final header logo, footer logo and browser icon were visually checked in
  both light and dark themes. The final build and shared JS syntax check passed.

This is not an exhaustive accessibility, native-app, security or cross-browser
certification. After updating the source baseline and copy, rebuild and repeat
the relevant local link/anchor, search, theme, tab and responsive checks. Keep
the original design working too. Leave the result locally reviewable and report
the exact source revision plus any remaining verification limits to Srinivas.

Suggested pickup prompt if hosting remains:

> Read this handover and the current PortPilot AGENTS.md. Preserve the committed
> website source. Use the existing PortPilot repository and `site/` build. Verify
> the selected host and DNS state, publish the validated artifact, attach only
> `portpilot.srinivas.dev`, then verify TLS, headers, routes and the exact revision.

# Skins — Theme Contract

A PortPilot theme is a **complete skin**: palette + fonts + geometry,
applied in one tap. Recolors alone are not themes and don't ship.

## The contract

Selecting a skin (Settings → Skin) applies all three layers at once:

| Layer | Source | Example |
|-------|--------|---------|
| Palette | `ThemePalette` (`Palettes+Standard.swift`, `Palettes+Character.swift`) | 17 color pairs, light + dark |
| Fonts | `VisualTheme.recommendedFont` / `recommendedMonoFont` (auto-applied, missing families skipped with a notice) | Noir → Helvetica Neue + Fira Code |
| Geometry | `Theme.usesTightGeometry` (square corners) vs soft radii | Noir → tight; everything else → soft |

Fonts stay individually overridable in Settings → Fonts. The skin never
fights a manual font choice made *after* it — re-tapping the skin
re-applies its pairing (the "Re-apply" button).

Severity colors (`Theme.Severity`) are deliberately outside every skin:
critical must read as critical under any palette.

## Adding a skin

1. Add a `ThemePalette` static in the fitting file.
2. Add the `VisualTheme` case + all seven switch arms in `AppSettings.swift`
   (palette, dark-native, UI font, mono font, subtitle, preview surface).
   The compiler enforces exhaustiveness — a case you skip won't build.
3. If it needs tight geometry, extend `usesTightGeometry` with a comment
   saying why that skin's character demands it.
4. Stored `visualTheme` strings for removed skins fall back to Classic
   (`?? .classic` at load) — never crash on a stale default.

## Cull history (3.5.0)

Removed Papercraft, Nord, Retro, Terminal, Synthwave: five near-identical
silhouettes in different hues. Survivors: Classic, Graphite, Sunset,
Oceanic, Noir, Paperwhite, Solarized, Sentinel — plus Folio, the first
skin authored fully under this contract (serif voice, print palette,
night-desk dark mode).

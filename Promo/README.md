# Hungry Frog App Store teaser

This folder contains a deterministic, compile-gated renderer for the 22-second
Hungry Frog App Store teaser. It renders two independent SwiftUI compositions,
then muxes the real game music and sound effects into H.264/AAC MP4 files.

## Render

From the repository root:

```sh
./Promo/render-app-store-teaser.sh
```

The script builds the iOS Simulator target with `TRAILER_EXPORT`, launches the
exporter, waits for its completion marker, and copies the finished files to
`Promo/exports`. It also generates checkpoint PNGs and two contact sheets when
the bundled Codex Python runtime is available.

Normal builds do not define `TRAILER_EXPORT`. The deterministic timeline,
exporter entry point, and private-component adapters therefore do not exist in
the compiled production app.

## Outputs

- `exports/frog-app-store-teaser-1920x886.mp4` — iPhone landscape layout
- `exports/frog-app-store-teaser-1600x1200.mp4` — iPad landscape layout
- `exports/previews/` — 24 timestamped checkpoint frames per format
- `exports/contact-sheets/` — visual review sheets
- `exports/export-complete.json` — duration/frame-rate manifest

The render uses the production animal artwork, environments, food glyphs,
question card, tutorial arrow, tongue geometry, wrong-answer eyes and poop,
completion flies, ×2 chip, score/life HUD, `app_icon_good`, music, and sound effects.
Trailer-only code controls timing, camera, copy, character crossfades, and the
repeatable fly paths needed for frame-exact offline rendering.

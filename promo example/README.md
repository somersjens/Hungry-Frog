# Flying Penguin App Store teaser

This folder contains the reproducible export wrapper and the final deliverables.
The actual deterministic composition and native frame/audio exporter live in
`Flying Penguin/Promo/TrailerCompositionView.swift` so they compile against and
reuse the production game's SwiftUI assets and visual systems.

## Re-render

Run `./promo/render-app-store-teaser.sh` from the repository root. The script:

1. builds the iOS app for an available simulator;
2. launches it with the isolated `--export-app-store-teaser` flag;
3. waits for the native 30 fps exports to complete;
4. copies the two MP4 files and representative one-second PNG frames here.

The exports are 2048 × 944 and 2048 × 1535 landscape masters. Each format is
laid out independently with the same geometry formulas as normal gameplay,
including the production player, hoop, lane, waterline and cannon proportions.
The timeline itself stays identical in both renders and uses a 1.5× gameplay
pace: midway between the earlier fast cut and the production cruise speed.

No external music, stock footage, generated imagery, or manually recorded
gameplay is used.

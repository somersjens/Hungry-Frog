# App Store teaser QA

## Final deliverables

| File | Dimensions | Duration | Frame rate | Streams |
| --- | ---: | ---: | ---: | --- |
| `frog-app-store-teaser-1920x886.mp4` | 1920×886 | 22.0 s | 30 fps | 1 H.264 video + 1 AAC audio |
| `frog-app-store-teaser-1600x1200.mp4` | 1600×1200 | 22.0 s | 30 fps | 1 H.264 video + 1 AAC audio |

SHA-256:

- `frog-app-store-teaser-1920x886.mp4`: `884d0f73e904b14c54a57c737e63685f78ed9f476175bde023dae24e4b877649`
- `frog-app-store-teaser-1600x1200.mp4`: `82c4a67cbdeeae5731f9a44721d0d982d310dba472935658b2828e807d8e76d4`

## Automated checks

- Trailer build with `TRAILER_EXPORT`: passed.
- Normal Release simulator build without the flag: passed.
- Exactly 660 frames are rendered for each format.
- An independent AVFoundation metadata read confirmed both final dimensions,
  22.0-second durations, 30 fps rates, H.264 video, and AAC audio.
- The exporter reopens each final MP4 with `AVAssetReader`, requires exactly one
  video and one audio track, and decodes both streams through end-of-file before
  writing `export-complete.json`: passed for both outputs.
- Final files were rendered from separate iPhone and iPad layout branches; the
  iPad file is not a crop or scale of the iPhone file.

## Visual checkpoints

The 30-frame contact sheets cover the opening, tutorial arrow, correct tongue
catch, wrong fly, eye/poop reaction, recovery, all character/environment
transitions, five-answer streak, real ×2 state, completion burst, and final app
icon. Review confirmed that promo copy remains inside safe areas, gameplay stays
visible behind copy, and no stale fly remains at the wrong-answer or character
transition boundaries.

The refinement pass confirms the first catch at 2.00 seconds, copy changes at
scene boundaries, zoom beginning during the wrong fly's tongue retraction, the
faster recovery ending exactly when the character sequence begins, doubled
character-showcase timing, the ×2 timer after streak fly three, and completion
flies plus HUD exit at streak fly five. The final `app_icon_good` reveal uses a
lightly blurred live-game background with no green end-card overlay.

An initial blur render exposed black rectangles around transparent fly and
scenery layers. The final pass composites the gameplay before blurring it;
review of both final contact sheets confirms that the artifact is gone.

The final timing refinement adds two seconds before the wrong-fly catch, keeps
the character showcase at 7.20 seconds while shortening every crossfade from
1.32 to 0.66 seconds, forces the production ×2 chip to the English locale, and
limits the app-icon end card to 20.00–22.00 seconds. The contact sheets confirm
long, fully resolved Bunny, Dog, and Crab holds and the wording “Double points!”
in both layouts.

## Intentional trailer-only direction

- The catalog calls the requested rabbit character `bunny`; the trailer uses
  that real catalog character rather than inventing a separate rabbit.
- Character morphs, camera zoom, promo typography, and exact fly trajectories
  are deterministic trailer direction. The displayed game artwork, geometry,
  HUD, reactions, environments, and audio all come from the production app.
- No third-party footage, fonts, music, or downloaded assets are used.

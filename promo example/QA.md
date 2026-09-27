# Final teaser QA

- Master timeline: 22.000 seconds at 30 fps
- Wide export: 2048 × 944, H.264, AAC stereo
- Tall landscape export: 2048 × 1535, H.264, AAC stereo
- Each export uses the production gameplay geometry for its own aspect ratio
- Both complete video streams decode from start to finish without errors
- Both files contain one video stream and one audio stream

Visual checks retained in `exports/`:

- whole-second contact sheets for both sizes;
- before/after transition sheets for both sizes;
- exact hoop-passage, underwater and resurfacing checkpoints;
- source PNG frames for every whole second and transition checkpoint.

The final pass checks that the world and rings move at the teaser's intermediate
1.5× gameplay pace, every retired stack fully clears both canvases, the
character is occluded by the hoop foreground while inside it, and the production
water/splash layers flow continuously into the turbo wake and final hoop set.

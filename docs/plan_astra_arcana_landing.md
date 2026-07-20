# Astra Arcana Landing Screen Plan

- [x] Review the existing campaign-slot, load, and delete APIs.
- [x] Create a full-screen landing screen with the working title and animated space backdrop.
- [x] Present all three campaign slots with start/continue and delete actions.
- [x] Use the two new landing-page music tracks without disrupting in-game music.
- [x] Verify parsing and run a headless startup smoke test.
- [x] Keep landing music through loading; hand off to game music at cinematic start.
- [x] Keep the docking tractor beam outside scaled station transforms and end it at the ship hull.
- [x] Gate world simulation and the loading/cinematic workflow until a campaign slot is selected.
- [x] Give newly created campaign slots distinct default display names.
- [x] Keep campaign storage read-only at the landing page; load a campaign only after Continue.

## Notes

- The three persistent campaign slots already exist as `slot_01` through `slot_03`.
- “Comets” is interpreted as occasional visual fly-bys.
- Verified with `tests/parse_check_scene_scripts.gd` and a six-second headless
  main-scene boot. The headless boot reached initialization without landing
  screen errors; its existing user-directory write warnings are sandbox-related.

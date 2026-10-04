# Outpost Harbor play test

Open `outpost_harbor.tscn` in Godot and press F6, or run `play_outpost_harbor.ps1` from the project root. Main scene and production station generation are unchanged.

- 1 / 2: stage the player outside Kestrel Depot / Crown Haven's capture range.
- D: real PlayerShip autopilot to the approach sphere, tractor capture and docking.
- U: tractor departure to the approach sphere and restored flight controls.
- V: overview / player camera. RMB and wheel use the existing ship camera.
- P: reload the sandbox with the next pair of finishes (default, pirate, research/merchant). Only available while undocked and idle; traffic resets.
- Esc: exit.

The current SystemFactory builds the starfield, planets and asteroid belts. This instance has no generated stations or campaign NPC manager. The scene adds the two new outposts at native scale, four friendly couriers, and shared StationLights beacon drones. It does not load GameRoot or campaign saves, or start story generation. Project autoload initialization still runs. Courier visuals are fitted to a 10 x 10 x 24 envelope in this sandbox; production ships are unchanged.

## Handoff for Claude

The adapter follows the current `scripts/Station.gd` public docking API: `is_berthed`, `get_docking_position`, `approach_sphere_radius`, `autopilot_radius`, `lane_entry_position`, `beam_origin`, `berth_position`, `berth_basis`, and `begin_dock_tractor`. The latter delegates to this scene's isolated procedure instead of UIManager's campaign services. The real PlayerShip navigation calls the adapter without production changes. Beam placement and reservation ownership mirror the existing station harbor sandbox.

Key integration differences:

1. Both models use scale 1.0 and four Dock_* markers. Marker local +X is outward. Ship center is 16 units out. Kestrel docks approach horizontally; Crown Haven approaches vertically. The sphere entry is the intersection of that outward ray with a radius-155 sphere, rather than a radial projection from the station center. This keeps the beam corridor clear.
2. `Radar_Rotor` turns; habitat and docking structure remain fixed. Do not spin the whole outpost.
3. Meshes are joined by material, so their AABBs span open areas. The main stations' box-per-mesh collision strategy would fill these openings. This test uses trimesh collision on the reduced-detail exports. A production implementation may prefer dedicated authored collision shapes.
4. `OutpostTractorBeam.gd` is a test-local copy of DockingTractorBeam with a fallback up vector for vertical beams. Without it, Crown Haven's vertical approach produces colinear look-at warnings. This is the only effect difference to port back if desired.
5. StationLights is reused with drones scaled down to 15% of the large-station size. Amber markers sit beside the approach lane, not inside it.
6. This is an asset/docking test, not a services/menu, campaign persistence, faction, or economy integration.

Files remain in `assets/NewForReview/Outposts/01_KestrelDepot` and `03_CrownHaven`. The test loads GLBs through GLTFDocument directly, avoiding Blender auto-import. No production asset references were replaced.

## Verification

Run the scene headlessly with `-- --outpost-harbor-smoke-test --baseline-offline`, always with a unique `--log-file`. It checks generated content, all eight berths, sampled radius-8 clearance along all tractor corridors, fixed dock markers and moving radar, player autopilot + docking + undocking at both outposts, friendly arrivals, and unchanged main-scene setting. `--outpost-finish=1` or `=2` selects alternate skins for automated runs. `--outpost-all-finishes` cycles through all three sets using the same reload path as P.

`--outpost-harbor-snapshot` renders both overview cameras and Crown Haven tractor/docked views to `.tmp_godot_user/outpost_harbor_*.png` and exits. This must run with rendering enabled. The snapshots are visual checks, not a substitute for the user's hands-on play test.

Completed 2026-10-04: all three paint sets passed the full smoke test, including two scene reloads. Rendered overview, tractor and docked snapshots reviewed. Logs retain project startup certificate-store and shutdown resource-leak warnings; no scene script errors or beam colinearity warnings in the final run. Human flight-feel review remains the purpose of this scene.

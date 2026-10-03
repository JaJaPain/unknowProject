# Station Harbor test scene

Open `scenes/tests/station_harbor/station_harbor.tscn` in Godot and press **F6** (Run Current Scene).
The main scene and campaign setup are unchanged. This scene has its own HUD and traffic controller; it never instantiates GameRoot, loads a campaign, or requests a campaign save. Project autoloads are still present, as with other in-project test scenes.

## Controls

- **1 / 2**: stage the player at Cinder Anchorage / Meridian Exchange. Disabled while clamped or on the beam.
- **D**: use the existing player navigation to approach, then tractor into the authored berth.
- **U**: release clamps and tractor the ship into the departure lane.
- **V**: switch between the station overview and the player's camera.
- **Right-drag / wheel**: orbit / zoom the ship camera.
- **Esc**: close the test.

The station buttons deliberately reposition the player for quick testing. The four friendly logistics ships repeatedly arrive, remain visibly parked for loading, undock, and return. Each has a separate berth, and the player has a dedicated berth. This test does not include campaign station services or jump travel.

## Assets and environment

Uses `SystemFactory.generate()` with a fixed seed for planets, asteroid belts, sky, and sun. The two full-size stations sit above the generated planet plane to keep approach lanes clear. Each has 24 authored berth markers, textured LOD1 geometry, mesh collisions, a rotating habitat, and the same seven floating beacon drones used by the main station. The test's tractor beams originate at the pier markers, using the existing `DockingTractorBeam` effect. The top tier is used for traffic so vertical approaches do not pass through other docking decks.

GLBs are loaded directly from the review folders with GLTFDocument, preserving embedded textures and avoiding Blender re-imports. Keep these existing local assets with the scene:

- `assets/NewForReview/Stations/01_CinderAnchorage/CinderAnchorage_LOD1.glb`
- `assets/NewForReview/Stations/02_MeridianExchange/MeridianExchange_LOD1.glb`

The project's ignore rules exclude GLBs from Git. The scene therefore requires those local files when copied to another machine. Meridian's Blender source was also saved beside Cinder's at `assets/NewForReview/Stations/01_CinderAnchorage/MeridianExchange.blend`.

## Automated check

From the project root, run sequentially with its own log file:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --scene res://scenes/tests/station_harbor/station_harbor.tscn --log-file D:/CodingProjects/spacegame/.tmp_godot_user/test_logs/station_harbor.log -- --baseline-offline --station-harbor-smoke-test
```

Checks generated planets/belts, both player approach/tractor/clamp/undock cycles, 48 fixed berths, rotating habitats, 14 beacon drones, four friendly arrivals, and the unchanged main scene setting. `--station-harbor-snapshot` instead captures two station overviews and a player tractor/docked view in `.tmp_godot_user` when run with the normal renderer.

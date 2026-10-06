# The Lighthouse

Original navigation beacon station for Brief #2 in `docs/set_piece_wishlist.md`.
A weathered, fluted pale-alloy tower carries an open lantern housing. Its lower
two-thirds support 29 mismatched habitat/container modules, catwalks with rails,
tanks, braces, sagging utility cables, three repaired solar wings and three
permanently docked craft hulls converted into homes. No writing, symbols, logos,
faction marks or flying ships.

## Files and scale

- `lighthouse.blend`: editable source; Lighthouse is the active scene. Earlier
  Blender scenes are preserved. Preview cameras/lights are in a separate collection.
- `lighthouse_preview.png`: rendered overview.
- `../../assets/landmarks/lighthouse.glb`: game asset, with no cameras or lights.
- `counts.json` and `validation.json`: geometry and export verification.
- `../../tools/art/build_lighthouse.py`: deterministic construction script.

Metres, unit scale 1. **900 m tall**, approximately **594 x 421 m** across solar
wings and settlement. Root centred at the tower's mid-height; base -450 m,
tip +450 m. **18 meshes, 19 material surfaces, 8 materials, 84,280 triangles**,
48,612 Blender vertices. Export vertices split at hard edges.
Repeated parts are merged by material within tower, lantern, settlement, solar
and converted-hull sections. Large static section pivots are centred on their
bounds. Weathering/faded panel variation is stored as vertex colours and real
patch geometry; no external textures or procedural shader dependencies.

## Godot integration

Y-up GLB, with the tower's long axis along Y. `EmitterRing_Pivot` is centred
at Y=347 m. Its single child `EmitterRing` has two material surfaces. Rotate
the pivot about local Y (Blender Z); the ring clears the stationary cage.

- `LH Beacon emission`: pale cyan core and emitter ring; animate to pulse.
- `LH Warm windows emission`: scattered amber habitation windows.
- `LH Navigation emission`: a few red navigation points; animate to blink.

Duplicate materials per instance before runtime edits. Static emission is included;
pulsing, blinking, ring rotation, bloom, sound, lighting and gameplay wiring are
game-side. No collision or LODs are included. Keep vertex colours enabled on
replacement non-emissive materials to preserve mottling and faded panels.

## Rebuild

With Blender MCP on localhost:9876, run from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_lighthouse.py
```

Use a fresh Blender session for a clean rebuild without duplicate datablock
names. The script creates a new scene, preserves existing scenes, and overwrites
the deliverable paths. Export is restricted to selected objects in the active
scene. Preview lights are hidden in the modelling viewport but render normally.

Validation: Godot 4.6.3 direct GLB import, dimensions, mesh/surface count, emitter
hierarchy and pivot; binary GLB checks for material count, vertex colours,
emission, triangles, scene isolation and absence of cameras/lights.

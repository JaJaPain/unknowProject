# The Silent Fleet's settlement

Original set piece for Brief #3 in `docs/set_piece_wishlist.md`: eight old convoy
ships permanently tied into a hidden town. Distinct hulls include two arks,
a terraced colony transport, container and spine freighters, a tank carrier,
a workshop tender and a colony ferry. Engines are cold and capped. There are
no weapons, battle damage, writing, faction marks, beacons or navigation lights.

## Files and scale

- `silent_fleet.blend`: editable source; Silent Fleet is the active scene.
- `silent_fleet_preview.png`: rendered overview.
- `../../assets/landmarks/silent_fleet.glb`: game asset, no cameras or lights.
- `counts.json` and `validation.json`: source counts and export checks.
- `../../tools/art/build_silent_fleet.py`: reproducible Blender builder.

Metres, unit scale 1. Overall footprint approximately **2,000 x 1,753 m**,
**313 m** deep. The root is centred on the complete settlement's bounds.
**32 mesh objects/surfaces, 7 materials, 29,946 triangles**, 18,018 Blender
vertices. Hard edges may split vertices during glTF export.

Each ship is batched into three material meshes. A later-built central hub,
13 inhabited bridges, exterior trusses, sagging utility lashings, two shared
radiator fields and three greenhouses bind them together. Main sections use
centred mesh pivots. Repaired hull plates and faded paint use vertex colours
and geometry, without external textures or procedural material dependencies.
Optional detached shuttle meshes are omitted.

## Godot integration

GLB is Y-up; the settlement spreads across XZ. No animation is required: these
ships are permanently docked. Static warm windows use `SF Dim warm windows`;
the three small gardens use `SF Greenhouse glow`. These are the only emissive
materials. They are deliberately restrained; presentation lights in Blender
are separate from the export. Keep vertex colours enabled when replacing hull
materials, and duplicate materials before per-instance edits.

No collision, LODs, sound or gameplay wiring is included. The asset does not
contain navigation lights, illuminated engines or active beacons.

## Rebuild and validation

With Blender MCP listening on localhost:9876, from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_silent_fleet.py
```

Use a fresh Blender session to avoid duplicate datablock names. The builder
creates a new scene, preserves other scenes, and overwrites these deliverables.
Export is restricted to selected objects in the active scene. Preview cameras
and lights remain in a separate collection and are hidden in the modelling
viewport. The saved source may also contain preserved earlier scenes.

Validation covers Godot 4.6.3 GLB import, overall footprint, mesh count and
absence of cameras/lights; GLB checks cover scene isolation, triangle/material
counts, vertex colours, eight ship sections and exactly two emissive materials.

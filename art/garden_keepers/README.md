# The Garden keepers' station

Original station for Brief #5 in `docs/set_piece_wishlist.md`. Six long and
short ribbed greenhouses branch from a compact pressure spine and protected
seed vault. Warm ivory and pale sage structures carry neatly matched repairs.
There is no planet mesh, writing, logo, faction mark, weapon or flying ship.

## Files and scale

- `garden_keepers.blend`: editable Blender source, Garden Keepers scene active.
- `garden_keepers_preview.png`: rendered overview.
- `../../assets/landmarks/garden_keepers.glb`: game asset, no cameras or lights.
- `counts.json`, `validation.json`: dimensions, geometry and export checks.
- `../../tools/art/build_garden_keepers.py`: reproducible builder.

Metres, unit scale 1. **600 m** across the solar wings; overall Blender XYZ
dimensions **404.5 x 600 x 90 m**. **17 meshes/surfaces, 8 materials,
37,456 triangles**, 21,828 source vertices. Sections are batched by material;
glass is one separate mesh/material. Main static section pivots are centred
on their bounds. The root is at the central spine's construction origin.

Includes six greenhouses with simple crop masses, armoured seed vault,
two living/service modules, three water/nutrient tanks, three suspended supply
pods with straps, a two-berth docking ring and two broad solar wings.
Optional tending drones are omitted. Hull variation uses vertex colours;
no external textures are required.

## Godot integration

Y-up GLB; the station spreads across XZ. `SolarPort_Pivot` and
`SolarStarboard_Pivot` independently rotate the two wings about their local
Z axes in Godot (Blender Y). Both frames and panel cells follow their pivot.
Use modest tracking angles and check clearance in the gameplay setup.

`GK Tinted greenhouse glass` uses tinted, double-sided alpha-blended panes
with alpha 0.19. Crop masses and growing-light strips are actual geometry
inside the glass. The glass does not depend on a transmission extension.

- `GK Growing light`: gentle green interior strips.
- `GK Living windows`: warm inhabited windows.
- `GK Dock navigation`: small cyan docking lights.

Duplicate materials for instance-specific edits. Keep vertex colours enabled
on non-glass hull/crop materials. Transparent sorting and bloom depend on the
game renderer; inspect the glass in the final station scene. No collision,
LODs, animation, audio, planet or gameplay wiring is included.

## Rebuild and validation

With Blender MCP on localhost:9876, from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_garden_keepers.py
```

The builder creates a new scene, preserves earlier scenes and overwrites these
deliverables. Use a fresh Blender session to avoid duplicate datablock names.
Only selected objects in the active scene are exported. Preview camera/lights
are separate and hidden in the modelling viewport, but available for rendering.

Checks cover Godot 4.6.3 direct GLB import, 600 m span, mesh/surface counts and
no cameras/lights. GLB checks cover scene isolation, glass alpha, vertex colours,
emissive materials, triangle count and both solar-pivot hierarchies. The final
Blender render was visually inspected for visible crops through the glass.

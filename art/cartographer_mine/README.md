# The Cartographer's secret mine

Original set piece for Brief #4 in `docs/set_piece_wishlist.md`: a covert,
efficient industrial operation cut into a large irregular asteroid. The
excavation is a real open depression with seven stepped bench/floor levels,
fresh cut faces and restrained metallic ore seams. The exterior includes
faceted rock, irregular ridges and smaller crater depressions.

## Deliverables and scale

- `cartographer_mine.blend`: editable Blender source, mine scene active.
- `cartographer_mine_preview.png`: rendered overview.
- `cartographer_mine_pit_detail.png`: overhead view of the excavation and conveyors.
- `../../assets/landmarks/cartographer_mine.glb`: game asset, no cameras/lights.
- `counts.json`, `validation.json`: geometry counts and validation results.
- `../../tools/art/build_cartographer_mine.py`: deterministic builder.

Metres, unit scale 1. Asteroid exterior is **1,500 m wide**. Including docked
haulers, the site is approximately **1,943 x 1,200 x 1,086 m** in Blender XYZ.
**29 meshes/surfaces, 8 materials, 39,384 triangles**, 21,380 source vertices.
Large section pivots are centred on their mesh bounds. Root is at the
asteroid's construction origin; it is not the complete dock's bounds centre.

Equipment includes two elevated bucket conveyors and a pit-floor extraction
head, uniform refinery blocks, four tanks, two loading cranes, a partly buried
crew habitat, utility passages and three physically moored ore haulers.
Ships are static, with cold engines. No text, logos, symbols, weapons or flying
ships. Wear and rock colour variation use vertex colours; no external textures.

## Godot integration

GLB uses Y-up; the open pit faces +Y. Blender's Z becomes Godot Y.
`CM Cold worklights` controls restrained white-blue worklight surfaces in the
pit and along the conveyors; `CM Habitat amber` controls the small habitat
windows. These are the only emissive materials. Game-side lights and glow are
not included in the export. Duplicate materials before per-instance edits.

`Conveyor belts | Conveyor rubber` is a separate mesh for the two belt strips.
Its UVs run U=0..1 across each belt and V=0..1 from pit to refinery, ready for
a scrolling shader. Ore buckets are separately batched geometry and currently
static. There are no animations, collision meshes, LODs or gameplay wiring.
Keep vertex colours enabled if replacing rock or dust materials.

## Rebuild and validation

With Blender MCP on localhost:9876, run from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_cartographer_mine.py
```

Use a fresh Blender session to avoid duplicate datablock names. The builder
creates a scene, preserves existing scenes, and overwrites deliverable paths.
Only selected objects in the active scene are exported. Preview cameras and
lights are in a separate collection, hidden in the modelling viewport.
The builder renders the overview; the additional pit view is a review render.

Validation covers Godot 4.6.3 direct import, asteroid dimensions, mesh/surface
counts, separate pit and belt meshes and no cameras/lights. GLB checks cover
scene isolation, three haulers, triangle/material counts, vertex colours,
belt UVs and exactly two emissive materials. Both rendered views were inspected.

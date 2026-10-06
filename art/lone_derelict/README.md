# A lone derelict ship

Original reusable working hauler for Brief #7 in `docs/set_piece_wishlist.md`.
Approximately 300 m long, with a plain spine, cargo hold, forward bridge and
cold aft engines. One side is genuinely torn open: absent shell panels expose
decks, frames, bulkheads, a long clear passage and retained cargo. Jagged metal
lips and scorching border the breach; frost/dust marks the underside.
No writing, registration, logos, faction marks, bodies or firing weapons.

## Files and budget

- `lone_derelict.blend`: editable Blender source, derelict scene active.
- `lone_derelict_preview.png`: rendered view into the breached side.
- `../../assets/landmarks/lone_derelict.glb`: game export, no cameras/lights.
- `counts.json`, `validation.json`, `breach_clearance.json`: verification data.
- `../../tools/art/build_lone_derelict.py`: reproducible builder.

Metres, unit scale 1. Envelope **301.7 x 106.1 x 71.75 m** in Blender XYZ,
including drifting containers and the beacon mast. **13 meshes, 15 material
surfaces, 7 materials, 3,818 triangles**, 2,420 source vertices. Well below
the requested 30 meshes / 20k triangles. Hull and visible interior are batched
by material. Two `DriftingCargo_01` / `DriftingCargo_02` objects have centred
pivots and two material surfaces each; they can drift independently.

## Godot use

GLB is Y-up. Bow is +X; breach faces +Z (Blender -Y). Root lies at the spine
origin. The opening runs approximately X=-68..68 m. Inside, a passage runs
along X with exposed upper ledges and side compartments. Entrance and passage
ray samples confirm open geometry; no collision or drone navigation is supplied.
The clearance check samples a 95 m passage on a 6 x 6 m cross-section grid;
it is not a full swept-volume or flight simulation.

`LD Neutral hull tint` and `LD Muted accent tint` use standard glTF base-colour
factors multiplied by grayscale vertex weathering. Duplicate their Godot
materials and change albedo colour to reuse the ship in different settings.
Keep vertex colours enabled. Other surfaces use baked vertex colour variation.
There are no external textures.

- `LD Emergency emission`: four tiny fixtures deep inside; turn off or flicker.
- `LD Beacon emission`: one hull beacon for the optional transmitting state.

These are the only emissive materials; all engines and bridge windows are dark.
No blinking, drift, collision, LODs, audio or gameplay wiring is included.

## Rebuild and verification

With Blender MCP on localhost:9876, run from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_lone_derelict.py
```

The builder creates a new scene, preserves prior scenes and overwrites the
deliverables. Use a fresh Blender session to avoid duplicate names. Export
is restricted to selected objects in the active scene. Preview camera/lights
are in a separate collection, hidden in the modelling viewport.

The builder temporarily exports grayscale vertex colours directly, writes
standard glTF material tint factors, then restores Blender's tint nodes. Use
this export path to preserve the intended tint behaviour; a manual Blender
export of its Multiply nodes may omit those factors.

Verified in Godot 4.6.3: import, dimensions, mesh/surface counts, two separate
containers and tint materials with vertex colours. GLB checks cover geometry
budget, material factors, scene isolation and absence of cameras/lights.
Final render inspected and breach geometry sampled with Blender BVH rays.

# The Archive — Brief #9

Seven tall, narrow library stacks hang beneath three large fabric lift envelopes.
Warm stone-like hulls, bronze storey bands and pilasters, many small reading
windows, staggered enclosed bridges, a railed reading balcony and a small lower
docking ring convey an old, carefully maintained archive. The envelopes have
cloth gores, sewn seams, reinforcing belts and suspension shoes. No writing,
symbols, faction marks, weapons, flying ships, books or exterior page motifs.

## Deliverables

- [Game GLB](../../assets/landmarks/archive.glb)
- [Editable Blender source](archive.blend): `The Archive` scene active.
- [Overview render](archive_preview.png) and [rear render](archive_rear.png).
- [Counts](counts.json), [binary export checks](validation_glb.json),
  [Godot import checks](validation_godot.json).
- [Reproducible builder](../../tools/art/build_archive.py).

**601 m wide × 422 m deep × 792 m tall.** Metres, scale 1. Blender Z-up;
GLB/Godot Y-up. **23 meshes / 23 material surfaces, 7 materials,
87,144 triangles, 63,408 Blender source vertices.** GLB approximately 6.4 MB.
All geometry is batched by material within structural sections. Mesh pivots
are centred on their bounds; the station root remains at the central spine's
reference origin. Blender bounds: (-300.44, -147, -332.5) to
(300.47, 274.58, 459.51) m. No textures or procedural shader dependencies.

## Materials and animation hooks

| Material | Purpose |
|---|---|
| `AR Warm limestone hull` | Pale warm stacks, bridge roofs/floors, dock |
| `AR Aged bronze framing` | Storey bands, pilasters, suspension and frames |
| `AR Matte woven envelopes` | Opaque, high-roughness fabric; subtle gore variations |
| `AR Recessed glazing` | Dark window and bridge recesses |
| `AR Reading windows` | Warm emission up all seven stacks |
| `AR Walkway lamps` | Separate soft bridge and dock lamp emission |
| `AR Dim red navigation` | Two dim red lights on the outer envelopes |

Keep vertex colours enabled for the four non-emissive materials. Emission is
separate from the structural materials; bloom is game-side. Some stack windows
are intentionally shuttered. Duplicate materials before per-instance edits.

`Envelope01_Pivot`, `Envelope02_Pivot`, `Envelope03_Pivot` each parent an
envelope's fabric, suspension shoe/straps and any navigation beacon, with a
centred pivot. Suitable for very subtle slow rotation. Lower suspension cables
are fixed geometry: larger sway requires game-side cable deformation to avoid
visible separation. No animation, collision or LOD meshes are included.

The lower dock is centred at Blender (0, -22, -325), equivalent to Godot
(0, -325, 22), with two small berths. The gas giant/clouds are not in the model;
the game supplies them. The existing `LodestarLandmark.gd` model lookup already
uses `res://assets/landmarks/archive.glb`; no gameplay scripts were changed.

## Validation and rebuild

Verified the GLB directly and imported it with Godot 4.6.3: one scene, 23
meshes/surfaces, seven materials, three distinct emission materials, three
envelope pivots, correct dimensions, zero cameras/lights and no external textures.
Overview and rear Blender renders were visually inspected. A live gameplay
placement/performance test has not been run; surface count is not a claim about
total in-game draw calls. The full-project headless run also emitted existing
service/certificate/shutdown warnings, while the Archive validation passed.

With Blender's local MCP server on port 9876:

```powershell
python tools/art/blender_rpc.py tools/art/build_archive.py
python tools/art/check_archive_export.py
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/art/validate_archive.gd --log-file D:/CodingProjects/spacegame/.tmp_godot_user/test_logs/archive_validation.log
```

The builder rebuilds its own tagged Archive scene and preserves unrelated open
scenes. It writes the GLB, source blend, counts and overview render. Preview
cameras/lights occupy a separate collection and are excluded from the GLB.

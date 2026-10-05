# The Humming Gate

Original, intact pre-decline jump gate built in Blender for `docs/set_piece_wishlist.md`.
48 precise pale-alloy segments, six forked crown pylons, recessed titanium details,
fine seams and an offset luminous inner halo. No text, logos, damage or other ships.
Optional maintenance drones are omitted.

## Deliverables

- `humming_gate.blend`: editable geometry plus a separate preview camera/light collection.
- `humming_gate_preview.png`: rendered three-quarter view.
- `../../assets/landmarks/humming_gate.glb`: game export; no cameras or lights.
- `../../tools/art/build_humming_gate.py`: reproducible Blender construction script.
- `counts.json`: source geometry counts and dimensions.

## Scale and budget

Metres, unit scale 1. Main ring including edge lips: **1,202 m diameter**.
Crown tip-to-tip diameter: **1,546 m**. Clear aperture: **919 m**.
Main structure depth: **80 m**. Inner halo plane: **30 m forward**.
13 mesh objects, 15 material surfaces, 6 shared materials, 59,800 source vertices,
115,780 triangles. GLB vertices can be higher because normals split at hard edges.
Repeated segments are batched by material and section; there are no individual
segment objects or textures. Geometry has crisp, intentionally machined edges.

## Godot use

The GLB uses glTF Y-up: ring lies in XZ, with its normal along Y.
`HummingGate` is centred on the aperture. `InnerRing_Pivot` is centred in the
offset halo plane. Rotate this pivot about its **local Y axis** in Godot
(local Z in the Blender source). Its single `InnerRing` mesh has three material
surfaces, keeping the entire halo independently animatable.

`HG Inner resonance emission` controls the continuous inner band;
`HG Segment point emission` controls the small segment and crown lights.
Both use glTF emission with strength, currently a restrained ice cyan.
Duplicate these materials per instance before changing their colour/energy.
Hum audio, environmental lighting, glow/bloom and rotation are game-side effects.
No portal disk, collision, LODs or game-script wiring are included in this asset.

## Rebuild

With Blender MCP listening on localhost:9876, from the project root:

```powershell
python tools/art/blender_rpc.py tools/art/build_humming_gate.py
```

The builder creates a new scene and preserves existing scenes. Rebuilding writes
the same deliverable paths; use a fresh Blender file to avoid duplicate source
scenes/material names. Preview cameras and lights are excluded using selected-only
export. The source remains open in Blender for inspection.

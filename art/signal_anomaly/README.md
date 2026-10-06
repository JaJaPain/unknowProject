# A signal anomaly site

Original reusable set piece for Brief #8 in `docs/set_piece_wishlist.md`.
Seven unequal, slightly leaning dark shards surround an empty centre, with
three smaller loose fragments. The surfaces are almost black and slightly
glossy. Thin longitudinal inlays and faint dust lines follow the facets without
forming writing or symbols. No ship parts, machinery, faces, creatures or
faction marks are included.

## Files and budget

- `signal_anomaly.blend`: editable Blender source; anomaly scene active.
- `signal_anomaly_preview.png`: rendered overview.
- `../../assets/landmarks/signal_anomaly.glb`: game asset, no cameras/lights.
- `counts.json`, `validation.json`: dimensions and export verification.
- `../../tools/art/build_signal_anomaly.py`: reproducible builder.

Metres, unit scale 1. **133 x 123 m footprint, 150 m tall** in Blender XYZ.
**7 meshes/surfaces, 4 materials, 1,256 triangles**, 1,154 source vertices.
The main cluster, dust inlays and luminous seams are each batched. No textures
or procedural shader dependencies are required. Root is at the centre of the
empty ring; static mesh pivots use their bounds centres.

## Godot integration

Y-up GLB: shards are tall along Godot Y. `LooseShard_01`, `LooseShard_02`
and `LooseShard_03` are separate meshes with centred pivots for slow rotation
or drift. They share the main dark material and have no independent lights.

- `SA Cold seam emission`: thin cyan seams, ready for signal-synchronised pulses.
- `SA Central faint glow`: small translucent glow at the empty centre.

`CentreGlow` is its own mesh, centred at the root origin. Scale it, hide it or
fade its material independently. It uses alpha 0.16 and low emission; bloom
and environmental lighting are game-side. The central mesh is small enough
that most of the space inside the ring remains empty. Duplicate materials
before per-instance edits. Keep vertex colours enabled on dark/dust surfaces.

No collision, LODs, signal behaviour, audio, pulsing or drift animations are
included. The Blender preview uses a separate presentation light rig; none
of those lights are present in the GLB.

## Rebuild and validation

With Blender MCP on localhost:9876, from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_signal_anomaly.py
```

The builder creates a new scene, preserves existing scenes and overwrites the
deliverables. Use a fresh Blender session to avoid duplicate datablock names.
Only selected objects in the active scene are exported. Camera and preview
lights occupy a separate collection and are hidden in the modelling viewport.

Verified in Godot 4.6.3: import, 150 m height, mesh/surface counts, independent
central glow and three loose shards. GLB checks cover scene isolation,
triangle/material counts, exactly two emissive materials, centre transparency
and no cameras/lights. Final render visually inspected.

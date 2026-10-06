# The Quiet War cache vault

Original set piece for Brief #6 in `docs/set_piece_wishlist.md`: a squat,
faceted, sealed military bunker with overlapping gunmetal/bronze plates and
heavy buttress ribs. Upper armour has real recessed impact dents and gouges,
with intact plate thickness beneath them. Dark surface variation represents
scorching and age, not repair patches or rust.

Five ruined defence platforms surround the core. Three have drooping, capped
barrel remnants; two have broken mount stubs. None are functional. Bare anchor
arms extend toward the absent wreck field. Three loose armour plates are
separate objects for optional drift. No ships, bodies, writing, symbols,
logos, flags or faction marks are included.

## Files and scale

- `quiet_war_vault.blend`: editable source; Quiet War Vault scene active.
- `quiet_war_vault_preview.png`: rendered overview.
- `../../assets/landmarks/quiet_war_vault.glb`: game export, no cameras/lights.
- `counts.json`, `validation.json`: dimensions and verification results.
- `../../tools/art/build_quiet_war_vault.py`: reproducible builder.

Metres, unit scale 1. Complete envelope approximately **500 x 438 x 142 m**
in Blender XYZ, including the dead perimeter and loose plates. The root is
centred on the core's construction axis; large static section pivots use their
bounds centres. **13 meshes, 15 material surfaces, 6 materials, 10,318
triangles**, 5,640 source vertices. Geometry is intentionally angular and
batched by section/material. Colour variation is stored as vertex colours;
there are no external textures or procedural shader dependencies.

## Godot integration

Y-up GLB. The front entrance faces +Z in Godot (Blender -Y).
`VaultDoor_Pivot` sits at Godot (0, 0, 175.047 m), centred in the closed
hatch. Its single child `VaultDoor` has three material surfaces. The hatch is
separate from the frame, locks and light seam. For a later reveal, retract it
outward along local +Z; no opening animation is baked. A shallow dark vestibule
and intact inner bulkhead are behind it, not a furnished vault interior.

- `QW Faint core status`: six tiny dim red/amber status points.
- `QW Sealed door seam`: thin warm seam around the hatch.

These are the only emissive materials; the perimeter is completely unlit.
Pulsing, glow and door logic are game-side. Duplicate materials before
per-instance edits. `LoosePlate_01`, `LoosePlate_02`, and `LoosePlate_03`
(names include a material suffix) have centred pivots for gentle drift.
No collision, LODs, audio, working weapons, gameplay scripts or surrounding
twin wreck field are included.

## Rebuild and validation

With Blender MCP on localhost:9876, from the repository root:

```powershell
python tools/art/blender_rpc.py tools/art/build_quiet_war_vault.py
```

The builder creates a new scene, preserves existing scenes, and overwrites
these deliverables. Use a fresh Blender session to avoid duplicate names.
Export is selected-only and restricted to the active scene. Preview lights
and camera live in their own collection and are hidden in the modelling
viewport. The source may retain earlier scenes from the shared Blender session.

Validation covers Godot 4.6.3 import, dimensions, mesh/surface counts, door
hierarchy and three separate debris plates. Binary GLB checks cover scene
isolation, material/triangle counts, vertex colours, two emissive materials
and absence of exported cameras/lights. Final render visually inspected.

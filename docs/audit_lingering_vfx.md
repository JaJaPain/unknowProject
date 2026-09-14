# Lingering Visual Effects Audit

Reviewed: 2026-06-21  
Sources: `scripts/NPCShip.gd`, `scripts/Wreckage.gd`, `scripts/PlayerShip.gd`, `scripts/NPCSalvager.gd`, `scripts/visuals/ImpactEffect.gd`, `scripts/visuals/EngineExhaust.gd`

## Bug Found: Engine Glow Surviving on Wreckage

**Root cause**: `NPCShip.die()` called `engine_glow.queue_free()` before `Wreckage.initialize(visual)`. Since `queue_free` defers deletion to end-of-frame, the engine glow was still a child of `visual` when `visual.duplicate()` ran inside the wreckage initializer. The duplicate captured the glowing MultiMeshInstance3D, and `_apply_wrecked_material` only handled `MeshInstance3D` nodes — the MultiMesh glow passed through untouched, leaving a bright emissive engine glow on the burnt-out wreckage hull.

**Fix applied (two layers)**:
1. `NPCShip.die()`: `remove_child()` the engine glow from its parent *before* `queue_free()`, so the duplicate never captures it.
2. `Wreckage._apply_wrecked_material()`: Strip `MultiMeshInstance3D` and `Light3D` nodes from the duplicated hull as a safety net, so any future glow-type nodes also get cleaned.

## Other Patterns Checked (all clean)

| Pattern | Status | Notes |
|---------|--------|-------|
| ImpactEffect hit/explosion containers | Clean | Self-cleanup via `create_timer(0.5/1.5)`, parented to system root |
| Player mining laser | Clean | Hidden when target invalid, child of ship |
| Player mine particles (top_level) | Clean | `emitting = false` when laser hidden, child of ship |
| Player boost flames | Clean | Hidden when boost inactive, child of ship |
| Player exhaust (EngineExhaust) | Clean | Child of ship, freed with ship |
| Player drones (top_level during collect) | Clean | Children of ship, freed with ship |
| Camera pivot (top_level) | Clean | Child of ship, freed with ship on death |
| Salvager laser beam | Clean | Hidden in every state transition, child of salvager |
| JumpGate charge tween | Clean | `create_tween()` bound to gate node, freed with system |
| Projectiles on system root | Clean | Self-destruct via lifetime timer |
| Wreckage on system root | Clean | Freed by salvager or system transition |
| MainScene salvager respawn timer | Safe | SceneTree timer on freed node — Godot ignores the callback |

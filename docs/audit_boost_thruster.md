# Boost & Thruster Visual Polish Audit

Reviewed: 2026-06-21  
Sources: `scripts/PlayerShip.gd`, `scripts/visuals/EngineExhaust.gd`, `scripts/UIManager.gd`

## Current State

### Engine Exhaust (idle/cruise)
- **Implementation**: `EngineExhaust.create_exhaust()` — spheres at thruster points, unshaded emissive material
- **Color**: Cyan-blue (`Color(0.15, 0.75, 1.0)`)
- **Behavior**: Scales with `speed_ratio` — hidden at rest, grows with speed, subtle sine pulse
- **Assessment**: Functional. Exhaust disappears at zero speed (good) and scales proportionally.

### Boost Effect (active boost)
- **Implementation**: `_create_boost_effect_at()` — sphere meshes + omni lights at thruster points
- **Color**: Cyan (`Color(0.25, 0.85, 1.0)`)
- **Behavior**: Visible only during boost, sine pulse on scale and light energy
- **UI Feedback**: Boost button shows countdown timer, cyan tint when active, grey when cooling down

### Thruster Point Detection
- **Implementation**: `_find_thruster_points()` — walks scene tree looking for nodes named "thruster", "engine", "exhaust", or "nozzle"
- **Fallback**: Two hardcoded positions (`Vector3(-1.4, -0.1, 4.7)` and `Vector3(1.4, -0.1, 4.7)`) if no named points found

## Findings

### Present and Working
- Exhaust scales with speed — hidden at rest, proportional during flight
- Boost exhaust has distinct larger/brighter appearance vs cruise
- Boost button gives clear timer + color feedback (cyan = active, grey = cooldown)
- Tooltip on boost button: "25% speed boost for 5 seconds. 60 second cooldown."
- Thruster fallback positions prevent missing exhaust on ships without named markers

### Missing Polish

1. **No camera shake on boost activation** — boost feels flat; a brief 0.1s shake would sell the acceleration
2. **No heat glow / color shift** — exhaust color stays identical between cruise and boost. A warmer white-hot core during boost would differentiate them visually
3. **No exhaust trail / stretch on boost** — the sphere meshes pulse but don't elongate proportionally to speed during boost. Current stretch goes from 1.6 to ~2.0 vs the base 0.6-1.4 — the difference is subtle
4. **No cooldown visual on ship** — boost ending has no visual cue on the ship itself (only the UI button changes). A brief exhaust flicker or fade-out would help
5. **No boost activation flash** — no bright initial flash when boost fires. A brief billboard flare at the thruster points would punctuate activation
6. **Exhaust disappears abruptly at zero speed** — could fade out over ~0.2s instead of snapping invisible

### Not Missing (intentional)
- No NPC exhaust: NPC ships have their own `engine_glow` OmniLight system (simpler, no mesh exhaust)
- No drone exhaust: mining drones are too small for visible exhaust

## Potential Safe Fixes (effect-only)

All deferred — these need design sign-off on feel:
1. Brief camera shake on boost activation
2. Warmer exhaust color ramp during boost
3. Billboard flare at thruster points on boost start
4. Smooth fade-out when exhaust goes to zero speed

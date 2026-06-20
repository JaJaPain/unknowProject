# Visual Effects Implementation Plan

**Branch:** `segment-3/economy-stores-events`
**Date:** 2026-06-20

Three visual-only features that do not touch gameplay logic, physics, damage, cooldowns, or any game state. Every change is purely cosmetic — rendering pipeline additions that layer on top of existing systems.

---

## Feature 1: Bloom / Glow Post-Processing

### What It Does
Enables Godot's built-in glow post-processing on the Environment resource so that emissive materials (engine glows, sun, nebulas, projectiles, boost flames, drone lights) naturally bloom outward. Zero new nodes or scripts — just Environment property changes.

### Why It's Safe
- Glow is a screen-space post-process — it reads the HDR framebuffer and adds blur around bright pixels. It does not affect collision, physics, `take_damage()`, or any game state.
- All emissive materials already exist (NPC engine glow at 4.0x emission, boost flames at 5.0x, drones at 3.0x, sun at 2.0x star energy, projectiles are unshaded full-brightness). Bloom just makes them visually bleed light.
- The `Environment` resource is already created in three places. We add glow properties to each.

### Current State (What Exists)
- **`scenes/systems/system_start.tscn`** — `Environment` with `background_mode=1`, `ambient_light_energy=0.45`. No glow settings.
- **`scenes/systems/system_test.tscn`** — `Environment` with `background_mode=1`, `ambient_light_energy=0.4`. No glow settings.
- **`scripts/generation/SystemFactory.gd:63-72`** — Creates `Environment.new()` programmatically with `BG_COLOR`, ambient color/energy. No glow settings.

### Implementation Checkpoints

- [x] **1.1 — Create helper function `_apply_glow(env: Environment)`**
  - File: `scripts/visuals/SystemAmbience.gd`
  - Add a static function that takes an Environment and sets glow properties:
    - `env.glow_enabled = true`
    - `env.glow_intensity = 0.75` (subtle, not overwhelming)
    - `env.glow_strength = 1.0`
    - `env.glow_bloom = 0.1` (slight bleed beyond bright areas)
    - `env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE`
    - `env.glow_hdr_threshold = 0.8` (only pixels above this brightness bloom)
    - `env.glow_hdr_scale = 2.0`
    - Enable 2-3 glow levels for varying blur radii (levels 1, 2, 4)
  - Centralizing in SystemAmbience means all three Environment creation sites call the same function, keeping values consistent.

- [x] **1.2 — Apply glow in SystemFactory (generated systems)**
  - File: `scripts/generation/SystemFactory.gd`
  - After line 68 (`env.ambient_light_energy = config.ambient_energy`), add:
    - `SystemAmbience.apply_glow(env)`
  - This covers all procedurally generated systems.

- [x] **1.3 — Apply glow in system_start.tscn**
  - File: `scenes/systems/system_start.tscn`
  - Add glow properties to the existing `[sub_resource type="Environment" id="Environment_1"]` block.
  - Same values as the helper function.

- [x] **1.4 — Apply glow in system_test.tscn**
  - File: `scenes/systems/system_test.tscn`
  - Add glow properties to the existing `[sub_resource type="Environment" id="Environment_test"]` block.
  - Same values as the helper function.

- [ ] **1.5 — Tonemap adjustment (optional, evaluate visually)**
  - If bloom makes the scene look washed out, add tonemap settings:
    - `env.tonemap_mode = Environment.TONE_MAP_ACES` (filmic, prevents clipping)
    - `env.tonemap_white = 6.0`
  - This is a tuning step — may not be needed.

- [ ] **1.6 — Visual verification**
  - Launch game, visit the start system (Indy's Cradle). Confirm:
    - Sun has visible bloom halo
    - NPC engine glows bloom softly (cyan/orange depending on faction)
    - Player boost flames bloom when active
    - Nebula clouds have subtle glow at bright regions
    - Projectiles glow during combat
    - Nothing is blindingly bright or washed out
  - Travel to a generated system via gate. Confirm bloom carries over.
  - Check performance: bloom should add <1ms on modern GPUs.

### Files Modified
- `scripts/visuals/SystemAmbience.gd` (new static function)
- `scripts/generation/SystemFactory.gd` (one line addition)
- `scenes/systems/system_start.tscn` (Environment properties)
- `scenes/systems/system_test.tscn` (Environment properties)

### Gameplay Impact: NONE
- No scripts that handle damage, movement, AI, quests, saves, or economy are touched.
- Glow is purely a post-process screen effect.

---

## Feature 2: Engine Exhaust Particles

### What It Does
Adds GPU particle trails behind the player ship and NPC ships that intensify with speed. A constant soft exhaust when moving, flaring up during boost. Replaces the static engine glow spheres on NPCs with something that feels alive.

### Why It's Safe
- GPUParticles3D nodes are visual-only — they have no collision layer, no physics body, no signals that connect to game logic.
- We attach particles as children of the `Visual` node on each ship, same as the existing engine glow `MultiMeshInstance3D`. They inherit position/rotation but don't affect `CharacterBody3D.move_and_slide()`.
- The existing `engine_points` array (NPCShip) and `_find_thruster_points()` (PlayerShip) already locate engine/thruster nodes on ship models. We reuse these — no new model scanning code.
- Particle `amount` will be kept low (8-16 per emitter) to avoid performance issues with many NPC ships.

### Current State (What Exists)

**Player Ship (`scripts/PlayerShip.gd`):**
- `_find_thruster_points()` (line 1625) scans Visual children for nodes named "thruster", "engine", "exhaust", "nozzle"
- Fallback positions at `(-1.4, -0.1, 4.7)` and `(1.4, -0.1, 4.7)` if none found
- `_create_boost_effects()` (line 1604) creates SphereMesh flames + OmniLight3D at thruster points — only visible during boost
- `boost_effect_material`: emission Color(0.15, 0.75, 1.0), energy 5.0
- `current_speed` (line 18): float, 0.0 to `max_speed` (25.0) * `BOOST_SPEED_MULTIPLIER` (1.25)
- `boost_timer` (line 23): > 0.0 when boost is active

**NPC Ships (`scripts/NPCShip.gd`):**
- `engine_points: Array[Node3D]` (line 24) — populated by `_setup_model_points()` scanning for "engine_", "thruster", "exhaust" nodes
- `_create_engine_glow()` (line 366) — creates MultiMeshInstance3D with small emissive spheres at engine points
- `_get_engine_color()` (line 397) — returns faction-specific color:
  - Zenith: Color(0.2, 0.65, 1.0) — cyan-blue
  - Aurelia: Color(0.35, 0.85, 1.0) — light cyan
  - Vanguard: Color(1.0, 0.25, 0.08) — orange-red
  - Default: Color(0.45, 0.75, 1.0) — cyan-blue
- `speed` (line 12): exported float, set between 10.0-15.0 by NPCManager
- Fallback engine point at `(0, 0, hull_size * 0.48)` if no engine nodes found in model

### Implementation Checkpoints

- [x] **2.1 — Create `EngineExhaust.gd` helper class**
  - File: `scripts/visuals/EngineExhaust.gd` (new file)
  - `class_name EngineExhaust extends RefCounted`
  - Static function `create_exhaust(parent: Node3D, anchor_points: Array[Node3D], color: Color, scale_factor: float = 1.0) -> Array[GPUParticles3D]`
  - Creates one `GPUParticles3D` node per anchor point with:
    - `amount`: 12
    - `lifetime`: 0.4 seconds
    - `one_shot`: false
    - `explosiveness`: 0.0 (continuous stream)
    - `fixed_fps`: 30 (consistent look, saves CPU)
    - `visibility_aabb`: sized to ~20 units behind ship
    - `local_coords`: false (particles stay in world space so trails form behind moving ships)
  - `ParticleProcessMaterial` settings:
    - `direction`: Vector3(0, 0, 1) (backward from ship, since ships face -Z)
    - `initial_velocity_min/max`: 8.0 / 14.0
    - `spread`: 12.0 degrees
    - `gravity`: Vector3.ZERO
    - `scale_min/max`: 0.15 / 0.35 (small particles)
    - `color`: engine color with alpha fade via color ramp
    - `emission_shape`: EMISSION_SHAPE_SPHERE, radius 0.2
    - `damping_min/max`: 2.0 / 4.0 (particles slow down)
  - Color ramp (GradientTexture1D): engine color at full alpha -> same color at 0 alpha over lifetime
  - Draw pass: small SphereMesh (radius 0.08) with unshaded emissive material matching engine color
  - Returns array of created GPUParticles3D nodes for later speed updates

- [x] **2.2 — Add static `update_exhaust_intensity()` function**
  - File: `scripts/visuals/EngineExhaust.gd`
  - `static func update_intensity(particles: Array[GPUParticles3D], speed_ratio: float, is_boosting: bool) -> void`
  - `speed_ratio` = `current_speed / max_speed`, clamped 0.0-1.0
  - When `speed_ratio < 0.01`: set `emitting = false` (ship is stopped)
  - When moving: `emitting = true`
    - `speed_scale` = lerp(0.5, 1.5, speed_ratio) — faster particles at higher speed
    - Modify `amount_ratio` = lerp(0.3, 1.0, speed_ratio) — fewer particles when slow
  - When `is_boosting`:
    - `speed_scale` = 2.0
    - `amount_ratio` = 1.0
    - Could increase `initial_velocity_max` for longer trails

- [x] **2.3 — Integrate into PlayerShip**
  - File: `scripts/PlayerShip.gd`
  - In `_create_boost_effects()` (after thruster point detection, ~line 1621):
    - Call `EngineExhaust.create_exhaust()` with the same thruster points, Color(0.15, 0.75, 1.0), store result in new `var exhaust_particles: Array[GPUParticles3D]`
  - In `_update_boost_effects()` (~line 1671):
    - Call `EngineExhaust.update_intensity(exhaust_particles, current_speed / (max_speed * GlobalState.engine_speed_mult), boost_timer > 0.0)`
  - This piggybacks on the existing per-frame boost update — no new `_process` overhead.

- [x] **2.4 — Integrate into NPCShip**
  - File: `scripts/NPCShip.gd`
  - Add `var exhaust_particles: Array[GPUParticles3D] = []` instance variable
  - In `_create_engine_glow()` (after MultiMesh creation, ~line 395):
    - Call `EngineExhaust.create_exhaust(visual, engine_points, _get_engine_color(), 0.7)` — slightly smaller scale for NPCs
    - Store result in `exhaust_particles`
  - In `_physics_process()` (existing, find the movement section):
    - Call `EngineExhaust.update_intensity(exhaust_particles, speed / 15.0, false)` — NPCs don't boost
  - In `apply_generated_model()` (~line 266):
    - Clear old `exhaust_particles` (queue_free each) before rebuilding
    - After `_setup_model_points()` is called, engine_glow and exhaust will be recreated

- [x] **2.5 — Handle NPC cleanup on death**
  - File: `scripts/NPCShip.gd`
  - In `die()` function (~line 646):
    - Particles are children of `visual` node, which gets passed to `Wreckage.initialize(visual)` — the wreckage duplicates the hull but won't include GPUParticles3D nodes in the duplicate since they're separate children of `visual`
    - Verify: `wreckage.initialize()` calls `original_hull.duplicate()` — GPUParticles3D children of `visual` that aren't children of the hull mesh won't be duplicated. If they are, we need to skip them in the wreckage material override.
    - Safest: parent particles to a separate container node under `visual` named "ExhaustContainer", and in Wreckage.gd skip nodes named "ExhaustContainer" during duplication. OR: parent exhaust to `self` instead of `visual`.

- [ ] **2.6 — Visual verification**
  - Launch game. Confirm:
    - Player ship has soft exhaust trail when moving
    - Trail intensifies during boost (matches the existing boost flame effect)
    - Trail disappears when stopped/docked
    - NPC ships have faction-colored exhaust trails
    - Vanguard ships have orange-red trails, Zenith/Aurelia have cyan-blue
    - NPCs that spawn mid-game (respawn timer) get particles
    - Hot-swapped generated models get new particles (via `apply_generated_model`)
    - No particles visible on wreckage
    - Performance: check FPS with 8+ NPC ships in system

### Files Modified
- `scripts/visuals/EngineExhaust.gd` (new file)
- `scripts/PlayerShip.gd` (integrate exhaust into existing boost system)
- `scripts/NPCShip.gd` (integrate exhaust into existing engine glow system)

### Files NOT Modified (Gameplay-Critical)
- `GlobalState.gd` — no changes
- `Projectile.gd` — no changes
- `GameRoot.gd` — no changes
- No `.tscn` scene files changed for ships (particles created in code)

### Gameplay Impact: NONE
- GPUParticles3D has no collision layer/mask. Cannot trigger `body_entered` or `area_entered`.
- Speed values are read-only — we read `current_speed` but never write to it.
- Particle nodes are purely visual children that don't affect `move_and_slide()` physics.

---

## Feature 3: Weapon Impact Flashes

### What It Does
When a projectile hits a ship, spawn a brief flash + particle burst at the impact point. When a ship dies, spawn a larger explosion burst. Currently both events are audio-only (`AudioManager.play_laser` / `play_explosion`) with no visual feedback beyond the ship disappearing.

### Why It's Safe
- Impact effects are spawned at the moment of `queue_free()` on the projectile — after `take_damage()` has already been called. The visual effect is a fire-and-forget node added to the system root, completely decoupled from damage logic.
- Death explosions are spawned in `die()` after all game state changes (reputation, credits, wreckage, signal emissions) have completed, right before `queue_free()`.
- The effects self-destruct via `one_shot = true` + `finished` signal or a lifetime timer. No persistent state.

### Current State (What Exists)

**Projectile Hit (`scripts/Projectile.gd:33-56`):**
- `_on_body_entered()` checks faction, calls `body.take_damage(damage, faction)`
- Line 50: `# Spawn explosion FX here if desired` — explicit TODO comment
- Then `queue_free()` — projectile vanishes instantly with no visual

**NPC Death (`scripts/NPCShip.gd:646-710`):**
- `die()` sets `destroyed = true`, plays explosion audio, spawns wreckage, awards credits
- Line 709: `# Play explosion FX here if desired` — explicit TODO comment
- Then `queue_free()` — ship vanishes instantly

**Player Death (`scripts/PlayerShip.gd:1592-1601`):**
- `die()` plays explosion audio, records death, shows death screen
- Then `queue_free()` — no visual explosion

**Projectile Visual (`scenes/projectile.tscn`):**
- SphereMesh (radius 0.3) with unshaded StandardMaterial3D
- Color set per-faction in `_ready()`: player=cyan, zenith=blue, aurelia=gold, vanguard/minor=red

### Implementation Checkpoints

- [ ] **3.1 — Create `ImpactEffect.gd` helper class**
  - File: `scripts/visuals/ImpactEffect.gd` (new file)
  - `class_name ImpactEffect extends RefCounted`
  - Two static functions:
    - `spawn_hit(parent: Node3D, position: Vector3, color: Color) -> void`
    - `spawn_explosion(parent: Node3D, position: Vector3, color: Color, scale: float = 1.0) -> void`

- [ ] **3.2 — Implement `spawn_hit()` — small impact flash**
  - Creates a temporary Node3D container at the hit position
  - **Flash sprite:** MeshInstance3D with a small QuadMesh (size ~2.0)
    - Billboard mode (always faces camera)
    - Unshaded material with projectile color, emission energy 6.0
    - Fades out over 0.15 seconds via Tween on material alpha
  - **Spark particles:** GPUParticles3D
    - `one_shot = true`
    - `amount`: 6-8
    - `lifetime`: 0.25 seconds
    - `explosiveness`: 0.9 (all particles burst at once)
    - `ParticleProcessMaterial`:
      - `direction`: Vector3.ZERO (omnidirectional)
      - `initial_velocity_min/max`: 15.0 / 30.0 (fast outward burst)
      - `spread`: 180.0 degrees
      - `gravity`: Vector3.ZERO
      - `scale_min/max`: 0.05 / 0.12
      - `damping_min/max`: 10.0 / 20.0 (sparks slow quickly)
      - `color`: projectile color -> transparent via gradient
    - Draw pass: tiny SphereMesh with unshaded emissive material
  - Self-cleanup: Timer node (0.5s) -> `queue_free()` the container

- [ ] **3.3 — Implement `spawn_explosion()` — ship death burst**
  - Larger version of the hit effect:
  - **Flash:** QuadMesh size ~8.0, emission energy 10.0, fades over 0.3s
  - **Debris particles:** GPUParticles3D
    - `one_shot = true`
    - `amount`: 20-24
    - `lifetime`: 0.8 seconds
    - `explosiveness`: 0.85
    - `ParticleProcessMaterial`:
      - `initial_velocity_min/max`: 10.0 / 25.0
      - `spread`: 180.0
      - `gravity`: Vector3.ZERO
      - `scale_min/max`: 0.08 / 0.25
      - `damping_min/max`: 3.0 / 8.0
      - Color ramp: bright white -> projectile color -> dark orange -> transparent
    - Draw pass: small SphereMesh with emissive material
  - **Secondary glow particles:** Optional second GPUParticles3D
    - `amount`: 4-6 larger, slower particles for a "fireball" feel
    - `lifetime`: 0.5 seconds
    - Larger scale (0.5-1.5), very high damping
  - Self-cleanup: Timer node (1.5s) -> `queue_free()`
  - `scale` parameter lets us make player death explosions bigger than NPC deaths

- [ ] **3.4 — Hook into Projectile.gd**
  - File: `scripts/Projectile.gd`
  - In `_on_body_entered()`, before the existing `queue_free()` (line 51):
    - `ImpactEffect.spawn_hit(get_parent(), global_position, color)`
  - The `color` variable already holds the faction-appropriate projectile color.
  - Also add hit flash for asteroid impacts (line 56) — smaller, grey/white color.

- [ ] **3.5 — Hook into NPCShip.gd die()**
  - File: `scripts/NPCShip.gd`
  - In `die()`, before `queue_free()` (line 710):
    - `ImpactEffect.spawn_explosion(get_parent(), global_position, _get_engine_color())`
  - Uses the faction engine color so Zenith ships explode blue, Vanguard explode orange-red.

- [ ] **3.6 — Hook into PlayerShip.gd die()**
  - File: `scripts/PlayerShip.gd`
  - In `die()`, before `queue_free()` (line 1601):
    - `ImpactEffect.spawn_explosion(get_parent(), global_position, Color(0.15, 0.75, 1.0), 1.5)`
  - Larger scale (1.5x) for the player death to feel more impactful.

- [ ] **3.7 — Visual verification**
  - Launch game. Engage in combat:
    - Player shoots NPC: cyan flash at impact point
    - NPC shoots player: faction-colored flash at player position
    - NPC dies: explosion burst in faction engine color + existing audio
    - Player dies: larger cyan-white explosion + existing audio + death screen
    - Asteroid hit by stray shot: small grey-white spark
  - Check that effects don't linger (all self-cleanup within 1.5s)
  - Check that wreckage still spawns correctly alongside the explosion
  - Performance: rapid fire combat should not cause FPS drops (one_shot particles are cheap)

### Files Modified
- `scripts/visuals/ImpactEffect.gd` (new file)
- `scripts/Projectile.gd` (one line before each `queue_free()`)
- `scripts/NPCShip.gd` (one line in `die()`)
- `scripts/PlayerShip.gd` (one line in `die()`)

### Files NOT Modified (Gameplay-Critical)
- `GlobalState.gd` — no changes
- `GameRoot.gd` — no changes
- Damage values, cooldowns, faction reputation — untouched
- Collision layers/masks — untouched

### Gameplay Impact: NONE
- Effects spawn after `take_damage()` / all game state changes have completed.
- `one_shot` GPUParticles3D with no collision layer cannot interact with physics.
- Self-destructing nodes (Timer -> queue_free) leave no persistent state.

---

## Implementation Order

Recommended order for implementation and testing:

1. **Feature 1 (Bloom)** — fastest to implement (~15 min), immediately improves everything else
2. **Feature 3 (Weapon Impacts)** — independent of Feature 2, fills the explicit TODO comments in Projectile.gd and NPCShip.gd
3. **Feature 2 (Engine Exhaust)** — most complex, benefits from bloom already being active

Each feature can be committed independently and tested in isolation.

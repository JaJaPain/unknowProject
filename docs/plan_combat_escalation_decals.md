# Plan: Combat Escalation Arc + Impact Decals

**Branch:** `segment-3/economy-stores-events`
**Status:** Ready to implement
**Depends on:** Existing enemy AP system (`NPCShip.generate_action_plan()`), `CombatManager`, `PlayerShip`

---

## Feature A — Enemy Low-Health Escalation Arc

### Goal

Combat should have a dramatic arc. Right now a Gunner at 5% HP plans the same as a Gunner at 90% HP. We want the enemy to visibly shift into a different mode when they're hurt — making fights feel like a story (controlled fight → damage exchange → desperate endgame) rather than a repeated action loop.

### Design

Three HP thresholds, each triggering increasingly desperate behaviour:

| Threshold | Label | What changes |
|---|---|---|
| < 50% | **Bloodied** | System chatter fires once ("Enemy hull damaged — they're running hot."), enemy begins choosing higher-variance actions |
| < 30% | **Critical** | System chatter fires once ("Target hull critical."), enemy shifts to all-or-nothing plan, fires `npc_low_health` taunt voice line |
| < 15% | **Last Stand** | Enemy burns ALL remaining AP on a single massive hull shot (1.6× damage), then can't act further this turn |

Thresholds fire **once per fight** (flags reset at `_reset_fight_state`). The 30% threshold already has `_enemy_low_alarmed` tracking it — we extend that pattern.

### Archetype behaviour shifts

**Gunner**
- Bloodied: 80% chance hull shot (was 65%), suppression chance drops
- Critical: always hull shot, damage range shifts to `damage_max * 1.2 → 1.5`
- Last Stand: single `damage_max * 1.6` shot, no second action regardless of AP

**Interceptor**
- Bloodied: stops repositioning, just fires (shield bypass no longer matters when you're desperate)
- Critical: desperation shot always, no flanking setup
- Last Stand: same as Gunner — one massive hit

**Logistics**
- Bloodied: repairs on every turn while damaged (was only < 50%)
- Critical: repairs first always, then fires weakly
- Last Stand: tries to flee via `surrender` action (unique to this archetype)

**MiningHauler**
- Bloodied: 90% surrender (was 60%)
- Critical: always surrender
- Last Stand: always surrender

### System chatter / voice

- **50% crossed:** `GlobalState.emit_chatter("SYSTEM", "Enemy hull damaged — they're running hot.", Color(1.0, 0.6, 0.2))` — fires once
- **30% crossed:** `GlobalState.emit_chatter("SYSTEM", "Target hull critical.", Color(1.0, 0.3, 0.3))` + plays `taunts["npc_low_health"]` in enemy voice (same pattern as flee taunt)
- **Last Stand trigger:** `GlobalState.emit_chatter("SYSTEM", "Enemy going for a kill shot!", Color(1.0, 0.2, 0.2))` + `_sfx("enemy_charge", enemy_pos, +2.0)` (louder than normal charge)

The 30% threshold already has `_enemy_low_alarmed` in `CombatManager`. The 50% "bloodied" and 15% "last stand" need new flags.

### Telegraph label changes

At Critical and Last Stand, the telegraph label in `CombatPanel` should reflect the shift:
- Critical plan: prefix first action label with "⚠ " (e.g. "⚠ Desperation hull shot")
- Last Stand: label becomes "⚠ LAST STAND — Kill shot"

The label is set from `action.get("label", "?")` in `_on_planning_started` — just set it in the planner.

### Implementation steps

1. **`NPCShip.gd`** — Update `_plan_gunner`, `_plan_interceptor`, `_plan_logistics`, `_plan_hauler` to check hp_ratio against thresholds and return escalated action lists. Add `⚠` prefix labels at Critical/Last Stand.
2. **`CombatManager.gd`**
   - Add `_enemy_bloodied_alarmed: bool` (50%) and `_enemy_last_stand: bool` (15%) to fight state, reset in `_reset_fight_state`
   - Add `_check_enemy_thresholds()` called at the start of `_begin_planning` (after enemy AP plan is built)
   - Wire system chatter + `_play_npc_low_health_taunt()` at 30% (reuses `_enemy_low_alarmed`)
   - Wire louder charge SFX at Last Stand

### Files touched
- `scripts/NPCShip.gd` — planner escalation logic
- `scripts/combat/CombatManager.gd` — threshold flags, chatter, SFX, new taunt helper

---

## Feature B — Impact Decals on Player Ship

### Goal

When the player takes hull damage, leave a visible scorch mark on their ship. Decals accumulate during combat. After combat ends they slowly fade out over 60 seconds — the ship looks battle-scarred for a minute before returning to pristine. This makes taking damage feel consequential beyond just the HP number dropping.

### Design

**Godot 4 `Decal` node** is the right tool — it projects a texture onto any mesh in its volume box without needing to modify ship materials. No custom shader on the ship itself.

**Decal properties:**
- Texture: a scorch/burn mark (dark centre, orange-ember fade ring, greyed ash edge) — needs a new asset `assets/combat/impact_scorch.png` (512×512, square, alpha channel for soft edges)
- Size: randomised per hit — `Vector3(randf_range(2.5, 5.0), 1.0, randf_range(2.5, 5.0))`
- Position: placed on the player ship's hull surface, offset slightly toward the enemy's direction at time of impact
- Rotation: random Y rotation so each mark looks unique
- Cap: max 6 simultaneous decals — oldest is removed when a 7th would spawn
- `albedo_mix = 1.0` at spawn, `emission_energy = 0.4` for slight glow (fresh hit)

**Fade timeline:**
- At hit: full opacity, slight orange emission glow (fresh scorch)
- During combat: emission fades to 0 over 3 seconds (cools down), albedo stays full
- On `combat_ended`: start 60-second fade tween (`albedo_mix` 1.0 → 0.0 over 60s), then `queue_free()`
- If another combat starts before 60s is up: interrupt the fade, keep decals at current opacity, don't add to the 6-cap pool (they're already fading out)

### Asset needed

`assets/combat/impact_scorch.png` — a 512×512 circular scorch mark:
- Centre: very dark (near black), alpha 0.95
- Mid ring: dark orange/amber glow, alpha 0.7
- Outer ring: grey ash/char, alpha 0.4
- Edge: transparent falloff, alpha 0

Can be generated with Blender's texture paint, Gimp, or a simple procedural script. The Decal node handles projection so the texture just needs to look good as a flat 2D stamp.

### Where decals attach

Decal nodes need to be children of a node in the 3D world (not the ship itself), positioned at the ship's surface. Since the camera is in combat orbit close to the ship, positioning matters.

**Approach:** Add decals as children of `player_node.get_parent()` (the main scene), positioned at `player_node.global_position` offset toward the incoming shot direction. The Decal's box volume should encompass the ship mesh for the projection to land.

Decal cull mask must include whatever layer the player ship is on.

### Decal manager

A lightweight `_CombatDecalManager` (inner class or standalone helper in CombatManager, not autoloaded) tracks:
- `_active_decals: Array[Decal]` — the 6-cap pool for current combat
- `_fading_decals: Array[Decal]` — decals that survived into the post-combat fade
- `spawn_impact(world_pos: Vector3, hit_dir: Vector3)` — creates and registers a decal
- `on_combat_end()` — moves active to fading, starts 60s tween on each
- `on_combat_start()` — doesn't touch fading decals, resets active pool

### Decal position calculation

At hit time we know:
- `player_node.global_position` — ship centre
- `enemy_node.global_position` — where the shot came from

Direction of impact: `(player_node.global_position - enemy_node.global_position).normalized()`

Decal position: `player_node.global_position + hit_dir * 4.0` (just in front of the hull surface, so the projection box overlaps the ship)

Decal Y orientation: `look_at` toward `hit_dir`, then random Y rotation for variety.

### Integration point

`_apply_hit()` in `CombatManager` already has `hit_pos: Vector3` and knows whether the hit was blocked. Call `_spawn_impact_decal(hit_pos, hit_dir)` when:
- Target is the player (`target == player_node`)
- Hit was NOT fully blocked by shield (blocked hits can still leave a faint mark at 0.3 albedo_mix — glancing hit)
- Damage > 0

Pass `hit_dir` by adding it as a param to wherever `_apply_hit` is called from `_execute_npc_action`.

### Implementation steps

1. **Asset:** Create `assets/combat/impact_scorch.png` (or generate procedurally at runtime as a `NoiseTexture2D` if no artist available — dark noise + radial gradient mask)
2. **`CombatManager.gd`**
   - Add `_active_decals: Array` and `_fading_decals: Array` as fight state vars
   - Add `_spawn_impact_decal(hit_pos: Vector3, from_dir: Vector3, blocked: bool)` 
   - Wire into `_execute_npc_action` fire/flank cases — pass enemy direction
   - Call `_start_decal_fade()` from `end_combat()`
   - Reset `_active_decals` in `_reset_fight_state()` (leave fading ones alone)
3. **`CombatManager.gd` — `_spawn_impact_decal`:**
   ```
   - Create Decal node, set texture, size (randomised), albedo_mix, emission
   - Cap: if _active_decals.size() >= 6, queue_free oldest
   - Position at hit_pos offset slightly from enemy direction
   - Random rotation around the hit normal
   - Add to parent scene, add to _active_decals
   - Tween emission 0.4 → 0.0 over 3s (cool-down glow)
   ```
4. **`CombatManager.gd` — `_start_decal_fade`:**
   ```
   - Move all _active_decals into _fading_decals
   - For each: tween albedo_mix 1.0 → 0.0 over 60s (wall-clock), then queue_free
   - Clear _active_decals
   ```

### Files touched
- `scripts/combat/CombatManager.gd` — decal spawn/fade/cap logic
- `assets/combat/impact_scorch.png` — new texture asset (needed before implementation)

---

## Implementation Order

1. **Feature A first** — pure logic, no assets needed, immediately testable
2. **Create scorch asset** — can be a placeholder dark circle to start
3. **Feature B** — wire decals using placeholder, tune position/size in-game, then swap final asset

---

## Open Questions

- Should blocked hits leave a faint decal? (Suggested: yes, at `albedo_mix = 0.3` — a graze mark)
- Should the scorch texture vary by damage amount? (Suggested: no for now — keep it simple, single texture at varying scale)
- Should decals survive between fights in the same session? (Suggested: no — they fade within 60s of each combat, so unlikely to stack across fights)

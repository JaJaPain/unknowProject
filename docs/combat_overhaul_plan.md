# Combat Overhaul Plan — Turn-Based AP System

_Branch: segment-3/economy-stores-events | Date: 2026-06-24_

## Problem
Current combat is a DPS race. Player clicks a target, auto-fire runs on a cooldown timer, and the outcome is decided purely by stats. Zero player interaction, zero skill expression.

## Solution
Replace real-time auto-fire with a **turn-based AP planning system**. Player spends Action Points to queue actions, commits, then watches them resolve. NPCs telegraph their intent so the player has something to react to. Combat remains short (3–6 turns typical) and exits cleanly back to free flight.

---

## Architecture Overview

```
[Free Flight]
     │  NPC enters aggro range OR player fires at NPC
     ▼
[CombatManager.start_combat(player, npc)]
     │
     ▼
[PLANNING phase]
  - Freeze player flight input + NPC real-time AI
  - Show CombatPanel UI
  - Display NPC intent telegraph
  - Player spends AP to queue actions
  - Player hits EXECUTE
     │
     ▼
[EXECUTION phase]
  - Play queued player actions in order (with visuals)
  - Play NPC intent action
  - Resolve damage, check deaths
  - If combat over → end_combat() → [Free Flight]
  - If combat continues → loop back to [PLANNING phase]
```

---

## Action Table

| Action | AP Cost | Effect |
|---|---|---|
| Fire Weapons | 2 | Deal weapon damage to enemy. Weapon tier scales damage. |
| Boost/Reposition | 1 | Change range band (Close/Mid/Long). Engine tier improves effect. |
| Shield Reroute | 1 | Set active shield face (Front/Rear/Flank). Blocks damage from that direction this turn. |
| Attack Drone | 2 | Animate one drone visual toward enemy, deal bonus damage. |
| Micro-Warp | 3 | Teleport to enemy flank — guaranteed flank hit, bypasses front shield. 3-turn cooldown. |
| Repair Kit | 2 | Consume one repair_kit from inventory. Heal at 50% of kit's normal value. One per turn. |
| Flee | 3 | Attempt to break combat. Engine tier vs enemy archetype determines success chance. |

### AP Pool by Powerplant Tier
- Mk I: 6 AP
- Mk II: 7 AP
- Mk III: 8 AP
- Mk IV: 9 AP
- Mk V: 10 AP

---

## Upgrade Hooks

| Upgrade Flag (GlobalState) | Combat Effect |
|---|---|
| `powerplant_tier` | Sets max AP per turn |
| `engine_tier` | Flee success rate, boost range-band steps, micro-warp cooldown reduction |
| `weapon_damage` / weapon tier flags | Fire action base damage |
| `shield_capacity` / shield tier flags | Shield reroute absorption amount |
| `has_max_rapid_weapon` | Fire costs 1 AP instead of 2 |
| `has_max_bulwark_shield` | Shield reroute blocks 2 directions simultaneously |
| `has_max_heavy_weapon` | Fire deals 2x damage but costs 3 AP |

---

## Range Band System

Instead of continuous 3D distance, combat uses three abstract range bands:

- **Long**: Low hit chance for both sides. Good for sniping, bad for fast ships.
- **Mid**: Default engagement range. Balanced hit/dodge.
- **Close**: High damage, high hit chance. Interceptors thrive here. Fleeing is harder.

Starting band is determined by how combat was triggered (player fired first = Mid, NPC aggro'd = Long).

Boost action shifts one band step. Close + Boost = stays Close (can't get closer). Long + enemy Interceptor = they shift toward Close each turn automatically.

---

## NPC Intent Telegraph

Each turn, the NPC generates one intent based on archetype:

| Archetype | Likely Intents |
|---|---|
| Gunner | "Hull shot" (high damage fire), "Suppression" (multiple weak hits) |
| Interceptor | "Flanking run" (shift to Close, flank attack), "Disable engines" (reduces player AP next turn) |
| Logistics | "Broadcast for reinforcements" (if alone), "Emergency repair" (heals self) |
| MiningHauler | "Surrender" (always), "Panic shot" (random, low damage) |

Intent is displayed in the UI before the player commits. Player can react by rerouting shields, micro-warping, etc.

---

## Hit Resolution Rules

Applied during execution phase in this order:

1. Determine attacker's range modifier (Long = 0.6x damage, Mid = 1.0x, Close = 1.3x)
2. Determine if attacker is flanking (micro-warp this turn, or Interceptor flank intent)
3. Check defender's active shield face vs attack direction:
   - Match: damage reduced by shield absorption amount
   - Mismatch: full damage hits hull directly
4. Apply damage via existing `take_damage()` — shields absorb first, then hull

---

## Voice Taunting

Hooks into the existing chatter/TTS system. Can be disabled in settings via `combat_voice_taunts` bool.

**NPC triggers:**
- Combat start: faction-appropriate taunt line
- Player flee attempt (success): dismissive line
- Player flee attempt (failure): threatening line
- NPC below 30% health: desperation line
- Player below 30% health: gloating line

**Player reply:**
- 0 AP button in planning UI: "Respond" → fires a Kaelen voice line back at them
- Kaelen line chosen based on context (low health = defiant, winning = confident)

---

## Files to Create

| File | Purpose |
|---|---|
| `scripts/combat/CombatManager.gd` | Autoload — state machine, action queue, resolution logic |
| `scripts/combat/CombatAction.gd` | Enum + data class for action types |
| `scenes/ui/CombatPanel.tscn` + `scripts/ui/CombatPanel.gd` | Planning phase UI panel |

## Files to Modify

| File | Changes |
|---|---|
| `scripts/PlayerShip.gd` | Freeze flight/fire when CombatManager active; expose AP to UI |
| `scripts/NPCShip.gd` | Freeze real-time AI when in combat; add `generate_intent()` method |
| `scripts/GlobalState.gd` | Add `combat_voice_taunts` setting, powerplant_tier helper |
| `project.godot` | Register CombatManager as autoload |

---

## Implementation Steps

### Step 1 — CombatManager core
Create `scripts/combat/CombatManager.gd` as an autoload with:
- State enum: `IDLE / PLANNING / EXECUTING`
- `start_combat(player, npc)` and `end_combat()`
- AP pool with powerplant tier lookup
- `queued_actions: Array[Dictionary]`
- Signals: `combat_started`, `planning_started`, `execution_started`, `combat_ended`
- Register in project.godot

### Step 2 — Freeze real-time behavior
- **PlayerShip**: gate auto-fire and flight input behind `CombatManager.state == IDLE`
- **NPCShip**: gate `_physics_process` steering and fire behind same check

### Step 3 — NPC intent system
Add `generate_intent() -> Dictionary` to NPCShip. Returns `{ "type": String, "label": String }` based on archetype weighted random. Intent executes during execution phase.

### Step 4 — CombatAction definitions
Create `scripts/combat/CombatAction.gd` with action type constants and a factory method that builds a Dictionary given type + params.

### Step 5 — CombatPanel UI
Build `scenes/ui/CombatPanel.tscn`:
- Player HP/Shield bar, Enemy HP bar
- Enemy intent label
- AP display (current / max)
- Action buttons (7 actions, grayed out if AP insufficient)
- Micro-warp cooldown indicator
- EXECUTE button
- 0-AP "Respond" voice button

### Step 6 — Action execution handlers
In CombatManager, one handler per action type:
- `_exec_fire()` — range-modified damage via take_damage()
- `_exec_boost()` — shift range band
- `_exec_shield_reroute()` — set active shield face
- `_exec_attack_drone()` — animate drone visual + deal damage
- `_exec_micro_warp()` — set flank flag, start cooldown
- `_exec_repair_kit()` — check inventory, consume, heal
- `_exec_flee()` — roll success, call end_combat() or apply fail penalty

### Step 7 — NPC execution
After player actions resolve, execute NPC's intent. Apply same hit resolution rules.

### Step 8 — Hit resolution
Shared `_resolve_hit(attacker_data, defender_node)` function applying range band + flank + shield face modifiers.

### Step 9 — Voice taunting
Wire NPC chatter calls into CombatManager event hooks. Add Kaelen reply lines. Add `combat_voice_taunts` to settings.

### Step 10 — Upgrade wiring
Pull GlobalState flags into CombatManager at `start_combat()` time to set AP pool, damage modifiers, flee odds.

### Step 11 — Polish + testing
- Headless smoke test for hit resolution math
- Verify flee works across all NPC archetypes
- Verify repair kit inventory deduction
- Verify micro-warp cooldown resets correctly between fights

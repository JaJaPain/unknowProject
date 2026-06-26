# Plan: Phase 19 (Mega-Boss) + Phase 20 (Multi-Enemy Squads)

**Tasks:** #19, #20
**Branch:** `segment-3/economy-stores-events`
**Key files:** `scripts/NPCShip.gd`, `scripts/combat/CombatManager.gd`, `scripts/ui/CombatPanel.gd`, `scripts/MainScene.gd`

---

## Phase 19 — Mega-Boss

### Design

A single named enemy with 3× normal HP, 6 AP, intelligence 0.85, and a **phase system** that shifts strategy at 60% and 30% HP. Each phase transition pauses combat briefly for a taunt and chatter message. The player sees the phase label change in the UI.

The boss uses the full existing action kit — nothing new to invent. What makes it a boss is the combination depth per turn and the strategy shift per phase.

### Boss Stats

Set on the NPCShip at spawn time:

```
max_health:          300  (3× normal ~100)
combat_ap:           6
combat_intelligence: 0.85
damage_min:          14
damage_max:          22
is_boss:             true
ship_role:           "Boss"
```

### Three Phases

| Phase | HP range | Strategy | AP spend |
|---|---|---|---|
| 1 "Dominant" | 100–60% | Brace → Fire × 2. Occasional flank. Controlled. | 6 AP: brace(2) + fire(2) + fire(2) |
| 2 "Wounded" | 60–30% | Shield angle → Flank fire. Repairs if below 45%. Starts mixing in disable_engines. | 6 AP: shield(1) + flank(3) + disable(2) |
| 3 "Last Stand" | 30–0% | All damage. No defense. Max aggression. Possibly two overcharge-labeled fires. | 6 AP: fire×3 at 1.5× damage |

### Phase Transition Moment

When HP crosses a threshold mid-turn (detected in `_after_npc_turn` or `_apply_hit`):
1. Short beat pause (0.6s wall-clock)
2. System chatter: `"TARGET ENTERING PHASE II — threat level escalating."` (red)
3. Boss voice taunt fires (`npc_boss_phase_2` or `npc_boss_phase_3`)
4. `boss_phase_changed(new_phase)` signal emitted
5. Resume execution

### New LLM Taunt Keys

```
npc_boss_phase_2:  "Still standing? Fine. Now I get serious."
npc_boss_phase_3:  "You want to see what I'm really capable of?"
```

### Phase Indicator in CombatPanel

A small label above the enemy HP bar: `"● PHASE I"` → `"●● PHASE II"` → `"●●● PHASE III"` in escalating red. Updates on `boss_phase_changed`.

### Implementation Steps

**Step B1 — NPCShip: `is_boss`, `boss_phase`, `_plan_boss()`**
- Add `var is_boss: bool = false` and `var boss_phase: int = 1`
- Add `_plan_boss(plan, ap, hp_ratio, intel)` with three strategy blocks keyed on `boss_phase`
- Wire into `generate_action_plan()`: if `is_boss`, call `_plan_boss()` instead of archetype planner

**Step B2 — CombatManager: phase vars + transition detection**
- Add `var _boss_phase_alarmed_2: bool` and `_boss_phase_alarmed_3: bool` to `_reset_fight_state()`
- Add `signal boss_phase_changed(phase: int)`
- Add `_check_boss_phase_transition()` — call from `_after_npc_turn()` and from `_apply_hit()` when target is `enemy_node`
- Transition: pause → chatter → taunt → emit signal

**Step B3 — LLMInterface: boss taunt keys**
- Add `npc_boss_phase_2` and `npc_boss_phase_3` to `COMBAT_TAUNT_FALLBACKS`
- Add to prompt JSON template

**Step B4 — CombatPanel: phase indicator label**
- Add `_boss_phase_label: Label` built in `_build_ui()`, hidden by default
- Connect to `boss_phase_changed` → update text and show/hide
- Show only when `enemy_node.get("is_boss")` is true at `combat_started`

**Step B5 — Boss spawn mechanism (debug + real)**
- Debug: in `MainScene.gd`, add a keybind (`KP_9` / Numpad 9) that spawns a boss-flagged Gunner 80 units from the player. Only active in debug builds.
- Real trigger: a named story quest sets `is_boss = true` on a specific tagged NPC before combat. Not implemented in this phase — F9 debug spawn is sufficient for playtesting.

### How to Test Phase 19

1. Press **Numpad 9** in-game — a boss ship spawns 80 units from you
2. Fly to it and open fire to trigger combat
3. **Phase 1 test:** telegraph should show "⛨ Brace → Hull shot → Hull shot". Boss should be noticeably tankier (300 HP)
4. **Phase 2 test:** get boss to ~55% HP — system chatter fires "TARGET ENTERING PHASE II", boss voice taunt plays, phase label updates to "●● PHASE II", strategy shifts to shield+flank
5. **Phase 3 test:** get boss to ~25% HP — same transition moment, "●●● PHASE III", all-out attack plan
6. Kill the boss — normal kill cinematic, `combat_loot_dropped` fires (loot still empty)
7. **Regression:** fight a normal Gunner — no phase label, no phase transitions, normal behavior unchanged

---

## Phase 20 — Multi-Enemy Squads

### Design

Two enemies attack simultaneously. The player picks a **target** at the start of planning (free, costs 0 AP). Both enemies plan independently. Both fire at the player each turn. Player attacks land on the targeted enemy only. When one dies, combat continues until both are gone.

### Architecture — What Changes

**`enemy_node: Node` → `enemy_nodes: Array`**

This is the core change. Almost everything in CombatManager that references `enemy_node` needs to become target-aware.

New property:
```gdscript
var enemy_nodes: Array = []          # all enemies in the fight
var _target_idx: int = 0             # which one the player is attacking
# helper — replaces all enemy_node reads
var enemy_node: Node:
    get: return enemy_nodes[_target_idx] if _target_idx < enemy_nodes.size() else null
```

Using a property getter means most existing code (`enemy_node.global_position`, `is_instance_valid(enemy_node)`) keeps working with zero changes.

**Per-enemy state**

`enemy_brace_active` and `enemy_shield_angle_active` become per-enemy arrays:
```gdscript
var _enemy_brace:  Array = []   # bool per enemy
var _enemy_shield: Array = []   # bool per enemy
```

Properties replace the old vars:
```gdscript
var enemy_brace_active: bool:
    get: return _enemy_brace[_target_idx] if _target_idx < _enemy_brace.size() else false
    set(v): if _target_idx < _enemy_brace.size(): _enemy_brace[_target_idx] = v

var enemy_shield_angle_active: bool:
    get: return _enemy_shield[_target_idx] if _target_idx < _enemy_shield.size() else false
    set(v): if _target_idx < _enemy_shield.size(): _enemy_shield[_target_idx] = v
```

Again, all existing code using `enemy_brace_active` keeps working.

**`npc_action_plan: Array` → `npc_action_plans: Array`**

Each enemy gets its own plan. Execution loops over all enemies:
```gdscript
for i in enemy_nodes.size():
    if is_instance_valid(enemy_nodes[i]):
        await _execute_enemy_plan(i)
```

### Squad Spawn — "Join Combat"

NPCShip gets `var squad_id: String = ""`. Ships with matching non-empty `squad_id` are in the same squad.

When an NPC tries to start combat but `already_fighting`:
```gdscript
var current_enemy_squad: String = CombatManager.enemy_nodes[0].get("squad_id") if not CombatManager.enemy_nodes.is_empty() else ""
if squad_id != "" and squad_id == current_enemy_squad and CombatManager.enemy_nodes.size() < 3:
    CombatManager.join_combat(self)
    return
```

`join_combat(enemy: Node)` appends to `enemy_nodes`, initialises per-enemy state arrays, adds the new plan slot.

### Target Switching

A small `[TARGET ▸]` button in CombatPanel (costs 0 AP, free action). Cycles through live enemies. Updates the target indicator (arrow or highlight on the targeted HP bar).

### CombatPanel Changes

- Multiple enemy HP bars, one per `enemy_nodes` entry
- Active target highlighted with a yellow border
- `[TARGET ▸]` button, disabled if only one enemy alive
- Phase indicator (from Phase 19) tracks the targeted enemy only

### Win / Death Handling

When an enemy in the squad dies mid-turn:
- Remove from `enemy_nodes`, remove its state arrays entry, remove its HP bar
- If `enemy_nodes` is now empty → `end_combat(true)`
- Otherwise: adjust `_target_idx` if it pointed to the dead one

### Implementation Steps

**Step S1 — NPCShip: `squad_id` property**
- `var squad_id: String = ""`
- Update `already_fighting` check to call `CombatManager.join_combat()` when squads match

**Step S2 — CombatManager: `enemy_nodes` array + property getter**
- Replace `var enemy_node: Node = null` with `var enemy_nodes: Array = []` and a getter property
- Replace per-enemy state booleans with array + getter/setter properties
- Update `start_combat()` to initialise `enemy_nodes = [enemy]`, `_enemy_brace = [false]`, `_enemy_shield = [false]`
- Add `join_combat(enemy: Node)` — appends and initialises

**Step S3 — CombatManager: multi-plan generation + execution**
- `npc_action_plans: Array = []` — one plan per enemy
- `_plan_all_enemies()` replaces the single `enemy_node.generate_action_plan()` call in `_begin_planning()`
- `_execute_all_enemy_plans()` loops over all enemies, `await`s each

**Step S4 — CombatManager: per-enemy death handling**
- `_remove_dead_enemies()` called after each enemy executes — purges invalid nodes, adjusts `_target_idx`

**Step S5 — CombatPanel: multi HP bars + target button**
- `_enemy_bars: Array` replaces `_enemy_bar`
- Built dynamically in `_on_combat_started` based on `CombatManager.enemy_nodes.size()`
- `[TARGET ▸]` button calls `CombatManager.cycle_target()`

**Step S6 — MainScene: squad spawn**
- `_spawn_squad(count: int, faction: String)` spawns `count` NPCs at nearby positions with matching `squad_id`
- Debug: **Numpad 0** spawns a 2-ship Reaver patrol near the player
- Real trigger: heavy-traffic systems or story beats set `squad_id` on patrol groups at system generation time

### How to Test Phase 20

1. Press **Numpad 0** in-game — two Reaver ships spawn ~60–80 units away with matching squad IDs
2. Attack one — combat starts, both enter the fight. CombatPanel shows two HP bars.
3. **Target switching:** press `[TARGET ▸]` — active target switches, yellow highlight moves
4. **Simultaneous fire:** each turn both enemies fire at you — you take 2 hits per execution phase
5. Kill the first enemy — its HP bar disappears, combat continues with the survivor
6. Kill the second — win screen, normal flow
7. **Regression tests:**
   - Solo fight still works (single enemy, no target button visible)
   - Flee works (both enemies taunt)
   - Boss fight (Phase 19) still works with single `enemy_nodes[0]`
   - Brace/shield chips still track the targeted enemy correctly

---

## Implementation Order

Do Phase 19 first — it touches NPCShip and CombatManager but doesn't change the core architecture. Phase 20 then refactors the enemy reference model, which everything else layers on top of.

**Phase 19:** B1 → B2 → B3 → B4 → B5. Parse-check and push after each.
**Phase 20:** S1 → S2 → S3 → S4 → S5 → S6. Parse-check and push after each. S2 is the riskiest step — the property getter approach means existing code doesn't break, but it needs careful testing.

---

## Risks

| Risk | Mitigation |
|---|---|
| Property getter for `enemy_node` not supported in GDScript 4 | GDScript 4 supports `get:` / `set:` on vars — confirmed pattern. Fall back to explicit helper `_get_target()` if needed. |
| Multi-enemy damage feels overwhelming | Each enemy does 80% of normal damage when in a squad (`combat_ap` starts at 3 for wingmen vs 4 for leaders) |
| Phase detection fires twice (HP crosses threshold in one big hit) | `_boss_phase_alarmed_2/3` flags prevent double-fire — same pattern as `_enemy_low_alarmed` |
| `join_combat` race: second NPC joins while first turn is mid-execution | Guard in `join_combat()`: only allowed during `State.PLANNING`, not `EXECUTING` |

# Single-Use Salvage Drone — Implementation Plan

**Date:** 2026-06-22
**Branch:** segment-3/economy-stores-events
**Goal:** Add a consumable "Single Use Salvage Drone" that, when used near a targeted wreck, sends the ship's drone to repeatedly smack the wreck and return — adding ore to the hold over time, with a small chance of a rare item drop. The run aborts permanently if the player takes fire. Must not affect any existing system.

---

## 1. How the relevant existing systems work (grounding)

These are the facts the design is built on, confirmed by reading the source:

- **Consumable definitions** live in [ConsumableEffects.gd](scripts/economy/ConsumableEffects.gd): an `EFFECTS` dict keyed by `item_id`, plus `can_use()`, `is_usable_now(item_id, player, inv, shield_cap)`, and `use(...)`. Effects are **instantaneous** (heal, shield, buff). `salvage_drone` currently has a **placeholder** entry `{"type":"heal","amount":50.0}` that must be replaced.
- **Use flow (UI):** [UIManager.gd:4288](scripts/UIManager.gd) builds a "Use" button for any `can_use()` item; the button is disabled unless `is_usable_now()` is true. [UIManager.gd:4311](scripts/UIManager.gd) `_on_inventory_use_pressed()` calls `ConsumableEffects.use()` and on failure shows `show_hud_warning("Cannot use that item right now.")`.
- **Mining smack/return animation** is in [PlayerShip.gd](scripts/PlayerShip.gd): two orbiting drones (`_create_drones()`), and `_update_drones(delta)` (line ~1847) drives the "one drone flies to target, returns, hand off to other drone" behavior. It is gated on `mining_laser.visible` and uses `_mining_target_pos`, `_drone_collecting`, `_drone_returning`, `_drone_collect_t`, `_drone_active_idx`.
- **Mining action** `perform_action()` ([PlayerShip.gd:1526](scripts/PlayerShip.gd)) fires only when `active_target` is in group `"asteroid"` and `dist < 75.0` (the **mining range**). Ore is granted by `Asteroid.mine()` → `GlobalState.add_ore()`.
- **Wrecks:** [Wreckage.gd](scripts/Wreckage.gd) extends `StaticBody3D`, is added to group `"wreckage"` (by [NPCShip.gd:713](scripts/NPCShip.gd)), has a collision shape so it is **targetable**. `GlobalState.active_target` holds the current target.
- **Ore grant:** `GlobalState.add_ore(amount) -> float` respects cargo cap and cargo-type rules; returns amount actually added. Hold must be EMPTY or ORE (`can_accept_ore()`).
- **Inventory:** `GlobalState.inventory.add(item_id, qty, stack_max)` / `.has_item()` / `.remove()` ([PlayerInventory.gd](scripts/economy/PlayerInventory.gd)).
- **Taking fire:** `PlayerShip.take_damage(amount, attacker_faction)` ([PlayerShip.gd:1823](scripts/PlayerShip.gd)) is the single chokepoint for incoming damage.
- **Docked state:** `PlayerShip.is_docked` (bool).
- **System chat message:** `GlobalState.emit_chatter(sender, message, color)` ([GlobalState.gd:1839](scripts/GlobalState.gd)) → routed to the chat window via `UIManager.add_chat_message` ([UIManager.gd:667](scripts/UIManager.gd)).
- **Base mining timing:** `mining_laser_yield = 1.0`, `mining_cooldown = 1.0` ([GlobalState.gd:20](scripts/GlobalState.gd)) → mining 40 ore at base stats ≈ **40 seconds**. This is the timing target to match.

### Store data (already partially present)
- [store_items.json](data/content/store_items.json) already defines `salvage_drone` (currently `base_price: 2` — **change to 25**), plus `encrypted_core` and `damaged_transponder` (the rare-drop items already exist).
- [store_layouts.json](data/content/store_layouts.json): `salvage_drone` is **already in `store.haven.general`** (the first system's station) and `store.kova.supply`. No layout change needed unless we want to confirm Haven is "system 1".

---

## 2. Design decision: where the salvage logic lives

The existing consumables are **instantaneous** — `ConsumableEffects.use()` applies an effect and returns. A salvage run is **stateful and time-based** (drones fly back and forth for ~40s, can be interrupted by fire). So it does **not** fit the instant-effect model.

**Chosen architecture (keeps everything isolated from existing systems):**

1. **Validation** stays in `ConsumableEffects.is_usable_now()` so the inventory "Use" button greys out correctly. We add a new effect `type: "salvage"` and special-case its validation (target is a wreck + in range + undocked).
2. **Activation** is intercepted in `UIManager._on_inventory_use_pressed()`: when the item is the salvage drone, instead of calling the instant `ConsumableEffects.use()`, we (a) re-run the salvage validation to produce a **specific failure reason**, (b) on success `inventory.remove("salvage_drone")` and call a new `PlayerShip.begin_salvage(wreck)`.
3. **The run itself** is a new, self-contained state machine on `PlayerShip` (`_salvage_*` vars + `_update_salvage(delta)` called from `_process`). It **reuses the existing drone smack/return animation** by pointing it at the wreck, but runs on its own flag (`_salvage_active`) so it never touches `mining_laser`/asteroid mining. Each completed drone return grants a chunk of ore and rolls for a rare drop.
4. **Interrupt on fire:** `PlayerShip.take_damage()` gets one added line — if `_salvage_active`, call `_abort_salvage("hit")`. The drone is already consumed, so the player loses it.

This means: **no existing function changes behavior** except `take_damage` (one guarded line) and the inventory-use handler (one new branch). Mining is untouched.

### Why not reuse the mining drones' `_update_drones` directly?
`_update_drones` is hard-gated on `mining_laser.visible` and the asteroid mine cycle. Rather than entangle salvage into that gate (risk to mining), the salvage state machine will **drive the same drone meshes** with the same lerp/smoothstep flight math, but from its own update path. We factor the per-trip flight math into a small shared helper if it's clean to do so; otherwise we duplicate the ~15 lines to keep mining risk-free. Decision made at implementation time after re-reading `_update_drones`.

### Timing & yield tuning
- Total ore per wreck: **40** (hard cap per run).
- Target duration: **~40s** (matches base mining of 40 ore).
- Mechanism: each drone round-trip (out to wreck + back) grants ore on **return**. If a round trip is ~2s, ~20 trips × 2 ore = 40 ore over ~40s. Exact `ore_per_return` and flight rate are constants tuned so total time lands in the 35–45s ballpark. Ore stops being granted once 40 delivered; the run then ends cleanly.
- If the hold fills (cargo cap) or hold can't accept ore mid-run, the run ends and a chat message explains why.

### Rare drop
- On each return, after granting ore, roll a small chance (proposed **~3% per return**, ≈ 45–50% chance of *at least one* rare over a full 20-trip run — see open question Q3 to tune this down if too generous).
- Drop table: `encrypted_core` or `damaged_transponder` (both already exist as items), 50/50, added via `GlobalState.inventory.add(...)`. If inventory is full, silently skip (or emit a "drone couldn't store salvage" chat line).

---

## 3. Step-by-step implementation

Each step is small and independently testable. Implement and verify in order.

### Step 1 — Store data (no code)
- **store_items.json:** change `salvage_drone` `base_price` from `2` → **`25`**. Keep `category: "consumable"`, `stack_max: 10`. Optionally refine `display_name`/`description` (e.g. "Single-Use Salvage Drone" / "Deploys a drone to strip a nearby wreck for ore. Stops permanently if you take fire.").
- **store_layouts.json:** confirm `salvage_drone` is present in the **first system's** station store. It is already in `store.haven.general` and `store.kova.supply`. **Verify Haven is system 1**; if the first system is a different `station_id`, add `salvage_drone` to that store's `item_ids`.
- No restock changes needed.

### Step 2 — Define the salvage effect + validation in ConsumableEffects.gd
- Replace the placeholder `salvage_drone` entry in `EFFECTS` with:
  ```gdscript
  "salvage_drone": {"type": "salvage", "total_ore": 40.0},
  ```
- In `is_usable_now()`, add a `"salvage"` case that returns true only when ALL of:
  - `player` exists and is **not** `is_docked`,
  - `GlobalState.active_target` is valid and `is_in_group("wreckage")`,
  - distance `player.global_position.distance_to(target.global_position) < SALVAGE_RANGE` (use the same range as mining; expose `75.0` as a shared const — see Step 6),
  - player is not already running a salvage (`not player.get("_salvage_active")`),
  - **the ore hold is not full and can accept ore** — `GlobalState.can_accept_ore() and GlobalState.cargo < GlobalState.cargo_max`. If the hold is full (or loaded with special cargo) the drone is blocked **up front** so it isn't wasted.
- Add a helper `static func salvage_block_reason(player, ...) -> String` returning `""` if usable, else the **specific** reason string ("No wreck targeted.", "Move closer to the wreck.", "Cannot salvage while docked.", "Ore hold is full.", etc.). The UI uses this for the chat message. The hold-full case must be one of these reasons so the player is told why up front.
- `use()` should NOT instant-apply salvage (return false / no-op for the salvage type) — activation is handled in the UI handler so it can start the state machine. (Or add a `start_salvage()` that the UI calls instead.)

### Step 3 — Salvage state machine on PlayerShip.gd
Add (near the other `_drone_*`/mining vars, ~line 32):
```gdscript
var _salvage_active: bool = false
var _salvage_target: Node3D = null
var _salvage_ore_remaining: float = 0.0
var _salvage_rare_dropped: bool = false
const SALVAGE_ORE_PER_RETURN := 2.0
const SALVAGE_RARE_CHANCE_PER_RETURN := 0.008  # ~0.8% per return → ~15% over a full 20-return run
```
Add `func begin_salvage(wreck: Node3D, total_ore: float) -> void`:
- guard: not docked, wreck valid, not already active;
- set `_salvage_active = true`, `_salvage_target = wreck`, `_salvage_ore_remaining = total_ore`;
- reset the drone collect arrays so a trip starts cleanly;
- emit a chat line ("Salvage drone deployed.").

Add `func _update_salvage(delta)` called from `_process` (only when `_salvage_active`):
- if target became invalid → `_abort_salvage("wreck_gone")`;
- if distance to target ≥ SALVAGE_RANGE → `_abort_salvage("out_of_range")` (player flew away);
- drive the drone mesh out-to-`_salvage_target` and back using the same smoothstep lerp as `_update_drones`;
- on each **completed return**: grant ore via `_salvage_collect_return()`.

Add `func _salvage_collect_return()`:
- `var give = minf(SALVAGE_ORE_PER_RETURN, _salvage_ore_remaining)`
- `var added = GlobalState.add_ore(give)`; if `added <= 0.0` (hold filled up / no longer accepting ore) → **stop the drone immediately** via `_abort_salvage("hold_full")` and return (no further ore granted this run). Also stop if `added < give` *and* the hold is now at cap — i.e. the trip that tops the hold off is the last one.
- `_salvage_ore_remaining -= added`;
- roll rare drop if `not _salvage_rare_dropped and randf() < SALVAGE_RARE_CHANCE_PER_RETURN` → set `_salvage_rare_dropped = true`; pick item: `randf() < 0.65` → `damaged_transponder`, else `encrypted_core`; add via `GlobalState.inventory.add(item_id, 1, stack_max)`; emit a chat line ("Drone recovered salvage: [item]."). If inventory is full, skip silently;
- - if `_salvage_ore_remaining <= 0.0` → `_end_salvage("complete")`.

Add `func _abort_salvage(reason)` and `func _end_salvage(reason)`:
- clear `_salvage_active`, `_salvage_target`, `_salvage_rare_dropped`; respawn/return drones to orbit;
- emit an appropriate chat line: `"complete"` → "Wreck stripped.", `"hit"` → "Salvage drone lost — you took damage!", `"hold_full"` → "Cargo hold full — drone recalled.", `"out_of_range"` → "Moved out of range — drone lost.", `"wreck_gone"` → "Target lost.";
- for `"complete"` only: call `_salvage_target.queue_free()` to remove the wreck (note: target ref may already be cleared — capture it in a local before clearing `_salvage_target`).

### Step 4 — Interrupt on fire
In `PlayerShip.take_damage()`, **after** the shield and armor math (i.e. after actual health/shield reduction has occurred), add:
```gdscript
if _salvage_active:
    _abort_salvage("hit")
```
Place it after the `current_shield` and `health` deductions so it only fires when a hit actually connects (health or shield reduced). This distinguishes a real hit from a missed shot — important because the NPC salvager will fire warning shots and we don't want to abort on a miss. Do **not** place it before shield math.

### Step 5 — Wire the UI "Use" button
In `UIManager._on_inventory_use_pressed()`, branch on `item_id == "salvage_drone"`:
- compute `var reason = ConsumableEffectsScript.salvage_block_reason(GlobalState.player, ...)`;
- if `reason != ""` → `GlobalState.emit_chatter("Drone Bay", reason, <amber color>)` and return (this is the "system message in chat saying why");
- else → `GlobalState.inventory.remove("salvage_drone")`, `GlobalState.player.begin_salvage(GlobalState.active_target, 40.0)`, then `_render_inventory_items()`.
- The generic `is_usable_now()`-driven button-disable still applies, so the button is greyed out when not usable; the chat reason fires on the edge cases / when pressed anyway.

### Step 5b — Close the inventory after using any consumable
Per request: using a consumable should **close the inventory panel** (avoids stale-button / double-use headaches and lets the player see the effect/chat/drone immediately). This is a **general** behavior for all consumables, not just the drone.

- Factor the existing close logic out of `_on_inventory_back_pressed()` ([UIManager.gd:4149](scripts/UIManager.gd)) into a small `_close_inventory_panel()` helper (hide panel; if `inventory_return_to_dock`, re-show `dock_panel` + `_render_dock_submenu()`; clear the flag). Have `_on_inventory_back_pressed()` call it so behavior is unchanged.
- In `_on_inventory_use_pressed()`:
  - **Salvage drone:** if blocked, emit the chat reason and **keep the inventory open** (so the player can read it / pick another item). If it starts successfully, call `_close_inventory_panel()` (the run is undocked, so it just hides the panel).
  - **Instant consumables:** after `ConsumableEffects.use()` returns true, call `_close_inventory_panel()`. On failure (`show_hud_warning(...)`), keep it open.
- Note the interaction with `inventory_return_to_dock`: if the inventory was opened from the dock, closing returns to the dock panel — correct for repair/shield use while docked. Salvage can't be used while docked, so it always just closes to the HUD.

### Step 6 — Shared mining range constant
Mining currently hardcodes `75.0` in two places. Introduce `const MINING_RANGE := 75.0` (or `GlobalState.mining_range`) and reference it from both the mining checks and `SALVAGE_RANGE` so they stay identical per the safeguard ("same distance we currently use for mining"). Keep this change minimal to avoid touching mining behavior — just replace the literals with the named constant.

---

## 4. Testing

- **Unit (headless):** extend [run_consumable_tests.gd](tests/economy/run_consumable_tests.gd) with a `salvage_drone` group:
  - `is_usable_now` false when docked / no target / wrong target type / out of range; true when wreck targeted + in range + undocked.
  - `salvage_block_reason` returns the right string per failure.
  - ore accounting: simulated returns deliver exactly 40 ore total and never exceed it; aborts stop ore grants.
  - Run one at a time with a unique `--log-file` per CLAUDE.md.
- **In-engine (manual / godot-ai):** kill an NPC to spawn a wreck, target it, use the drone, watch drones smack/return and ore tick up; confirm taking a hit aborts and consumes the drone; confirm docked/out-of-range/no-target all emit a chat reason and do not consume the drone.
- **Regression:** mine an asteroid to confirm mining is unchanged (drone animation, ore, range).

## 5. Risk / isolation notes

- Only two existing functions are touched: `take_damage` (one guarded line) and `_on_inventory_use_pressed` (one branch). Everything else is additive (`begin_salvage`, `_update_salvage`, new EFFECTS entry, new const).
- The drone meshes are shared with mining, but salvage runs on its own flag and only when `_salvage_active`; mining and salvage cannot both run (mining needs an asteroid target, salvage needs a wreck target, and salvage checks `not _salvage_active`).
- Save/load: a salvage run is transient and need not persist; if the player saves mid-run, the run simply ends on load (the drone is already consumed). Confirm no crash if `_salvage_target` is freed across a scene change — the `is_instance_valid` guard in `_update_salvage` covers it.

## 6. Open questions for the user

1. **First-system station:** ✅ *Resolved* — **Haven** (`store.haven.general`) is correct. Already stocked there, no layout changes needed.
2. **"Shot at" definition:** ✅ *Resolved* — abort only when **actual damage is taken** (health or shield reduced). Reason: the NPC salvager will take pop shots at you when he spots you; we need to distinguish actual hits from missed fire. Implemented in `take_damage()` after shield math, when `amount > 0` reaches the hull or `current_shield` actually decreases.
3. **Rare-drop rate:** ✅ *Resolved* — **~15% total probability per wreck**, cap at **one rare per wreck**. With ~20 returns: per-return chance ≈ **0.8%** so `P(at least one) = 1 - 0.992^20 ≈ 15%`. Once one rare drops, stop rolling for the rest of that run.
4. **Rare-drop items:** ✅ *Resolved* — **Damaged Transponder 65%, Encrypted Data Core 35%** (weighted roll using `randf()`).
5. **Hold-full behavior:** ✅ *Resolved* — block the drone up front if the hold is already full (chat reason, drone not consumed), and stop the run immediately if the hold fills mid-run. Both covered in Steps 2 & 3.
6. **Wreck depletion:** ✅ *Resolved* — **remove the wreck** at the end of a successful salvage run (`queue_free()`). A model-swap animation for the "being consumed" state is planned for later once a new model is ready; skip it for now and just delete the node. The `_exit_tree()` signal on Wreckage already refreshes the overview list — that fires for free.

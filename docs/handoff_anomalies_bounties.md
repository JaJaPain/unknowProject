# Handoff: Space Anomalies + Kaelen Bounties
**Date written:** 2026-06-22
**Branch:** `segment-3/economy-stores-events`
**Plan file:** `docs/plan_anomalies_bounties.md`

---

## What We're Building

Two new self-contained gameplay systems. Read `docs/plan_anomalies_bounties.md` for the full design. Summary:

### System A: Kaelen's Standing Bounties
Kaelen has "paper" out on specific minor factions in the current system. Kill their ships, she quietly pays you a small bounty (minus her cut) via a chat confirmation. Player learns about it through Kaelen's voice in chat on dock — no new menus, no popups.

### System B: Space Anomalies with LLM Toolkit
1–3 anomaly nodes spawn per system. Each is a fully LLM-authored mini-event: the LLM picks a story type, writes narrative chat lines, AND chooses from a toolkit of real mechanical actions (grant ore/credits/items, spawn hostiles, temp buffs, etc.). The story and the mechanics are coherent because the LLM designs the whole thing. Completely unique every time.

---

## Codebase Context You Need

### Engine & Setup
- Godot 4.6, GDScript, Windows 11
- Branch: `segment-3/economy-stores-events` — all pushed, clean tree
- Use `PROJECT_MAP.md` as navigation index (grep it for class/function names)
- CLAUDE.md has rules — read it first

### Key Files
- `scripts/PlayerShip.gd` — player ship, `take_damage()`, `begin_salvage()` etc.
- `scripts/NPCShip.gd` — NPC ships, `die()` is where kill detection hooks go
- `scripts/GlobalState.gd` — all global state: `player_credits`, `active_target`, `emit_chatter()`, `inventory`, `reputations`
- `scripts/MainScene.gd` — system scene setup, where new node spawning goes
- `scripts/UIManager.gd` — all UI, including Kaelen's panel and the overview list
- `scripts/LLMInterface.gd` — all LLM calls. Pattern: `func fetch_X(callback)` → HTTPRequest → parse response → call callback, with fallback
- `scripts/economy/BountyRegistry.gd` — **DOES NOT EXIST YET**, you create it
- `scripts/economy/ConsumableEffects.gd` — consumable definitions (reference for item IDs)
- `data/content/store_items.json` — all item definitions (reference for valid item_ids)
- `scripts/events/EventScheduler.gd` — existing event system (anomalies may hook into this later but Phase 1 doesn't need it)
- `scripts/NPCSalvager.gd` — reference for how a simple NPC with state machine works

### Patterns to Follow
**LLM fetch pattern** (copy from `request_kaelen_reaction()` in LLMInterface.gd ~line 3292):
- Create temp HTTPRequest node, add_child, connect request_completed
- On completion: parse outer envelope → inner JSON → validate fields → call callback
- On any failure: call fallback function that calls callback with static data
- Add `_attempts_left: int = 1` parameter for one automatic retry

**Chat messages:** `GlobalState.emit_chatter(sender_name, message, Color(...))`
- Kaelen's color: `Color(0.0, 0.9, 0.9)`
- System messages: `Color(0.0, 0.9, 0.9)` with sender `"SYSTEM"`
- Danger/hostile: `Color(1.0, 0.5, 0.2)`

**Spawning nodes in the scene:** See `MainScene._spawn_salvager()` — create node, set_script(), add_child(), position near station or at a specific world pos.

**Overview list:** In `UIManager.gd` search for `get_nodes_in_group("wreckage")` — anomalies should appear in the same overview loop as an "Anomaly" type.

**Minor faction list:** `GlobalState.MINOR_FACTIONS` — keys are faction ids (reavers, obsidian, dustborn, wraiths, ironclad)

**Known item IDs (for LLM whitelist):** repair_kit, shield_cell, scanner_probe, salvage_drone, flare_decoy, fuel_booster, emp_charge, target_painter, data_chip, kinetic_ammo, thermal_ammo, explosive_ammo, energy_ammo, damaged_transponder, encrypted_core, antimatter_pod

---

## Build Order

### DO THIS FIRST: Kaelen Bounties (Phase 1)

**Step 1 — `scripts/economy/BountyRegistry.gd`** (new file)
Static singleton pattern (same as StoreRegistry). Stores active bounties as an array of dicts:
```gdscript
{
  "faction": "dustborn",
  "system_id": "...",
  "payout_per_kill": 9,
  "cap": 8,           # -1 = unlimited
  "kills_credited": 0,
  "expires_day": 12,
  "kaelen_line": "...",   # flavor for why she wants them dead
}
```
Functions needed:
- `shared()` — static singleton
- `set_bounties(bounties: Array)` — called after LLM generates them
- `check_kill(faction: String, system_id: String) -> int` — returns payout or 0, increments kills_credited, respects cap
- `get_active_bounties() -> Array` — for UI display
- `clear()` — on system change

**Step 2 — `LLMInterface.fetch_bounty_brief(system_id, factions, callback)`** (new function)
Prompt: give LLM current system's minor factions + player rep + day number. Ask it to pick 1–2 factions to put bounties on, give a one-sentence reason (Kaelen's voice), suggest payout 7–15 SC.
Response JSON:
```json
{
  "bounties": [
    {
      "faction": "dustborn",
      "payout": 9,
      "cap": 6,
      "kaelen_line": "The Dustborn hit a shipment I had a stake in. I want receipts."
    }
  ]
}
```
Fallback: pick 1 random faction from minor factions list, generic line, payout 8 SC, cap 5.

**Step 3 — `NPCShip.die()`** — add ONE line near the end:
```gdscript
BountyRegistry.shared().check_kill(faction, GlobalState.current_system_id)
```
But check_kill should also handle the payout and chat emit internally (keep die() clean). Have BountyRegistry call `GlobalState.player_credits +=` and `GlobalState.emit_chatter("Kaelen", ...)` when a bounty hit lands.

**Step 4 — Wire into dock flow in `UIManager.gd`**
- On dock (find where dock_player is called or where Kaelen's panel opens): if BountyRegistry has active bounties, emit one Kaelen chat line announcing them.
- In Kaelen's panel UI: small "Active Paper:" label showing faction + per-kill rate. One line, subtle. Find `_render_dock_submenu` or wherever Kaelen's panel is built.
- Trigger `fetch_bounty_brief` on system entry (MainScene._ready or on first dock of a session).

---

### DO THIS SECOND: Space Anomalies Phase 1 (foundation, no LLM yet)

**Step 1 — `scenes/anomaly.tscn` + `scripts/SpaceAnomaly.gd`** (new files)
SpaceAnomaly extends StaticBody3D. Add to group `"anomaly"`.
- Visual: simple glowing sphere (OmniLight3D + MeshInstance3D with SphereShape collision), pulsing emission, maybe 2–3 different colors for different flavor types
- `anomaly_data: Dictionary` — the LLM-authored event data
- `_activated: bool = false`
- On player within 50u (check in `_physics_process` against `GlobalState.player`): trigger activation
- Activation sequence: execute `anomaly_data.actions` array in order, using timers for delays
- After all actions complete: `queue_free()`

Action executor — a `_execute_action(action: Dictionary)` function with a match on `action.type`:
```
"emit_chat" → GlobalState.emit_chatter(action.sender, line, color) per line with delays
"grant_ore" → GlobalState.add_ore(clampf(action.amount, 0, 30))
"grant_credits" → GlobalState.player_credits += clampi(action.amount, 0, 150)
"grant_item" → GlobalState.inventory.add(item_id, 1, stack_max) if item_id in VALID_ITEMS
"spawn_hostiles" → spawn 1–3 NPC ships of faction (same pattern as MainScene._spawn_npc)
"grant_temp_buff" → future (skip in Phase 1, log a warning)
"damage_player" → GlobalState.player.take_damage(clampf(amount, 0, 20))
```

**Step 2 — `scripts/AnomalyRegistry.gd`** (new file)
- `generate_for_system(system_id, scene_parent)` — places 1–3 anomaly nodes at random world positions (500–1200u from origin, away from station and asteroids)
- Phase 1: use static fallback table of 8–10 preset event dicts (no LLM yet)
- Store which anomaly IDs have been activated (for save/load later)

Static fallback table examples (write at least 8 varied ones):
- Abandoned cargo cache → grant ore + grant_item
- Distress beacon (no survivors) → emit_chat logs + grant_credits
- Reaver ambush point → emit_chat warning + spawn_hostiles
- Cracked reactor core → damage_player + grant_credits (dangerous scavenge)
- Drifting weapon cache → grant_item (ammo) + grant_item
- Encrypted black box → emit_chat mystery lines + grant_item(encrypted_core)
- Faction skirmish debris → grant_ore + spawn_cargo_pod (future) or just grant_ore
- Navigation buoy → grant_rep(zenith, 5) + emit_chat

**Step 3 — `MainScene.gd`**
In `_ready()`, after `_spawn_salvager()`, call `AnomalyRegistry.generate_for_system(...)`.

**Step 4 — `UIManager.gd` overview**
Anomaly nodes appear in overview as type "Anomaly" — yellow/amber color. Find the `get_nodes_in_group` loop that builds the overview and add an `elif entity.is_in_group("anomaly")` branch.

---

### Phase 3 (FUTURE SESSION): LLM Brain for Anomalies
1. `LLMInterface.fetch_anomaly_event(system_context, callback)` — prompt + JSON parse + validation + retry
2. Wire into `AnomalyRegistry` — async fetch on system entry, fallback if slow/fails
3. Validate every action field before executing (whitelist item IDs, cap values, known faction IDs)

---

## Guardrails — Do NOT Touch
From CLAUDE.md: procedural story generation, campaign bible, story-pack persistence, generated-system save/load, event scheduler (read it but don't modify it for Phase 1), mission generation, quest objective schemas, inventory transaction rules, gate unlock rules, generated faction identity rules.

## Testing
- Run headless tests one at a time with unique --log-file paths (see CLAUDE.md for the command pattern)
- Anomaly: manually spawn the scene in TestSystem.gd for quick iteration
- Bounty: easiest to test by temporarily lowering MINOR_FACTIONS kill count threshold or adding a debug dock trigger

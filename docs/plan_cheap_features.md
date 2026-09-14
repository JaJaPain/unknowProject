# Cheap Feature Plan — Non-Core Gameplay Loops
_Date: 2026-06-22 | Branch: segment-3/economy-stores-events_

Five features pulled from memory notes and design_parking_lot.md. All are self-contained — none touch mission logic, quest schemas, or campaign persistence in ways that could break anything.

---

## Feature 1: Gate Portal Particles
**Status:** Not started  
**Files:** `scripts/JumpGate.gd` only  
**Effort:** ~1 hour

### What it does
Additive particle emitters that float off the portal surface — tiny energy motes drifting away from the gate ring. The portal shader is locked; particles sit on top.

### Implementation
- In `JumpGate._ready()`, after `portal_material` is set, spawn a `GPUParticles3D` node as a child of `portal_surface`
- Particles: small bright quads, additive blend, short lifetime (1–2s), slow random drift outward, color sampled from gate light color
- Scale emission rate with `charge` value — idle gate emits a trickle, charged gate emits more
- No scene file changes — fully procedural in script

### What NOT to touch
- `jumpgate_portal.gdshader` — do not edit, it's approved as-is
- Gate knowledge state logic, activation range, arrival/approach markers

---

## Feature 2: System Arrival Text Banner
**Status:** Not started  
**Files:** `scripts/JumpTransitionFX.gd`, `scenes/jump_transition_fx.tscn`  
**Effort:** ~1 hour

### What it does
After the flash clears on gate exit, a 2-second fullscreen text overlay fades in then out:
```
ENTERING
FRONTIER SYSTEM
```
System name in large caps, faction (if controlled) in a smaller line below. Pure visual — zero game logic.

### Implementation
- Add a `Label` (or two) to `jump_transition_fx.tscn` inside the CanvasLayer, starting invisible
- Add `play_arrival_banner(system_name: String, faction: String = "")` to `JumpTransitionFX.gd`
- Call it from `GameRoot.gd` after `jump_fx.play_exit()` finishes, passing the arriving system's `display_name` and dominant faction if any
- Tween: fade in over 0.3s, hold 1.5s, fade out over 0.5s

### What NOT to touch
- Existing `play_entry`, `play_exit`, `hold_covered` logic — add only, don't edit
- Camera shake, FOV, distortion shader params — untouched

---

## Feature 3: Route Planner → Overview Gate Highlight
**Status:** Partially done (BranchMapUI already has full route logic)  
**Files:** `scripts/UIManager.gd` only  
**Effort:** ~30 min

### What already exists
`BranchMapUI` already computes BFS routes, draws them on the map, stores `planned_route`, and exposes `get_next_hop_legacy_id()` which returns the legacy_id of the next system to jump to.

### What's missing
In `UIManager.update_overview_list()`, when `branch_map` has an active route, the overview entry for the jumpgate leading to the next hop should show a `→` marker or a highlighted color so the player can see which gate to take without reopening the map.

### Implementation
- In `update_overview_list()`, after building each button, check if `branch_map` exists and `branch_map.planned_route.size() >= 2`
- Get next hop via `branch_map.get_next_hop_legacy_id()`
- If the entity is a JumpGate whose `destination_system_id` (or `world_id`) matches the next hop, apply a green tint to that button and prepend `→ ` to the name label

### What NOT to touch
- BranchMapUI pathfinding — already correct
- Route clear logic — already fires when player arrives at destination

---

## Feature 4: Map Tooltip Ore Types
**Status:** DEFERRED — ore type data does not exist in SystemConfig or SystemDefinition. No `ore_types` field anywhere in the generation pipeline. Would need the data layer built first (add field to SystemConfig, populate during zone generation). Tooltips already show station count + factions with rep colors, which covers the core need.  
**Files:** `scripts/generation/SystemConfig.gd`, `scripts/ui/BranchMapUI.gd`  
**Effort:** ~1 hour (once data exists)

### What already exists
`BranchMapUI._update_hover_tooltip()` already shows station count and faction names with rep colors. The `system_nodes` dict already holds `station_count`, `faction_names`, `faction_ids`.

### What's missing
Ore type data. `SystemConfig` doesn't currently store which ore types are available. Asteroids get their ore type from zone config, not system config.

### Implementation
- In `SystemConfig.gd`, add `var ore_types: Array[String] = []` — populated from the zone definitions when the system config is built
- In `BranchMapUI._build_system_nodes()`, add `"ore_types": sys_def.ore_types` (or equivalent) to the node dict
- In `_update_hover_tooltip()`, add: `if not ore_types.is_empty(): text += "\nOre: " + ", ".join(ore_types)`
- If ore type data isn't available on SystemDefinition yet, show nothing (graceful fallback)

### What NOT to touch
- Zone generation logic — read only, don't change asteroid placement
- Existing tooltip layout — extend only

---

## Feature 5: Station Lounge — Rumor Badge + Contact Moods
**Status:** Not started  
**Files:** `scripts/UIManager.gd` (dock panel section)  
**Effort:** ~1.5 hours

### What it does
Two cheap social-sim affordances on the NPC contact list in the station lounge:
- **Rumor badge**: A `(!)` indicator next to contact names when they have fresh flavor text the player hasn't seen this visit. Clears on click. Session-only (not persisted).
- **Contact mood**: A one-word tag `[Chatty]`, `[Tense]`, `[Distracted]` next to each contact name, seeded off `GlobalState.day_seed` so it changes daily but is consistent within a day.

### Implementation
- Rumor badge: track a `Set`-like dict `_contacts_with_new_content: Dictionary` (contact_id → bool). When a contact's LLM flavor fires or dock opens, mark them. Clear on click. Show `(!)` in the button label if marked.
- Contact mood: 3-4 moods, pick via `hash(contact_id + str(day_seed)) % moods.size()`. Display as `[Mood]` in grey after the name.
- Both live entirely inside `_build_contact_list()` / `_create_contact_button()` in UIManager

### What NOT to touch
- `CampaignNPCIdentityStore` — no persistence changes
- LLM generation, quest logic — read-only signals only
- Any contact's actual dialogue or stat system

---

## Build Order

1. **Gate portal particles** — pure visual, self-contained, great warmup
2. **Arrival text banner** — pure visual, hooks into existing transition at one call site
3. **Route overview highlight** — 30 min, big QoL for navigation
4. **Map tooltip ore types** — depends on whether SystemDefinition exposes ore data; if not, skip/stub
5. **Lounge moods + rumor badge** — slightly more code but still self-contained


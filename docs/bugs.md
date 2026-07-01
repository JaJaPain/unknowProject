# Known Bugs
_Confirmed issues spotted during playtesting. Move to todo.md or close with a commit reference when fixed._

---

## Active

### Autopilot object avoidance regressed
**Status:** STILL BROKEN — confirmed 2026-07-01 playtest. Prior fix attempts (2026-06-26, 2026-06-30) did NOT hold. New symptom: trying to "Fly to" a hostile target on the far side of a planet, the ship flew the OPPOSITE direction, then got stuck/stalled and never reached the target — playtest was unplayable because of it. So the failure is not just grazing hazards; the route/steer target itself is inverting or dead-ending when a large body (planet/gas giant) sits between ship and target. Re-investigate `_route_steer_target` planner output + `_get_autopilot_avoidance` wiring; check for a heading sign-flip and a stall with no replan. Previous notes below still apply.
**Spotted:** ~2026-06-21  
**Severity:** Medium — ship flies into stations and asteroids during autopilot  
**Root cause identified:** `_get_autopilot_avoidance()` (`PlayerShip.gd:999`) is fully implemented but is **never called** from the main autopilot movement block (`PlayerShip.gd:740–754`). The movement loop only calls `_route_steer_target()` (static A* planner). The real-time avoidance system exists but got disconnected from the autopilot loop, likely when the planner was introduced.

**Fix plan:**
Two complementary layers need to work together:
1. **Static planner** (`_route_steer_target`) — runs A* at route-start to generate waypoints around known hazards. Good for long-distance routing.
2. **Real-time avoidance** (`_get_autopilot_avoidance`) — scans for obstacles along the current heading every frame. Acts as a forward whisker/feeler (the Unity "empty object on the ship nose" equivalent). Needs to be called every frame in the autopilot block and its `steer_target` fed into `steer_towards()` in place of the planner's output when avoidance is active.

**Wire-up:** In `_physics_process`, after getting `steer_target` from `_route_steer_target`, pass it through `_get_autopilot_avoidance(steer_target, active_target)`. If `is_avoiding` is true, use avoidance's `steer_target` instead. This gives the planner the big picture and the whisker handles surprises.

**Additionally:** Add a `RayCast3D` on the ship nose for imminent collision (distance < 30u) that forces `_clear_planned_route()` immediately, triggering a fresh A* replan without waiting for the 2.5s stall timer.

**Where to change:** `scripts/PlayerShip.gd:740–754` (autopilot movement block).

---

### Agent accept reply uses Kaelen voice
**Spotted:** 2026-06-23  
**Severity:** Medium — breaks immersion every time a quest is accepted  
**Description:** After the player accepts a quest from an agent (Liaison Ryn, Director Voss, etc.), the agent's spoken reply uses Kaelen's voice instead of the agent's own voice blend.  
**Where to look:** `UIManager.gd` or `SpeechService` — wherever the post-accept dialogue TTS call is made. Check that the agent's voice blend is passed, not defaulting to the Kaelen blend.

---

### New campaign overwrites existing slot instead of using next empty slot
**Spotted:** 2026-06-26  
**Severity:** High — data loss risk  
**Description:** Starting a new campaign appears to overwrite an occupied slot rather than selecting the next empty one. Player loses an existing campaign save.  
**Where to look:** `GameRoot.gd` → new campaign slot selection logic. Check `campaign_slot_registry.first_empty_slot_id()` is being called and that the result is being used rather than defaulting to slot 1 or the active slot.

---

### Quest tracker panel blue box reappears on second quest
**Spotted:** 2026-06-25  
**Severity:** Low — cosmetic  
**Description:** When the player accepts a second quest, the oversized empty blue box (quest tracker panel) reappears. The `call_deferred("reset_size")` fix only fires when the panel first becomes visible; it doesn't re-fire when a new quest loads into an already-visible panel.  
**Where to look:** `scripts/UIManager.gd` → `_update_quest_tracker()`. The `reset_size()` call needs to fire every time quest content changes. Also check if `user://ui_layout.json` is persisting a saved `w`/`h` for the quest panel and re-applying it on each update.

---

### Mechanic pickup prompt persists after quest delivery
**Spotted:** 2026-06-25  
**Severity:** Low  
**Description:** After the player delivers a special cargo item to the mechanic NPC and receives credits, the "I'll Grab It / Not Now" buttons still show on subsequent visits. They should disappear permanently once the pickup quest is complete.  
**Where to look:** `scripts/UIManager.gd` — wherever the mechanic dock panel is built/refreshed. The prompt visibility is likely gated on a quest state flag that isn't being cleared after completion. Check `QuestManager` or `GlobalState` for the relevant completion flag.

---

### Agent dialogue sometimes addresses player as "Indy" or "Shiny"
**Spotted:** 2026-06-26
**Severity:** Low — immersion break
**Description:** Agent NPC dialogue (quest offers, contract details) occasionally includes "Indy" or "Shiny" directly in the agent's speech — e.g. "3 Wraiths raiders are probing our perimeter, Indy." The agent should not know or use the player's callsign; only Kaelen uses "Shiny". "Indy" appears to be leaking from the pilot backstory or prompt context into the agent prompt.
**Where to look:** `LLMInterface.gd` — quest generation prompt assembly. Check what context fields are passed and whether the pilot callsign/name is included in a way the agent template can pick up. Add a post-generation strip or a prompt rule: "Do NOT address the pilot by name or callsign. You do not know their name."

---

### Shield visual persists after combat ends
**Spotted:** 2026-06-26
**Severity:** Low — cosmetic
**Description:** The shield effect sometimes remains visible on the player ship after combat ends instead of disappearing with the combat state. Likely the shield deactivation call is not firing on all combat-exit paths (timeout, enemy death, flee).
**Where to look:** `CombatManager.gd` — wherever combat ends; check that shield deactivation is called on every exit path, not just the primary one.

---

### Mouse cursor lost when entering combat
**Status:** Fix attempt made 2026-06-28 and seems to be working in playtest so far. PlayerShip.gd now releases mouse capture on combat start/end, and UIManager.gd forces MOUSE_MODE_VISIBLE when pause or inventory opens. Keep this bug open until it survives more combat sessions without recurrence.
**Spotted:** 2026-06-28
**Severity:** High — can soft-lock input; only recoverable by Alt-Tab + closing from the taskbar
**Description:** Occasionally on combat entry the mouse cursor disappears with no way to get it back inside the game — the player must tab out and close the window from the taskbar (the in-window X doesn't respond). Intermittent. Likely the mouse mode is set to CAPTURED/HIDDEN on combat start and not restored to VISIBLE on some path (or a combat-camera/orbit handler grabs it and never releases).
**Where to look:** `CombatManager.gd` combat-start and `PlayerShip.gd` combat-camera handlers (`_on_combat_started_orbit`, etc.) — grep for `Input.set_mouse_mode` / `MOUSE_MODE_`. Ensure mouse mode is forced back to `MOUSE_MODE_VISIBLE` on every combat-enter and combat-exit path; consider an unconditional safety reset while combat is active.

---

### NPC kills count toward player's KILL_SHIPS mission
**Spotted:** 2026-07-01
**Severity:** High — lets missions "complete" without the player doing anything; combined with the autopilot bug the player literally couldn't reach the target, yet the kill counter climbed to 2/3 from NPC-vs-NPC kills.
**Description:** A KILL_SHIPS objective (target faction Dustborn) incremented "Kills: 2/3" from ships destroyed by OTHER NPCs (Aurelia combat vessels killing Dustborn), not by the player. Kill credit must require the player (or the player's drones) as the killer.
**Where to look:** `scripts/QuestManager.gd` kill-tracking / the combat death signal handler that increments KILL_SHIPS progress. Check the killer attribution — it likely counts any death of a matching-faction ship rather than deaths where `killer == GlobalState.player` (or a player-owned drone/projectile). Gate the increment on player attribution.

---

### "Trade Ore for <part>" errand button broken
**Spotted:** 2026-07-01
**Severity:** High — blocks completing PICKUP/errand quests that require clearing cargo for the part
**Description:** At Iron Reach Outpost lounge, the "Trade Ore for Quantum Drive Bypass Coil (15 m³ → 45 SC)" action (and its "Sell Ore, Take the Part" confirm) did nothing / did not complete the trade. The errand pickup (Parts Run: Quantum Drive Bypass Coil from Oleg Stroud) could not be fulfilled.
**Where to look:** `scripts/UIManager.gd` — the outpost lounge "trade ore for part" button handler and its confirm buttons; verify the pressed signal is wired, the ore-sell + item-grant transaction fires, and quest state advances. Cross-check with `QuestManager` pickup/errand completion.

---

### Campaign bible (gemma4:12b) JSON parse fails + starves small-model dialogue at session start
**Spotted:** 2026-07-01 (from logs/fallback_summary.txt)
**Severity:** Medium — causes session-start fallbacks
**Description:** Two issues, both at session start. (1) `campaign_bible` generation on `gemma4:12b` fails with `response_json_parse_failed` (quality — model returns unparseable JSON). (2) While the 12B runs the bible, three `mechanic_intro` requests time out (`http_failed_result_13`, 8s) even though the small model was warmed — GPU/VRAM contention from the large model starves the small dialogue model. NOTE: the cold-start warm-up fix DID work for quest generation (candidates now return in 3–6s vs prior 15s timeouts; quest came from `llm`, not fallback).
**Where to look:** (1) `NarrativeDirector`/`CampaignBibleStore` prompt + JSON-mode/schema for gemma4; (2) sequence campaign_bible generation so it doesn't run concurrently with the first dock's small-model calls, or raise `mechanic_line` timeout, or don't block dialogue behind the large model.

---

## Fixed

| Date | Bug | Fix |
|---|---|---|
| 2026-07-01 | Dummy word "Slithern" leaked into quest TITLE (e.g. "Slithern Scourper") | `_substitute_dialogue_placeholders` now applies replacements to `quest_data["title"]`, not just dialogue/choices — `LLMInterface.gd` |
| 2026-06-26 | Autopilot object avoidance regressed | Re-wired `_get_autopilot_avoidance()` into autopilot loop; added `RayCast3D` nose whisker; added mid-route validity re-check — `PlayerShip.gd` (NOTE: regressed again, see Active) |
| 2026-06-25 | Combat flee taunt used Kaelen voice | Added `_play_npc_flee_taunt()` in `CombatManager._exec_flee()` |


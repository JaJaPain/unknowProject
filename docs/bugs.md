# Known Bugs
_Confirmed issues spotted during playtesting. Move to todo.md or close with a commit reference when fixed._

---

## Active

### N.O.V.A. talks during first dock flow
**Spotted:** 2026-07-08 (intro cinematic playtest)
**Severity:** Medium - can interrupt/confuse the first dock onboarding beat
**Description:** On the player's first dock after the opening cinematic, N.O.V.A. can speak as part of the normal dock flow. That first dock is supposed to belong to Kaelen's onboarding / station direction, so regular N.O.V.A. dock chatter should be suppressed until the first-dock intro flow has cleared.
**Where to look:** `scripts/UIManager.gd` first-dock / dock-menu flow and any `Nova.on_docked` or dock-chatter calls. Gate the regular N.O.V.A. dock line behind the same first-dock story flags that control Kaelen's starter guidance.

---

### First mission target ship never respawns after logout/login (mission uncompletable)
**Spotted:** 2026-07-03 (playtest)
**Severity:** High — soft-locks the first mission; the kill objective can never be satisfied
**Description:** If the player logs out (saves + quits) BEFORE the first mission's target ship is destroyed, then loads that save back in, the mission ship does not come back. The KILL objective stays at 0 with no target present in the system, so the first mission can never be completed. Mission targets are spawned at mission start but appear not to be persisted into the campaign save and not re-spawned on load.
**Where to look:** `GlobalState.spawn_mission_targets` (spawns the starter target(s) at mission start) + the save/restore path — `savegame.json` / `CampaignManifestStore` and the persistent-entity system (`NPCShip.capture_state`/`restore_state`, `persistent_id`). Confirm whether mission target ships are included in the persisted entity set. If they aren't persisted, `QuestManager` should, on load, detect any in-progress KILL_SHIPS mission whose targets are missing and re-spawn them (mirror the "respawn replacement target far away" logic already used when an NPC kills a target — see the 2026-07-01 fixed entry). Also verify the mission's own state (progress, target ids) round-trips through save/load.

---

### Kaelen handoff batch intermittently returns no JSON array
**Spotted:** 2026-07-02 (live playtest during story-wiring session)
**Severity:** Low — falls back gracefully (`StoryManager.generate_handoff_pool` just logs "Handoff batch returned empty" and the pool stays at its previous size), but worth root-causing.
**Description:** During one live session, `request_kaelen_handoff_batch()` failed for all 3 faction agents (Director Voss, Captain Dask, Liaison Ryn) right after startup — two with `[LLMInterface] Handoff batch: no JSON array found in response`, one with an outright HTTP error (`result=13 code=0`). This happened concurrently with a `campaign_bible` generation request (large model) and several background-chatter caching calls (small model) all firing in the same startup window.
**Where to look:** `LLMInterface.gd` around line 5174-5188 (`request_kaelen_handoff_batch` completion handling) and `StoryManager._trigger_handoff_pool_for_system`/`generate_handoff_pool`. Suspect Ollama resource contention from multiple concurrent requests (large model warming up while several small-model calls queue) rather than a prompt/parsing bug — worth checking if `campaign_bible_priority_active` (which already defers some other LLM calls while the bible generates) should also cover handoff batch generation.

---

### Public board pickup offer shows oddly at station (same family as mechanic offer)
**Spotted:** 2026-07-01
**Severity:** Low-Med — confusing offer/pickup state on the station board panel
**Description:** At KOVA STATION the board panel showed two WANTED bounty cards (Reavers 0/4, Obsidian 0/5) AND a side pickup offer "Unlabeled Heat Sink Pickup From KOVA STATION, Please Stop Asking Why — Pickup: Unlabeled Heat Sink from Dasha Invar @ KOVA STATION" with a "Set Course: KOVA STATION" button. Likely the same class of bug as the mechanic offer: a pickup offer surfacing at the wrong time / pointing the pickup at the SAME station you're docked at (set course to where you already are). Also the LLM flavor title reads as placeholder-ish ("Please Stop Asking Why").
**Where to look:** `scripts/UIManager.gd` public board / station board panel builder + the pickup offer that renders alongside board bounties; and `MissionTemplateRegistry` / public board offer builder for the pickup destination (should not be the current station). Cross-check with the mechanic offer gating fix (2026-07-01) — same "offer unmasked at wrong moment" pattern.

---

### Autopilot object avoidance regressed
**Status:** STILL BROKEN — confirmed 2026-07-01 playtest. Prior fix attempts (2026-06-26, 2026-06-30) did NOT hold. New symptom: trying to "Fly to" a hostile target on the far side of a planet, the ship flew the OPPOSITE direction, then got stuck/stalled and never reached the target — playtest was unplayable because of it. So the failure is not just grazing hazards; the route/steer target itself is inverting or dead-ending when a large body (planet/gas giant) sits between ship and target. Re-investigate `_route_steer_target` planner output + `_get_autopilot_avoidance` wiring; check for a heading sign-flip and a stall with no replan. Previous notes below still apply.

**Current code map (2026-07-01, so we don't re-trace):** Autopilot lives in `PlayerShip.gd _physics_process` (~1160-1186). Per frame it: (1) nose whisker `_nose_ray` sphere-cast → `_clear_planned_route()` on obstacle; (2) `_route_steer_target(dest, active_target)` — STATIC A*-ish planner (`_plan_route_with_belt_clearance` ~1365, `_plan_route_with_vertical_clearance` ~1435) returns a `steer_target`; (3) `_update_route_progress`; (4) `_get_autopilot_avoidance(steer_target, active_target)` (~1641) — REAL-TIME avoider with `_get_locked_avoidance_obstacle`, `_choose_avoidance_side` (~1967), `_build_avoidance_waypoint` (~2163) — can override the steer target; (5) `steer_towards`. TWO stacked systems (~700 lines) that interact; the "flies opposite" is almost certainly one of them emitting a steer target behind the ship (bad side choice or degenerate planner node), and the stall is no-replan when steering into a body. This over-complex pair is the thing Abe wants to REPLACE, not keep patching.

**Proposed redesign (Abe's idea + refinements, 2026-07-01) — REPLACE the ad-hoc avoider with a clean sphere keep-out:**
- Give every planet/gas giant an invisible **keep-out sphere**, radius = body radius + its asteroid-belt outer radius + small margin (sized "just past the orbiting asteroids"). Store it on the body (or a registry the ship can query).
- Navigation rule (per frame, ship→target):
  1. If the straight segment ship→target does NOT intersect any keep-out sphere → steer straight at target. (No planner needed.)
  2. If it DOES intersect a sphere → steer to a **tangent waypoint** on that sphere's silhouette (the edge point on the shorter-detour side), then re-evaluate next frame. This naturally hugs the OUTSIDE of the sphere and can't invert. (Preferred over grid A* — lighter, no degenerate-node "fly opposite" failure.)
  3. If the ship is currently INSIDE a sphere and the target is OUTSIDE it and > X away → first steer to the nearest point on the sphere surface (exit), then resume rule 1/2.
  4. Ignore a sphere only when the TARGET is within X of the ship AND not on the far side of that sphere (final approach). If the target itself is inside a sphere — e.g. an enemy hugging the planet — you must enter; that's expected, just approach directly once close.
- Keep the `_nose_ray` whisker as a last-resort hard-stop/replan; drop `_choose_avoidance_side` / `_build_avoidance_waypoint` / belt-clearance planners in favor of the tangent rule.
- **Moving-target companion fix (Abe):** any enemy/mover OUT of the player's sight range is held still (AI LOD freeze) until it enters viewable range — stops the autopilot from chasing a target that teleports around off-screen and keeps the goal stationary while pathing. Freeze is invisible to the player (it's out of sight range).
- Standards note: sphere keep-out + tangent steering is the standard lightweight approach for a single dominant spherical obstacle and is far more robust than the current side-choosing avoider. Pushback only if bodies overlap or belts are non-spherical (then a couple of spheres per body, still fine).
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

### "Trade Ore for <part>" errand button broken
**Spotted:** 2026-07-01
**Severity:** High — blocks completing PICKUP/errand quests that require clearing cargo for the part
**Description:** At Iron Reach Outpost lounge, the "Trade Ore for Quantum Drive Bypass Coil (15 m³ → 45 SC)" action (and its "Sell Ore, Take the Part" confirm) did nothing / did not complete the trade. The errand pickup (Parts Run: Quantum Drive Bypass Coil from Oleg Stroud) could not be fulfilled.
**Where to look:** `scripts/UIManager.gd` — the outpost lounge "trade ore for part" button handler and its confirm buttons; verify the pressed signal is wired, the ore-sell + item-grant transaction fires, and quest state advances. Cross-check with `QuestManager` pickup/errand completion.

**Research 2026-07-01 (traced, NOT yet fixed — start here):** The whole chain is implemented and looks correct, so the break is a RUNTIME condition, not missing code. Flow: `ask_for_part_btn` ("Trade Ore for X") → `_on_ask_for_part_pressed()` (UIManager ~9546) → passes all guards (right outpost, has ore) → `_show_ore_trade_popup()` (the popup Abe screenshotted, showing correct 3 SC/m³ = 45 SC) → "Sell Ore, Take the Part" = `_on_ore_trade_accept_pressed()` (~9615) → `GlobalState.buyback_ore_at_outpost()` → `_complete_pickup_with_handoff()` (~9636) → `QuestManager.mark_pickup_complete()`. Two SILENT failure branches to check on next repro:
1. `buyback_ore_at_outpost()` (GlobalState ~1492) returns 0 → handler aborts with only a `push_warning("buyback returned 0")`, no on-screen feedback ("did nothing"). But it should return 45 here (cargo=15 ORE, rate=3), so only fails if cargo/type changed between popup-show and accept.
2. `mark_pickup_complete()` returns false → shows "Couldn't load the part. Clear your cargo hold and try again."
NEXT REPRO: dock at the outpost with ore, press through, and check the console for `buyback returned 0` OR the "Couldn't load the part" message — that one line says which branch failed. Note the popup and the menu button were BOTH visible at once (possible stale-panel UI state worth checking too).

---

### Campaign bible (gemma4:12b) JSON parse fails + starves small-model dialogue at session start
**Spotted:** 2026-07-01 (from logs/fallback_summary.txt)
**Severity:** Medium — causes session-start fallbacks
**Description:** Two issues, both at session start. (1) `campaign_bible` generation on `gemma4:12b` fails with `response_json_parse_failed` (quality — model returns unparseable JSON). (2) While the 12B runs the bible, three `mechanic_intro` requests time out (`http_failed_result_13`, 8s) even though the small model was warmed — GPU/VRAM contention from the large model starves the small dialogue model. NOTE: the cold-start warm-up fix DID work for quest generation (candidates now return in 3–6s vs prior 15s timeouts; quest came from `llm`, not fallback).
**Where to look:** (1) `NarrativeDirector`/`CampaignBibleStore` prompt + JSON-mode/schema for gemma4; (2) sequence campaign_bible generation so it doesn't run concurrently with the first dock's small-model calls, or raise `mechanic_line` timeout, or don't block dialogue behind the large model.

---

### Mission state machine never uses READY_TO_TURN_IN — every completion warns "Invalid transition"
**Spotted:** 2026-07-13 (headless test output while proving the Kaelen bundle save/reload exit gate)
**Severity:** Low — warning noise only, no behavior break
**Description:** `MissionInstance.VALID_TRANSITIONS` requires ACTIVE → READY_TO_TURN_IN → COMPLETED, but no production code ever transitions an instance to READY_TO_TURN_IN (only `MissionInstance.gd` itself references it). So every `QuestManager.complete_quest()` hits `focused.transition_to(State.COMPLETED)` from ACTIVE, logs `[MissionInstance] Invalid transition: ACTIVE -> COMPLETED`, and removes the instance while still ACTIVE. Harmless today because removal follows immediately, but the state machine is dead weight and the warning pollutes every turn-in.
**Where to look:** `QuestManager._mark_objective_ready_if_completed()` (scripts/QuestManager.gd:783) is the natural place to transition the focused instance to READY_TO_TURN_IN (and back to ACTIVE if progress can regress), or route `complete_quest()` through it. Keep `_instance_state` save/restore round-trip intact. A spawn-task chip was filed for this.

---

## Fixed

| Date | Bug | Fix |
|---|---|---|
| 2026-07-01 | Dock panel opened over the combat wheel (docked while in combat) | Autopilot dock (e.g. the completed-mission "Dock at Station" button) could reach a station while combat started en route, opening the dock menu mid-fight. `Station.dock_player` + `OutpostStation.dock_player` now bail with a HUD warning if `PlayerInteractionQueue.in_combat_window()` (covers active combat + post-combat cooldown) |
| 2026-07-01 | Mechanic pickup offer buttons appeared during turn-in | Completing the pickup freed the STATION lane, unmasking the next dock's already-rolled offer mid-turn-in. `_on_deliver_part_pressed` now clears `_mechanic_pickup_offer`, hides the buttons, and sets the cached greeting to the thanks line — `UIManager.gd` |
| 2026-07-01 | NPC kills counted toward player's KILL_SHIPS mission | Split attribution via existing signals: `player_kill` (player-only) counts progress; `ship_destroyed` now fires ONLY for non-player kills (`NPCShip.gd`) and schedules a replacement target instead of counting. KILL_SHIPS capability refuses credit when `by_player=false`; respawn now 20s + ≥800u from the player (`QuestManager.gd`, `KillShipsCapability.gd`, `GlobalState.spawn_mission_targets`). Design per Abe: NPC-killed targets replaced far away so the contract stays player-completable. |
| 2026-07-01 | Dummy word "Slithern" leaked into quest TITLE (e.g. "Slithern Scourper") | `_substitute_dialogue_placeholders` now applies replacements to `quest_data["title"]`, not just dialogue/choices — `LLMInterface.gd` |
| 2026-06-26 | Autopilot object avoidance regressed | Re-wired `_get_autopilot_avoidance()` into autopilot loop; added `RayCast3D` nose whisker; added mid-route validity re-check — `PlayerShip.gd` (NOTE: regressed again, see Active) |
| 2026-06-25 | Combat flee taunt used Kaelen voice | Added `_play_npc_flee_taunt()` in `CombatManager._exec_flee()` |

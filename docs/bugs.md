# Known Bugs
_Confirmed issues spotted during playtesting. Move to todo.md or close with a commit reference when fixed._

---

## Active

### Quest card disappears (after load, and after docking) until the layout is unlocked and relocked
**Spotted:** 2026-09-09 (Abe, playtest). Reported for LOADING, then for DOCKING.
**Severity:** Medium -- the player's active contract is invisible, and the only
workaround is a UI ritual nobody would guess.
**Status:** STILL OPEN as of 2026-09-10 -- **the first fix was a no-op.** Second
attempt landed 2026-09-10, needs a playtest.

**Why the first fix failed, recorded because it is an easy trap to fall into
twice:** `UIManager.undock_player()` was made to call `_update_quest_tracker()`.
But `is_docked` is cleared by **GameRoot**, not by that function, so at that
moment the player STILL counted as docked, `_tracker_suppressed_by_dock()`
returned true, and the refresh re-hid the card it was supposed to restore. The
call looked correct and did nothing.

**Second fix:** `_watch_dock_state()`, an edge trigger in `_process`, refreshes
the tracker whenever the docked flag OR the quest-active flag actually changes.
Five separate sites clear `is_docked`, so watching the STATE is reliable where
hooking any one call site is not. The quest-active edge closes the same ordering
trap on LOAD, where `refresh_restored_state()` can refresh the tracker before
`QuestManager` has restored the quest -- the refresh then correctly finds nothing
and hides the card, and nothing runs again.

**Root cause:** the tracker's visibility is only ever recomputed inside
`_update_quest_tracker()`, and that function is driven by QUEST events (accepted,
progress, completed, abandoned, expired) plus combat end and
`refresh_restored_state()`. Docking is not a quest event. `_tracker_suppressed_by_dock()`
hides the card on dock, and before this fix NOTHING restored it on undock, so it
stayed hidden until some unrelated quest event happened to fire.

Toggling the layout lock works around it because edit mode force-shows the panel
so it can be repositioned, and the lock half then re-runs the update.

**A WRONG THEORY, recorded so it is not re-investigated:** the first guess was
that this was a SIZING problem -- the quest panel is the only dynamic
(auto-sizing) panel, and `_load_layout()` deliberately skips size restore for it.
That is all true but is NOT the bug: `_update_quest_tracker()` already ends with
`_refit_quest_tracker_panel()`, which already calls `reset_size()` deferred. The
panel was not mis-sized, it was never made visible.

**Still open -- the load path.** `refresh_restored_state()` does call
`_update_quest_tracker()`, so loading should already work by the same reasoning.
Since Abe saw it fail after loading too, the likely explanation is ORDERING:
`refresh_restored_state()` runs before `QuestManager` has restored the active
quest, or while the player still counts as docked, so the update correctly hides
the card and is never re-run. **Where to look:** the call order between
`QuestManager` restore and `UIManager.refresh_restored_state()`, and whether
`GlobalState.player.is_docked` is still true at that moment.

---

### Kaelen speaks a second turn-in line right after the agent's own reply
**Spotted:** 2026-09-09 (Abe, playtest). Turned a contract in to Jenna Kross:
she replied correctly IN HER OWN VOICE, then about a second later Kaelen spoke a
SECOND completion line complaining about the low payout.
**Severity:** Medium -- reads as the game speaking twice about one event, and
undercuts the agent who just handled the turn-in.
**Status:** FIXED 2026-09-09 (unverified in play). `GameRoot` now HOLDS the beat
while the player is docked (`_pending_quiet_moment_beat`) and
`UIManager.undock_player` releases it via `flush_pending_quiet_moment()`. The
line is delayed, never dropped. Only one beat is held: two turn-ins in a single
dock means she remarks on the LAST one, which is the one the player just did.
**Needs a playtest** to confirm she now speaks after undocking rather than over
the agent, and that the line still arrives at all.

**Cause:** two independent systems both fire on completion, and neither knows
about the other.
1. The agent's own turn-in reply, in the agent's voice. Correct.
2. `GameRoot._on_quiet_moment_quest_completed` -> `quiet_moment_director.try_fire()`,
   which picks a Kaelen beat by payout band: `kaelen_low_pay_safe`,
   `kaelen_high_pay_dangerous`, or `kaelen_public_board`. This is Kaelen's
   commentary on the work, and it is authored content behaving as designed.

The beat itself is not wrong -- Kaelen having opinions about a bad payout is
exactly her. The problem is TIMING: it lands immediately, on top of the agent
exchange, so it reads as a second turn-in line rather than a later aside. The
system is literally called a QUIET moment, and a turn-in conversation is not one.

**NOT a voice bug.** Kaelen is the correct speaker for the board lane
(`_on_public_board_turn_in_pressed` routes to `_on_agent_complete_pressed`, which
sets "BROKER KAELEN" deliberately). Nothing is mis-routing a voice here.

**Hypothesis worth testing:** this may be what the older report "Agent accept
reply uses Kaelen voice" (filed 2026-06-23) actually was all along -- Kaelen
speaking a SECOND line after the agent, misheard as the agent's line coming out
in her voice. If a playtest of ACCEPT shows the same double-speak shape, the two
entries are one bug and the older one should be closed into this.

**Where to look:** `GameRoot.gd:1274` `_on_quiet_moment_quest_completed`;
`scripts/story/QuietMomentDirector.gd` `try_fire()` for its gating (currently a
cooldown, with no "player is mid-conversation" check).

**Fix direction:** gate quiet moments on the player NOT being in an agent
interaction -- defer the beat until the dock conversation ends, or until undock,
rather than dropping it. Losing the line entirely would be worse than delaying
it; her commentary is good, it is just arriving over someone else's dialogue.

---

### Anomalies spoiled their own outcome in the target window
**Spotted:** 2026-09-09 (Abe, from a screenshot).
**Severity:** Medium-High -- silently removed the point of the entire anomaly
mechanic. Not a visual glitch; a design leak.
**Status:** FIXED 2026-09-09 (unverified in play).

An unvisited anomaly 621m away displayed as
`Anomaly_0 [Anomaly — Reaver Ambush Point]`. The target window was printing the
anomaly's registry NAME, and in `AnomalyRegistry.gd` that name is its OUTCOME:
"Reaver Ambush Point", "Cracked Reactor Core", "Distress Beacon — No Survivors".
So every anomaly announced what it would do before the player went near it.
Nobody flies into an ambush that is labelled as an ambush, which means the trap
could never spring on an attentive player.

**The registry proves the intent was the opposite.** Each anomaly carries
`approach_lines` that are deliberately ambiguous -- the ambush's is "Debris
field. Pattern suggests deliberate placement." That line only has a job if the
player does NOT already know. The name was authored as designer-facing content
and leaked into the UI.

**Fix:** `UIManager._anomaly_display_name()` returns "Unknown Signal" until the
anomaly's existing `_activated` flag is set, then its real name. Applied to the
target window and the overview both, so a resolved anomaly still earns its name
and a place the player has been reads as known.

**Related, deliberately NOT changed:** `SiteRevealModel` already models exactly
this (hidden -> anonymous contact -> identified once scanned) but is default OFF
pending tuning. This fix is independent of it, so anomalies stop spoiling
themselves whether or not sensor reveal is ever switched on.

---

### Overview flickered between two different label sets each frame
**Spotted:** 2026-09-10 (Abe, playtest). Two different entities alternated on the
same row every frame; a screenshot only ever caught one of them.
**Status:** FIXED 2026-09-10 (unverified in play).

**Cause:** `update_overview_list()` cleared the list with `child.queue_free()`
alone. queue_free is DEFERRED -- the old buttons stay parented for the rest of
the frame while the new ones are appended immediately after, so the container
briefly holds BOTH sets and the layout alternates between them. Fixed by calling
`remove_child()` before `queue_free()`, which unparents immediately.

**It was NOT** a sorting problem (the sort runs on a timer and has proper
tie-breakers) or a visibility problem (the per-frame reveal toggle was a red
herring), though both looked plausible. The give-away was that only the SMALL
objects swapped while stations and celestials stayed put -- the small ones are
the entries the rebuild churns.

**Same pattern exists at ~27 other sites in UIManager.** They were left alone
deliberately: those containers rebuild on discrete events, so a frame passes and
the stale children are gone before the next rebuild. If any of them is ever moved
onto a per-frame path, it will develop this exact bug.

---

### System crash preceded by a flood of narrative_quality warnings
**Spotted:** 2026-09-10 (Abe: "system crashed").
**Severity:** was High, now Low -- the warning flood is FIXED; the crash itself
is unexplained and stays open.
**Status:** WARNING FLOOD FIXED 2026-09-10. Crash NOT reproduced or diagnosed.

**I over-read the log first time and want that on record.** I described 518
consecutive `narrative_quality quality_warning` events as an "unbounded retry
loop". There is no evidence of a loop: the counter is a session-wide running
total, and the events are consistent with ordinary validation of many lines. The
crash may be entirely unrelated. Do not treat the two as one bug.

**The flood WAS real and is fixed.** The quality gate's only warning is
`unexplained_reference:<Term>`, raised for any capitalised word not in
`allowed_aliases`. Two faults made it fire constantly:
1. `GameRoot.validate_and_register_narrative_lines` never PASSED any aliases, so
   every faction, character and station name warned on every line, forever.
2. The heuristic flagged SENTENCE-INITIAL capitals, so any line opening with an
   ordinary word warned -- "Docked.", "Structural.", "Threat.". A stop-word list
   cannot fix that: the set of words that can begin a sentence is the language.

Both fixed, with tests. This matters beyond tidiness: the gate exists to surface
lines referencing things the player has never heard of, and at hundreds of false
positives a session nobody could ever see a real one. A diagnostic nobody can
read costs attention and returns nothing.

**Still open:** the crash. No stack trace was captured. If it recurs, get the
crash log before assuming a cause -- the warnings were a red herring.

---

### Mission dialogue is permanently in the deterministic fallback
**Spotted:** 2026-09-10, while attempting the P4 dispatch switch.
**Severity:** High by Abe's own rule -- "canned LLM responses = a failure to fix".
This is that failure, standing, for every mission conversation in the game.
**Status:** OPEN. Not a regression; the LLM path appears never to have been wired.

`StoryAgentOfferBuilder._attach_mission_conversation` builds every mission
conversation with `MissionConversationCompiler.fallback_bundle()` -- the
deterministic template composer -- and then unconditionally sets:

    mission_dialogue_bundle_source   = "deterministic_fallback"
    mission_dialogue_bundle_degraded = true
    mission_dialogue_bundle_degraded_reason = "template_safe_emergency_composer"

and records a `record_fallback` diagnostic. So the game reports mission dialogue
as degraded on EVERY mission, and is correct to.

**The LLM path is dormant, not broken.** `build_prompt()` and `parse_bundle()`
exist, are maintained, and have ZERO external call sites. No `mission_conversation`
job kind is handled in `GameRoot._process_narrative_cache_job`. Nothing dispatches
a conversation to a model.

**Why this matters more than it looks:** the compiler, the plan builder, the
bundle validator and the causal-visibility check are all live and all exercised
-- by the fallback. It looks like a working pipeline. Only the generation step is
absent, which is why this has survived without being noticed.

**Where to look:** `StoryAgentOfferBuilder._attach_mission_conversation`;
`GameRoot._process_narrative_cache_job` (job-kind switch);
`MissionConversationCompiler.build_prompt` / `parse_bundle`.

**Note:** P4-3/P4-4 built and tested conversation slicing and scheduler slice
dependencies, which is the right shape for this path when it is built. That work
is preparation, not a fix.

---

### Illegal-mining fines can never be paid
**Spotted:** 2026-08-18 (found while writing enforcement taunt lines — Abe asked
whether the fine could be paid and the answer turned out to be no)
**Severity:** Medium — the player accrues a debt with no way to clear it, and
the enforcement patrols that come with it never stop being justified.
**Description:** `IllegalMiningEnforcement` tracks `outstanding_fines` per
system/faction and stacks 250 credits per violation. It exposes `fine_due()` and
a complete `pay_fine()` that handles partial funds, clears the debt, and reports
whether enforcement heat was lifted — but **neither function has a single caller
anywhere in the codebase.** The debt accrues and is never collectable.
**Where to look:** `scripts/systems/IllegalMiningEnforcement.gd` (the working
capability), then the station dock menu in `scripts/UIManager.gd` for where a
"pay outstanding fine" affordance would live. `pay_fine()` already returns
everything a UI needs (`paid`, `amount_paid`, `remaining_due`, `heat_cleared`),
so this is a wiring job, not new logic.
**Related:** taunt lines for the `code_enforcement` cause deliberately avoid
naming a sum, because quoting a fine the player cannot pay would advertise a
mechanic that is not there.

---


### N.O.V.A. bank lines can share a one-word closer ("Good.")
**Spotted:** 2026-08-18 (nova line-bank live fire) — **accepted limitation, not scheduled**
**Severity:** Low — mild audible repetition; the bad cases are already caught
**Description:** Batch parsing now rejects a line that reuses a whole 4+ word sentence (`duplicate_sentence`) or repeats a 2+ word CLOSING sentence (`duplicate_closer`). A repeated ONE-word closer still gets through, e.g. a draw where two victory lines ended "Good." and a third ended "Still good."
**Why it was left:** dropping the closer floor to one word would also reject lines ending "Captain.", which is in-voice and frequent, and would gut ordinary terse batches. The two-word floor is the deliberate trade.
**If it becomes worth fixing:** `LLMInterface._nova_bank_final_sentence` is the single knob (the `>= 2` word floor). A better fix is probably a small stop-list of one-word closers rather than a blanket floor change.
**Do not "fix" by tightening the prompt** — that was tried on 2026-08-18 and drove the 4b into one shared template across eight beats, worse than the problem. See the session log.

---

### Jenna Kross replayed her first-meeting intro at a second dock
**Status:** FIXED 2026-08-06 — the flag write moved from `_on_maintenance_bay_pressed()` to `_render_mechanic_intro()`, i.e. from "a particular button was clicked" to "the intro actually reached the player". Both known entry points and any future third one are now covered by construction. Awaiting a live regression run (dock, undock via N.O.V.A.'s repair prompt, re-dock — she should greet normally the second time).
**Spotted:** 2026-08-02 (playtest)
**Severity:** Medium — breaks the fiction of having already met someone, and the line explicitly introduces her by name ("Name's Jenna...") so the repeat is very noticeable
**Description:** Jenna Kross delivered her first-meeting introduction twice, at two separate docks. Playtester is ~95% sure the text was **identical** both times, and reports a **different, normal greeting after turning in the first mission**. Note the spelling for searching: `npc.jenna_kross`, Kross with a K.

Both observations are explained by one cause. Her intro is not generated — it is the hardcoded constant `JENNA_FIRST_MEETING_LINE` (`UIManager.gd:7973`), which is why it was word-for-word identical. It is served whenever `_mechanic_has_prior_visit()` returns false, and the later normal greeting means that check finally started returning true.

**CONFIRMED by the playtester:** they tried to undock, N.O.V.A. prompted about repairs, and they entered maintenance via **her** button rather than the main Maintenance Bay button. That path does not mark the visit.

```gdscript
func _on_maintenance_bay_pressed() -> void:
    SpeechService.stop()
    _mark_current_mechanic_first_visit()     # flag written
    current_submenu = DockSubmenu.MAINTENANCE
    _render_dock_submenu()

func _on_nova_repair_prompt_repairs() -> void:   # UIManager.gd:9140
    _hide_nova_repair_decision()
                                             # flag NOT written
    current_submenu = DockSubmenu.MAINTENANCE
    _render_dock_submenu()
```

**Fix:** move the flag write so it cannot be bypassed. Marking it inside `_render_dock_submenu()` when the maintenance submenu renders — or better, at the point the intro line is actually SERVED in `_cache_mechanic_intro()`/`_render_mechanic_intro()` — closes both entry points and any future third one. Patching only `_on_nova_repair_prompt_repairs()` fixes today's repro and leaves the same trap for the next entry point added.

**Supporting detail (original analysis):**
- **The first-meeting line is served at DOCK time.** `_cache_mechanic_intro()` (~`UIManager.gd:8171`) pre-caches the greeting on arrival and, if `_mechanic_has_prior_visit()` is false, uses `JENNA_FIRST_MEETING_LINE`.
- **The flag is written from exactly ONE place, and it is a different event:** `_mark_current_mechanic_first_visit()` has a single call site, `_on_maintenance_bay_pressed()` (`UIManager.gd:7351`) — i.e. only when the player clicks into the Maintenance Bay submenu.
- So docking, hearing/seeing the intro, and leaving **without entering the maintenance bay** would never set the flag, and the next dock legitimately serves the first-meeting line again. Confirm whether the intro can be surfaced anywhere the flag write isn't reached.
- If the player DID enter the bay both times, then the write itself is the suspect: `campaign_npc_state_store.has_one_shot_flag(mechanic_id, _MECHANIC_FIRST_VISIT_FLAG)` — check the flag actually persists (the store is captured under `npc_states` in the save) and that `mechanic_id` is non-empty at write time, since `_mechanic_has_prior_visit` returns false for an empty id.
- **Fix direction:** mark the first visit when the intro is SERVED, not when a submenu is opened. The two should not be able to disagree.
- **Correcting an earlier note in this entry:** a first-meeting flag *does* exist. Searching for `intro_seen` / `first_meeting` / `has_met` finds nothing because it is named `_MECHANIC_FIRST_VISIT_FLAG` and goes through `has_one_shot_flag`.

**How to verify next time:** the line is a constant, so an exact-match repeat confirms the first-meeting path fired twice. Any *differently worded* greeting came from the generated path instead and is a separate issue.

---

### Kaelen handoff batch intermittently returns no JSON array
**Spotted:** 2026-07-02 (live playtest during story-wiring session)
**Status:** Fixed in code 2026-07-22; awaiting a live regression run.
**Resolution:** `LLMInterface` now serializes handoff batches and holds queued batches while campaign-bible priority is active, so startup/chapter batches cannot contend with one another or campaign initialization.
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
**LIKELY FIXED -- Abe flew tight spaces 2026-09-09 (run sheet 2.6) and reports it appears fixed, along with the fishtailing. Kept open per his standing preference: this one has ALREADY regressed once after being fixed (2026-06-26), so it earns a second confirmation before closing. Watch it specifically when steering code is next touched.**
**Status:** FIXED 2026-08-18, verified by the in-engine smoke test on real Kova
and Kova-to-Iron-Reach routes past a rocky planet and a gas giant.

**WHY THE JUNE AND JULY FIXES DID NOT HOLD: they were patching dead code.**
`_get_autopilot_avoidance` had NO callers, and `_route_steer_target` only ever
called itself. This entry's own "code map" pointed at both. The smoke tests
looked green because they invoked those dead functions DIRECTLY, so the tests
passed while the live autopilot flew players into planets. About 650 lines of
unreachable code have been deleted so the trap cannot be walked into again.

**Root causes in the live path** (each reproduced in a test before fixing):
1. Inside a keep-out sphere the planner exited to the NEAREST surface point.
   With the target on the far side that is directly behind the ship -- the
   "flew the OPPOSITE direction" report, literally a heading agreement of -1.
   The ship is inside those spheres routinely, because the radius is body plus
   comfort margin.
2. The waypoint was the sphere's widest point relative to the ship, not a true
   tangent. The ship stepped sideways until clear, turned at the target, that
   heading re-entered the sphere, and it stepped sideways again -- circling the
   boundary forever at a constant distance. That is the "stalled and never
   arrived" half.
3. Flying an arc in discrete steps chords inward, so the ship sank until it hit
   a "too close" branch, got pushed out, and sank again -- shuddering in place.
4. Steering considered only the NEAREST blocker, so the ship was pushed deep
   inside a second body's envelope while rounding the first.
5. Aiming at exactly the required radius left no headroom, and real planets
   ORBIT into that gap.

**The design is the sphere keep-out plus tangent steering proposed in this
entry**, now in `scripts/navigation/TangentNavigator.gd` as pure functions over
plain data so it is testable without a scene -- which is what made the causes
findable. Key rule learned: the margin is NOT a wall. Once inside it, route
around the actual body; fighting back out is what sent the ship away.

**Regression cover:** `tests/navigation/run_tangent_navigator_tests.gd` (the
reported scenario, closed-loop flight, long range, crowded fields, moving
target) and `--autopilot-smoke-test` in engine.

**Also fixed along the way:** the player-facing "Direct route obstructed"
notice had gone silent, because the dead avoider was its only caller.

**Spotted:** ~2026-06-21 — **superseded notes below**
**Old status:** STILL BROKEN — confirmed 2026-07-01 playtest. Prior fix attempts (2026-06-26, 2026-06-30) did NOT hold. New symptom: trying to "Fly to" a hostile target on the far side of a planet, the ship flew the OPPOSITE direction, then got stuck/stalled and never reached the target — playtest was unplayable because of it. So the failure is not just grazing hazards; the route/steer target itself is inverting or dead-ending when a large body (planet/gas giant) sits between ship and target. Re-investigate `_route_steer_target` planner output + `_get_autopilot_avoidance` wiring; check for a heading sign-flip and a stall with no replan. Previous notes below still apply.

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

### Quest tracker panel blue box reappears on second quest
**LIKELY FIXED -- Abe took a second quest 2026-09-09 (run sheet 2.7) and does not recall seeing the blue box. Kept open on his instruction: not recalling it is weaker evidence than confirming it is gone, and no commit is known to have addressed it. Close once a second quest is taken with this specifically watched for.**
**Spotted:** 2026-06-25  
**Severity:** Low — cosmetic  
**Description:** When the player accepts a second quest, the oversized empty blue box (quest tracker panel) reappears. The `call_deferred("reset_size")` fix only fires when the panel first becomes visible; it doesn't re-fire when a new quest loads into an already-visible panel.  
**Where to look:** `scripts/UIManager.gd` → `_update_quest_tracker()`. The `reset_size()` call needs to fire every time quest content changes. Also check if `user://ui_layout.json` is persisting a saved `w`/`h` for the quest panel and re-applying it on each update.

---

### Agent dialogue sometimes addresses player as "Indy" or "Shiny"
**Status:** FIXED 2026-08-18. Abe's call, with the reason that made it obvious:
the agents were using it in EVERY clause -- "Indy ... and Indy ... so Indy" --
and nobody talks that way. You use a name once at the start of a conversation
if at all, never again while still sitting at the table. Implied address reads
as normal speech; stated address reads as a chatbot.

Fixed in two halves, because the prompt alone was never going to hold it:
- The four agent personas said "only occasionally call the pilot 'Indy'", which
  is an invitation. They now say never to use a name or nickname.
- `GlobalState.strip_player_address()` is the structural guarantee. It removes
  every address form including the one that actually leaked, an address riding
  a conjunction ("So Indy," / "and Indy,"), which no comma-first pattern caught.
  It runs in `SpeechService.prepare_text` so it covers every prepared line, not
  just the single follow-up path the old stripper was wired to, and on the
  displayed dock message so panel and audio cannot disagree.

**Kaelen keeps "Shiny"** -- it is hers, and it is part of what makes her read as
more than an ordinary NPC. She is exempt from both the tone guard and the strip,
and `tests/story/run_player_address_tests.gd` pins that so a later change cannot
quietly take it away.

**Correcting this entry's original guess:** "Indy" was not leaking from the pilot
backstory. It was passed in deliberately as `player_nickname`.

---

### Shield visual persists after combat ends
**LIKELY FIXED -- not observed by Abe in play, 2026-09-09 (run sheet 2.5). Kept open deliberately: absence of a sighting is not a fix, and no commit is known to have addressed this. Close it once it survives more combat sessions.**
**Spotted:** 2026-06-26
**Severity:** Low — cosmetic
**Description:** The shield effect sometimes remains visible on the player ship after combat ends instead of disappearing with the combat state. Likely the shield deactivation call is not firing on all combat-exit paths (timeout, enemy death, flee).
**Where to look:** `CombatManager.gd` — wherever combat ends; check that shield deactivation is called on every exit path, not just the primary one.

---

### Mouse cursor lost when entering combat
**LIKELY FIXED -- not observed by Abe in play, 2026-09-09 (run sheet 2.5), which adds a session to the 2026-06-28 fix attempt's evidence. Still open by its own terms until it survives more combat.**
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

## Fixed

| Date | Bug | Fix |
|---|---|---|
| 2026-09-09 | Tutorial overview panel starts collapsed for new players | **Not a bug -- confirmed correct by Abe, 2026-09-09, and promoted to a design rule:** the overview expands ONLY outside the station, never inside it. Already enforced structurally: `set_overview_collapsed` forces the collapsed state while `_overview_dock_locked` is on, so the invariant sits at the single write point and no call site can expand it while docked. Docking hides and locks it; undocking unlocks and expands. Now documented at the guard and pinned by `tests/domain/run_intro_handhold_tests.gd` (previously only string-matched the function names). |
| 2026-09-09 | First run of a session: no station welcome overlay, N.O.V.A. portrait missing | Root-caused and fixed 2026-08-06 from a live console log. Self-inflicted by the ambient speech queue added the same day: that queue split a line's EMIT from its PLAYBACK, but two consumers still assumed the next `playback_finished` belonged to the line just emitted, so the arrival beat silently lost both visuals. **Confirmed correct in play by Abe, 2026-09-09 -- overlay and portrait both present.** |
| 2026-09-09 | N.O.V.A. talked during the first dock flow | Marked NOT REPRODUCIBLE 2026-08-18: the first dock belongs to her AUTHORED arrival line, not ordinary dock banter. `UIManager` branches on `kaelen_briefing_seen`, which is only set inside the agent panel, and the player cannot reach that before docking -- so the branch was already correct. **Confirmed in play by Abe, 2026-09-09.** |
| 2026-09-09 | N.O.V.A. filler word played during new-campaign loading screen | Fixed 2026-07-15 (commit 1a62701), hardened 2026-08-18 (ban moved out of a single UIManager helper so other callers could not bypass it, extended to Kaelen, and the suppression re-keyed to "gameplay has resumed" rather than "loading panel still exists" -- the panel is freed to START the intro cinematic). Pinned by `tests/story/run_intro_dock_gating_tests.gd`. **Confirmed silent in play by Abe, 2026-09-09.** |
| 2026-09-09 | New campaign overwrote an existing slot instead of using the next empty one | **No known fix commit -- it simply stopped reproducing.** Filed 2026-06-26 as a high-severity data-loss risk; Abe confirmed 2026-09-09 that a new campaign now lands in an empty slot. Something between those dates fixed it incidentally, so there is no test pinning the behaviour and nothing preventing a regression. If save slots are touched again, re-check this first. |
| 2026-07-15 | Active KILL_SHIPS mission could have no targets after save/load | Saved mission ships still restore normally. `QuestManager` now also reconciles every unfinished KILL_SHIPS contract after system and player restore: if its faction has no living quest target, it spawns only the remaining count at the normal safe distance. The focused mission is preserved, so regenerated persistent IDs belong to the correct contract. Covered by `tests/domain/run_mission_state_transition_tests.gd`. |
| 2026-07-14 | Game crashed on player death — "Trying to cast a freed object" in NPCShip.gd | `_redirect_from_combat_queue` and the gateless-flee path cast `GlobalState.player as Node3D`. `die()` calls `queue_free()` but never nulls `GlobalState.player`, so the next NPC frame cast a freed object — and `as` crashes *before* `is_instance_valid` runs. `player` is already `Node3D`-typed, so both sites now assign without the cast and validate first — `NPCShip.gd:779,1043` |
| 2026-07-13 | Every mission completion warned `[MissionInstance] Invalid transition: ACTIVE -> COMPLETED` (READY_TO_TURN_IN was dead state) | `_mark_objective_ready_if_completed` now transitions the instance to READY_TO_TURN_IN when the objective completes; `complete_quest` and the comms-bribe resolution route through `_transition_to_completed()` (hops via READY_TO_TURN_IN for pre-fix saves); READY_TO_TURN_IN → EXPIRED added so timed contracts can still expire awaiting hand-in. State persists through save/reload via `_instance_state`. Covered by `tests/domain/run_mission_state_transition_tests.gd` — `QuestManager.gd`, `MissionInstance.gd` |
| 2026-07-01 | Dock panel opened over the combat wheel (docked while in combat) | Autopilot dock (e.g. the completed-mission "Dock at Station" button) could reach a station while combat started en route, opening the dock menu mid-fight. `Station.dock_player` + `OutpostStation.dock_player` now bail with a HUD warning if `PlayerInteractionQueue.in_combat_window()` (covers active combat + post-combat cooldown) |
| 2026-07-01 | Mechanic pickup offer buttons appeared during turn-in | Completing the pickup freed the STATION lane, unmasking the next dock's already-rolled offer mid-turn-in. `_on_deliver_part_pressed` now clears `_mechanic_pickup_offer`, hides the buttons, and sets the cached greeting to the thanks line — `UIManager.gd` |
| 2026-07-01 | NPC kills counted toward player's KILL_SHIPS mission | Split attribution via existing signals: `player_kill` (player-only) counts progress; `ship_destroyed` now fires ONLY for non-player kills (`NPCShip.gd`) and schedules a replacement target instead of counting. KILL_SHIPS capability refuses credit when `by_player=false`; respawn now 20s + ≥800u from the player (`QuestManager.gd`, `KillShipsCapability.gd`, `GlobalState.spawn_mission_targets`). Design per Abe: NPC-killed targets replaced far away so the contract stays player-completable. |
| 2026-07-01 | Dummy word "Slithern" leaked into quest TITLE (e.g. "Slithern Scourper") | `_substitute_dialogue_placeholders` now applies replacements to `quest_data["title"]`, not just dialogue/choices — `LLMInterface.gd` |
| 2026-06-26 | Autopilot object avoidance regressed | Re-wired `_get_autopilot_avoidance()` into autopilot loop; added `RayCast3D` nose whisker; added mid-route validity re-check — `PlayerShip.gd` (NOTE: regressed again, see Active) |
| 2026-06-25 | Combat flee taunt used Kaelen voice | Added `_play_npc_flee_taunt()` in `CombatManager._exec_flee()` |

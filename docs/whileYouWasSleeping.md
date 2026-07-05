# While You Was Sleeping — Session Changelog

---

## Session: 2026-07-01/02 (Campaign Bible Reliability + Wire Story Into Gameplay) — Claude
**Branch:** `segment-3/economy-stores-events`
**Commit:** `9ea1301`

### Overview
Two connected pieces of work. First, reviewed and independently tested the team's Ollama/gemma4 campaign-bible generation consensus work — root-caused the JSON reliability problem to gemma4 being a thinking model with `think` never set (fixed via `think:false`, landed by Codex in `2f1ffbac`). Second, and the larger piece: traced the actual gameplay pipeline and found the generated campaign bible never reached the player — `StoryManager.story_state` (the living doc injected into every mission/dialogue prompt) was seeded from a hardcoded empty default and never read the bible at all. Implemented the missing bridge plus mission causality, Kaelen's protected hidden angle, and rumor firing (design doc's Phases B/C/D/F). Found and fixed three real bugs along the way while testing live in the user's running game.

### What Landed

**Campaign bible → story_state bridge (`scripts/story/StoryManager.gd`, `scripts/GameRoot.gd`)**
- `StoryManager.seed_story_state_from_bible()` — one-time, idempotent, maps `story_arcs`→`active_tensions`, unconsumed `act_1_outline` beats + `main_mystery`→`player_does_not_know_yet`, `rumor_trails` clue templates→`pending_hooks`, `kaelen_angle`→`kaelen_hidden_angle`.
- Called both at `init_story_state()` (covers a bible already generated in a prior session) and from `GameRoot._on_campaign_bible_generation_result()` (covers the common async case for a fresh campaign).
- `CampaignBibleStore._migrate_legacy_bible()` — backfills fields added to the schema after a save was written, so an old save doesn't fail validation forever; resets `generation_status` to bootstrap so it gets a real fresh regeneration next.

**Mission causality (`scripts/LLMInterface.gd`, `scripts/story/StoryManager.gd`)**
- `because` field (from `active_tensions[0]`) now threads into quest generation prompts.
- Quests get stamped with `story_hook_ref`; `on_quest_completed()` resolves that hook and checks chapter advancement.
- Chapters never end the campaign — hook exhaustion refills from the bible's `act_1_outline`/`story_arcs`/`rumor_trails` reserve, then (once exhausted) fires a `regeneration_trigger` LLM call (`NarrativeDirector.build_story_horizon_expansion_prompt` + `LLMInterface.request_story_horizon_expansion`) that appends fresh content. Retry-once before any fallback; every fallback logged via `GenerationDiagnostics`, loudly `push_warning`'d, and counted in `story_state.regeneration_fallback_count` (never resets) so it can't silently become the norm.

**Kaelen's hidden angle (`scripts/ai/NarrativeDirector.gd`, `scripts/persistence/CampaignBibleStore.gd`, `scripts/story/StoryManager.gd`)**
- `kaelen_angle` added to the bible schema as director-only knowledge (prompt + validation + repair-pass fallback).
- Seeded into `story_state.kaelen_hidden_angle`, never included in `get_story_context_block()`.
- `_update_kaelen_mood()` derives a safe 2-4 word mood descriptor from the angle via the small model; `request_kaelen_reaction()` (previously got zero story context) now gets the mood.

**Rumor firing (`scripts/story/StoryManager.gd`)**
- `on_docked()` now has a ~40% chance to fire a rumor via the existing (already fully built, just never triggered) `get_lounge_rumor()`/`record_lounge_rumor_heard()` pipeline.

**Ollama recovery (`scripts/LLMInterface.gd`, `scripts/ui/DevPanel.gd`, `scripts/GameRoot.gd`)**
- Connection-level generation failures (timeout/http_failed, not content/validation failures) now auto-trigger the existing startup watchdog's launch-if-missing flow mid-session.
- Opt-in DevPanel toggle ("Allow Ollama Auto-Restart") lets the game kill+relaunch a hung Ollama process it didn't start itself — off by default, since that's a much more invasive action than launching a missing one.

**Bugs found + fixed live while testing**
- Untyped `Array` indexing in `_use_story_horizon_expansion_fallback` crashed the parser (`factions: Array` → `Array[String]`).
- Stuck-loading race: `_wait_for_campaign_story_before_gameplay()` had no retry path when the campaign slot wasn't initialized yet at the moment it first checked — added a 1s retry.
- No retry existed for content-level campaign bible parse/validation failures (only connection failures) — added a capped 3-retry, 3s-apart path.
- Dock message panel resized on every NPC "Talk" press — `dock_message_slot`/`dock_message_portrait` toggled `.visible`, which shrank/grew their shared VBoxContainer (also affecting the lounge card grid below it). Fixed by keeping both permanently visible and fading via `modulate.a` / clearing texture instead.
- Diagnosed (not code-fixed, it's an editor-only quirk) a `RefCounted` script hot-reload gotcha: editing a `RefCounted`-derived script while an instance is already alive in a running game can degrade that instance to its base class, throwing "nonexistent function" on real methods. Added defensive `has_method()` guards around `_campaign_bible_store` usage so a stale reference degrades gracefully instead of crashing.

### Verification
Bash/PowerShell were gated by a tool-safety-classifier outage for most of the session. Verified all new logic (Phase B seed mapping + idempotency, Phase C hook resolution + chapter refill, Phase D prompt/parse/repair, Phase F rumor ranking/firing, the legacy-bible migration) via `game_eval` — live execution inside the user's running Godot instance with real return values — since the headless CLI test runner wasn't reachable. The four new/extended test files (`tests/persistence/run_story_state_bible_seed_tests.gd`, `tests/story/run_story_manager_hook_tests.gd`, extended `run_narrative_director_tests.gd` + `run_campaign_bible_store_tests.gd`) are committed in the project's standard format for a normal headless run once the classifier issue clears.

### Still Open For Next Session
- **Handoff batch intermittent parse failures**: `[LLMInterface] Handoff batch: no JSON array found in response` fired for all 3 faction agents during one live test session (see bugs.md). Not investigated this session — possibly Ollama resource contention from a concurrent campaign_bible generation call.
- **Phase E (ambient two-person NPC dialogue)** — explicitly deferred, new subsystem not wiring.
- **Kaelen chapter_comment/hint line types** — deferred from Phase D, design is ready in `docs/design_narrative_system.md`.
- Full B/C/D/F flow hasn't been playtested end-to-end over a real session yet (hook resolution → chapter advance → rumor firing over actual play) — only unit-verified.

---

## Session: 2026-06-26 (Intro Quest Flow + Story Context Injection + Plans) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Wired up the scripted intro quest as a proper QuestManager kill quest delivered by Kaelen directly (no agent). Added first-dock hand-holding (UI lock), story context injection into Kaelen handoff prompts, and wrote design plans for the docking sequence and Kaelen handoff pool system.

### What Landed

**Intro quest flow (`scripts/UIManager.gd`)**
- First dock locks all dock buttons except "Talk to Agent" + shows teal hint message. Lock checks `intro_agent_visited` flag, lifts the instant the player clicks Talk to Agent.
- `_show_kaelen_intro_quest_offer()` (new) — fires after the first briefing "Let's hear it." Kaelen presents the pirate kill job directly in her voice, no agent. Player clicks "I'll take it." → `QuestManager.accept_quest()` registers a normal KILL_SHIPS quest (1 reaver, 350 SC, 20-min timer), `intro_quest_delivered = true` saved, `_request_background_agent_quest()` starts LLM gen for quest 2 immediately.
- `_show_kaelen_first_briefing()` "Let's hear it." now routes to `_show_kaelen_intro_quest_offer()` instead of `_refresh_agent_quest_board()`.
- `on_kaelen_intro_dismissed()` called from popup dismiss handler → sets `intro_conversation_had = true`, saves.
- `intro_agent_visited` set in `_on_talk_to_agent_pressed()` — lifts lock before agent panel opens.
- All three agent-panel back-button paths now call `_render_dock_submenu()` on return so the re-render actually runs.
- `try_fire_intro_quest()` removed from `_request_background_agent_quest()` — intro quest is no longer LLM-path.

**Story state flags (`scripts/persistence/StoryStateStore.gd`, `scripts/story/StoryManager.gd`)**
- Added `intro_conversation_had`, `intro_agent_visited`, `intro_quest_delivered` to story_state and default state in all three locations (StoryManager, StoryStateStore, clear_story_state).
- `try_fire_intro_quest()`, `_maybe_fire_intro_quest()`, `_fire_intro_quest()` removed from StoryManager — delivery is now entirely UIManager's job. StoryManager only owns persistence flags.
- `on_kaelen_intro_dismissed()` added to StoryManager.

**Story context injection (`scripts/LLMInterface.gd`, `scripts/story/StoryManager.gd`)**
- `StoryManager._save_story_state()` and `init_story_state()` both call `_push_context_to_llm()`, which writes `get_story_context_block()` into `LLMInterface.story_state_context_text`.
- `_build_kaelen_intro_prompt()` now takes a `story_clause` parameter — injected between `local_tone_clause` and `correction_suffix`. Instruction: "color tone and urgency only, do NOT quote directly."
- `request_kaelen_intro()` builds the clause from `story_state_context_text` if non-empty.
- `_kaelen_intro_request_attempt()` and its retry call both thread `story_clause` through.

### Plans Written
- `docs/plan_docking_sequence.md` — full 4-phase docking animation design (approach tween, camera hold, clamp SFX, fade-in UI). Combat chase edge case: safe zone at initiation, only pursuers hold, re-engage on undock with warning. Build order: 5 pieces, one new file (DockSequence.gd).
- `docs/plan_kaelen_handoff_pool.md` — Gemma4 pre-generates 16 story-aware Kaelen handoff lines per agent during gate travel dead time. Stored in `kaelen_handoffs.json` via new KaelenHandoffStore. Draw in `request_kaelen_intro` before falling through to small model. Triggers: game start, gate "Fly to", system arrival top-up, chapter advance replace. Build order: 5 steps.

### Bugs Added to bugs.md
- Agent dialogue sometimes addresses player as "Indy" or "Shiny" (prompt leak from backstory context)
- Shield visual persists after combat ends

### Notes
- `_SQ_DEBUG` confirmed `false`
- All scripts pass parse_check.gd headless with no errors
- Story context at chapter 1 is sparse (just "guarded" mood) — pool plan will fix this materially

---

## Session: 2026-06-26 (Narrative Phase B — Story State Document) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Implemented Phase B of the narrative system: a living `story_state` document in StoryManager, with persistence via a new `StoryStateStore` (follows the CampaignTransactionStore pattern), and injection into LLMInterface quest-generation prompts.

### What Landed

**`scripts/persistence/StoryStateStore.gd`** (new) — RefCounted store following CampaignBibleStore pattern. Stores `story_state.json` in the campaign slot folder via `CampaignTransactionStore.commit_json_set`. Fields: `chapter`, `active_tensions`, `player_knows`, `player_does_not_know_yet`, `pending_hooks`, `current_foreshadow`, `kaelen_current_mood`. `prompt_context()` returns a formatted string that excludes `player_does_not_know_yet`. `save_state(data)` commits atomically.

**`scripts/story/StoryManager.gd`** — Added Phase B state API:
- `story_state: Dictionary` — in-memory working copy with all 7 fields
- `init_story_state(campaign_path)` — opens StoryStateStore, loads persisted state
- `clear_story_state()` — resets to defaults and drops store reference
- `get_story_context_block() -> String` — formats public fields; never includes `player_does_not_know_yet`
- `advance_chapter(truths_to_reveal)` — increments chapter, promotes secrets to player_knows, clears active_tensions, saves, then fires `_generate_foreshadow()`
- `_generate_foreshadow()` — async HTTPRequest to the small Ollama model; one sentence foreshadow for ambient content; saves on completion

**`scripts/LLMInterface.gd`** — Added `story_state_context_text: String = ""`. The quest-generation prompt now includes a `### STORY STATE:` block immediately after `### CAMPAIGN BIBLE:`.

**`scripts/GameRoot.gd`** — Added `_refresh_llm_story_state_context()` (reads StoryManager.get_story_context_block()). Wired `StoryManager.init_story_state(slot_path)` and `_refresh_llm_story_state_context()` at the end of `_initialize_campaign_chronicle()`. Added `StoryManager.clear_story_state()` + `LLMInterface.story_state_context_text = ""` to all campaign unload/reset paths (delete slot, factory reset, new-campaign wipe).

**`.godot/global_script_class_cache.cfg`** — Added `StoryStateStore` entry so Godot can resolve the class name at compile time (editor would add this automatically on next scan).

### Notes
- `_SQ_DEBUG` remains `false` — confirmed before touching StoryManager
- All scripts pass parse_check.gd headless with no errors

---

## Session: 2026-06-26 (Unified Combat System + FactionRegistry + Dev Panel) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Completed the full unified combat system (Steps 1–7). NPCs now share the same action enum, damage pipeline, and stat derivation as the player. FactionRegistry is live with 8 known profiles and 14 unknown faction entries across 4 progression bands. Damage-type resistances (weapon vs drone) are active. A single extensible dev panel replaces all scattered Numpad shortcuts.

### What Landed

**CombatAction.gd** — Added `BRACE`, `FLANK`, `SHIELD_ANGLE`, `DISABLE_ENGINES` to the Type enum. `make(type, params)` is now the single constructor for all action dicts.

**FactionRegistry.gd** (autoload) — 8 known faction profiles (aurelia/vanguard/zenith × role), 14 unknown faction entries across 4 tier bands (Rift Collective → Apex Remnant). `get_profile(key)`, `get_faction_for_danger_level(tier, idx)`, stat derivation helpers, runtime override dict, JSON save/load.

**NPCShip.gd** — Added tier vars (`weapon_tier`, `hull_tier`, `powerplant_tier`, `shield_tier`, `engine_tier`), `weapon_dmg_mult`, `drone_dmg_mult`, `hull_composition`. `apply_faction_profile(profile)` derives all combat stats from tiers and re-applies reinforcement/difficulty multipliers. All `_action_*` helpers now use `CombatAction.make()` so NPC and player action dicts share the same shape.

**Spawn wiring** — `MainScene._spawn_npc()` calls `apply_faction_profile()` for known factions. `GeneratedSystemNPCManager._apply_npc_profile()` covers all three spawn paths; unknown factions pull from the tier band matching `config.difficulty_tier`.

**CombatManager.gd** — `_execute_npc_action` now matches on `CombatAction.Type` int enum (not strings). Damage read from `action["params"]["damage"]`. `_apply_hit` gained `is_drone` param; applies `weapon_dmg_mult`/`drone_dmg_mult` from the target before `take_damage`. Drone hits pass `is_drone=true`.

**CombatPanel.gd** — `SENSOR_SIGS_NAMED` deleted. `BRACE`, `FLANK`, `SHIELD_ANGLE`, `DISABLE_ENGINES` entries added to the int-keyed `SENSOR_SIGS` const. `_sensor_sig()` simplified to a single dict lookup.

**DevPanel.gd** (new) — Extensible CanvasLayer dev tool. Numpad 7 toggles it. Left sidebar: quick-action buttons (`add_action_button(label, callable)` API). Right area: `TabContainer` with `add_tab(title)` API. Tab 0: Faction Tuning — scrollable table of all 22 factions × 7 fields with ↑/↓ per cell; changes hot-apply to `FactionRegistry._overrides`; Save writes `user://faction_tuning.json`, Reset clears. Built-in actions: Spawn Boss, Spawn Squad, Restock Stores.

### How to Extend the Dev Panel
```gdscript
# In GameRoot._init_dev_panel(), after the existing connections:
_dev_panel.add_action_button("My Action", my_callable)

var tab := _dev_panel.add_tab("My Tool")
# tab is a VBoxContainer — populate it freely
```

---

## Session: 2026-06-25 (Enemy AP System + Shield Reroute Redesign + UI Fixes) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Three major systems landed this session: a full AP-driven enemy AI that mirrors the player's action economy (with intelligence tuning for difficulty scaling), a redesigned Shield Reroute ability with a Fresnel shader bubble visual, and several UI fixes including a quest dialogue choice cap and a panel size reset bug.

---

### 1. Enemy AP System (`scripts/NPCShip.gd`)

Enemies now plan their entire turn at the **same moment the player begins choosing** — both sides commit simultaneously. The enemy's plan is revealed as a sequence in the telegraph label (e.g. "Enemy: Reposition → Fire → Fire") so the player can counter it.

**Two new properties on every NPCShip:**
- `combat_ap: int = 4` — AP budget for the turn. Elite ships can be set to 6+, noob ships to 2.
- `combat_intelligence: float = 0.5` — 0.0 = dumb, 1.0 = optimal. Controls three things:
  - **Action choice:** dumb enemies pick suppression/weak options; smart ones pick hull shots
  - **Action order:** dumb enemies fire *before* repositioning (Shield Reroute not bypassed); smart ones reposition *first* to bypass it
  - **AP waste:** dumb enemies randomly skip their last action, leaving AP on the table

**Archetype planners** (`generate_action_plan()`):
- `Gunner` (4 AP): fires twice; desperate low-HP goes all-in on hull shot
- `Interceptor` (5 AP): smart = reposition then fire; dumb = wrong order or forgets
- `Logistics` (4 AP): repairs if damaged, then fires or disrupts engines
- `MiningHauler` (2 AP): surrender or panic shot only

`generate_intent()` kept as a shim for backwards compatibility.

---

### 2. Shield Reroute Redesign (`scripts/combat/CombatManager.gd`, `scripts/ui/CombatPanel.gd`)

Old behavior: face-picker sub-menu, reduces damage from chosen direction.
New behavior: one button, auto-faces enemy, blocks first hit 65%, **bypassed** if enemy repositions first.

**Mechanics:**
- Player activates Shield Reroute (1 AP) → `player_shield_reroute_active = true`, hemisphere dome spawns
- First enemy *damaging* action this turn → 65% mitigation, dome consumed
- If enemy plan contains `boost` or `flank` *before* their fire → dome bypassed and consumed (they changed angle). Player saw it coming in the telegraph and could have used AP differently.
- Smart enemies (intelligence ≥ 0.55) plan a reposition before firing to exploit this.

**Visual (Fresnel shader hemisphere):**
- `SphereMesh` with `is_hemisphere = true` oriented toward the enemy
- Custom `ShaderMaterial` with `blend_add` + `cull_disabled`: `ALPHA = pow(1 - dot(NORMAL, VIEW), rim_power)` — clear in center, glowing yellow at edges
- Despawned when dome is consumed or combat ends

**UI change:** `planning_started` signal now carries the full `npc_plan: Array` as a 5th parameter. `CombatPanel` builds "Enemy: X → Y → Z" from the labels array.

---

### 3. Traditional Shield Face Blocking Preserved (`scripts/combat/CombatManager.gd`)

`_npc_hit_shield_blocked()` re-added (was removed with old execute block) — still checks player's equipped shield direction for regular NPC fire hits. Shield Reroute and equipped-shield are two separate systems that stack correctly.

---

### 4. Quest Dialogue Choice Cap (`scripts/UIManager.gd`, `scripts/LLMInterface.gd`)

LLM was generating 12+ player response choices. Fixed two ways:
- **UI hard cap:** `_show_quest_briefing()` now shows at most 3 choices, ignoring extras
- **Prompt fix:** Added "IMPORTANT: The choices array MUST contain EXACTLY 3 entries — no more, no fewer." to the quest generation instruction

---

### 5. Quest Tracker Panel — "ACTIVE CONTRACT" Header Removed (`scripts/UIManager.gd`)

The `quest_tracker_nav_label` always showed "ACTIVE CONTRACT" / "BOARD JOB" / "STATION ERRAND" during normal play, creating a visual that looked like an edit-mode placeholder. Fixed:
- With 1 active mission: nav row (`quest_tracker_nav_container`) hidden entirely — no navigation needed
- With 2+ missions: shows compact count `"2 / 3"` with arrows
- Initializes hidden instead of with hardcoded "ACTIVE CONTRACT" text

---

### 6. Quest Tracker Panel Size Reset (`scripts/UIManager.gd`, `scripts/ui/UILayoutManager.gd`)

Panel retained its explicit size from edit-mode resize drag even after exiting edit mode, causing a large empty blue box.

- `UILayoutManager.toggle_edit_mode()` — on exit from edit mode, calls `reset_size()` on all dynamic panels (quest panel) to let PanelContainer shrink to content
- `UILayoutManager.setup()` — calls `reset_size()` at startup after `_load_layout()` to flush any stale size from old sessions
- `_update_quest_tracker()` — calls `call_deferred("reset_size")` every time the panel becomes visible, ensuring content-fit after quest accept

Also: deleting `user://ui_layout.json` clears any old save that had `w`/`h` for the quest panel.

---

### 7. Flee Taunts — NPC Voice Fixed (`scripts/combat/CombatManager.gd`)

`_exec_flee()` was calling only `_play_kaelen_line("kaelen_player_fled")` on successful flee, meaning Kaelen voiced the enemy reaction. Fixed:
- New `_play_npc_flee_taunt()` fires first: plays `npc_player_fled_success` ("Run, coward. I'll hunt you down.") in the enemy's angry voice blend
- Kaelen's comment fires after as normal
- Silently skips if taunt data not yet loaded

---

### 8. `_SQ_DEBUG` Fixed (`scripts/story/StoryManager.gd`)

Was inadvertently left `true`. Reset to `false`.

---

### Files Modified
- `scripts/NPCShip.gd` — `combat_ap`, `combat_intelligence`, `generate_action_plan()`, archetype planners, action builders, `generate_intent()` shim
- `scripts/combat/CombatManager.gd` — `npc_action_plan`, `player_shield_reroute_active`, `_shield_dome`, `_spawn_shield_dome()` (Fresnel shader), `_despawn_shield_dome()`, `_consume_shield_reroute()`, `_exec_shield_reroute()` redesign, `_execute_npc_action()`, `_npc_hit_shield_blocked()`, `_plan_npc_actions()`, `_play_npc_flee_taunt()`, `reset_size()` calls
- `scripts/ui/CombatPanel.gd` — `planning_started` 5th param, enemy plan sequence label, SHIELD_REROUTE no longer sends face param
- `scripts/UIManager.gd` — choice cap at 3, nav row hidden when single mission, count label for multi-mission, `call_deferred("reset_size")` on quest panel show
- `scripts/LLMInterface.gd` — "EXACTLY 3 entries" prompt instruction
- `scripts/story/StoryManager.gd` — `_SQ_DEBUG = false`
- `scripts/ui/UILayoutManager.gd` — `reset_size()` on edit mode exit, `reset_size()` at startup for dynamic panels

---

## Session: 2026-06-23 (StoryQuestManager Pipeline + UI Layout Improvements) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Full end-to-end smoke test of the StoryQuestManager pipeline — quest fires on first kill, tagged Reaver spawns, Kaelen hail auto-opens with TTS, kill completes quest, 500 SC lands, comms panel fires again on completion. Multiple bugs squashed along the way. UI layout system improved with no-overlap enforcement and cleaner edit mode for dynamic panels.

---

### 1. Wanted Poster Images (`scripts/UIManager.gd`, `assets/WantedPosters.png`, `assets/wanted_posters.json`)

Replaced the text-based bounty board with a sprite-sheet of wanted poster images. `WantedPosters.png` is 1536×1024 (3 columns × 2 rows, 512×512 per cell): Row 0 = Reavers, Obsidian, Dustborn; Row 1 = Wraiths, Ironclad, Blank. `_render_bounty_board()` slices cells via `AtlasTexture` and renders each poster as an image with a kill-progress label overlay. Tooltip trimmed to faction + payout + progress — no flavor quote.

---

### 2. GlobalState `player_kill` Signal (`scripts/GlobalState.gd`, `scripts/NPCShip.gd`)

`GlobalState.ship_destroyed` fires for ALL NPC deaths including NPC-vs-NPC. Added `signal player_kill(faction_name: String)` that only fires when `last_attacker_faction == "player"` inside `NPCShip.die()`. `StoryManager` connects to `player_kill` in `_ready()` instead of `ship_destroyed`, preventing story beats from triggering on friendly-fire kills.

---

### 3. StoryQuestManager Smoke Test (`scripts/story/StoryManager.gd`, `scripts/story/StoryQuestManager.gd`)

Added `const _SQ_DEBUG := true` (currently true — **must flip to false before shipping**) and `_sq_debug_fired` guard. On first player kill of the session, `_fire_debug_story_quest()` calls `StoryQuestManager.begin_quest()` with a hardcoded "kill the Reaver leader" quest definition (10 min timer, 500 SC reward, kaelen_voice hook, tagged spawn). `StoryQuestManager.reset_for_restart()` added to clear all quest state on new campaign.

---

### 4. Credits Centralization (`scripts/GlobalState.gd` + 6 call sites)

Replaced 14 direct `GlobalState.player_credits +=` / `-=` mutations across 6 files with `GlobalState.add_credits(amount)` and `GlobalState.spend_credits(amount)`. The existing `credits_changed` signal still fires through the property setter — all UI listeners unaffected. Single point for future logging, achievements, or stat tracking.

**Files touched:** `GlobalState.gd`, `GameRoot.gd`, `NPCShip.gd`, `QuestManager.gd`, `SpaceAnomaly.gd`, `UIManager.gd`, `navigation/GateDiscoveryManager.gd`, `story/StoryQuestManager.gd`

---

### 5. Bug Fix — `GlobalState.credits` → `player_credits` (`scripts/story/StoryQuestManager.gd`)

`_complete_quest()` was calling `GlobalState.credits += credits` — that property doesn't exist. Caused a runtime crash on quest completion. Fixed to use `GlobalState.add_credits(credits)` (part of the credits centralization pass).

---

### 6. UIManager Group Registration + Kaelen Voice Pipeline (`scripts/UIManager.gd`)

- `add_to_group("ui_manager")` added to `_ready()` — `StoryQuestManager._find_ui_manager()` uses `get_nodes_in_group()` and was silently returning null on every call, causing all kaelen_voice hooks to no-op.
- `queue_kaelen_voice_message(text)` public method added — routes to the `▶ KAELEN` intel button. Used for background intel drops.
- `open_kaelen_hail(line)` extracted from `_on_kaelen_intel_btn_pressed()` — immediately opens the comms hail panel with Kaelen's portrait, purple border, and TTS. StoryQuestManager uses this for story quest hooks (feels like an incoming transmission rather than optional intel).
- Kaelen intro pacing: added " . . " pauses after "That's you, by the way" and "I take a modest cut".

---

### 7. Story Quest HUD Card (`scripts/UIManager.gd`, `scripts/story/StoryQuestManager.gd`)

- `_story_quest_panel` (PanelContainer) added as a direct child of UIManager.
- Repositioned every frame via `_process` while visible — tracks `quest_tracker_panel.position + size.y + 6` so it stacks below the mission tracker and follows it when dragged.
- `_reposition_story_quest_panel()` helper.
- `UIManager._ready()` connects to `StoryQuestManager.quest_ui_updated` and `quest_ui_hidden` after confirming `is_instance_valid(StoryQuestManager)`.

---

### 8. Comms Hail Panel Positioning (`scripts/UIManager.gd`)

Comms hail panel (incoming transmissions) was clipping under the overview panel. Switched from static 20-80% anchors to center-screen: `anchor_left = 0.25`, `anchor_right = 0.75`, `anchor_top = 0.35`. Panels live on edges; center is reliably clear.

---

### 9. UILayoutManager: No-Overlap Enforcement (`scripts/ui/UILayoutManager.gd`)

Panels can no longer be dropped on top of each other. On mouse release after a drag, `_snap_back_if_overlapping()` checks the dragged panel's `Rect2` against all other visible panel rects. If any intersect, the panel snaps back to its pre-drag position (`_drag_start_pos`) and fires an orange SYSTEM chatter message: "Panel placement blocked — overlaps another panel."

---

### 10. UILayoutManager: Placeholder Overlay for Dynamic Panels (`scripts/ui/UILayoutManager.gd`)

The quest tracker panel is content-sized (not resizable), which caused it to appear oversized or invisible in unexpected positions during edit mode. Fix: when edit mode is unlocked, `_create_placeholder()` nests a dark `ColorRect` child inside the real panel labelled "ACTIVE CONTRACT". The real panel stays visible and fully draggable. On lock, the overlay child is `queue_free()`'d and the real content is restored. No panel swapping, no hidden/shown theatrics — `_panels[id]` always points to the real panel so the overlap check works correctly throughout.

---

### ⚠️ Before Shipping
- **`_SQ_DEBUG` in `scripts/story/StoryManager.gd` line 16 is currently `true`.** Flip to `false` before any release build.

---

### Files Modified
- `scripts/story/StoryManager.gd` — `_SQ_DEBUG`, `player_kill` signal connection, `_fire_debug_story_quest()`, `reset_for_restart()`
- `scripts/story/StoryQuestManager.gd` — `reset_for_restart()`, `open_kaelen_hail` call, `GlobalState.add_credits`
- `scripts/GlobalState.gd` — `signal player_kill`, `add_credits()`, `spend_credits()`
- `scripts/NPCShip.gd` — `GlobalState.player_kill.emit()` in `die()`
- `scripts/GameRoot.gd` — `StoryManager.reset_for_restart()`, `StoryQuestManager.reset_for_restart()`, `add_credits` / `spend_credits`
- `scripts/QuestManager.gd` — `add_credits` / `spend_credits`
- `scripts/SpaceAnomaly.gd` — `add_credits`
- `scripts/navigation/GateDiscoveryManager.gd` — `spend_credits`
- `scripts/UIManager.gd` — group registration, `open_kaelen_hail()`, `queue_kaelen_voice_message()`, story quest panel, comms hail positioning, `_process` tracker follow, `add_credits` / `spend_credits`
- `scripts/ui/UILayoutManager.gd` — snap-back overlap check, placeholder overlay system

### Files Added
- `assets/WantedPosters.png` — 1536×1024 wanted poster sprite sheet (3×2 grid)
- `assets/wanted_posters.json` — cell coordinate mapping

---

## Session: 2026-06-22 (Small Features Pass + UI Fixes + Story Manager Design) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Six features implemented, two bugs fixed (one serious), and a full story manager system designed and documented for Codex to implement.

### 1. Anomaly Rumors (`scripts/AnomalyRegistry.gd`, `scripts/MainScene.gd`)
After jumping to a new system, if anomalies were spawned there, a passing ship or comms relay has a 60% chance to emit a vague hint in the chatter log 8–18 seconds after arrival. Lines are flavor-matched to the anomaly type (military, pirate, scientific, civilian). `AnomalyRegistry` now tracks `_last_spawned_flavors` and exposes `get_arrival_rumor()`. `MainScene._ready()` calls `_schedule_anomaly_rumor()`.

### 2. Bounty Board (`scripts/UIManager.gd`)
A purple-bordered read-only panel in Services and Lounge submenus showing Kaelen's active contracts: faction, SC/kill rate, kills credited vs cap. Inserted BEFORE `station_contacts_panel` in the vbox (critical — contacts panel has SIZE_EXPAND_FILL and would push anything after it off-screen).

### 3. Wreckage Loot Variation (`scripts/PlayerShip.gd`)
Expanded salvage rare-drop from 2 hardcoded items to 7-outcome roll table via new `_salvage_grant_wreck_bonus()`. Outcomes: 30% credits (40–180 SC), 25% Damaged Transponder, 13% Encrypted Core, 10% Repair Kit, 9% Shield Cell, 8% Scanner Probe, 5% Data Chip.

### 4. Kaelen Voice Message Button (`scripts/UIManager.gd`, `scripts/GameRoot.gd`)
Replaced auto-firing Kaelen intel with a player-triggered voice message button on the SYSTEM COMMS RADIO panel. Button lights up purple ("▶ KAELEN — VOICE MESSAGE") when a message is queued. Clicking opens the comms hail panel with Kaelen's portrait, purple border, her line, and TTS. Dismissed with "Got it." Message triggers on system arrival (60–90s delay) via `GameRoot.notify_system_arrived()` → `UIManager.notify_system_arrived()` → `_maybe_kaelen_intel_drop()`.

### 5. Gate Portal Particles (`scripts/JumpGate.gd`)
CPUParticles3D emitter on each gate's portal surface — additive blend, ring emission shape, color matched to gate light. Spawned procedurally in `_spawn_portal_particles()`.

### 6. System Arrival Banner (`scripts/JumpTransitionFX.gd`)
"ENTERING / [SYSTEM NAME]" banner fades in then out after gate exit. Built in `_build_arrival_banner()`, triggered from `GameRoot` after `play_exit()`.

### Bug Fix A — Arrival Banner Blocking All Mouse Input (`scripts/JumpTransitionFX.gd`)
**Serious.** The `CenterContainer` inside the arrival banner used `PRESET_FULL_RECT` and defaulted to `MOUSE_FILTER_PASS`, creating an invisible full-screen click blocker. Broke dock UI and pause menu entirely. Fix: explicit `mouse_filter = Control.MOUSE_FILTER_IGNORE` on `CenterContainer` and `VBoxContainer` inside the banner.

### Bug Fix B — Kaelen Intel Firing During Quest Acceptance (`scripts/UIManager.gd`)
The 2.5s intel drop timer fired exactly as agent quest confirmation TTS was playing, causing Kaelen to speak Voss's line. Fixed by checking `agent_panel.visible` before firing. Later made irrelevant by the voice message button redesign.

### Story Manager Design (`docs/story_manager_design.md`, `docs/story_manager_impl.md`)
Full design and implementation spec for a narrative director system. Designed for Codex to implement. Key concepts:
- Gemma4 generates a structured story arc on first campaign load
- StoryManager autoload evaluates beats on game events (system arrival, kills, docking, quests)
- Nudge system (5 levels) steers the player toward story beats organically via quest injection, world pressure, and hints — never forcing
- StoryManager owns all story-adjacent messages (Kaelen arrival lines, intel drops, anomaly rumors)
- Triggers arc refresh generation from Gemma4 when current arc runs low
- Full GDScript implementation in `story_manager_impl.md` — every function, every hook, every file change with line context

### Story Manager Conflict Analysis (Section 10 of `story_manager_impl.md`)
10 concrete conflicts identified and resolved via sweep of GameRoot, GlobalState, LLMInterface, MainScene, UIManager:
- **Kaelen arrival double-fire**: GameRoot `_maybe_emit_kaelen_system_arrival` and StoryManager beats would both fire. Resolution: empty the GameRoot function body in Phase 2, keep the stub.
- **No GlobalState save methods**: `get_save_data()`/`apply_save_data()` don't exist; save lives in `CampaignCheckpointStore.capture_autosave()`. Find `kaelen_briefing_seen` to locate the right block.
- **LLMInterface `is_waiting` gate**: Arc generation calls silently dropped if quest gen is in flight. StoryManager queue must retry after delay.
- **story_quest_hint injection**: Must be read from GlobalState inside `request_quest_generation()` body — never added as a parameter.
- **MainScene NPC spawner**: Hardcoded faction uniform random. Need soft weight from `story_world_pressure.intensity` before the pick.
- **Anomaly rumor ordering**: StoryManager fires `on_system_arrived` AFTER AnomalyRegistry `generate_for_system()` — safe to call `get_arrival_rumor()` from nudge handler.
- **UIManager voice button already done**: `queue_kaelen_voice_message()` is already implemented. StoryManager just calls it.
- **Third GameRoot hook missing**: `StoryManager.on_system_arrived()` not yet wired into gate arrival sequence at lines 429–436.
- **Autoload order**: StoryManager must appear after QuestManager in project.godot.
- **Double-decrement on rapid re-dock**: Acceptable v1 behavior; fix recipe documented if it surfaces in playtesting.

## Files Modified
- `scripts/AnomalyRegistry.gd` — flavor tracking + `get_arrival_rumor()`
- `scripts/MainScene.gd` — anomaly rumor schedule + `notify_system_arrived` hook
- `scripts/UIManager.gd` — bounty board, voice message button, Kaelen intel, MOUSE_FILTER fixes
- `scripts/PlayerShip.gd` — `_salvage_grant_wreck_bonus()` loot table
- `scripts/JumpGate.gd` — `_spawn_portal_particles()`
- `scripts/JumpTransitionFX.gd` — arrival banner + MOUSE_FILTER_IGNORE fix
- `scripts/GameRoot.gd` — `notify_system_arrived` + `StoryManager.on_system_arrived` hook

## Files Added
- `docs/story_manager_design.md` — narrative director design doc (v2, active director model)
- `docs/story_manager_impl.md` — full implementation spec for Codex

---

## Session: 2026-06-22 (Skybox Fixes + Overview Height Bug) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Three persistent visual/UI bugs squashed: camera far-clip artifact, sky colored-cloud overlay, and overview panel height not saving.

---

### 1. Camera Far Clip (`scenes/player_ship.tscn`)

Hard diagonal edge splitting the sky was the camera clipping the starfield sphere. Increased `Camera3D.far` from `20000` to `50000`. Starfield sphere sits at radius 18000 — now always within clip range no matter which direction you look.

---

### 2. Starfield Sphere + Nebula Follow the Player (`scripts/visuals/SkyFollower.gd`, `scripts/visuals/SystemAmbience.gd`)

Both the starfield sphere and nebula container now track the player's world position each frame via a new `SkyFollower` helper node. Only `global_position` is updated — rotation is never touched — so stars remain direction-fixed even as you fly across the system. Eliminates any future far-clip risk regardless of how far the player travels from origin.

**Files added/modified:**
- `scripts/visuals/SkyFollower.gd` — new `extends Node`, sets parent's `global_position` to player each `_process`
- `scripts/visuals/SystemAmbience.gd` — attaches `SkyFollower` child to both the `Starfield` mesh and the `Nebula` container in `add_starfield()` / `add_nebula()`

---

### 3. Removed Galactic Haze Band from Starfield Shader (`shaders/starfield.gdshader`)

The starfield shader had a built-in colored haze band (simulated Milky Way) that was covering large portions of the sky with purple/colored fog every system. Removed entirely — shader now outputs stars only. The separate nebula billboard system handles per-system sky color.

Also removed the unused `seed_hash()` helper and simplified the star color to a clean `tint * lum`.

---

### 4. Overview Panel Height Persistence (`scripts/UIManager.gd`)

Overview panel height was reverting to full-screen tall on every restart or undock. Root cause: `set_overview_collapsed()` was setting `anchor_bottom = 0.65` after `UILayoutManager` had already converted the panel to pixel coordinates (all anchors zeroed). With `anchor_top = 0` and `anchor_bottom = 0.65`, the panel stretched from the top of the screen to 65% height on every expand, ignoring the saved size.

**Fix:** `set_overview_collapsed()` now manipulates `size.y` directly (never anchors). Collapsing stores the current expanded height in `_overview_expanded_h`; expanding restores it. UILayoutManager's saved layout survives intact.

---

## Session: 2026-06-22 (Draggable UI Layout + HUD Icon Buttons) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Full draggable/resizable HUD layout system shipped. Players can now rearrange and resize the 4 HUD panels and lock the layout in place. SYSTEM MAP and INVENTORY text buttons replaced with real icon buttons. Hover effect established as the game-wide standard.

---

### 1. Draggable UI Layout System (`scripts/ui/UILayoutManager.gd`)

Four HUD panels (chat, overview, HUD stats, target) are now fully repositionable and resizable by the player.

**How it works:**
- Click the **lock icon** (top-right) to enter edit mode — panels get a blue drag bar across the top and a resize grip on the bottom-right corner
- Drag the bar to move, drag the corner to resize
- Click the lock icon again to save and exit — icon swaps between open/closed padlock
- Layout persists to `user://ui_layout.json` and auto-loads on next launch

**Files added:**
- `scripts/ui/UILayoutManager.gd` — RefCounted singleton, handles drag/resize/save/load

---

### 2. HUD Icon Buttons

Replaced the old `SYSTEM MAP` and `INVENTORY` text blocks with proper icon buttons. Three square icon buttons now sit top-right: **[I] [M] [L]**.

- **I** — Inventory (briefcase icon)
- **M** — System Map (star constellation circle)
- **L** — Lock/Unlock UI layout (open/closed padlock, swaps on toggle)

Icons sourced from `assets/UIicons2.png`, split into individual files by Gemini: `lock_open.png`, `lock_closed.png`, `map.png`, `inventory.png`.

---

### 3. Chat Font Scaling

Chat panel text now scales proportionally as you resize the chat window — minimum 12px, maximum 24px. All existing messages update live when you drag the panel larger.

---

### 4. Standard Hover Effect (`_add_icon_hover()` in UIManager)

All icon buttons now have a consistent hover animation: 15% scale-up with a slight overshoot bounce on enter, smooth snap-back on exit (~120ms total). Implemented as `_add_icon_hover(btn: TextureButton)` — call it once after any future icon button to apply the standard effect game-wide.

---

## Session: 2026-06-22 (Kaelen Bounties + Space Anomalies Phase 1) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Two new self-contained gameplay systems shipped and playtested this session.

---

### 1. Kaelen's Standing Bounties (`scripts/economy/BountyRegistry.gd`)

Kaelen now has "paper" out on minor factions operating in the current system. Kill their ships, she pays you a small bounty (minus her cut) via a chat confirmation. No new menus — discovery happens through chat and her dock panel.

**How it works:**
- On first dock of a session, LLM generates 1–2 factions to put bounties on, with a one-sentence Kaelen-voice reason (e.g. "The Reavers hit a shipment I had a stake in. I want receipts.")
- Fallback picks a random minor faction with a static reason if LLM is unavailable
- On eligible kill: credits paid, money sound effect plays, Kaelen sends a confirm chat line in her new **violet** color
- Cap enforcement: bounties expire after N kills; final kill says "That closes the contract."
- Kaelen's dock panel shows `[Active Paper: Faction — X SC/kill]` when you click her in the contacts list
- Announcement fires only once per system per session

**Files added/modified:**
- `scripts/economy/BountyRegistry.gd` — new singleton, pure logic (no GlobalState dependency, fully unit-tested)
- `scripts/LLMInterface.gd` — `fetch_bounty_brief()` + `_trigger_bounty_brief_fallback()`
- `scripts/NPCShip.gd` — one guarded call in `die()`, pays credits + plays sound + emits Kaelen chat
- `scripts/UIManager.gd` — `_announce_bounties_on_dock()`, Active Paper in Kaelen lounge panel
- `tests/domain/run_bounty_registry_tests.gd` — 8 unit tests, all passing

**Kaelen color:** Changed from cyan (same as SYSTEM) to `Color(0.85, 0.5, 1.0)` (violet) across all emit_chatter calls in UIManager, NPCShip, GameRoot, BountyRegistry.

---

### 2. Space Anomalies Phase 1 (`scripts/SpaceAnomaly.gd`, `scripts/AnomalyRegistry.gd`)

1–3 anomaly nodes spawn per system (0–2 at normal rarity). Each is a self-contained mini-event — fly within 50 units to trigger. Events execute an `actions` array in sequence with optional delays.

**Action types implemented:**
- `emit_chat` — timed chat lines from a named sender (distress logs, AI voices, ghost signals)
- `grant_ore` — adds ore to hold (capped at 30)
- `grant_credits` — pays credits directly (capped at 150), plays money sound
- `grant_item` — adds item to inventory (whitelist enforced)
- `spawn_hostiles` — spawns 1–3 faction ships at a distance with optional pre-spawn chat line
- `damage_player` — small hull hit for dangerous scavenge scenarios
- `grant_temp_buff` — stub, logs warning (Phase 3)

**10 preset events in fallback table:**
1. Abandoned Cargo Cache — ore + repair kit
2. Distress Beacon (No Survivors) — old log lines + 65 SC + data chip
3. Reaver Ambush Point — story beat then 2 hostiles spawn
4. Cracked Reactor Core — 12 hull damage + 90 SC + antimatter pod (dangerous scavenge)
5. Drifting Weapon Cache — 3 ammo items
6. Encrypted Black Box — mystery log lines + encrypted core + data chip
7. Faction Skirmish Debris — ore + damaged transponder
8. Navigation Buoy (Derelict) — scanner probe + 30 SC
9. Emergency Med Cache — repair kit + shield cell
10. Hostile Scout Probe — 1 hostile spawns 4s after trigger (already transmitted your position)

**Visual:** Glowing sphere (OmniLight3D + MeshInstance3D), pulsing emission, color-coded by flavor type (blue = military, green = civilian, red = pirate, purple = scientific, amber = unknown).

**Overview:** Anomalies appear in the system overview as amber "Anomaly" entries. Clicking one in the overview shows "Anomaly — [name]" in the target panel.

**Spawn rate:** `randi_range(0, 2)` — 33% chance none, 33% chance 1, 33% chance 2. Keeps them a pleasant surprise, not guaranteed.

**Future (Phase 3):** LLM brain — `LLMInterface.fetch_anomaly_event()` generates fully unique events. Data core delivery loop (see memory note) deferred until campaign progression warrants it.

**Files added/modified:**
- `scripts/SpaceAnomaly.gd` — new node, proximity trigger, action executor, visual builder
- `scripts/AnomalyRegistry.gd` — new registry, fallback table, position randomizer
- `scripts/MainScene.gd` — preloads AnomalyRegistry, calls `generate_for_system()` in `_ready()`
- `scripts/UIManager.gd` — anomaly group in `refresh_overview()`, type label + amber color, target panel label

---

## Session: 2026-06-22 (Single-Use Salvage Drone + Store/UI Polish) — Claude
**Branch:** `segment-3/economy-stores-events`
**Commits:** `875c95e`, `56eb706`, `000c9f8`
**Date:** 2026-06-22

### Feature: Single-Use Salvage Drone Consumable

New consumable that strips a targeted wreck for ore using the ship's existing mining drones.

**How it works:**
- Activate from inventory while undocked, within 75u of a targeted wreck, with space in the ore hold
- One orbiting drone detaches and makes ~20 round trips to the wreck and back, granting 2 ore per return (~40 ore total over ~40 seconds — same ballpark as mining that much manually)
- ~0.8% rare drop chance per return (~15% total per wreck): 65% Damaged Transponder / 35% Encrypted Data Core, capped at one rare per run
- Run aborts permanently if the player takes any damage that actually connects (shield or hull hit). Drone is consumed regardless
- Wreck is removed on successful completion (model-swap animation deferred until a new model is ready)
- Priced at **25 SC** at Haven store — guaranteed 40 ore profit at 1 SC/ore, real upside is the rare drop

**Safeguards (checked up-front with a chat reason, drone not consumed on block):**
- Must be targeting a wreck (`"wreckage"` group)
- Must be within 75u (same as mining range)
- Must not be docked
- Ore hold must not be full / must be able to accept ore
- Only one active run at a time

**Mid-run stops:**
- Ore hold fills up during the run → abort, drone consumed
- Player flies out of range → abort, drone consumed
- Player takes a hit → abort, drone consumed
- Wreck becomes invalid → abort, drone consumed

**Files modified:**
- `scripts/economy/ConsumableEffects.gd` — new `"salvage"` effect type, `salvage_block_reason()` helper, `is_usable_now()` wired to it, `SALVAGE_RANGE = 75.0` const
- `scripts/PlayerShip.gd` — `begin_salvage()`, `_update_salvage()`, `_salvage_collect_return()`, `_abort_salvage()`, `_end_salvage()` state machine; `MINING_RANGE = 75.0` const replaces hardcoded literals; `take_damage()` abort hook (after shield/health math)
- `data/content/store_items.json` — price `2→25`, updated description

### Feature: NPCSalvager Taunt Lines + Visual Detection

The station salvager now mouths off when it catches the player poaching one of its wrecks.

- **Spot taunt** (8 lines): fires once when salvager is actively working a wreck and detects `player._salvage_active == true` on the same wreck within **150 units**. Examples: *"Hands off. I called that wreck."*, *"Nice drone. Be a shame if something happened to it."*
- **Lost-wreck taunt** (5 lines): fires if the player's drone completes and the wreck disappears out from under the salvager. Only triggers if the salvager had already spotted the player — not on normal salvage completions. Examples: *"That was mine. Every gram of it."*, *"Enjoy it. You just made an enemy for forty ore."*
- Flags reset each IDLE→wreck cycle so every new wreck is a fresh encounter

**Files modified:** `scripts/NPCSalvager.gd`

### Feature: Second Salvager Spawns at 5+ Wrecks

When the system has more than 5 active wrecks simultaneously, a second salvager spawns (within 30 seconds via the existing NPC spawn timer). Gets its own LLM-generated name so chat messages are distinguishable. Falls back to one when destroyed naturally.

- `NPCSalvager` added to group `"salvager"` for counting
- Wreck + salvager count checked in `MainScene._on_npc_spawn_timeout()`

**Files modified:** `scripts/NPCSalvager.gd`, `scripts/MainScene.gd`

### Store UI: Buy Button Repositioned

Moved the Buy button from the far right of each store row to the **far left, immediately before the icon**. Eliminates the wide gap between button and item that made it hard to tell which Buy belonged to which item.

**Files modified:** `scripts/UIManager.gd`

### Inventory: Closes After Successful Consumable Use

Any successful consumable use now closes the inventory panel. If the inventory was opened from the dock, it returns to the dock panel correctly (via `inventory_return_to_dock` flag). On failure (blocked use, wrong state), the inventory stays open so the player can read the reason / pick something else.

Salvage drone specifically: failure emits a chat reason from "Drone Bay" and keeps the inventory open. Success deploys the drone, removes the item, and closes inventory.

**Files modified:** `scripts/UIManager.gd`

### Bug Fix: Docked Inventory Limbo

**Problem:** Closing the inventory while docked could leave the player with no visible UI and `is_docked = true` — unable to fly or get back to services. Happened when `inventory_return_to_dock` was false because the inventory was opened from within a dock sub-panel (store, agent, etc.) where `dock_panel.visible` was already false at that moment.

**Fix:** Both close paths (`_on_inventory_pressed` toggle and new `_close_inventory_panel()` helper) now check `player.is_docked` as a fallback. If the player is docked, the dock panel is always restored regardless of the flag state.

**Files modified:** `scripts/UIManager.gd`

### Bug Fix: Kaelen Reaction Lines Showing Raw Template Placeholder

**Problem:** Kaelen's post-quest dialogue occasionally displayed the literal string `[Kaelen's unique completion line]` instead of generated text — the LLM was echoing the prompt template back verbatim.

**Fix 1:** Added bracket detection after parsing — if either field contains `[`, treat as a failed generation.
**Fix 2:** Added one automatic retry with a fresh random seed before falling back to static lines. All failure paths (HTTP error, parse failure, missing fields, echoed template) retry once.

**Files modified:** `scripts/LLMInterface.gd`

---

## Session: 2026-06-21 (~4:30 PM — Loading Hang Fix + UI Label Polish) — Claude
**Branch:** `segment-3/economy-stores-events`
**Commits:** `4f7da80`, `272422e`, `5a5da5b`
**Date:** 2026-06-21

### Bug Fix: Loading screen hung at 35% (no error)

Abe hit a hard stall: the loading screen froze at exactly 35% ("Generating
first contract briefing…") with no error, music still playing. Deleting
`savegame.json` did **not** help — the game restores from the campaign-slot
system (`campaigns/slot_01/`), not the legacy save. The selected slot
("Cold Meridian") was last saved by **undocking at a generated station**
(`system.gen.frontier.first`).

**Root cause:** At 35%, `UIManager._check_both_services_ready()` calls
`_request_background_agent_quest()` to make the opening contract. That station
has **no local faction contact**, and it is not the start system, so the
function logs `"No local faction contact for generated station; skipping
old-agent fallback."` and returns `false` **without requesting a quest**. The
loading bar only advances past 35% inside the `_on_background_quest_generated`
callback, which never fires → permanent hang.

**Fix (UIManager only — `4f7da80`):** `_check_both_services_ready()` now checks
the return value. When `false`, it calls a new `_finish_loading_without_contract()`
that completes the loading screen via the same TTS-cache completion path the
quest flow uses. Resuming a campaign mid-game at a generated station is
legitimate and should not require a fresh opening briefing. No generation,
save/load, or mission logic was touched.

### ⚠️ For Codex — deeper question I left alone (guardrail: generation domain)

The *symptom* (hang) is fixed defensively, but the underlying design question
is yours: **should a generated frontier station offer any contract source, or
is "no opening contract on resume" intended?** Right now resuming at such a
station drops the player in with no agent/board contract path until they
travel. If that's wrong, the fix belongs in station/NPC generation (faction
contact assignment), not the loading screen. I did not modify generation code.

### UI Label Polish (low-risk, `272422e` + `5a5da5b`)

- Dock/service buttons: `Talk To Agent`→`Talk to Agent`, `Hear Gossip From the
  Locals`→`…from the Locals`, removed double space in the Kaelen lounge button,
  reworded the repair "insufficient credits" disabled message.
- Inventory panel: `m3`→`m³` in the summary line, special-cargo route arrow
  `->`→`→`, removed a double space before the item category bracket, and a
  friendly muted empty-cargo-hold message instead of the raw HUD `EMPTY` string.

---

## Session: 2026-06-20 (Late Night — Visual Effects & Asteroid Overhaul)
**Branch:** `segment-3/economy-stores-events`
**Commits:** `712e78e` → `46e6989`
**Date:** 2026-06-20

### Feature 3: Weapon Impact Flashes & Death Explosions

Added visual feedback for projectile hits and ship destruction — previously both events were audio-only with no visual.

- **`ImpactEffect.gd`** (new file) — two static functions:
  - `spawn_hit()` — radial-gradient billboard flash (additive blend, fades over 0.15s) + 8 spark particles (omnidirectional burst, 0.25s lifetime). Self-cleans after 0.5s.
  - `spawn_explosion()` — larger flash (fades 0.3s) + 22 debris particles (white → faction color → orange → transparent gradient) + 5 secondary glow particles for a fireball feel. Self-cleans after 1.5s.
- **Projectile.gd** — cyan/faction-colored hit flash on ship impacts, grey sparks on asteroid hits
- **NPCShip.gd** — faction-colored explosion on death (Zenith=blue, Vanguard=orange-red)
- **PlayerShip.gd** — 1.5x scale cyan explosion on player death

### Bug Fix: Engine Glow Persisting on Wreckage

NPC engine glow (MultiMeshInstance3D) was a child of the `visual` node, which got passed to wreckage on death. Dead ships showed glowing thrusters. Fixed by `queue_free()`-ing `engine_glow` in `die()` before wreckage handoff.

### Feature: Blender-Generated Asteroid Rock Models

Replaced the plain SphereMesh asteroids with 20 unique rock models generated headlessly in Blender 5.1.

- **`tools/generate_asteroids.py`** — Blender Python script that creates 20 rocks using icospheres + 3 displacement layers (clouds, voronoi, musgrave noise). Varies scale, deformation, roughness per rock. Normalizes to radius 5.0, UV unwraps via smart project, exports as clean .glb files.
- **`assets/asteroids/`** — 20 `.glb` model files + `asteroid_models.json` mapping each model to a random cell from the 3×3 texture atlas (`asteroidTextures.png`)
- **`AsteroidModels.gd`** (new file) — preloads all 20 meshes at startup, creates shared `StandardMaterial3D` per atlas cell with UV scale/offset. `apply_random_model()` swaps an asteroid's MeshInstance3D mesh and material based on `persistent_id.hash()` for deterministic selection.
- **`Asteroid.gd`** — calls `AsteroidModels.apply_random_model()` in `_ready()`

### Feature: Asteroid Tumble Rotation

Each asteroid's MeshInstance3D slowly rotates around a random axis (0.05–0.25 rad/s, ~25–125 seconds per full rotation). Axis and speed seeded from `persistent_id` for determinism. Only the visual mesh rotates — collision shape stays fixed.

### Feature: Asteroid Vertical Bob (Double Sine Wave)

Each asteroid oscillates vertically with two overlapping sine waves at different frequencies (0.08–0.4 Hz) and random phases. Combined amplitude is roughly ±4.5–9.5 units (about the asteroid's height), breaking up the flat conveyor-belt look of orbital rings.

### Feature: Mining Laser Rock Dust Particles

Spawns 18 fine rock-colored particles (earthy brown/tan, unshaded, emissive) at the asteroid surface while the mining laser is active. Particles scatter omnidirectionally with high damping (dust-like). Stops the frame the laser turns off.

### Feature: Drone Collection Behavior During Mining

The two orbiting player drones now alternate flying to the asteroid and back while the mining laser is active, simulating ore collection:

- Active drone detaches from orbit, flies to asteroid impact point (~1s at 45 units/sec with ease-in-out), pauses briefly, flies back to ship hull, then the other drone takes its turn
- Non-active drone continues orbiting normally
- When mining stops, both drones are destroyed and respawned fresh from the hull, guaranteeing clean state with no lost drones

### Files Added
- `scripts/visuals/ImpactEffect.gd` — hit flash and explosion effects
- `scripts/visuals/AsteroidModels.gd` — asteroid model/texture loader
- `tools/generate_asteroids.py` — Blender headless rock generator
- `assets/asteroidTextures.png` — 3×3 rock texture atlas
- `assets/asteroids/` — 20 `.glb` rock models + JSON mapping

### Files Modified
- `scripts/Asteroid.gd` — random model, tumble, vertical bob
- `scripts/Projectile.gd` — hit flash on impact
- `scripts/NPCShip.gd` — death explosion, engine glow cleanup
- `scripts/PlayerShip.gd` — death explosion, mining particles, drone collection behavior
- `docs/plan_visual_effects.md` — checkpoints marked complete

---

## Session: 2026-06-20 (Night — Codebase Indexing & Repository Mapping)
**Branch:** `segment-3/economy-stores-events`

### Feature: Repository Map Generator & Codebase Indexing

To assist LLMs (Gemini, Claude, ChatGPT) in quickly understanding the project structure and symbol layout without consuming excessive context tokens, added a modular indexing script and generated codebase layouts.

- **Generator Script (`generate_repo_map.py`)**: A fast, recursive codebase scanner implementing specialized symbol extraction:
  - **Python**: Uses native `ast` AST parser for exact class, function, and method signatures.
  - **GDScript**: Line-by-line parsing utilizing backtracking-safe regular expressions to extract global class names, inner classes, and functions with return types.
  - **JavaScript/TypeScript & C#**: Handles classes and method signatures.
  - **Loop/Cycle Prevention**: Tracks visited canonical paths and ignores symbolic links to avoid traversal hangs.
  - **Encoding Protection**: Forces console UTF-8 output streams on Windows to prevent Unicode print crashes.
- **`PROJECT_MAP.md`**: Clean, indented markdown tree representing the project hierarchy with clickable `file://` scheme links to easily navigate directly to the files.
- **`PROJECT_MAP.json`**: Machine-readable JSON index storing files and parsed signature data.

### Files Added

- `generate_repo_map.py` — The generator utility
- `PROJECT_MAP.md` — Human/LLM-scannable project index map
- `PROJECT_MAP.json` — Machine-readable project index map

---

## Session: 2026-06-20 (Late — Bug Fixes & Runtime Ship Loading)
**Branch:** `segment-3/economy-stores-events`

### Bug Fix: Kaelen Intro Speech Skipped on New Campaign

**Problem:** Starting a new campaign skipped Kaelen's intro popup — she went straight into a mission intro at the station. Root cause: `GlobalState.reset_for_restart()` didn't reset `kaelen_briefing_seen` or `kaelen_briefing_accepted`, so flags from the previous campaign carried over.

**Fix:** Added resets for both flags in `reset_for_restart()`.

### Bug Fix: Same Generated Systems Across Campaigns

**Problem:** Traveling to a new system via gate produced the same system as the previous campaign. Two causes:
1. Generated system seeds were deterministic from fixed gate destination IDs (`dest_sys_id.hash()`), with no campaign-specific variation.
2. `CampaignSystemNames` saved to a global `user://campaign_systems.json` — not scoped per campaign — so used names persisted.

**Fix:**
- New `GlobalState.campaign_seed` (random int, saved/loaded with campaign state). XORed into all generated system seeds in `GateDiscoveryManager` and `GameRoot._init_generated_system_configs`.
- `CampaignSystemNames.reset()` clears the global names file on new campaign start.
- `_init_generated_system_configs` now rebuilds configs when the seed changes (detects stale configs from early startup).
- Old saves default to `campaign_seed = 0` (`hash ^ 0 == hash`), preserving existing system generation.
- `GeneratedGateBuilder` uses `config.seed_value` for outbound gate destination IDs, so different campaign seeds cascade into completely different system chains.

### Feature: Runtime Ship Model Loading (No Restart Required)

**Problem:** Ship models were generated by Blender into `res://assets/ships/generated/`, which required Godot's import pipeline. Models only appeared after restarting the game.

**Fix:**
- Ship output moved to `user://campaigns/{slot_id}/ships/` — inside each campaign's folder. Deleted automatically when the campaign is deleted via `_remove_tree`.
- New `ShipGenerator.load_runtime()` uses `GLTFDocument`/`GLTFState` to load `.glb` files at runtime without the import pipeline.
- `NPCShip` gains `custom_model_scene` (pre-loaded Node3D) and `apply_generated_model()` for hot-swapping hulls mid-gameplay.
- `ShipPreGenerator` now emits `ship_generated` signal when background thread finishes a model. Also queues the current system's ships (not just neighbors).
- `GeneratedSystemNPCManager` connects to that signal and hot-swaps models onto already-spawned NPCs that still have fallback hulls.

### Files Modified

- `scripts/GlobalState.gd` — `campaign_seed`, briefing flag resets
- `scripts/GameRoot.gd` — campaign seed save/load, generated config rebuild, campaign slot path helper, ship generator path sync
- `scripts/NPCShip.gd` — `custom_model_scene`, `apply_generated_model()`
- `scripts/generation/ShipGenerator.gd` — `user://` output, per-campaign paths, `load_runtime()`, `has_cached()`
- `scripts/generation/ShipPreGenerator.gd` — `ship_generated` signal, current-system queuing
- `scripts/generation/GeneratedSystemNPCManager.gd` — hot-swap on `ship_generated`, runtime GLTF loading
- `scripts/generation/CampaignSystemNames.gd` — `reset()` static method
- `scripts/navigation/GateDiscoveryManager.gd` — campaign seed XOR into system generation

---

## Session: 2026-06-20 (Early — Space Visuals)
**Branch:** `segment-3/economy-stores-events`
**Commits:** `088a3ad` → `1d3faf4`

### Nebula Layer for Space Background

Added procedural nebula clouds to generated systems. Five pre-baked grayscale nebula textures (2048×1024) are tinted at runtime via an additive shader on billboard quads. Each system's `SystemConfig` seeds a random sky direction, texture pick, color pair, brightness, and layer count (1–2 overlapping layers) so nebulas vary per system without covering the whole sky.

- New `nebula.gdshader` — additive unshaded spatial shader with power-curve contrast (`pow(mask, 1.8)`) so thin edges fade and dense cores glow
- `SystemAmbience.add_nebula()` — places billboard quads at 17k units from origin, slightly offset per layer so they overlap without being identical
- `SystemConfig` — new `nebula_seed`, `nebula_colors`, `nebula_brightness`, `nebula_layer_count` fields, all derived from the system seed
- `SystemFactory` — calls `add_nebula()` during system generation
- Camera far plane bumped to 20k; starfield radius pushed to 18k to accommodate

### Starfield Shader Improvements

Enhanced the starfield shader with more visual variety:
- Cubed brightness distribution (most stars dim, few bright)
- Per-star random sizes instead of uniform dots
- Soft glow halos on brighter stars
- Subtle independent twinkling on ~10% of stars
- ~0.8% of star slots render as small fuzzy elongated smudges representing distant galaxies

### Files Modified

- `scripts/visuals/SystemAmbience.gd`, `scripts/generation/SystemConfig.gd`, `scripts/generation/SystemFactory.gd`, `scripts/MainScene.gd`, `scripts/TestSystem.gd`, `scenes/player_ship.tscn`
- `shaders/nebula.gdshader` (new), `shaders/starfield.gdshader`
- `assets/nebula_cloud_1–5.png` (new)

---

## Session: 2026-06-19 (Late — Dialogue Substitution Pivot)
**Branch:** `segment-3/economy-stores-events`
**Commits:** `e66dab3` → `e2c5a9d`
**Date:** 2026-06-19

### Context
Continued from the prior session's dialogue alignment work. This session focused on the initial placeholder approach, discovered it didn't work with the 1.5B model, and pivoted to a dummy-name approach that works much better.

### What Was Attempted and Why It Failed

**Placeholder approach (reverted):** Tried having the LLM write `{PILOT}`, `{TARGET_FACTION}`, `{KILL_COUNT}` etc. in dialogue, with explicit instructions to use these tags. The 1.5B model could not follow these instructions — it wrote stage directions ("Captain Dask Briefing his crew"), ignored placeholders and used literal names, referred to itself in third person, and produced garbage dialogue.

### What Was Implemented Instead

**Dummy-name substitution system:** Instead of explaining placeholders, we feed the LLM examples that consistently use fixed dummy names. The LLM mimics the pattern naturally without knowing they're placeholders:

- **"George"** → swapped to "Indy" (most agents) or "Shiny" (Kaelen)
- **"Slithern"** → swapped to actual target faction (e.g., "Obsidian", "Ironclad")
- **"3"** (ship count) → swapped to actual count (2-4) via `_sync_dialogue_to_validated_objective`
- **"25"** (ore amount) → swapped to actual amount (20-300) via same sync
- **"Sable Mercer" / "Morrow Station" / "Sealed Data Drive"** → swapped to actual pickup NPC/outpost/item

### New Functions in LLMInterface.gd

- `_substitute_dialogue_placeholders()` — swaps all dummy names for real pre-rolled values in dialogue + choice responses
- `_nickname_for_agent(agent_name)` — returns "Shiny" for Kaelen, "Indy" for all others
- `_dialogue_has_faction_mismatch()` — catches dialogue mentioning factions other than the target
- `_dialogue_is_too_vague()` — catches dialogue with zero objective-relevant keywords (no combat words for kill missions, no ore words for delivery, etc.)
- `_dialogue_has_placeholder_artifacts()` — catches leftover "George"/"Slithern" or agent referring to itself by name
- `_request_dialogue_retry()` / `_on_dialogue_retry_completed()` — gives LLM a second attempt with a simpler prompt before falling back to safe canned dialogue
- `_finish_quest_with_current_dialogue()` — unified callback path that sets `is_waiting = false`
- `_apply_replacements()` — generic string replacement helper

### New State Variable
- `_pending_substitutions: Dictionary` — stashed at quest generation time with real pre-rolled values (kill target, count, ore amount, pickup details, nickname, agent name, faction)

### Other Changes
- `is_waiting` management refactored — stays `true` during retry, set `false` in `_finish_quest_with_current_dialogue()` and `_trigger_fallback()`
- Agent persona text reverted to natural language (removed `{PILOT}` references)
- Example dialogues simplified to short flavor sentences using George/Slithern
- Prompt instructions simplified — tells LLM to use "George"/"Slithern"/3 instead of explaining placeholder syntax
- Pre-rolling objective values (kill target, ore amount) moved before prompt construction so they can be stashed

### Test Results
- **Ore missions:** Working well — dialogue matches contract, amounts correct
- **Pickup missions:** ~50% work great, ~50% trigger Kaelen fallback ("not putting my name on it")
- **Kill missions:** Not seen during testing — may need type-specific example dialogues added back

### What Still Needs Work (see handoff_dialogue_alignment.md)
1. **Per-type example dialogues** — every agent currently has ONE kill-themed example. Need DELIVER_ORE and PICKUP_SPECIAL examples using dummy names so the LLM sees the right pattern per mission type
2. **Kaelen pickup fallback rate** — vague dialogue check may be too strict, or Kaelen's example doesn't demonstrate pickup format well enough
3. **Kill mission generation** — need to verify KILL_SHIPS quests generate and test the Slithern→real faction swap
4. **"Neutral Fixer & Profit Broker" subtitle** — all agents show Kaelen's subtitle instead of their own role

### Files Modified
- `scripts/LLMInterface.gd` — all changes

### Files Added
- `docs/handoff_dialogue_alignment.md` — detailed handoff for next session

---

## Session: 2026-06-19 (Early — Dialogue Validation & System-Aware Quests)
**Branch:** `segment-3/economy-stores-events`
**Commit:** `02ab6c6`
**Date:** 2026-06-19

## Context

Picked up from `docs/handoff_dialogue_alignment.md`. The dummy-name substitution system was in place but had several open issues causing broken quests. This session resolved all active items from that handoff.

---

## Changes Made

### 1. Per-Type Example Dialogues (LLMInterface.gd)

**Problem:** Every agent had ONE kill-themed example dialogue regardless of mission type. When the LLM was asked to generate a DELIVER_ORE or PICKUP_SPECIAL quest, it had no ore/pickup examples to mimic and produced vague or wrong-type dialogue that failed validation.

**Fix:** Added `_get_type_examples(agent_key, mission_type)` function (~line 665) that returns 5 type-matched example dialogues + 3 choice responses for each agent × mission type combination. That's 4 agents (zenith/aurelia/vanguard/neutral) × 3 mission types = 12 example sets, each with 5 dialogues.

The prompt now:
- Picks one of the 5 dialogues randomly for the JSON structure example
- Lists the other 4 as a reference block under `### EXAMPLE DIALOGUES FOR THIS MISSION TYPE`
- Uses type-matched choice responses in the JSON example

The old single `example_dialogue` / `example_response_1/2/3` variables per agent were removed.

### 2. System-Aware Kill Targets (LLMInterface.gd + GlobalState.gd)

**Problem:** Kill missions always picked targets from the hardcoded `MINOR_FACTIONS` dict (reavers, obsidian, dustborn, wraiths, ironclad). Generated systems with their own factions (`gen_*` / `faction.generated.*`) were ignored.

**Fix:**
- Added `GlobalState.get_current_system_minor_factions()` — looks up the current system's `SystemDefinition.faction_ids` via the system registry (same data source the map UI uses). Falls back to hardcoded `MINOR_FACTIONS` for the starter system.
- Kill target picker now calls `get_current_system_minor_factions()` instead of `MINOR_FACTIONS.keys()`.
- The minor faction context string in the prompt also uses this function.

### 3. System-Aware Pickup Outposts (LLMInterface.gd)

**Problem:** Pickup missions were hardcoded to `PICKUP_OUTPOST_IDS` (iron_reach, kova). Generated system outposts were never used as pickup destinations.

**Fix:** Pickup outpost picker now calls `GlobalState.get_current_system_outposts()` first, falling back to the starter outposts only if no system outposts are found. Also added an empty-NPC guard that falls back to `random_minor_npc_name()`.

### 4. Faction Capitalization Bug Fix (LLMInterface.gd)

**Problem:** The LLM sometimes wrote `"faction": "Zenith"` (capitalized) instead of `"zenith"`. `DomainId.canonicalize` only has lowercase entries in `LEGACY_ALIASES`, so "Zenith" failed `is_valid()`, causing `QuestManager.accept_quest()` to return false. The player saw Kaelen say "That contract is broken, Shiny."

**Fix:** `_substitute_dialogue_placeholders()` now lowercases and strips the faction value before it reaches validation. Also forces `agent_name` from the pre-rolled value so the LLM can't change it.

### 5. Slithern Variant Regex (LLMInterface.gd)

**Problem:** The LLM sometimes wrote "slitherers", "slithering", etc. instead of the exact dummy name "Slithern". The exact-match substitution didn't catch these.

**Fix:**
- Added explicit variants to the replacement dict (Slitherns, slitherers, Slitheren, etc.)
- Added a regex fallback in `_apply_replacements()` that catches any word starting with "slither" and replaces it with the real faction name

### 6. Agent Subtitle Fix (UIManager.gd + LLMInterface.gd)

**Problem:** All agents showed "Neutral Fixer & Profit Broker" as their subtitle — this is Kaelen's role, not the quest giver's.

**Fix:**
- `agent_role` is now stashed in `_pending_substitutions` and injected into quest data as `quest_data["agent_role"]` during substitution
- Fallback quests also get `agent_role` set
- Added `agent_subtitle_label` as an instance variable in UIManager
- Updated all locations where `agent_name_label` is set to also update `agent_subtitle_label` (8 reset points for Kaelen, 2 dynamic points from quest data, 1 for public board)

### 7. Second-Person Dialogue Instruction (LLMInterface.gd)

**Problem:** The LLM sometimes wrote dialogue in third person ("Indy is cleared to initiate the assault") instead of speaking directly to the player.

**Fix:** Added prompt instruction: "The dialogue is the agent OFFERING the job to the pilot — the pilot has NOT accepted yet. Speak directly to the pilot in second person. Do not narrate, announce, or talk about the pilot in third person."

### 8. Wider Pickup Vague Check (LLMInterface.gd)

**Problem:** `_dialogue_is_too_vague()` for PICKUP_SPECIAL only accepted 10 keywords (retrieve, fetch, pick up, etc.). Many valid pickup dialogues using words like "grab", "courier", "cargo", "bring back" were rejected and fell back to safe dialogue.

**Fix:** Expanded keyword list to 23 words. Also dynamically includes the actual substituted item/NPC/outpost names as valid keywords.

### 9. Validation Tracing (LLMInterface.gd + UIManager.gd)

**Problem:** When a quest was rejected or dialogue was rewritten, there was no way to tell which validation check fired or what the LLM originally wrote.

**Fix:**
- `_finalize_validated_quest_display()` now logs: `⚠ VALIDATE REWRITE REASON: <check_name>` and `⚠ VALIDATE ORIGINAL DIALOGUE: <text>`
- Retry failure logs: `⚠ RETRY FAILED` with the retry dialogue text
- `_on_choice_selected()` logs: `⚠ QUEST REJECTED — reason: <validation_error>` with full quest data JSON
- Filter Godot output for `⚠ VALIDATE` or `⚠ RETRY` or `⚠ QUEST REJECTED` to see rejection chains

### 10. Quest Generation Test Script (test_quest_gen.gd + test_quest_gen.tscn)

New stress test that runs 20 quest generations back-to-back (configurable via `ITERATIONS`). Run with F6 on `scenes/test_quest_gen.tscn`.

Output shows each quest formatted as the player would see it: agent name, role, full dialogue, contract details, and all choice responses. Automated checks flag leftover dummy names, missing fields, wrong subtitles, and fallbacks. Summary at the end shows pass/fail counts by type.

---

## Files Modified

- `scripts/LLMInterface.gd` — bulk of changes (per-type examples, system-aware targets, substitution fixes, validation tracing, prompt improvements)
- `scripts/GlobalState.gd` — added `get_current_system_minor_factions()`
- `scripts/UIManager.gd` — agent subtitle label, quest rejection tracing

## Files Added

- `scripts/test_quest_gen.gd` — stress test script
- `scenes/test_quest_gen.tscn` — scene to run the test

## Remaining Monitor Items (No Code Changes Needed)

- **Ore "25" false positives:** `_sync_dialogue_to_validated_objective` searches for "25" near ore-context words. Could false-positive. Watch logs for `⚠ VALIDATE: Final objective changed`.
- **`is_waiting` state:** Stays true during retries, set false in `_finish_quest_with_current_dialogue()` and `_trigger_fallback()`. If quests stop generating, check these paths.
- **Kaelen intro dialogue:** Separate LLM path (`request_kaelen_intro`). Sometimes reads oddly (talking about the agent instead of to the player). Not addressed this session.

---

## Session: 2026-06-25 (Phase 19 Mega-Boss + Phase 20 Multi-Enemy Squads) — Claude
**Branch:** `segment-3/economy-stores-events`

### Overview
Full boss fight system with 3-phase AI, plus 2-on-1 squad combat. Debug keys moved to GameRoot so they work everywhere. Several crash/queue bugs fixed during playtesting.

---

### Debug Keys (Numpad — GameRoot._input)

| Key | Action |
|---|---|
| Numpad 8 | Force-restock all station stores to max |
| Numpad 9 | Spawn boss ship 80u ahead (500 HP, 1.5× scale) |
| Numpad 0 | Spawn 2-ship Aurelia squad ~75u ahead |

Previously in `MainScene._unhandled_key_input` — moved to `GameRoot._input` so UI panels can't swallow the events.

---

### Phase 19 — Mega-Boss

**NPCShip.gd**
- `is_boss: bool`, `boss_phase: int` (1–3) added
- `_plan_boss()` — three phase strategies:
  - **Phase 1 "Dominant"** (100–60% HP): 80% brace chance, then fire ×2–3
  - **Phase 2 "Wounded"** (60–30% HP): repair if <45%, shield angle + flank/disable engines
  - **Phase 3 "Last Stand"** (<30% HP): all AP into 1.3–1.6× kill shots, no defense

**CombatManager.gd**
- `signal boss_phase_changed(phase: int)`
- `_check_boss_phase_transition()` — detects 60%/30% HP crossings, guarded against double-fire
- `_transition_boss_phase()` — red system chatter + NPC voice taunt + signal emit
- Called from `_apply_hit()` and `_after_npc_turn()`

**LLMInterface.gd**
- `npc_boss_phase_2`: "Still standing? Fine. Now I get serious."
- `npc_boss_phase_3`: "You want to see what I'm really capable of?"
- Prompt count 16 → 18

**CombatPanel.gd**
- `_boss_phase_label` — hidden for normal fights, shown for boss
- Phase I (pink) → Phase II (orange-red) → Phase III (bright red)

**Boss stats (debug spawn)**
- 500 HP, 6 AP, intel 0.85, damage 14–22, scale 1.5×, Vanguard Gunner faction

---

### Phase 20 — Multi-Enemy Squads

**NPCShip.gd**
- `squad_id: String` — ships with matching non-empty ID fight together
- Join path: if state is PLANNING and squad matches, calls `CombatManager.join_combat()` instead of queueing a new fight

**CombatManager.gd**
- `enemy_node: Node` → `enemy_nodes: Array` + property getter (all existing code unchanged)
- `enemy_brace_active`/`enemy_shield_angle_active` → per-enemy array getters
- `join_combat(enemy)` — appends enemy, generates its plan immediately so it acts this turn
- `set_target(idx)` — explicit index selection, spawns white outline flash on ship
- `_remove_dead_enemies()` — removes dead nodes after each turn, kill cinematic per death
- `_kill_and_end()` gains `skip_end` param for mid-squad kills
- `_spawn_target_flash()` — 1.08× white unshaded ghost meshes, fade out over 0.35s

**CombatPanel.gd**
- Top bar always shows `enemy_nodes[0]`, bottom always `enemy_nodes[1]`
- Each bar has its own invisible click button — click to select that ship as target
- Selected bar: full size + full opacity. Unselected: 70% width, 65% opacity
- Hovering a non-selected bar brightens it as a clickable hint
- `_wingman_label` shows the ship name

---

### Bug Fixes

**Combat queue drop** (`NPCShip.gd`)
- NPCs that entered attack range during the kill cinematic were silently dropped (never queued)
- Fix: removed `CombatManager.state != IDLE` guard from `_request_combat_via_queue()`

**Freed instance crash** (`CombatManager.gd`)
- `enemy_node` getter was returning a `queue_free`'d node, crashing on first squad kill
- Fix: `is_instance_valid()` check added to getter

---

### Boss Tuning
| Stat | Old | New |
|---|---|---|
| Max HP | 300 | 500 |
| Phase 1 brace chance | 55% | 80% |

---

## 2026-06-27 — Kitbash Ship System (data-driven, no Blender at runtime)

Replaced the old per-spawn Blender ship generator (`ShipGenerator.gd` shelling
out to `blender.exe` with the cube-extrusion `spaceship_generator.py`) with a
runtime kitbash system built from the new `Shipyard.blend` part library.

### Pipeline
1. **Offline part export (Blender, one-time):** `Shipyard.blend` → 155 individual
   origin-centered GLBs under `res://assets/ship_parts/{hulls,engines,weapons,greebles,detail}/`
   plus `manifest.json` (Godot-space AABBs). Parts carry geometry only; flat
   placeholder materials stripped. Forward axis = Blender +Y → Godot -Z.
   - Export gotchas (documented in script): part objects live in view-layer-
     EXCLUDED collections so `visible_get()` is False — must `link()` into the
     active scene + `hide_set(False)` per object or `use_selection` exports empty
     132-byte GLBs. Also `export_apply=True` produced empty meshes; removed it.
2. **Assembler (`scripts/generation/ShipAssembler.gd`, pure GDScript):**
   - `generate_recipe(role, seed)` → data dict (hull + placed parts + transforms
     + engine/weapon markers). Hull spine + rear engine cluster + mirrored dorsal
     weapons, bbox-snapped. Symmetry is what keeps them from looking like junk.
   - `build_from_recipe(recipe, faction)` → Node3D, reskinned per faction
     (metal albedo + normal map, triplanar; + dorsal faction badge decal).
   - `pick_design(role, seed)` / `build_catalog_ship(...)` → read frozen catalog.
3. **Design catalog (`res://assets/ships/ship_designs.json`):** auto-generated by
   `tools/assembler_preview/catalog_gen.tscn` — 20 candidates/role scored by
   proportion heuristics, deduped by part combo, best 6 distinct kept per role.
   Designs are frozen as explicit recipes (NOT just seeds) so future assembler
   changes can't silently alter blessed ships.

### Integration
- `NPCShip.gd`: `ASSEMBLED_FACTIONS = {"vanguard"}`. `_setup_hull()` routes
  Vanguard through `_build_assembled_hull()` → `ShipAssembler.build_catalog_ship`,
  falls back to legacy GLB on failure. Existing `_fit_major_hull` /
  `_setup_model_points` / engine-glow plumbing picks up the `engine_*` / `weapon_*`
  markers automatically.
- Verified end-to-end: real NPCShip instances build catalog ships for all 4 roles
  (Interceptor/Gunner/Logistics/MiningHauler), correct fit-to-target scaling,
  clean hardpoint/engine counts, convincing silhouettes (screenshots reviewed).

### Architecture note (hybrid plan)
Designs are faction-agnostic geometry; variety = color + normal + badge swap at
runtime. Vanguard uses a curated subset now; add/recycle designs for new factions
by system 4–5. Mesh-merge + texture atlas per design is a DEFERRED optimization
(only needed if hundreds of ships are on screen at once).

### Dev tools (kept under tools/assembler_preview/)
- `preview.tscn` — live-gen multi-angle render of each role.
- `integ.tscn` — spawns real NPCShips as Vanguard and screenshots them.
- `catalog_gen.tscn` — regenerates `ship_designs.json` + contact sheets.

### Reusable 3D ModelViewer (same session)
- `scripts/ui/ModelViewer.gd` (class_name `ModelViewer`) + `scenes/ui/model_viewer.tscn`.
- Self-contained Control: builds its own SubViewport (own World3D) + env + 2 lights
  + yaw/pitch orbit rig + camera in code. Drop into any panel.
- API: `show_ship(faction, role, seed)` (builds via `ShipAssembler.build_catalog_ship`)
  or `set_model(node: Node3D)`. Auto-frames to model AABB, starts on a 3/4 bow-hero
  angle. Left-drag orbit, scroll zoom, idle auto-spin (`auto_rotate`).
- Note: `SubViewportContainer.mouse_filter = IGNORE` so the Control receives orbit
  input (per the mouse-filter rule). Built to back the sensor/ship-info panel todo.
- Verified via `tools/assembler_preview/viewer_test.tscn` (frame/orbit/zoom/swap).

### Dev Panel: Ship Viewer tab (same session)
- Added a "Ship Viewer" tab to `DevPanel` (Numpad 7) embedding the reusable
  `ModelViewer`. Dropdown auto-populates from
  `ShipAssembler.styled_factions() × catalog_roles() × design_count()` — every
  frozen design, labelled e.g. "Vanguard Gunner #1". Selecting rebuilds + reframes.
- New assembler accessors: `catalog_roles()`, `design_count(role)`, `styled_factions()`.
- New factions/designs appear in the dropdown automatically once styled. Verified
  via `tools/assembler_preview/devpanel_test.tscn`.

### Fix: open-shell hulls caused "holes" (same session)
- `hull.Grill` and `hull.rib` are hollow open-shell meshes — used as primary
  hulls they showed a big hole (Gunner #6, etc.). Geometry, not a UV/texture issue.
- Removed open hulls from the assembler hull pools (Gunner now bullHead/block_split/
  lump/fish; Interceptor dropped hull.v). Regenerated `ship_designs.json` — all 24
  designs now use solid closed hulls. Verified via contact sheets.
- Guidance: keep open/forked hulls (Grill, rib, Jaw, split, v, handle) out of the
  primary-hull pools; they're only suitable as greebles/attachments.

### Blender MCP + 5-Engine thruster split (2026-06-28)
- Set up Blender MCP (ahujasid/blender-mcp) in Claude Desktop config; connected live.
- Finding: the turbine exhaust the player liked is the **5-Engine** part (the gunmetal
  hero ship uses 2× 5-Engine + hull.tall + 4× hardpoint.dev.hammer) — NOT hull.tall.
  hull.tall is just the body. So the "separate thruster from engine" split belongs on 5-Engine.
- 5-Engine breaks into clean loose parts: 216-face mounting shell (body) + 5 nozzle
  cylinders & turbine fans at the rear (1320 faces). Split by connected-component centroid
  (y < -2.5 = thruster). Assigned 2 materials: EngineBody + Thruster.
- Exported `assets/ship_parts/engines/5-Engine_split.glb` (2 surfaces) and swapped it in as
  `5-Engine.glb` (original kept as `5-Engine_ORIG.glb.bak`).
- Assembler: added PART_LOOK "thruster" (crisp dark metal, faint hot rim emit) and per-surface
  material application — surfaces whose source material name contains "thruster" get the
  thruster material; engine body keeps engine metal. Verified rendering, no errors.
- NOTE: triplanar is used for materials, so the old Trellis "bad UV" problem doesn't apply
  to kitbash parts — crisp exhaust comes from the dedicated material + in-game glow, not UV unwrap.

### STILL OPEN (player ship)
- Player ship NOT yet wired (still INDYMiner). Tasks remaining: cockpit emissive strip decals,
  swap gunmetal hull.tall in as player ship (orient fore-aft, refit collision/camera),
  make drones parametric to new size. See todo.md + memory project_drone_ship_fitment.

---

## 2026-06-28 (cont.) — Player ship build-out + more factions

Built the gunmetal hull.tall into the actual player ship and iterated its details
live via the new DevPanel controls (then removed them). Also extended the kitbash
reskin to two more factions and fixed the thruster material.

### Player ship
- `PlayerShip.gd` now builds `ShipAssembler.build_special(0)` (★ Gunmetal — Tall)
  into the Visual node, replacing the old INDYMiner; fit to target size, centered,
  collision box refit. Upright (`PLAYER_SHIP_TILT_DEG = 0`; opposite-tilt is a todo).
- **Drones parametric:** orbit radius + drone size now derive from the player visual
  AABB (`_drone_orbit_radius` / `_drone_size`), replacing the hardcoded 6.8 / 0.12 so
  any future ship/upgrade auto-fits. (See memory `project_drone_ship_fitment`.)
- **Combat fires from hardpoints:** PlayerShip collects the model's `weapon_*` markers;
  `spawn_projectile` cycles through them as fire origins. Mining laser origin untouched.
- **Weapons:** player ship forces `Turret_Set` (reads as guns) via weapon_override.
- **Cockpit:** two emissive white window boxes on the hull -Z face. Final baked values
  Y 0.60/0.41, Z 0/0, thickness 0.10. Boxes (not flat planes) so they never float.

### Tooling
- DevPanel "Ship Viewer" tab: dropdown of all catalog designs + specials (★), live 3D
  orbit/zoom via reusable `ModelViewer`. Temporary Y/Z/thickness tuning spinboxes were
  added, used to dial in the cockpit, then removed. **Lesson logged** (memory
  `feedback_live_tuning_debug_panel`): for eyeball tuning, build a live debug control
  FIRST — the screenshot-calibrate loop cost ~40 min before we did.

### Materials / parts
- `5-Engine` nozzles split (Blender MCP) into `EngineBody` + `Thruster` material slots.
  Thruster is now crisp dark METAL (no emission) — glow should be the plume at the
  engine markers, not the part. Todo: do the same nozzle split for ALL engine parts
  (one-time per piece, reusable forever).
- Added `zenith` (NavyBlueMetal + ZenithBadge) and `aurelia` (ForestGreenMetal +
  AurelliaBadge) reskin styles. Preview-only — NOT in `ASSEMBLED_FACTIONS` yet, so
  in-game ships unchanged; they show in the Ship Viewer dropdown. One-line toggle to go live.

### NOTE — "Claudework" todo list untouched this week
We never got to the planned **Claudework** todo list this week — the kitbash ship
system + player ship rabbit hole ate the whole session (worth it, but flagging it).
Pick that list back up next time. Also still open: flip Zenith/Aurelia on in-game,
the mouse-lost-on-combat-entry bug (High — forces hard exit), NPC exhaust glow rework.

---

## LLM Dialogue Content Registry — first slice (segment-3/economy-stores-events)

Started migrating scattered LLM dialogue steering out of GDScript into a single
human-editable JSON file (Codex plan: `docs/plan_llm_dialogue_content_registry.md`,
editing guide: `docs/llm_dialogue_content_editing.md`).

**Moved into JSON** (`data/content/llm_dialogue_content.json`):
- Quest few-shot examples for all 4 agent voices × 3 mission types (the old
  `_get_type_examples` content — verbatim).
- Per-mission-type `dummy_constraints` (Slithern/George/3 ships, 25 m³ ore, Sable
  Mercer @ Morrow Station / Sealed Data Drive).
- `global_rules` + `speakers` cards documenting nickname ownership (Shiny = Kaelen
  only; Indy = rare for faction agents; enemies never address the player). These are
  documentation/future-wiring for now.

**New code:** `scripts/registry/LLMDialogueContentRegistry.gd` (boring accessor, safe
defaults on bad/missing JSON), test `tests/registry/run_llm_dialogue_content_registry_tests.gd`.

**Wired:** `LLMInterface._get_type_examples()` and the quest `dummy_name_instruction`
now read the registry; the original hardcoded strings remain as a byte-identical
safety-net fallback (renamed `_get_type_examples_fallback`).

**Still hardcoded (with TODO markers pointing at JSON keys):** faction agent persona
strings, Kaelen handoff few-shot lines, and everything in UIManager (mechanic/lounge)
and combat taunts. Model-profile file/registry deliberately NOT built yet (future).

Tests run & passing: parse_check, new registry test, mission_contract, public_board
validation, speech_service, game_content_registry, local_model_gateway.

### Follow-up: in-game editor + base/override safety net
- Added DevPanel tabs (Numpad 7): **Dialogue Content** (quest examples/dummy
  constraints, per mission-type × agent dropdowns) and **Dialogue Rules**
  (global nickname rules + speaker cards). Live "Shiny is Kaelen-only" validation;
  edits blocked if they'd leak Shiny into a non-Kaelen bucket.
- **Base/override split** (Abe's idea): panel edits save to a *delta* file
  `data/content/llm_dialogue_content.override.json`, deep-merged over the trusted
  base at load. Base file is never written by the panel. Malformed override is
  ignored (base still runs). Toggle to flip override on/off live for A/B; Discard
  deletes it. Review = diff base vs override; promote = fold into base + delete.
- Registry gained base_data/override_data/merged data, has_override(),
  set_override_enabled(), discard_override(); save() writes only the delta.
- Tests extended: in-memory mutation + full override lifecycle (save→reload→
  toggle→discard, self-cleaning). parse/mission_contract green.

### Permanent fallback log (Abe: "fallbacks are failures")
- Relocated GenerationDiagnostics' persistent log from user:// into the repo at
  **logs/** (gitignored): `fallback_events.jsonl` (raw), `fallback_summary.json`
  (machine), `fallback_summary.txt` (human-readable, glanceable). Exported builds
  fall back to user:// (res:// read-only there). So "check our fallback status" =
  read logs/fallback_summary.txt.
- Closed two SILENT fallback paths so the log is complete: request_lounge_chatter
  (now logs a specific reason per failure branch) and the content-file-missing
  path in _get_type_examples (logs content_file_missing). Rule going forward: no
  callback.call(fallback_line) without a record_fallback(reason).
- Reason codes split into environment (http/timeout/model_unavailable) vs quality
  (parse/validation/shape) — that split is the fix roadmap. by_reason counts tell
  us what to attack first.
- diagnostics + parse tests green. Log getter is path-agnostic so tests unaffected.

### Ollama cold-start fix (morning follow-up to fallback log)
- Root-caused the first playtest's fallbacks from logs/fallback_events.jsonl: 3 of 4
  hit in the first ~51s, all the SMALL dialogue model (qwen2.5:3b) timing out at
  cold-load (Godot result 13 = TIMEOUT). Campaign_bible's 2 fails were gemma4:12b
  JSON parse (quality, separate).
- Fix 1 — keep_alive: LocalModelGateway.generation_body now sets keep_alive="30m"
  (const MODEL_KEEP_ALIVE) on every request, so models stay resident instead of
  unloading after Ollama's 5min default (also helps the mid-session
  reaction_line_not_ready case).
- Fix 2 — proactive preload: after model discovery, LLMInterface._ollama_warm_models
  fires an empty-prompt /api/generate (done_reason=load) to pull the small model into
  VRAM BEFORE the first dock, then sequences chatter pre-warm behind it. Guarded
  against re-warm. Logs a model_warmup diagnostics event.
- Large model intentionally NOT pre-warmed (its fail was quality not timeout; long
  60s callers absorb a cold load; avoids evicting the small model from VRAM).
- Verified live against running Ollama: warm call returns done_reason=load in 0.2s,
  /api/ps shows the model resident with a ~30min expires_at.
- Tests green: gateway (now asserts keep_alive), parse, mission_contract, diagnostics.
- WATCH next playtest: confirm the first-50s timeouts are gone; the lone
  reaction_line_not_ready at ~11min and gemma4:12b JSON parse are separate follow-ups.

### Procedural campaign architecture pass — N.O.V.A. in the bible, plot armor, no-vacuum ambience (2026-07-04)
- Checkpoint first: commit f5df569, tag `pre-fable-narrative-overhaul` (rollback:
  `git reset --hard pre-fable-narrative-overhaul`).
- New doc `docs/campaign_bible_schema.md` — the enforced bible schema, privacy
  tiers (player-safe vs director-only allowlist), the 3-layer plot-armor
  contract, top-down data flow, and the new-campaign wipe contract.
- **N.O.V.A. joins the campaign bible**: `nova_quirk` (first-person line, player-
  safe — she speaks it verbatim as an occasional arrival/long-dock aside, 7min
  cooldown, per-campaign unique) and `nova_memory_flicker` (director-only
  fragment of her wiped past tied to the mystery; delivery beats still todo).
  Full pipeline: @@labels, aliases, repairs w/ telemetry, migration backfill for
  old saves (no forced regen — factions pattern), seeding into story_state,
  wipe on clear/restart (`Nova.reset_for_restart` added to GameRoot reset chain).
- **Plot armor, 3 layers** (Kaelen + N.O.V.A. can never die/be removed):
  (1) prompt hard constraints; (2) `NarrativeDirector.plot_armor_offense()` —
  narrow death-assertion phrase templates (word-boundary matched, supernova/
  goes-nova masked, Kaelen can still ASSIGN kill work) validated on generated
  bibles AND story-horizon expansions, feeding the correction-retry loop;
  (3) `StoryQuestManager.quest_violates_plot_armor()` — hard runtime wall
  rejecting kill objectives/destroyable spawns naming protected cast, logged
  via GenerationDiagnostics.
- **Narrative Relevance Rule (no line in a vacuum)**: new
  `StoryManager.get_ambient_flavor_block()` — compact player-safe block (tone,
  core pressure, humor rule, lead tension, foreshadow, latest known truth) now
  injected into `fetch_chatter_background` (taunts/death cries/salvager banter)
  and `request_lounge_chatter`; UIManager greeting/faction/trouble canned topics
  + bartender press gained story-anchored variants; lounge rumor Echo weight
  scales with chapter so late-campaign dock talk audibly catches up to what the
  player has uncovered.
- **Test harness bug found + fixed (pre-existing)**: suites that `const preload`
  autoload-referencing scripts (StoryManager, Nova) cached a FAILED compile in
  --script mode and printed PASS with zero assertions (verified vacuous at the
  checkpoint too). Fixed via runtime `load()` after autoloads register + loud
  quit(1) if compile fails: seed/hook/nova suites now genuinely execute. Other
  suites may share the flaw — flagged for a follow-up audit. New
  `tests/parse_check_scene_scripts.gd` compile-checks UIManager/GameRoot/etc.
- Tests green (real passes, serial, unique --log-file): narrative_director (+
  plot-armor + nova cases), campaign_bible_store, story_state_bible_seed (+
  nova seed/privacy/wipe), story_manager_hooks (+ quest plot-armor guard),
  nova (+ quirk lifecycle), parse_check, parse_check_scene_scripts.

### Follow-up same day — the two dark narrative features now fire (2026-07-04)
- **Kaelen's hint plan was generated but NEVER delivered** — `deliver_next_kaelen_hint()`
  had zero callers since Phase D landed. Now wired: `get_lounge_rumor()` offers the
  next hint as a top-weight (5) "Something About Kaelen" observation from the lounge
  contact ("<npc> glances toward the broker's corner..."), paced at most ONE hint per
  chapter; the hidden→delivered pop happens in `record_lounge_rumor_heard()` only when
  the player actually hears it, and nudges `_update_kaelen_mood()` — so she reads
  progressively more slippable as the campaign uncovers her.
- **N.O.V.A. memory-flicker delivery** (todo item from this morning): new
  `nova_glitch` capability (large_story profile — the prompt carries the director-only
  flicker, so it must never run on the small model). One request per campaign at
  `_on_llm_ready` writes 4 first-person gate-transit glitch lines (sensation/almost-
  memory only, no facts); `StoryManager.glitch_line_leaks_flicker()` rejects any line
  sharing a long distinctive word with the flicker (gate/memory vocabulary allowlisted);
  kept lines persist in `story_state.nova_glitch_hints` and interleave with her stock
  gate-flinch lines (~40% share). Failure path: retry once, then stock lines + logged
  diagnostics event — absence, not canned filler; retries naturally next session.
- Wipe contract extended: glitch lines cleared in `Nova.reset_for_restart()` and
  `clear_story_state()`.
- Tests green (real passes): seed suite (+ hint pacing + leak guard cases), nova
  (+ glitch lifecycle), gateway (capability map), story hooks, scene parse check.

### Stuck-at-35% campaign generation — root cause + fix (2026-07-04)
- SYMPTOM: new campaign hangs at 35% "Writing campaign story with large story
  model"; fallback log showed EVERY small-model call also timing out (mechanic
  8s, quest gen 45s, salvager ~100s).
- ROOT CAUSE: not the qwen3 wiring, not Ollama being down. Ollama 0.31.1 loads a
  model at its FULL trained context when the request omits num_ctx — and the game
  never sent num_ctx. qwen3's trained context is 262144, so qwen3:4b (a 2.3GB
  model) loaded as a 43GB allocation, 66% spilled to CPU (ollama ps: "43 GB,
  66%/34% CPU/GPU, CONTEXT 262144" on a 16GB 5060 Ti). Every small generation
  crawled → timeouts; and qwen3:8b could never fit beside it → the campaign-bible
  request queued forever behind a model pinned resident for 30min → 35% deadlock.
- FIX: explicit context pinned per profile in LocalModelGateway.generation_body —
  SMALL_NUM_CTX=8192, LARGE_NUM_CTX=16384 — plus the 4 raw-payload sites that
  bypass generation_body (warmup probe, handoff batch, foreshadow, kaelen mood).
  Caller-supplied num_ctx is deliberately ignored (one odd value = full reload).
  Gateway test asserts all three behaviors so this can't silently regress.
- VERIFIED LIVE: after eviction, qwen3:4b@8k = 3.9GB 100% GPU (4.5s), qwen3:8b@16k
  = 7.5GB 100% GPU cold load 7.8s, BOTH resident simultaneously — vs 300s+ never
  loading before. Restart the game; campaign gen should now clear 35% in seconds.
- Budget check: bible prompt + labeled output fits comfortably in 16k; quest-gen
  prompt (biggest small-model prompt: examples + bible + story state) fits in 8k.
  If a future prompt grows past these, raise the profile const — do NOT per-call.

### Phase E landed — the world now talks to itself (2026-07-04, dedicated session)
- Checkpoint tag: `pre-phase-e-ambient-chat` (rollback: git reset --hard <tag>).
- New autoload `AmbientChat` (scripts/story/AmbientChatGenerator.gd), per
  docs/design_narrative_system.md §7: every 3-5 min of open play, two named
  station locals (8 archetype pools: hauler captain, dock controller, customs
  clerk, cafeteria cook...) have a 2-4 line conversation in system chat.
- Bucket roll per beat: 50% mundane (24-subject pool — sock-eating laundry
  cyclers, form 77-C in triplicate, the horoscope printer that only prints bad
  omens), 30% story-adjacent (active tension / foreshadow / uncovered truths),
  20% overheard intel (pending hooks as half-heard fragments — "at least one
  detail wrong or disputed between them").
- Privacy: candidates read ONLY player-safe story-state keys; test suite feeds
  a state salted with SECRET_* tokens in every director-only field and asserts
  none can surface. Flavor comes from get_ambient_flavor_block() (already safe).
- used_topics: per-chapter retirement in story_state.ambient_used_topics
  (advance_chapter clears; capped 48). Story/intel exhaustion falls back to
  mundane; full mundane exhaustion allows reuse over silence.
- Delivery: staggered 2.4-4.2s line gaps, two muted speaker colors, mid-convo
  abort on dock/combat/restart (reads as the channel drifting out of range).
- Fallback policy: generation/shape failure = silence + GenerationDiagnostics
  event ("fallbacks are failures" — no canned filler). Single-voice responses
  rejected (a monologue is not a conversation).
- Wiring: ambient_chat capability (small profile, 14s timeout), project.godot
  autoload, GameRoot reset chain, DevPanel "Fire Ambient Chat" action button.
- Tests green: new run_ambient_chat_tests (buckets, privacy, dedup, prompt,
  parser, chapter bookkeeping) + parse_check, seed, hooks, gateway all EXIT 0.

### Phase E follow-up — protocol hardened by live-firing the real model (2026-07-04)
- Live-fired the actual build_prompt() output against qwen3:4b (probe tool:
  tests/tools/print_ambient_prompts.gd + shell). Two failure modes found that
  unit tests could never catch:
  1. NESTED json ({"lines":[{...},{...}]}): corrupted the second speaker
     object in 3/3 runs (garbage keys, placeholder rambling).
  2. Freeform labeled lines (no format:json): model narrates its PLANNING
     instead of answering, 6/6 runs, even with think:false.
- Fix: FLAT four-key json under format:"json" — {"a1","b1","a2","b2"} — the
  same flat-fields lesson as the campaign bible's @@labels. 6/6 valid after.
- Residual artifact handled in code: model sometimes self-tags lines
  ("Ivet: ...", "Ivet, dock controller: '...'", truncated "Sk: ...").
  _strip_speaker_prefix removes own-name/slot labels + unwraps quoted lines;
  addressing the OTHER speaker is preserved as real dialogue. Prompt also now
  forbids self-tagging.
- Sample of what players will overhear (mundane bucket, real model output):
  "Another one of these double-vending machines broke on the pier." /
  "Ran a tug through it. Now it's just giving quarters."
- run_ambient_chat_tests updated for the flat protocol + live-fired self-tag
  variants; all suites green.

### Story screenshots — capture core + first three triggers (2026-07-04)
- New StoryScreenshots.gd: silent frame grabs at narrative moments, saved to
  <campaign>/screenshots/<unix>_<tag>.png (beside the save, so the future
  closure-PDF generator finds them). frame_post_draw-timed so never half-drawn;
  200-shot cap per campaign (stop, don't rotate — the PDF wants the whole arc).
- Triggers wired in StoryManager: campaign_start (bible seed), chapter_N
  (advance), hook_resolved (only when it's NOT the chapter's last hook — the
  chapter shot covers that moment).
- Two engine gotchas found by the test suite: (1) root.get_viewport() is NULL —
  the root Window IS the viewport, cast it; (2) a never-firing frame_post_draw
  connection in headless dangles into shutdown and crashes at exit (0xC0000005)
  — headless now returns early from both entry points.
- Remaining triggers (first system jump, boss kill, first dock, kill cinematic)
  live in GameRoot/CombatManager and are logged in todo.
- Tests: run_story_screenshot_tests + hooks/seed/scene-parse all EXIT 0.

### Lounge Social Layer L1-L4 — the bar is a place now (2026-07-05)
- Plan-first session (18% weekly budget): docs/plan_lounge_social_layer.md is
  the hand-off doc — phases, exact seams, house rules — written and committed
  BEFORE code so any smaller model can continue. Tag: pre-lounge-social-layer.
- L1 two-way conversations: LoungeConversation.gd (flat line/r1/r2/r3 JSON,
  parse_turn, transcript capping) + shared _request_small_inner_text transport
  (lounge_chat capability, 12s). Card press = opener + reply buttons on the
  existing dock-message choices row + always-available "(nod and leave)".
  Up to 3 NPC turns, wind-down instructed at the end. Completing a chat with
  a faction contact: +1.0 rep, once per contact per dock. Failure falls back
  to the old one-liner path, logged.
- L2 buy them a drink: 20cr, once per contact per dock; persistent warmth
  0..3 per contact (story_state.lounge_warmth, capped 64); warmth warms
  openers via prompt context and raises approach odds.
- L3 wants-a-word: one contact per dock may seek the player out (12% +4%/
  warmth, 45-min cooldown stamp) — amber "wants a word" card badge; opener
  priority: unhinted story hook as personal tip (consumes it via rumor dedup)
  > personal beat at warmth 2+ > odd station observation.
- L4 the stranger: 6%/90-min rare temp card, exclusive with L3, never in the
  start system. LLM only writes the pitch; the deal is code (intel|goods,
  chapter-scaled ask, 35% scam, one haggle, 10% walk-away sweetener). Goods
  fence 1.6x, intel appends a pending story hook, scams sting dryly. All
  outcomes via record_player_choice + diagnostics.
- Gotchas hit: fresh class_name not visible headless (use preload consts —
  fixed LoungeConversation refs); PS5.1 mangles embedded double quotes in
  git commit -m here-strings (avoid them).
- Tests: run_lounge_conversation_tests (new) + lounge/hooks/gateway/ambient/
  seed/scene-parse all EXIT 0. L5 (real quest side-jobs, heat-bar UI) parked
  in the plan doc.

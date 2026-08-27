# While You Was Sleeping — Session Changelog

---

## Session: 2026-07-28 (Quiet-Moment Curated Banks) — Codex
**Branch:** `segment-3/economy-stores-events`
**Status:** Uncommitted; content and sampler foundation are ready for the owner's review batch.

### Goal and implementation boundary
- Curate 30 **semantic-premise-distinct** `quiet_moment` references for each Kaelen and N.O.V.A. They are prompt rhythm/idea references, never canned player output.
- The prompt sampler selects only three examples at a time. With 30 uniquely tagged entries, `C(30,3) = 4,060` unordered reference combinations before a repeat. Runtime persistence of the combination index is intentionally deferred until the owner approves generation samples.
- Curated lines are protected from copying: exact matches and five-word overlap runs are rejected before presentation.

### What the live local LLM taught us
- A loose direct prompt can restate instructions rather than make a line. Strict `response_format: json` with a one-field inner schema fixed structural compliance.
- Kaelen failure patterns: Earth-calendar language (for example “Tuesday”), invented unnamed crew, invented next offers, generic endings such as “no drama,” and copying a supplied reference.
- N.O.V.A. failure patterns: invented Captain safety/breathing/comms facts, unasked directives (“let's move”), repeated “hull stable / no pursuit / no alarms,” and copying a supplied reference.
- Broad, semantically varied references are necessary. A trial using only a couple of narrow premises caused obvious mode collapse even though individual outputs followed the broad voice.
- A 10-per-character small-model probe did **not** clear human review: Kaelen repeatedly invented coffee/fees/prior jobs or used “no surprises”; N.O.V.A. repeatedly invented 98% hull values, safety, threats, or “systems nominal.” Tightening negative wording did not materially improve compliance.
- A one-per-character 8B probe also failed: it introduced an unsupported ceiling/no-alarms claim and copied a supplied reference phrase. Model size alone is not the safety fix.
- A fact-prefix prototype removed the model's access to numeric/mechanical facts but the small model still repeated the prefix verbatim and assumed the Captain's gender. Treat this as experimental probe code only, not runtime design.
- Design conclusion: any future live quiet-moment path must validate, retry only when useful, and otherwise choose silence or a code-owned approved fallback. Never surface a raw draft merely because it is valid JSON.

### Current artifacts
- `data/content/fixed_cast_voice_examples.json`: 30 Kaelen + 30 N.O.V.A. `evergreen/quiet_moment` lines, all tagged with distinct `semantic_premise_tag` values.
- `scripts/story/FixedCastVoiceBank.gd`: small style-slice sampler, tag exclusion, deterministic combination selection, combination count, and copy detection.
- `scripts/story/QuietMomentLineValidator.gd`: deterministic prototype guard against the observed live-model errors; not yet wired into a gameplay quiet-moment trigger.
- `data/content/fixed_cast_souls.json`: explicit quiet-moment must/must-not rules for each character.
- `tests/tools/run_quiet_moment_live_probe.gd`: serial local-LLM probe; do not run parallel Godot tests.

### Next owner-facing step
Run one fresh **10-line generated batch per character** with three varied curated references per request, review it for voice, fact invention, copying, and repetition. Iterate the prompt/validator only if that batch exposes a real failure mode. Do not build the actual runtime ambient trigger until the batch is approved.

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

### Story screenshots complete — all seven triggers live (2026-07-05)
- Finished the PARTIAL item (plan: docs/plan_screenshot_triggers.md, tag
  pre-screenshot-triggers). New triggers, all in StoryManager:
  - system_first_visit_<id>: on_system_arrived + screenshot_systems_seen list
    (campaign-load arrival excluded — campaign_start shot covers it)
  - station_first_dock: on_docked + screenshot_stations_seen (node name key)
  - kill_cinematic: lethal CombatManager.action_impact (the execute-camera
    frame), rate-limited 10 real minutes
  - boss_kill: same signal, is_boss targets always capture
- _first_visit_and_record helper is viewport-free and unit-tested (dedup,
  empty-id, 64-entry cap) in run_story_manager_hook_tests.
- hooks/seed/shots/parse suites all EXIT 0.

### L5a — agents in the lounge now read the ledger (2026-07-05)
- LoungeConversation.agent_disposition(rep): pure, code-owned numbers.
  Sworn enemy = refused outright (template line, no LLM, no rep change).
  hostile/unfriendly = talkable but cold, completion +2.0 (hard-won).
  wary..cordial = +1.5, lead 15%. friendly+ = +1.0, lead 30%, bail -0.25.
- Disposition context_line joins the agent's conversation prompt so the model
  plays the actual relationship instead of generic politeness.
- Completion lead: first unhinted pending hook, slipped as a discreet aside
  3s after the goodbye, marked heard via the shared rumor dedup.
- Walking out on an agent's OPENER: bail_rep hit + contact cold for the dock
  (_lounge_cold_contacts, cleared on fresh dock) + a dry consequence line.
- Agent cards gained rep_key (faction_key minus prefix) for rep lookups.
- Tests: agent_disposition tier table in run_lounge_conversation_tests;
  lounge/scene/parse suites EXIT 0.

### Tutorial: hold enemy opening taunt until N.O.V.A. finishes (2026-07-05)
- Bug: on the first-ever fight, the enemy's opening taunt fired while N.O.V.A.'s
  combat-tutorial line was still playing, cutting her off.
- Fix: CombatManager.hold_opening_taunt() / release_opening_taunt() — UIManager
  holds the taunt when it shows the one-time tutorial popup
  (_maybe_show_combat_tutorial) and releases it on the GOT IT close button. A
  taunt that tries to fire while held is queued (_opening_taunt_pending) and
  flushed on release.
- Race-free by construction: the hold is set synchronously inside the
  combat_started emission, which precedes the async taunt fetch + first
  planning phase where _play_combat_taunt runs. Flags reset in
  _reset_fight_state (before that emission). Reopening the popup from the pause
  menu calls release harmlessly (no-op when nothing held). Tag:
  pre-tutorial-taunt-hold.

### Stuck-at-35% (recurrence) — evict VRAM before bible generation (2026-07-05)
- Same symptom as the num_ctx bug, different root cause. That fix (pinned
  num_ctx) is still working — qwen3:4b loads at 8192 fine. But: the startup
  combat-taunt fetch loads qwen3:4b into VRAM BEFORE campaign_bible_priority
  activates (so the priority-deferral can't stop it — the model's already
  resident). On a 16GB card, 4b (3.6GB) + Godot rendering (~2.3GB) leaves too
  little for the 8B story model, so Ollama spills 8B layers to CPU and the
  bible request times out. Proven: 8B alone = 6.4s; 8B with 4b+game resident
  = >180s timeout.
- Fix (user's call): before generating the bible, evict BOTH models
  (keep_alive:0) so the 8B model reloads into a clean GPU.
  LLMInterface._evict_models_then([small, large], fire) wraps the bible send
  in a closure fired only after eviction completes. Logs a
  vram_cleared_for_generation diagnostics event. Small model warms back up
  after the bible gate releases (existing behavior). Tag:
  pre-tutorial-taunt-hold covers this too (same session; also see
  pre-screenshot-triggers).
- Verified live: 4b resident -> evict both -> 8B fresh = 2.4s (vs timeout).

### Intro cinematic — the thrown-through cold open (2026-07-05)
- Plan + living checklist: docs/plan_intro_cinematic.md (tag
  pre-intro-cinematic). New campaign only: after the loading panel fades,
  instead of scheduling Kaelen directly, UIManager spawns IntroCinematic.
- Sequence (no UI, no control): violent gate tumble w/ new
  shaders/intro_glitch.gdshader (screen-tear bands + chromatic aberration +
  white-out, one intensity uniform) + full-axis ship spin (camera rides the
  ship, so the spin sells it); N.O.V.A.'s first-ever line lands mid-crisis
  ("ONE last thing I can try!"); white-flash FLING; reveal shows the ship
  thrown INTO the system (no gate); hull set to 40%; her amnesia beat ("my
  memory starts fourteen seconds ago"); untraceable data stream wires
  EXACTLY the repair bill (missing_hp * 2.0, mirrors _repair_ship); then UI
  restores and the existing show_kaelen_intro() runs unchanged.
- Safety: SPACE skips (consequences still applied, idempotent _finish), 30s
  watchdog forces restore, load-game path untouched (welcome_back as before).
- Verified: scene parse check green. NOT playtested — feel-tune consts at top
  of IntroCinematic.gd; TTS pacing vs subtitles needs a real run.

### Intro cinematic timing fix — phases were collapsing together (2026-07-05)
- Symptom: the whole thrown-through intro rushed into ~3s instead of ~20s.
- Cause: _beat() used get_tree().create_timer(seconds) and the tweens used
  plain create_tween(), both affected by Engine.time_scale. Combat drives
  time_scale to 0.02x and back (CombatManager); any non-1.0x state makes every
  beat fire near-instantly. Same class of bug the combat code already guards
  against with set_ignore_time_scale(true) + wall-clock timers.
- Fix: _beat now create_timer(s, true, false, true) (ignore_time_scale=true);
  every intro tween (spin/flicker/reveal/residual/stream/hint) gets
  set_ignore_time_scale(true); watchdog + Kaelen-handoff timers too. Phases now
  last real wall-clock seconds regardless of engine time scale. Parse green.
  Still needs a real playtest to feel-tune the per-phase durations.

## Session 2026-07-13 (living narrative: Phase 7 exit gate + Phase 8A start)

### Kaelen reaction bundle save/reload exit gate -- PROVEN (a9408e2)
- New tests/persistence/run_kaelen_reaction_bundle_persistence_tests.gd runs
  the real pipeline end to end: accept_quest -> store acceptance-time Kaelen
  bundle -> capture_all_quests -> SaveMigrator.prepare_for_save -> JSON on
  disk -> load_for_runtime -> restore_all_quests (reset_for_restart between,
  simulating app restart) -> deliver_partial completes objective ->
  quest_objective_completed_details snapshot refreshes the bundle ->
  turn-in reads the refreshed contextual line before complete_quest.
- Also proves a stale runtime id cannot clobber a restored bundle.
- Phase 7 exit gate "save after accepting, reload, complete, turn in"
  checked in the plan with this evidence. The two remaining Phase 7 gates
  (3 causes -> 3 distinct reactions; 50 turn-ins w/o stock line) need live
  LLM gameplay runs -- intentionally left unchecked.
- Found pre-existing: EVERY complete_quest() warns
  "[MissionInstance] Invalid transition: ACTIVE -> COMPLETED" because
  nothing ever transitions instances to READY_TO_TURN_IN. Harmless (the
  instance is removed right after) but noisy; flagged as a spawn-task chip.

### Phase 8A slices 1-3: semantic movement events (70a5c7d, 88b77ee, 11337e4)
- scripts/story/ShipMovementEvents.gd: registry of 12 raw event ids.
- GlobalState.ship_movement_event + emit_ship_movement_event() validates ids.
- PlayerShip emits: boost activated/rejected (with reason), autopilot
  started/retargeted/cancelled (mode + safe target category), evasive
  maneuver, stall route replans, severe hull impact (single hit >= 10% max
  hull). Dock/undock emit from the is_docked setter -- single choke point
  for all 9 GameRoot/UIManager assignment sites.
- GameRoot emits gate_departure/system_arrival around the jump transition
  and spawns ShipBehaviorObserver in _ready.
- scripts/story/ShipBehaviorObserver.gd aggregates raw events into
  boost_again_quickly / changed_mind_again / returned_to_same_station /
  clean_long_transit / rough_arrival with tunable windows; time is injected
  through observe() so tests are deterministic. Rate limits: 30s global
  spacing + 180s per-event cooldown; suppressed events still update state;
  state_snapshot() lets N.O.V.A. read instead of being pushed.
- Tests: tests/story/run_ship_movement_event_tests.gd,
  tests/story/run_ship_behavior_observer_tests.gd. Parse check green after
  every slice.
- NOT done yet (next in 8A): safe context enrichment (mission beat, hull
  band, new/returning system, route deviation) on semantic events, then
  Phase 8B campaign-aware line banks. Nothing consumes
  semantic_movement_event yet -- Nova wiring comes with 8B.
- Headless note: AudioManager.play_sfx errors out-of-bounds in headless if
  a bare PlayerShip calls play_align; the movement-event test avoids the
  boost success path behaviorally for that reason (source-level checked).

### Phase 8A slices 4-5 addendum (acedafe, ce03b5e)
- Safe context now stamped on every semantic event: recent_actions streak
  (last 6 raw event ids) + injectable context_provider merged without
  overwriting event fields. GameRoot supplies the live provider: hull band
  (healthy/worn/critical), active mission public beat (title + objective
  type), new/returning system, route_deviation
  (no_mission / in_mission_system / off_mission_system).
- Model-call tripwire: observer test audits ShipMovementEvents.gd and
  ShipBehaviorObserver.gd for any LLMInterface/Ollama/http reference.
- Phase 8A status: checkboxes 1-4 checked with evidence; checkbox 5
  (movement only consumes prepared line banks) tripwired but left
  unchecked until Phase 8B wires Nova consumption.
- Correction to the entry above: safe context enrichment IS done; the next
  work is Phase 8B (campaign-aware line banks + Nova consuming
  semantic_movement_event through severity/preemption/cooldown rules).
- PowerShell note: git commit -m here-strings must not contain double
  quotes (PS 5.1 native-arg quoting mangles them into extra pathspecs).

### READY_TO_TURN_IN dead-state fix (spawned task, 2026-07-13)
- Root cause: VALID_TRANSITIONS required ACTIVE -> READY_TO_TURN_IN ->
  COMPLETED but nothing ever set READY_TO_TURN_IN, so every completion
  (and the comms accept_bribe resolution) warned Invalid transition and
  removed the instance still ACTIVE.
- Fix: _mark_objective_ready_if_completed transitions the instance to
  READY_TO_TURN_IN at objective completion (READY -> ACTIVE remains valid
  if a future capability regresses); complete_quest and accept_bribe go
  through _transition_to_completed(), which hops via READY_TO_TURN_IN when
  the instance is still ACTIVE (pre-fix saves, paths that skip progress);
  READY_TO_TURN_IN -> EXPIRED added so timed contracts can expire while
  awaiting hand-in (_cleanup path at QuestManager check_active_quest_expiration).
- Proven: new tests/domain/run_mission_state_transition_tests.gd (unit
  transition rules, dict round trip, accept -> deliver -> READY -> real
  SaveMigrator save/reload -> still READY -> complete_quest lands
  COMPLETED, timed expire from READY lands EXPIRED). Regressions green:
  timed missions, Kaelen bundle persistence (its earlier Invalid
  transition warning is now gone from the output), comms reversal,
  mission contract, mission history revision, parse check.
- bugs.md entry moved from Active to Fixed.

## Session 2026-07-13 (continued): Phase 8B line banks
- ce3b12b NovaLineBankCategories: 5 movement semantics + system_arrival
  (legacy startup_navigation accepted), gate_transit, gate_glitch
  (protected), hull_critical, welcome_back, docked, 3 combat-end beats.
- cf02e65 Global speech budget in Nova.speak(): 3 casual lines / 2 min,
  15s min gap; COMBAT/THREAT bypass but still count. reset wipes ledger.
- 3be1175 GameRoot routes semantic_movement_event -> Nova; movement
  consumes prepared bank lines only, silence otherwise. Phase 8A gate 5
  (never call a model on movement) checked with tripwires.
- 932c582 Silence tests: 6 instant docks = exactly 1 line.
- aec16ee FallbackLineBank retirement ledger: consumed text fingerprints
  persist; replace_used_with_generated refuses retired texts forever.
- 121997a Low-bank refill: consume at <=3 unused queues
  line_bank_low_refill (deduped); worker refills used slots via
  replace_used_cached_fallback_lines. Template content until batch gen.
- e9c7532 Protected glitch bank on consumption: _line_kind_allowed
  refuses protected kinds without an explicit filter; burned > leaked.
- 4df36f1 Stock pools demoted: all flat-pool beats bank-first via
  _bank_line_or_stock; stock draws logged as nova_line_bank /
  stock_line_used. Tutorial stays authored; dock tier ladder kept.
- Remaining Phase 8B: batch generation (6-10 field flat batches, per-line
  validation) + the persona/quirk/system-tone prompt (do together; use
  the labeled_field @@label approach per project_labeled_field_generation
  memory), then relevance scoring (needs generated lines tagged
  mission-aware, so it comes after generation).

## Session 2026-07-13 (continued 2): Phase 8B completed
- 0aa732b FallbackLineBank accepts {kind, text} generated entries so one
  batch spans several categories.
- 6dbcfdb LLMInterface.request_nova_line_bank_batch: flat @@label batches
  (max 10 fields), small model (nova_line_bank capability, 30s timeout),
  per-line validation (length/speaker-prefix/braces/dupes), pure parser +
  validator proven headless in tests/ai/run_nova_line_bank_batch_tests.gd.
- 11fea48 Refill worker dispatches an 8-field batch (5 movement semantics
  + 3 arrivals) with persona/quirk/bible-tone/system-fact/recent-actions
  context; template floor on failure, logged template_refill_used.
- 128e419 Relevance scoring: consume(prefer_generated) serves story-aware
  generated lines before template jokes; Nova sets it when the movement
  context shows a live mission beat.
- ALL Phase 8B checkboxes now checked. Phase 8 exit gates: pattern
  recognition checked (structural + tests); the other three (scripted
  flight no-repeat, knowledge audit of generated output, instant with
  model stopped) need a live gameplay smoke run.
- NOTE for the smoke run: the nova_line_bank batch has never run against
  live Ollama — verify @@label format compliance on qwen3 small and check
  GenerationDiagnostics for all_lines_rejected / template_refill_used.

## Session 2026-07-13 (continued 3): Phase 9 protocol slices
- 88ae1ab LoungeConversation bundle protocol: build_bundle_prompt carries
  2-3 code-approved {id,text} player intents verbatim (model never writes
  the player side); flat {opener, a1..aN, close} JSON; parse_bundle
  degrades bad/duplicate answer slots to "" per-slot, rejects bundles
  with no valid answers.
- fa17aa6 LoungeIntentSelector: code-owned player questions from RUMORED
  knowledge gaps only (player can only ask about what they heard),
  delivered rumors, current mission stake, warm-contact callback;
  generic friendly/pushback/odd filler pads to the 2-minimum only.
- c1e4dfe Answer relevance: intents carry anchor_tokens from the phrase
  each question was built on; validate_bundle_answers degrades answers
  missing every anchor or containing meta markers.
- NEXT (Phase 9 remaining): UIManager runtime wiring — replace per-reply
  build_reply_prompt calls with bundle consumption; single-reply +
  cached-second-bundle "keep talking"; flight-time bundle caching with
  pending card state; rumor marked heard only on display (fix the
  approach-path early-mark bug); NPC stance/facts into structured memory;
  stable NPC IDs for warmth keys; mission-beat hooks by fact ID; stranger
  deal contracts. All in UIManager lounge section + KnowledgeLedger.

## Session 2026-07-13 (continued 4): Phase 9 slices 4-8
- 61a2fe7 Hook-heard-on-display fix: _lounge_approach_instruction stashes
  pending_hook_id; _on_lounge_turn_result records it only after the opener
  displays. Failed turns leave the hook available for retry.
- 6bcb8fa Stable NPC IDs: _apply_lounge_completion falls back to
  _stable_lounge_contact_key (was raw display name); agent lead marked
  heard inside the 3s display callback (undock no longer burns it).
  Warmth + cold contacts were already stable-keyed.
- 47cc467 Refusal tripwire: agent_disposition owns refusal + rep numbers;
  test fails if refusal check moves after the model call.
- 4a6f1a7 NPC lounge memory: CampaignNpcStateStore.record_lounge_conversation
  (stance -> relationship.last_player_stance; bounded lounge_exchanges<=8,
  lounge_fact_ids<=24, invalid IDs skipped). GameRoot bridge maps contact
  keys into the npc namespace (lounge.agent.zenith -> npc.lounge.agent.zenith).
  _lounge_convo.learned_fact_ids is the hook the bundle display will fill.
- c86a866 Bundle transport: request_lounge_exchange_bundle, small model,
  lounge_bundle capability (25s / 520 tokens).
- Phase 9 checked so far: intent selection, answer validation, rumor-heard
  fix, NPC memory, stable IDs, refusal. Checkbox 1 (bundle protocol) has
  protocol + transport landed but stays UNCHECKED until UIManager consumes
  bundles at runtime.
- REMAINING Phase 9: UIManager runtime bundle consumption (replace
  per-reply build_reply_prompt flow), single-reply + cached second bundle
  keep-talking, flight-time bundle caching with pending card state,
  mission-beat hooks by fact/beat ID, stranger deal contracts. Then the
  exit gates (instant replies with Ollama stopped, 50/50 fixtures, no
  reset opener on return).

## Session 2026-07-13 (continued 5): Phase 9 runtime landed
- 73371aa Stranger intel -> real fact ID: record_stranger_intel_fact
  promotes fact.stranger_intel.* to RUMORED with public_text + alias
  (also makes the tip an askable lounge question). Free-form
  pending_hooks append is gone.
- 6a7142a Stranger deal tripwires: roll/resolution never touch the model;
  pitch prompt reads no story_state outside _lounge_flavor_block.
- d78a95e Bundle preparation: lounge render fires background bundle
  requests per contact card (kinds npc/agent/bartender; Kaelen/stranger/
  planted keep their own machinery). Intents from LoungeIntentSelector
  (rumored gaps + mission stake + warmth); results run parse_bundle +
  validate_bundle_answers; cached per stable contact key in
  _lounge_bundle_cache, reset each dock; failures logged lounge_bundle.
- be8bad6 Bundle consumption: _start_lounge_conversation prefers a ready
  bundle — instant opener + intent buttons, intent press shows prepared
  answer then close, ZERO model requests (tripwired). Degraded slots
  never offered; gap: intents record learned_fact_ids consumed by the
  NPC-memory write at completion. Live per-turn flow = fallback.
- 77ed6ec Keep talking: consuming a bundle preps the second immediately;
  warmth >= 2 contacts get the button only when it is already ready.
- Phase 9: 10 of 11 checkboxes done. Remaining: flight-time prefetch +
  card pending indicator (partial note in plan). Exit gates need a live
  run: instant replies with Ollama stopped after prep, 50/50 fixtures
  vs real-model batch review, returning-NPC memory-aware exchange.
- NOTE for live smoke: the lounge_bundle capability has never fired
  against real qwen3 — watch GenerationDiagnostics for lounge_bundle
  fallbacks and verify the flat 5-key JSON holds up.

## 2026-07-29 — Quiet-moment LLM research (paused for PC repair)

- Reviewed the quiet-moment LLM block documented in
  `docs/quiet_moment_llm_research_log.md`. The log's diagnosis ("the model
  invents facts") was wrong. Three prompt-side causes, all measured:
  - `FixedCastSoulRegistry.prompt_block()` emits `public_board_money_rule`
    unconditionally, so every Kaelen prompt CONTAINED the broker fee the log
    recorded as invention. Board/fee mentions 5/8 with the line, 1/8 without.
  - Prompt ban lists primed the banned words. "Do not invent ... coffee"
    produced coffee 5/10 in the log, 2/6 in my repro, 0/16 once deleted.
  - The 30 curated examples demonstrate unanchored idle observations, NOT the
    fact-packet -> line transform actually being asked for. Copying was the
    symptom of that mismatch, at 4b, 8b and 14b alike.
- Fixing the few-shot to demonstrate the real transform: Kaelen 0/10 -> 11/12
  fact-clean on qwen3:4b. `qwen3.6:35b-a3b` (MoE, 3B active) reaches
  publishable voice at 3.0s warm, 7/8 clean. qwen3:8b is WORSE than 4b.
- Opener mode-collapse fixed code-side, not prompt-side: rotating the
  code-owned fact-packet wording took distinct openers from 1/10 to 10/10.
  Prompt-side "vary the shape" instructions could not beat the attractor.
- Voice work with the author: Kaelen is mercenary and candid about her own cut
  (risk<->pay), NOT the zen broker the model defaults to; and "she isn't cold,
  just wants her money" -- the complaint targets the job/rate/client, never the
  Captain. That axis change moved shippable output ~2/10 -> ~6/10.
- NOTE: `QuietMomentLineValidator._contains_any()` uses substring matching --
  "fee" matches "feel", "use " matches "because ", "ready" matches "already".
  It flags 26 of the project's own 30 curated Kaelen lines. Not yet fixed.
- NOTE: in Ollama `format:"json"`, any `Label:` in the prompt becomes a JSON
  key. Few-shot demos written as `FACTS:`/`LINE:` returned `{"facts": [...]}`
  and looked like parse failures. Do not combine with the `@@label` technique.
- Paused mid-way through voice tuning. Working state, current best config (V5),
  reproducible harness and raw outputs: `docs/research/quiet_moment/RESUME.md`.
  No production code changed; findings only.

## 2026-08-01 (later) — Quiet-moment beat build-out

- Built NINE beats on a new data-driven definition (`beat.py`: who / register /
  valence / packets / demos), all measured on qwen3:14b at ~3.0s:
  Kaelen low_pay_safe, high_pay_dangerous, public_board, abandoned;
  N.O.V.A. post_combat_damaged, repair_done, long_transit, cargo_full,
  rough_arrival. Most run 19-20/20 clean. Research only; nothing wired
  into Godot yet. Handoff: `docs/research/quiet_moment/SYSTEM.md`.
- Selector tuned: opener_window 8->5 with max_calls 5 gives 12% silence
  (author's target ~10%), 2.2 calls/moment, ZERO duplicates over 24 firings.
- Author gave three voice corrections that reshaped N.O.V.A.: she needs dry
  humour, she's subtly flirting, and the canon examples ("dust my intakes",
  "hands up my manifold... owe me dinner first", "filled up to my larynx, or
  at least my vocal processor"). Ship-as-body, self-undercutting retraction,
  and deniable double entendre are now her three signature moves.
- KEY: the anatomy slip is enforced in CODE (`anatomy.py`), not prompted.
  If she uses a human body word, code appends the machine correction. The
  model was unreliable at the two-part structure and produced machine-to-
  machine ("stuffed to the bulkheads, or at least the cargo hold").
- New deterministic checks: packet_echo, demo_echo, wrong_address,
  generic_praise, invented_number. Two bugs in my own checks worth
  remembering: models emit U+2019 apostrophes so ASCII regexes silently
  miss them, and a `\b` written through a shell heredoc becomes a literal
  backspace. Write regexes in an editor.
- `diagnose.py` (local, no LLM) reproduced the manual diagnoses on
  historical batches and worked COLD on N.O.V.A. with no changes.
- Author listened to rendered audio and confirmed the text-level accept and
  reject decisions hold up spoken. 49 WAVs in
  `.tmp_godot_user/quiet_moment_audio/session_2026_08_01/` with INDEX.txt.
- Standing rule proven repeatedly: fix diversity/consistency in CODE, never
  by instructing the model. Every prompt-side attempt failed; every
  code-side rotation worked.

## 2026-08-02 (overnight) — Quiet-moment feedback pass + 2 more beats

- Acted on all four pieces of author audio feedback:
  1. "didn't understand one of the words" in kaelen_abandoned_02 -> traced to
     `mid-job`. Hyphenated compounds have no reliable spoken form in Kokoro.
     Added a `tts_risk` screen; applied to the 55-line listening set it
     flagged EXACTLY the one line the author flagged. Beat regenerated.
     Noted in docs/tts_hygiene_notes.md (not yet confirmed by ear).
  2. "all the public board are wrong, the wrong idea was sent" -> correct.
     Rebuilt on CLASS SNOBBERY (trash work beneath both of them, slumming,
     too bougie) instead of professional redundancy. Distinct openers
     3/16 -> 13/16.
  3. "cargo_full_05 is perfect, the rest didn't do well" -> the one that
     worked had no anatomy correction. Curated the ANATOMY map to pairs where
     the machine term is a SURPRISING substitute (larynx->vocal processor
     lands; belly->cargo hold is flat because a hold IS a belly), and steered
     the beat to understatement.
  4. "long transit 01 and 02 are a bit insulting" -> third occurrence of the
     overcorrection pattern. Added an aim-constraint; needling 0/16.
- ELEVEN beats now. Added kaelen_declined and nova_returned_same_station,
  both clean on the FIRST run with no iteration.
- First mixed-beat playthrough sim (recency per CHARACTER, not per beat):
  32/32 served, 0% silence, 1.4 calls/moment, 0 duplicates, 17/17 and 15/15
  distinct openers across beats. Interleaving beats IMPROVES coverage, so the
  single-beat 12% silence figure is a pessimistic bound.
- New checks: brief_echo (model quoted my valence prose back), word_echo
  (same content word 3+ times), tts_risk family.
- Two self-inflicted bugs worth remembering: combining case-sensitive regex
  alternatives under one re.I made [A-Z]{2,} match any two letters and flag
  55/55 GOOD lines; and putting a target line in the brief makes the model
  reproduce it (that caused both the "this is the kind of job" collapse and
  the "and I don't mean the cargo bays" formula).
- 67 WAVs for review in
  `.tmp_godot_user/quiet_moment_audio/MORNING_2026_08_02/` with INDEX.txt
  marking which beats were revised and which are new.
- Still research only. Nothing wired into Godot.

## 2026-08-02 (later) — Quiet moments wired into Godot + methodology skill

- Wrote `skills/skill_llm_character_dialogue.md`: how this was made to work,
  written because the first attempt failed badly enough that switching to
  canned lines looked like the only option. Leads with the three
  misdiagnoses (examples demonstrating the WRONG TASK; ban lists
  manufacturing their own failures; the bible injecting the "invention"),
  then the hook, demos-as-spec, code-side rotation, valence/aim constraints,
  why validation cannot judge quality, and what transfers between characters.
- WIRED INTO GODOT. Live end-to-end run: 22/24 served, 0 duplicates, 22/22
  distinct openers; both declines were nova_hard_burn losing its 25% roll.
  - `data/content/quiet_moment_beats.json` (generated, not transcribed)
  - `QuietMomentChecks.gd` / `QuietMomentBeats.gd` / `QuietMomentSelector.gd`
    / `NovaAnatomySlip.gd` / `QuietMomentDirector.gd`
  - capability `quiet_moment` in LocalModelGateway; request path on
    LLMInterface at temperature 0.9 / top_p 0.95
  - four headless test suites + a live serial soak, all green
- The live run caught three defects, ALL in text we authored ourselves:
  third-person "The Captain" in a valence and two packets (she echoed it back
  while talking TO him), four hyphen compounds in packets, and temperature
  shipped at 0.95 where the research measured 0.9. export_beats.py now
  refuses to ship authored text that fails our own screening.
- STILL TO DO before this is live in a playthrough:
  1. nothing calls `try_fire()` yet — connect the ShipBehaviorObserver and
     QuestManager signals
  2. save/load does not call `to_save_dict()`/`load_from_dict()` — WITHOUT
     THIS THE FRESHNESS GUARANTEE RESETS EVERY RELOAD
  3. call `reset_for_new_campaign()` on new-campaign start
  4. arbitration with lounge chatter and mission dialogue

## 2026-08-02 (final) — In-game wiring + mission-agent personalities

- QUIET MOMENTS NOW FIRE IN GAME. Previously the scripts passed headless but
  nothing instantiated the director, so launching the game produced nothing.
  Wired in GameRoot: ShipBehaviorObserver semantic events, QuestManager
  completion/abandon/decline, combat_ended (gated on hull <=85%, since her
  post-combat beat needs DAMAGE to have material), and cargo_changed on the
  transition into a full hold. Lines route to Nova.speak or Kaelen's flavor
  path. Save/load persists recency; new campaign resets it.
  11 of 12 beats have a real trigger. nova_repair_done has none - there is no
  repair-completion signal in the codebase and inventing one is a gameplay
  decision. Reachable from the DevPanel.
- DevPanel -> Story -> "Quiet Moments": pick a beat, Fire Quiet Moment.
  Ignores cooldown; silences echo to chatter while the panel is open.
- TWO-MODE BEATS: cargo-full always announces "Cargo hold is full" and only
  uses the character line 25% of the time (measured 76/24). Better than
  silencing, because the hold filling is information the player wants every
  time while the joke only stays funny if rare. Three quarters of that beat's
  triggers now cost no model call.
- NOVA's transit flirting was failing because 9 of 12 entries in the detail
  pool had NO sexual second reading ("a film on the forward viewport"). The
  model was being asked to flirt about wiping a window. transit_vocab.py now
  enforces a two-readings rule with a self-audit. NOTE: we never teach the
  model to misuse words - she is always technically accurate; the innuendo is
  loaded into WHICH JOB CODE PICKS.
- NEW: skills/skill_llm_character_dialogue.md - the whole methodology,
  written because the first attempt failed badly enough that canned lines
  looked like the only option.
- NEW: five mission-agent personalities (desperate / old_hand / chancer /
  believer / paranoid). Author approved 4 outright; the weirdo is accepted on
  the basis that the mission card carries the real facts. Research only.
  Handoff: docs/research/quiet_moment/AGENTS.md
- Biggest recurring lesson, now proven a fourth time: every decision moved
  from the model into code improved the output. Latest instance is the
  author's own - let Godot choose WHICH FACTS each personality receives,
  rather than sending all of them and asking the model to be selective.

---

## 2026-08-06 — First-five-minutes affordance pass + Jenna fix

Everything here lands inside the opening five minutes, which is the milestone
Abe named last session. All of it is UI-layer; no gameplay systems changed.
None of it has been playtested yet.

- JENNA'S REPEATED INTRO IS FIXED. The first-visit flag was written by
  _on_maintenance_bay_pressed() — i.e. by a particular BUTTON — while the
  intro is served from _render_mechanic_intro(). N.O.V.A.'s repair prompt
  reaches the same panel without passing through that button, so the flag
  never got written and she reintroduced herself at the next dock. The write
  moved to where the line actually reaches the player. Both known entry
  points and any future third one are now covered by construction; patching
  only the N.O.V.A. path would have fixed the repro and left the trap.
- "ATTACK HOSTILE" IS RANGE-GATED, with hysteresis: enables at 600m, stays
  enabled out to 1200m. One bool on the targeting side, cleared when the
  target changes. Both the target window and the right-click context menu
  route through one writer (_apply_attack_reach) so they cannot disagree.
  Disabled-but-visible with a tooltip, not hidden — a vanishing button reads
  as a bug. Skipped while ATTACK is already the active nav mode: there the
  button reports a running order, and range must not revoke it mid-chase.
- EXECUTE PULSES WHEN THE TURN IS A DEAD END. Derived from every wheel wedge
  being unavailable rather than from AP == 0, so it also covers "AP left but
  nothing costs that little" and "cooldowns/consumables closed the rest".
  Wall-clock tween, like _fade_controls — the planning phase runs in slow-mo
  and a pulse that slowed with it would read as UI lag, not as a prompt.
- COLD-OPEN LOOK PROMPT. New UIManager.show_control_hint/clear_control_hint:
  persistent, softly pulsing, low-centre, NO timeout. The dead air is the
  problem, so a prompt that expires wouldn't solve it. Clears the instant the
  control is used. Polled via Input.is_mouse_button_pressed rather than
  hooked into _input, because the ship's own handler may consume the event.
- CONTROL CORRECTION (settled): the todo said "left mouse button to look
  around". Left mouse is select / double-click-to-move; look-around is HOLD
  RIGHT MOUSE AND DRAG (PlayerShip.gd:946). Abe confirmed right mouse is
  correct and intended — the prompt stands, no rebind wanted.
- FIRST-TURN-IN FLASH. The "return to station button" turned out to be
  quest_tracker_route_btn, relabelled to "Dock at Station" on completion —
  the todo had it as not-yet-located. Flash reuses the same attention pulse
  the intro handhold arrow drives, so there is one flashing treatment in the
  game rather than two that look slightly different. Gated on
  get_completed_count() == 0, which parses quest history off disk, so it is
  read once on the hidden->shown edge and latched.
- NEW: tests/tools/run_parse_check.gd. UIManager is a scene script, not an
  autoload, so no headless suite loads it and --check-only can't be used on
  it (it compiles without a running main loop, so every autoload identifier
  reports as missing). This loads the file from inside a real SceneTree
  instead. Worth running after any edit to a big scene script.
- Green: parse check (4 scripts), Mechanic dialogue, Intro handhold, Campaign
  NPC state store.

## 2026-08-06 (later) — first playtest of the affordance pass, five findings

Abe ran the first five minutes and reported five issues. All five addressed.

- THE FIRST-TURN-IN FLASH NEVER FIRED, and the reason is worth remembering:
  it was gated on QuestManager.get_completed_count() == 0, and that parses
  user://quest_history.md — which is GLOBAL, not per-campaign. On any machine
  that has ever finished a contract it can never read as zero, so the gate was
  dead on arrival for everyone except a fresh install. Replaced with a new
  per-campaign story_state flag, first_contract_handed_in, latched in
  StoryManager.on_quest_completed() so it covers every hand-in path. No disk
  read, so the UI side lost its caching complexity too.
  LESSON: check whether a "have I ever" signal is per-campaign or per-machine
  before gating first-run content on it.
- MISSION CARD NOW HIDES WHILE DOCKED. Everything it offers (set course, dock
  at station) is meaningless or redundant once you are parked, and it overlaps
  the dock menu. Gated in _update_quest_tracker via _tracker_suppressed_by_dock;
  both dock and undock edges re-run the update. Layout edit mode still forces
  it visible for repositioning.
- SPEECH NO LONGER CUTS ITSELF OFF. Two N.O.V.A. lines landed on one event
  (combat ending fires both a post-combat line and a quiet-moment beat) and
  the second truncated the first mid-sentence; same for Kaelen. Root cause:
  SpeechService.play() goes straight to provider.play(), which is a hard cut.
  Added SpeechService.play_ambient() — an "arrived unbidden" lane that queues
  behind whatever is talking (cap 3, drops beyond that rather than stacking a
  stale backlog). _on_npc_flavor_spoken is the one consumer switched over.
  Player-INITIATED speech deliberately still uses play() and still cuts in:
  when you click something, the answer to that click is what you want to hear.
- "KAELEN VOSS" WAS A NAME COLLISION, and a real bug. The salvager profile is
  fully LLM-generated with no constraint on names, so the model welded the
  broker's given name onto the Zenith agent's surname. The chatter feed then
  showed "Kaelen Voss" and "Broker Kaelen" as two different speakers in one
  conversation. Added LLMInterface.name_collides_with_cast() — token matching
  plus an exact match on the punctuation-stripped whole string, so "N.O.V.A."
  is caught too but "Bryn" and "Karyn" are not. Applied at the salvager
  callback, with a prompt constraint as the first line of defence and the
  guard as the second. Also dropped "Caelen Drake" from the fallback name
  list: seeding a near-homophone of Kaelen is the exact confusion we are
  trying to prevent. Guard is unit-tested in run_parse_check.gd.
  Worth applying to every other model-invented character name.
- THE AGENT PANEL WAS A FORM, NOT A CONVERSATION. It rendered
  "Response choice accepted: '...'" and "Agent feedback: '...'" — the UI
  narrating its own mechanics next to Kaelen's portrait — and replayed the
  entire original briefing every time the panel was reopened. Abe's call: she
  should just say something like "oh, you're back". Now a short header plus
  one greeting from _kaelen_return_line(), a 3-pool round-robin (working /
  done / public board, 8/8/4 lines) so returns vary. True round-robin, not
  random: this panel gets opened a lot and random repeats read as broken.
  agent_response was also arriving EMPTY, which is what produced the literal
  '' on screen — that path now logs record_fallback("agent_response",
  "empty_agent_response") instead of rendering empty quotes.
- Also reworded the mission card's "Return to the station and speak with your
  agent" to a settlement line. NOT what Abe was pointing at (he meant the
  agent panel) — flagged to him, trivial to revert if unwanted.
- Green: parse check (8 scripts) + cast-name guard, speech service, story
  state migration, mechanic dialogue, intro handhold, campaign NPC state.

## 2026-08-06 (third pass) — tutorial gating + N.O.V.A. repeat

- ONE PREDICATE FIXED TWO REGRESSIONS. Bounty WANTED posters and the mechanic's
  fetch errand were both appearing before the starter contract was handed in.
  Both now go through UIManager._starter_contract_pending(), which reads the
  same per-campaign story_state flag added earlier today for the turn-in flash.
  The rule is one sentence: nothing offers the player a SECOND thing to do
  until the first job is closed, because a new player cannot tell which one is
  the tutorial.
  WATCH OUT: intro_quest_delivered is NOT this signal — it is set when the
  player ACCEPTS the starter contract, so it is already true while they are
  flying it. That is very likely how these gates rotted in the first place.
  Gated the bounty ANNOUNCEMENT as well as the posters, because
  _bounty_announced_system latches per system — announcing early would also
  burn the single announcement that system ever gets.
- N.O.V.A. REPEATED THE ENGAGEMENT WARNING (new bug, not a regression). Root
  cause: warn_hostile_engagement had an 8s time cooldown but no IDENTITY
  check, and one hostile can trip it at target acquisition and again when
  combat opens — far enough apart to clear the cooldown. Now one warning per
  hostile instance id.
  Also added a general verbatim-repeat guard to Nova.speak(): the same
  sentence within 45s is dropped. Placed ABOVE the severity check on purpose —
  THREAT lines bypass the speech budget entirely, so without it the highest
  priority lines are the ones most able to repeat. This catches two unrelated
  code paths independently arriving at the same sentence, which no single
  per-beat timer can.
- Green: Nova tests, parse check + cast-name guard.

## 2026-08-06 (diff audit) — a latent silence bug in the new speech queue

Abe suspected an edit had clobbered something. Audited every removed line in
the diff: 28 deletions across scripts, all of them accounted for by an
intentional edit. Nothing was overwritten.

The audit did surface a real defect in code added earlier today, though:

- THE AMBIENT SPEECH QUEUE COULD WEDGE PERMANENTLY. It drained only on the
  audio player's `finished` signal, and that signal is not guaranteed. A TTS
  request that fails at the HTTP layer clears TTSInterface.is_requesting
  WITHOUT ever producing audio, and provider.stop() does not emit `finished`
  either. Either path left the queue holding lines with nothing left to wake
  it, so every later ambient line — every N.O.V.A. observation, every Kaelen
  quiet moment — would have been silently swallowed for the rest of the
  session. Exactly the kind of failure that presents as "the characters just
  stopped talking" hours later and is miserable to trace back.
  Fixed by polling: _process re-checks every 0.25s, so `finished` is now a
  latency optimisation rather than the only way out. Entries also carry a
  queued_ms stamp and are dropped after 20s, since a line commenting on
  something the player has long since stopped doing is worse than silence.
  LESSON: never make a queue's only exit an event that a failure path can skip.

## 2026-08-06 (fourth pass) — the missing welcome + portrait, root-caused from a live log

Abe caught the repeat and sent the running console output. That log settled it
in one read, and the cause was mine.

THE ORDERING IN THE LOG:
  [TTSInterface] Requesting speech for: Docking control acknowledges...
  [StoryScreenshots] captured ..._station_first_dock.png
  [TTSInterface] Requesting speech for: Captain... this station wasn't on any route...

Dock control was still speaking when the dock completed, so N.O.V.A.'s arrival
line QUEUED behind it. Then:
  1. her portrait went up (shown at EMIT time)
  2. the welcome overlay opened, arming a one-shot playback_finished
  3. dock control's clip finished -> that ONE signal faded her portrait AND
     dismissed the welcome
  4. only then did her line start — to an empty screen

ROOT CAUSE: the ambient queue I added earlier today made EMIT and PLAYBACK two
different moments, but two consumers still treated "the next playback_finished"
as "my line finished". Neither of them was wrong before the queue existed.

FIX: SpeechService now emits ambient_line_started(text) when a line actually
begins, and exposes has_pending_ambient().
  - The portrait is REGISTERED at emit time (keyed by line text) and only SHOWN
    on ambient_line_started for that exact line, so it arrives with her voice
    and the next playback_finished genuinely is hers.
  - _release_station_welcome re-arms instead of releasing while ambient work is
    pending. STATION_WELCOME_MAX_WAIT_SECONDS still guarantees release, so a
    line that never plays cannot strand the overlay.
  - Registration happens BEFORE play_ambient is called: when the line plays
    immediately, ambient_line_started fires inside that call.

ALSO RULED OUT (do not re-investigate): the first dock showing only
`Talk to Agent` / `Undock Ship` is CORRECT. Services are gated on _intro_done
(UIManager.gd ~4356) until the player has visited the agent once.

THE LESSON, worth keeping: putting a queue in front of playback silently
invalidates every listener that treats the next completion signal as its own.
When you add a queue, audit the CONSUMERS of the completion event, not just the
producer. Two unrelated features broke this way and neither was touched.

- Green: parse check + cast-name guard, speech service tests.

## 2026-08-18 — live-verifying the dialogue fixes, and what the live model exposed

Step 1 of the hand-off: get a real Ollama run behind the dialogue-quality work
that had only ever been unit-tested.

- BUILT A REAL-MODEL GATE FOR THE N.O.V.A. BANKS,
  `tests/tools/run_nova_line_bank_live_fire.gd`. It fires the exact two seed
  batches GameRoot dispatches on campaign load (movement/arrival, then
  combat/hull/welcome/dock) and prints every line with the label it landed on,
  so the output is readable as dialogue rather than as a pass count.
- THE FLAT-JSON FIX WORKS LIVE. First run: 17/17 labels accepted, both batches
  OK, ~1.5s each. No seed_batch_failed, no all_lines_rejected. Three rounds
  came back 51/51. The @@label form that qwen3 rejected wholesale is properly
  dead.
- Ruled out on the way past: a banked `system_arrival` line naming a specific
  system ("Kepler Reach confirmed.") is NOT a bug. Banks are keyed
  `prefetch:current_system_nova:<system_id>` and the generation context names
  that same system, so such a line can only ever be consumed where it is true.

THE ACTUAL FINDING, which the live run gave up and no unit test could:

- A BATCH CAN BE STRUCTURALLY PERFECT AND STILL BE ONE LINE WEARING EIGHT HATS.
  One draw returned "Good thing you didn't take the long way." as the TAIL of
  six lines — on beats as unrelated as hull_critical and docked. Every one of
  them passed validation, because exact-match dedupe only ever compared whole
  strings and the opening clauses differed. Another draw closed three lines
  with "Still flying." and two with "Stay calm."
  Two guards added on the accepted-lines side, where a prompt cannot undo them:
    - `duplicate_sentence` — a line reusing a whole 4+ word sentence from one
      already accepted this batch. Normalization drops apostrophes and splits
      on em-dashes, because the model mixes straight/curly quotes freely and
      likes welding a stock tail on with a dash.
    - `duplicate_closer` — a repeated CLOSING sentence, floor of two words.
      The tic lands on the tail and it lands short. Shared OPENINGS stay legal
      on purpose: "Hull's intact." has to work on more than one beat, and a
      stricter rule would gut ordinary terse batches.

- I TRIED FIXING THIS IN THE PROMPT FIRST AND IT BACKFIRED, which is the part
  worth remembering. Adding "no two lines may share an opening phrase or end
  on the same word" drove the 4b into a SINGLE shared template across eight
  beats — the exact failure the rule was meant to prevent, but worse, and
  accept rate fell 100% -> 88%. Reverted. Piling negative constraints on a 4b
  spends instruction budget it does not have.
  LESSON: an anti-repetition rule belongs in the parser, not the prompt. The
  prompt asks; only the parser can refuse.

- FIXED WHAT THE GATE ASSERTS while I was in there. Rejecting a repetitive
  draw is the system working, so quality rejections (duplicate_*,
  missing_label) no longer fail the run; a STRUCTURAL rejection does —
  unparseable body, leaked label, speaker prefix, placeholder braces. Those
  mean our format contract broke. Final live state: 51 lines, zero structural
  failures, 88.2% accepted, duplicate_closer firing once and correctly.

The other two step-1 items are deterministic, so they got read + tested rather
than played:

- STARTER TURN-IN IS CLEAN. `_TUTORIAL_KAELEN_COMPLETION_LINES` /
  `_TUTORIAL_KAELEN_ABANDON_LINES` (UIManager ~12375) are authored, pinned to
  the actual task (the raider), and name no faction and no payer. The "Shiny"
  in two of them is CORRECT and must not be "fixed": per docs/bugs.md the rule
  is that only Kaelen uses it — the open bug is the AGENT NPC using it.
- N.O.V.A.'S COMBAT BUDGET FIX NOW HAS THE TEST IT WAS MISSING. The existing
  test proved combat lines PASS the budget gate; nothing proved they stay OUT
  of the ledger, and that second half is what fixed her going silent on docks
  after a fight. Added that coverage and MUTATION-CHECKED it: reverting the
  guard in `speak()` to append unconditionally fails all three assertions, so
  the test is not vacuous.

STILL NEEDS A HUMAN AT THE CONTROLS (I cannot fly the ship): confirming in a
real session that she actually speaks on docking and that the starter turn-in
reads well in the panel. Everything reachable from the model and the
deterministic layers is verified.

- Green: nova line bank batch parser (incl. two new dedupe tests), nova tests
  (incl. new accounting test), line bank refill, scene script parse check,
  nova line-bank live fire x3 rounds.

KNOWN LIMITATION LEFT ON PURPOSE: a repeated ONE-word closer ("Good.") still
slips both guards. Lowering the closer floor to one word would also reject
lines ending "Captain.", which is in-voice and common, so the trade was not
worth it. Logged in docs/bugs.md as low severity.

## 2026-08-18 (second pass) — enemy taunts now know why the fight started

Abe: the taunts are VERY BAD; they need a flag for WHY they are being said, a
format per reason, and the dark/dry house humour.

THE BUG WAS ONE SENTENCE IN A PROMPT. `request_combat_taunts` described the
speaker as "a furious stranger trash-talking whoever just attacked them" --
which is wrong every single time the NPC started the fight. A pirate who
ambushed you, a patrol collecting a mining fine, and a contract target who has
just worked out they were sold all read from the same two buckets, `rage` and
`reason`, the second of which was even commented "generic motive for v1; see
the REVISIT task for splitting this into reason buckets later". This was that
task.

THE CAUSES ARE DERIVED, NOT INVENTED. This was the design constraint worth
holding: every cause has to come from state the game already tracks, because a
speaker who claims a grievance the player never earned is worse than a vague
one. `NPCShip` decides the player is an enemy for exactly two reasons (minor
faction, or reputation < -10), and the rest fall out of existing metadata:
  contract_hit       player fired on an is_quest_target
  preemptive_strike  player fired on someone already hostile
  unprovoked         player fired on a neutral
  code_enforcement   is_code_enforcement -- the illegal-mining fine system
  reinforcement      is_reinforcement -- called in after an earlier fight
  pirate_predation   is_minor_faction
  reputation_grudge  reputation past the same threshold NPCShip uses
  opportunist        THEY started it and we cannot prove why, so they claim
                     nothing. The honest default.
Precedence is tested: enforcement outranks faction, a contract outranks
hostility, backup outranks a standing grudge.

ROUND-ROBIN, AND IT SURVIVES A RESTART. Abe asked for true round-robin over a
huge pool. `TauntBag` gives a shuffled bag per cause -- nothing repeats until
its cause is exhausted -- and the rotation is written to disk the moment a line
is consumed, so quitting cannot rewind it. The shuffle is SEEDED so that state
is three numbers instead of an index per line, which is what makes saving on
every draw affordable as the pool grows. Pools grow in the background toward
120 per cause, always feeding whichever cause is furthest behind, with every
banked line sent as an exclusion so a long campaign stops re-collecting what it
already has.

THE CACHE HAD TO BE RETIRED, not migrated. The 434 lines in cached_taunts.json
were written with no idea why their fight had started, so they cannot be sorted
into causes; importing them would have quietly undone the feature. New path,
cached_taunts_v2.json, old file left on disk. The yo-mama comedy pool went with
it -- that was the "humour" bucket, and it is not the register this game wants
anywhere near a fight.

WHAT LIVE FIRE CAUGHT THAT UNIT TESTS COULD NOT (twice now this session):
- WHOLE CAUSES RETURNED NOTHING because generation stopped one brace short of
  valid JSON. Raised the token budget to cover the wrapper, then stopped
  relying on that: a truncated body is now salvaged for its complete strings,
  and anything cut mid-word is dropped rather than delivered half-said.
  Discarding a batch over a missing "}" cost five good lines to save nothing.
- THE FAILURE PATH REPORTED NO REASON AT ALL -- `all_lines_rejected` with the
  rejections thrown away. Fixed my own diagnostics first, which is how the
  truncation was identified in one run. Ollama's `done_reason` and eval count
  now come back with the failure too.
- A CURLY APOSTROPHE ARRIVED AS A BARE "?" ("This isn?t personal"), which TTS
  would read aloud as a glitch. Now rejected. I checked the raw bytes before
  writing that guard: the em-dashes in the same file are intact UTF-8, so the
  save path is fine and the "?" came from the model. Worth recording, because
  the obvious next move would have been hunting an encoding bug that is not
  there.

ABE'S NOTE MID-BUILD, and it was the right call: not every line should explain
itself. Some should just be a flat threat -- "I'm going to make this one hurt"
-- carrying the mood of the cause without narrating it. Added as one prompt
rule (deliberately one, after the lesson earlier today that piling rules on the
4b backfires), and it came back verbatim in the next run.

SAMPLE OF WHAT IT NOW PRODUCES:
  pirate:      "You're cargo with opinions."
  contract:    "You didn't shoot me. You bought me."
  enforcement: "I'm not here to shoot you. Just to finish the form."
  reinforcement: "This mess was their problem, now it's ours."
  grudge:      "Your reputation's a stain we're cleaning up."

- Green: taunt cause + bag (mutation-checked), taunt parse, scene parse check,
  ambient chat, nova suites. Live: 8 causes generated, rotation probe, growth
  probe 32 -> 93 lines.

STILL OPEN: only a human can confirm these sound right in a real fight with
voice. The per-fight LLM bundle (npc_brace, npc_dying and friends) now receives
the cause but its 20 keys have NOT been live-checked one by one.

## 2026-08-18 (third pass) — first-five-minutes bugs, and one nobody had hit yet

Abe could not playtest, so I took the first-five-minutes list and stuck to what
is provable without eyes on the screen. Two of the four were already fixed and
never closed out; checking them properly is what found the new one.

- THE FILLER LEAK WAS FIXED ON 2026-07-15, two days after it was filed. The
  guard held. But it had two gaps worth closing anyway:
  it lived inside ONE UIManager helper, so any other caller of
  play_latency_filler_clip bypassed it and Kaelen had no equivalent guard at
  all; and it was keyed on `loading_panel` still existing, while that panel is
  freed to START the intro cinematic -- so the gate opened while the player was
  still watching an authored sequence with no control. The ban now lives in
  SpeechService, where every caller goes through it, and lifts when gameplay
  actually resumes rather than when a panel disappears.
  THE RULE: a policy about when the game may make a noise belongs with the
  service that makes the noise, not at one of its call sites. Same reasoning as
  moving the ambient queue's exit condition off a single signal.
- "N.O.V.A. TALKS DURING FIRST DOCK" IS NOT REPRODUCIBLE AS WRITTEN. The first
  dock already belongs to her authored arrival line: UIManager branches on
  kaelen_briefing_seen, and that flag is only set inside the agent panel, which
  cannot be reached before docking. The branch is correct by construction.
- BUT THAT AUTHORED LINE COULD REPEAT, and this one was live. kaelen_briefing_seen
  stays false until the player actually TALKS to Kaelen, so dock -> undock
  without visiting him -> re-dock served the identical authored line a second
  time. Exactly the Jenna Kross repeat, in a different costume, and fixed the
  way her entry prescribes: latch where the line is SERVED
  (StoryManager.claim_intro_first_dock_line), not where a later button is
  pressed, so every dock path is covered including ones added later.
  Mutation-checked: disabling the latch fails the repeat test.
- THE "INDY" BUG IS A DESIGN DISAGREEMENT, NOT A LEAK, so I changed nothing and
  wrote the question down instead. The mechanical leak is genuinely closed --
  "Shiny" in a non-Kaelen mouth is rewritten by apply_tone_guard on BOTH the
  audio path and the displayed dock message. But the entry says agents should
  never use the player's callsign, while the agent prompts deliberately pass
  "Indy" as player_nickname and say to use it occasionally. That is Abe's call
  to make, and it is a two-minute change once he makes it. Details and both
  options are in docs/bugs.md.

- Green: intro dock gating (new, mutation-checked, and run three times after the
  first attempt hit the known autoload compile-order flake), speech service,
  scene parse check.

STILL OPEN from that list: the tutorial overview panel starting collapsed. It is
a UI-layout bug whose failure mode is "it looks wrong", so it wants the same
human pass as the taunts rather than a headless assertion.

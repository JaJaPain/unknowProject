# While You Was Sleeping — Session Changelog

---

## Session: 2026-06-19 (Late)
**Branch:** `segment-3/economy-stores-events`
**Commits:** `e66dab3` → `e2c5a9d`

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

## Session: 2026-06-19 (Early)
**Branch:** `segment-3/economy-stores-events`
**Commit:** `02ab6c6`

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

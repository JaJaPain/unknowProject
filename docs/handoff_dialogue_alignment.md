# Handoff: LLM Quest Dialogue Alignment

> **⚠️ HISTORICAL SNAPSHOT — June 2026**
> This document describes the state of dialogue alignment at the time of the
> dummy-name substitution implementation. The "What Still Needs Work" items
> below may be partially or fully resolved in current code. Do NOT treat the
> example dummy names (George, Slithern, Sable Mercer, Morrow Station) as
> the desired NPC tone — they are internal LLM prompt placeholders only,
> never shown to the player. Verify current behavior against `LLMInterface.gd`
> before acting on these notes.

## What Was Done

Implemented a **dummy-name substitution system** in `scripts/LLMInterface.gd` to ensure LLM-generated quest dialogue always matches the actual mission contract.

### The Problem
The 1.5B LLM (qwen2.5) was hallucinating wrong faction names, wrong ship counts, and inventing enemies not in the contract. Example: dialogue said "Three ships: a Reaver and 2 Obsidian" but the contract was "Destroy 2 OBSIDIAN ships."

### The Solution (Dummy Names)
Instead of asking the LLM to use `{PLACEHOLDER}` tags (which it couldn't follow), we feed it **fixed dummy names** in every example:
- **"George"** = pilot name (swapped to "Indy" or "Shiny" after)
- **"Slithern"** = enemy faction (swapped to real target faction)
- **"3"** = kill count (swapped to real count via `_sync_dialogue_to_validated_objective`)
- **"25"** = ore amount (swapped via same sync)
- **"Sable Mercer" / "Morrow Station" / "Sealed Data Drive"** = pickup dummy names

The LLM mimics the pattern naturally without needing to understand placeholders.

### Key Functions Added
- `_substitute_dialogue_placeholders()` (~line 1070) — swaps dummy names for real values in dialogue + choice responses
- `_nickname_for_agent()` — returns "Shiny" for Kaelen, "Indy" for everyone else
- `_dialogue_has_faction_mismatch()` — catches dialogue mentioning wrong factions
- `_dialogue_is_too_vague()` — catches dialogue with zero objective-relevant keywords
- `_dialogue_has_placeholder_artifacts()` — catches leftover "George"/"Slithern" or agent self-reference
- `_request_dialogue_retry()` / `_on_dialogue_retry_completed()` — gives LLM a second attempt before safe fallback
- `_finish_quest_with_current_dialogue()` — unified callback that sets `is_waiting = false`

### State Variable
- `_pending_substitutions: Dictionary` — stashed at quest generation time, holds the real pre-rolled values (kill target, count, ore amount, pickup details, nickname, etc.)

## What Still Needs Work

### 1. Kill Ship Missions Not Generating
No KILL_SHIPS missions appeared during testing. The examples all use "George" and "Slithern" and "3 ships" but the example dialogue block is only set for KILL_SHIPS format. Need to verify:
- The example dialogue in the prompt matches `chosen_type` (currently the base example dialogue is kill-themed for all agents — ore/pickup examples are missing from the base examples)
- The `example_obj_block` for KILL_SHIPS uses `"slithern"` as target_faction

### 2. Kaelen Pickup Missions Broken
~50% of Kaelen pickup missions show "not going to put my name on it" — this is the safe fallback dialogue firing. Likely causes:
- The vague dialogue check (`_dialogue_is_too_vague`) may be too aggressive for pickup missions
- Or Kaelen's example dialogue doesn't show the pickup dummy names well enough

### 3. Ore Amount "25" Replacement
The `_sync_dialogue_to_validated_objective` searches for the number "25" near ore-context words and replaces it with the real amount. This works but could false-positive on other "25" occurrences. Monitor logs for `⚠ VALIDATE: Final objective changed` entries.

### 4. Example Dialogues Per Mission Type
Currently every agent has ONE example dialogue (kill-themed). The old code had type-specific example overrides per faction — those were removed during the placeholder experiments. Should add back per-type examples using the dummy names:
- KILL_SHIPS: "3 Slithern ships..." (already done)
- DELIVER_ORE: "25 m³ of ore for George..." (needs adding)
- PICKUP_SPECIAL: "George, pick up Sealed Data Drive from Sable Mercer at Morrow Station..." (needs adding)

### 5. "Neutral Fixer & Profit Broker" Subtitle
All agents show "Neutral Fixer & Profit Broker" as their subtitle — this should show the agent's actual `agent_role` value. This is likely set elsewhere in UIManager.

### 6. `is_waiting` State Management
`is_waiting` was refactored — it stays `true` during dialogue retries and is set `false` in `_finish_quest_with_current_dialogue()` and `_trigger_fallback()`. If there's a bug where quests stop generating, check these paths.

## Files Modified
- `scripts/LLMInterface.gd` — all changes are here

## How to Test
1. Run the game, go to the station, talk to Kaelen → agent
2. Check the quest dialogue matches the Contract Details section
3. Check Godot logs for `[LLMInterface] ⚠ VALIDATE:` and `✓ Dialogue retry` entries
4. Test all 3 mission types: KILL_SHIPS, DELIVER_ORE, PICKUP_SPECIAL

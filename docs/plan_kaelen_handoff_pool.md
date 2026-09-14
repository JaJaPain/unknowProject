# Kaelen Handoff Pool — Implementation Plan

_Save this file incrementally — do not batch everything into one write._

## What This Solves

The current Kaelen intro line before each agent is generated on-demand by the small model (qwen2.5:3b) with story context as a color hint. The result is functional but generic. This system pre-generates 16 story-aware handoff lines per agent using Gemma4 (12b) during dead travel time, so the line is instant and rich when the player actually docks.

---

## Architecture Overview

**New file:** `scripts/persistence/KaelenHandoffStore.gd`
- RefCounted, follows CampaignTransactionStore pattern (same as StoryStateStore)
- Persists `kaelen_handoffs.json` in the campaign slot folder
- Data shape: `{ "agent_name": ["line1", "line2", ...], ... }`
- `draw(agent_name) -> String` — pops the first line, saves, returns `""` if pool empty
- `refill(agent_name, lines: Array)` — sets/replaces the pool for that agent, saves

**StoryManager additions:**
- `generate_handoff_pool_for_agents(agents: Array[Dictionary])` — async, calls Gemma4 once per agent, 16 lines each; stores via KaelenHandoffStore
- Called from two trigger points (see below)

**LLMInterface additions:**
- `request_kaelen_handoff_batch(agent_name, agent_role, faction, story_context, count, callback)` — single Gemma4 call, returns Array of lines
- Prompt is story-context-first, agent-voice-second; same speaker rules as existing kaelen intro

**`request_kaelen_intro` change (LLMInterface):**
- Before building the small-model prompt, call `KaelenHandoffStore.draw(agent_name)`
- If non-empty string returned: call the callback immediately with that line — no LLM call
- If empty: fall through to existing small-model flow (current behavior, unchanged)

---

## Trigger Points

### Trigger 1 — Game Start / Campaign Load
In `StoryManager.init_story_state()`, after loading state: call `generate_handoff_pool_for_agents()` with the starting system's agents. Starting system is authored (`system.start`) so faction_ids are known from `data/systems/system_registry.json`: zenith → Director Voss, aurelia → Liaison Ryn, vanguard → Captain Dask.

### Trigger 2 — Gate "Fly to" Pressed
In `UIManager`, in the `JUMP_APPROACH` button handler (the "Fly to" button when targeting a jumpgate): read `active_target.destination_system_id`. Look it up in the system registry. If the system has known `faction_ids`, resolve agents and call `StoryManager.generate_handoff_pool_for_agents()` immediately.

For generated systems (`system.gen.*`) — not in the registry — defer to Trigger 3.

### Trigger 3 — System Arrived
In `StoryManager.on_system_arrived(system_id)`: check if the KaelenHandoffStore pool for the current system's agents is low (< 4 lines). If so, generate a top-up. This is the safety net for generated systems — the player still has to cross the system and dock, giving 30–60s of runway.

### Trigger 4 — Chapter Advance
In `StoryManager.advance_chapter()`: after saving new story state, call `generate_handoff_pool_for_agents()` for all known agents. Story context has just changed — old lines may be tonally stale. Replace the pools.

---

## Pool Sizing and Depletion

- 16 lines per agent at generation time
- Draw is destructive (pops from front, saves)
- When pool hits 0 for an agent: `request_kaelen_intro` falls through to small-model live generation — no error, no gap
- Trigger 3 (arrival) tops up any pool below 4 — so a depleted pool gets refilled on the next system jump before it runs dry mid-session

---

## Gemma4 Prompt Design

One call per agent, asking for 16 lines in a JSON array. Structure:

```
You are writing for Broker Kaelen — a dry, transactional, faintly condescending space broker.
She is about to introduce [AGENT_NAME] ([AGENT_ROLE], [FACTION]) to the pilot "Shiny."

Story context (color her tone — do NOT quote this directly):
[STORY_CONTEXT_BLOCK]

Write 16 SHORT handoff lines (under 25 words each) in Kaelen's voice.
Rules:
- First person as Kaelen. She is talking TO Shiny about [AGENT_NAME].
- [AGENT_NAME] is silent. Never put words in their mouth.
- Mention [AGENT_NAME] by name in every line (third person).
- Vary the angle: some urgent, some dry, some with a hint of the story tension.
- No line should repeat another. No numbering.

Respond ONLY with a valid JSON array of 16 strings:
["line one", "line two", ...]
```

The story context block comes from `StoryManager.get_story_context_block()` — same source as the current color injection. At chapter 1 it's sparse; by chapter 3+ it's rich with tensions, player_knows, and foreshadow.

---

## KaelenHandoffStore — Key Methods

```gdscript
class_name KaelenHandoffStore
extends RefCounted

static func open(campaign_path: String) -> KaelenHandoffStore
func is_valid() -> bool
func draw(agent_name: String) -> String          # "" if empty
func pool_size(agent_name: String) -> int
func refill(agent_name: String, lines: Array) -> void
func _commit() -> void                           # saves via TransactionStore
```

Data file: `kaelen_handoffs.json`
Schema: `{ "schema_version": 1, "document_type": "kaelen_handoffs", "pools": { "Director Voss": [...], "Liaison Ryn": [...] } }`

---

## Build Order

1. **`KaelenHandoffStore.gd`** — new store, no dependencies beyond TransactionStore
2. **`StoryManager`** — open the store in `init_story_state()`, expose `generate_handoff_pool_for_agents()`
3. **`LLMInterface`** — add `request_kaelen_handoff_batch()`; wire draw into `request_kaelen_intro`
4. **`UIManager`** — gate "Fly to" trigger: read destination system, call StoryManager
5. **`StoryManager.on_system_arrived()`** — top-up trigger
6. **`StoryManager.advance_chapter()`** — full replacement trigger

Items 1–3 are the core and can ship alone. Items 4–6 are the trigger wiring that makes it automatic.

---

## What Stays the Same

- `request_kaelen_intro` signature is unchanged — callers don't know or care whether the line came from the pool or the small model
- Small model + story color fallback is unchanged — pool depletion degrades gracefully
- Speaker-leakage validation is skipped for pool lines (Gemma4 output is pre-validated by the prompt; add a lightweight check on refill if needed)
- `KaelenHandoffStore` is optional at runtime — if it fails to open, `draw()` returns `""` and the existing path runs


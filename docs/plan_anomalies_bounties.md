# Plan: Space Anomalies + Kaelen Bounties
**Date:** 2026-06-22
**Status:** Design — not yet built

---

## System A: Kaelen's Standing Bounties

### The Concept
Kaelen has standing "paper" out on specific minor factions operating in the current system. Kill their ships, she quietly pays you — minus her cut. Small money compared to a mission, but it makes every combat feel economically meaningful and fits her character perfectly.

### Player Discovery (The Problem You Identified)
The player needs to know bounties exist without a wall of text. Three-layer approach:

1. **On first dock of a session**, if active bounties exist, Kaelen drops a single chat line through the normal chat window (not a popup, not a new panel):
   *"Dustborn are running raids in this corridor. I've got standing paper — ten SC a hull, after my finder's fee. You'll know when it hits."*

2. **On every eligible kill**, Kaelen sends an immediate chat confirmation:
   *"Tagged. Nine SC deposited. Keep it up, Shiny."*
   (The difference between the "10 SC" she quoted and the "9 SC" you receive IS her cut — she never explains it, it just... happens.)

3. **In Kaelen's panel**, a small "Active Paper" line under her portrait — just faction name + per-kill rate. One line, no modal. Easy to miss if you don't look, which is correct — it's a side hustle, not the main event.

### Data Model
```gdscript
# In a new BountyRegistry.gd (autoload-style singleton)
# Active bounties are per-session, generated on system entry
{
  "faction": "dustborn",
  "system_id": "...",
  "payout_per_kill": 9,      # after Kaelen's cut
  "gross_per_kill": 13,      # what Kaelen charges her client (flavor only)
  "kills_credited": 0,       # tracking
  "cap": 8,                  # bounty expires after X kills (-1 = unlimited)
  "expires_day": 12,
  "kaelen_line": "...",      # LLM-generated flavor for why she wants them dead
}
```

### Kill Detection
In `NPCShip.die()`, one new call: `BountyRegistry.shared().check_kill(faction, system_id)` → returns payout or 0. If > 0, `GlobalState.player_credits += payout` and `GlobalState.emit_chatter("Kaelen", line, kaelen_color)`.

**Nothing else in NPCShip changes.** It's one guarded call at the end of die().

### Bounty Generation
- On system entry (or on first dock), LLM generates 1–2 active bounties for current minor factions
- Prompt gives LLM: current system factions, player rep, day number
- LLM returns: which faction(s), why (1 sentence), payout range
- Fallback: pick 1 random minor faction from `MINOR_FACTIONS`, generic line

### Making It Feel Fresh (Your "always new" goal)
- The LLM writes Kaelen's *reason* each time — not just "kill dustborn" but "the Dustborn hit a shipment I had a stake in. I want receipts."
- Payout varies slightly (7–15 SC range) so it's never the same number
- Some bounties have a cap ("I only need 5 confirmations"), some are open-ended
- Occasionally Kaelen has NO active bounties — silence is also information
- Rare: double-faction bounties ("I've got paper on the Ironclad AND the Wraiths this week — there's a proxy war I'm profiting from")

### Isolation
- New file: `scripts/economy/BountyRegistry.gd`
- One new line at end of `NPCShip.die()`
- Small addition to Kaelen's panel in `UIManager.gd`
- New `LLMInterface.fetch_bounty_brief()` function (same pattern as existing fetch functions)

---

## System B: Space Anomalies with LLM Toolkit

### The Core Vision
A Space Anomaly is a one-time, fully LLM-authored mini-event. The LLM doesn't just write flavor text — it picks from a **toolkit of real mechanical actions** and sequences them into a coherent scene. The result is something that feels like the game world generated a tiny story, not a loot box with a label on it.

### The Toolkit (What the LLM Can Order)

These are the building blocks. The LLM constructs an `actions` array from this menu:

| Tool | What It Does |
|------|-------------|
| `emit_chat` | Print timed chat lines from a named sender (log entries, distress signals, AI voices) |
| `grant_ore` | Add ore to hold (respects cap; 5–30 range) |
| `grant_credits` | Add SC directly |
| `grant_item` | Add a specific item to inventory (`data_chip`, `encrypted_core`, `damaged_transponder`, etc.) |
| `spawn_hostiles` | Spawn 1–3 ships of a faction at a distance, delayed (the ambush arrives after you've already committed) |
| `spawn_cargo_pod` | Drop a drifting pod nearby with specified contents (player must fly to it) |
| `grant_temp_buff` | Speed/weapons/shields multiplier for N seconds |
| `grant_rep` | Small reputation change with a faction (positive or negative) |
| `damage_player` | Small hull hit (e.g. "the reactor vents caught your hull — 8 damage") |
| `reveal_contacts` | Pulse scan, like scanner probe |
| `spawn_follow_up` | Mark a second anomaly location elsewhere in the system — "there's more" |

### The LLM's Job

The LLM receives a prompt containing:
- Current system factions and tone (frontier, industrial, war-zone, etc.)
- Time of day / day number
- Player reputation state
- A list of available action types with their parameter constraints

It returns a JSON object:
```json
{
  "name": "Emergency Extraction Beacon — WX-7",
  "description": "Automated distress loop. Signal is old.",
  "icon_type": "beacon",
  "flavor_type": "military",
  "approach_lines": [
    "Signal acquired. Beacon class: civilian evac, pre-war.",
    "Logs intact. Someone didn't make it out."
  ],
  "actions": [
    {
      "type": "emit_chat",
      "sender": "Beacon WX-7",
      "lines": ["...day 84... fuel depleted... requesting any vessel..."],
      "delay": 1.5
    },
    { "type": "grant_credits", "amount": 55 },
    { "type": "grant_item", "item_id": "data_chip" },
    {
      "type": "spawn_hostiles",
      "faction": "reavers",
      "count": 2,
      "delay": 6.0,
      "spawn_chat": "Someone else found your signal."
    }
  ]
}
```

The game executes each action in sequence. No hardcoded event logic — the LLM is the designer.

### Why This Stays Unique Every Time

1. **The LLM picks the STORY TYPE** — military, civilian, pirate cache, scientific, mysterious void entity. Different types pull different action combinations naturally.

2. **The LLM sequences the tension** — it can front-load reward and then spawn danger (the ambush arrives *after* you've grabbed the loot), or deny the reward if the story is a trap.

3. **The LLM writes the voice** — `emit_chat` lets it invent a sender with a name and a fragment of a story. "Beacon WX-7" feels different from "Enforcer Lev Dask" or "Station AI CHORUS-9."

4. **The narrative + the mechanic are coherent** — the LLM won't write a happy civilian refugee story and then spawn reavers... unless it's building a trap. It has the whole event in view when it picks the actions.

5. **Context injection makes each system feel different** — passing in current factions means a system controlled by Vanguard generates different anomaly flavors than a Reaver-heavy frontier zone.

### SpaceAnomaly.gd (New File)
```
extends StaticBody3D

var anomaly_data: Dictionary = {}   # the LLM JSON
var _activated: bool = false
var _action_index: int = 0

# Visual: simple glowing orb or beacon mesh, pulses gently
# On player within ~50u: triggers activation sequence
# Executes action queue with timers
# After all actions: despawn (quietly queue_free)
```

### AnomalyRegistry.gd (New File)
- Generates 1–3 anomaly positions per system at load time
- Requests LLM event data asynchronously (same pattern as salvager identity fetch)
- Has a fallback table of ~10 preset events for when LLM is unavailable or slow
- Stores which anomalies have already been activated (so save/load works)

### Validation Guardrails on LLM Output
Before executing any action:
- `grant_ore` capped at 30
- `grant_credits` capped at 150  
- `grant_item` must be in known item registry (whitelist)
- `spawn_hostiles` count capped at 3, faction must be in known factions list
- `grant_temp_buff` duration capped at 60s, multiplier capped at 1.5×
- `grant_rep` magnitude capped at ±10
- `damage_player` capped at 20
- Unknown action types silently skipped

### Isolation
- New files: `scripts/SpaceAnomaly.gd`, `scripts/AnomalyRegistry.gd`, `scenes/anomaly.tscn`
- One new `LLMInterface.fetch_anomaly_event()` function
- `MainScene.gd`: spawn anomaly nodes at generation time (same pattern as salvager spawn)
- `UIManager.gd`: anomalies appear in overview as "Unknown Contact" type (one new `elif` in the overview builder)
- **Nothing else touched**

---

## Build Order

### Phase 1 — Kaelen Bounties (smaller, can ship in one session)
1. `BountyRegistry.gd` — data model + singleton
2. `LLMInterface.fetch_bounty_brief()` — prompt + fallback
3. `NPCShip.die()` — one-line kill check
4. `UIManager.gd` — "Active Paper" line in Kaelen panel + on-dock chat emit

### Phase 2 — Anomalies, Foundation (one session)
1. `SpaceAnomaly.gd` — node, visual, proximity detection, action executor
2. `AnomalyRegistry.gd` — static fallback table (10 presets), no LLM yet
3. `MainScene.gd` — spawn 1–3 per system
4. `UIManager.gd` — overview entry

### Phase 3 — Anomalies, LLM Brain (one session)
1. `LLMInterface.fetch_anomaly_event()` — prompt construction, JSON parse, validation
2. Wire into `AnomalyRegistry` — async load, fallback on failure
3. Save/load of activation state

### Phase 4 — Depth Passes (ongoing)
- Add more action types (follow-up anomaly, faction rep, etc.)
- Expand fallback preset table
- Add sound design hooks
- Anomaly visual variety (different mesh/color per flavor_type)

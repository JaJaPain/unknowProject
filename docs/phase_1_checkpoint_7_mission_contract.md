# Phase 1 Checkpoint 7: Mission Contract Adapter

Status: Complete

## Purpose

Mission data now crosses a validated typed boundary before it can change player
state or enter a save. The player-facing prototype still supports exactly one
active mission and retains its existing balance and UI behavior.

## Typed Contracts

- `MissionDefinition` describes stable mission identity, title, giver, faction,
  dialogue, objective, rewards, timing, and choices.
- `MissionObjectiveDefinition` supports the current `KILL_SHIPS`,
  `DELIVER_ORE`, and `PICKUP_SPECIAL` mechanics.
- `MissionRewardDefinition` validates the base credit payout.
- `MissionConsequenceDefinition` contains immediate credits, reputation
  changes, combat difficulty, payout multiplier, and response dialogue.
- `MissionTimingDefinition` establishes the future timed/untimed boundary
  without activating timed missions.
- `MissionState` validates mutable progress and save-facing runtime fields.

## Compatibility

`MissionAdapter` converts generated and handcrafted mission dictionaries into
the same `QuestManager.active_quest` shape already consumed by the HUD, station
services, mission targets, cargo handling, and save system.

Current version-1 mission saves receive deterministic definition and runtime
IDs when loaded. This normalization does not introduce the Phase 2 campaign
store or the future multiple-mission collection.

## Failure Rules

- Unsupported objective types are rejected.
- Required objective fields cannot be absent or empty.
- Requirements must be positive.
- Credit rewards cannot be negative.
- Invalid offers cannot change credits, reputation, cargo, or active mission
  state.
- Invalid active mission state cannot be written to or restored from a save.
- The mission board shows a readable rejection and returns to station services
  when an offer fails verification.

## Automated Coverage

The baseline suite now runs both:

- focused definition, adapter, legacy normalization, and malformed-data tests
- the complete gameplay mission smoke test

The gameplay test deterministically covers all three current mission types,
including acceptance, consequences, partial ore banking, kill progress,
pickup cargo validation, completion payouts, abandonment reputation loss,
fallback generation, speaker naming, and speech-service failure.

Checkpoint completion baseline: 13 of 13 steps passed.

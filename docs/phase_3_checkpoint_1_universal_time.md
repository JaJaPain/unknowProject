# Phase 3 Checkpoint 1: Universal Campaign Time

Date: 2026-06-15

Purpose: add one deterministic campaign clock for saves, travel, future mission
timers, and later off-screen simulation.

## Time Model

Campaign time is not real time. It does not advance because the player leaves
the game open, reads a menu, or waits at the keyboard.

Campaign time advances from controlled gameplay actions:

- gate travel: 45 minutes
- docking checkpoint: 10 minutes
- undocking checkpoint: 5 minutes

The HUD displays the current campaign date as `Day 001 08:00` style flavor.
Future timed missions should present player-facing urgency as countdowns such
as `2h 30m remaining`, while storing deadlines against this same campaign
clock. That keeps timed mission outcomes deterministic without forcing players
to do calendar math.

## Save Contract

The saved global state now includes:

```json
"campaign_time": {
  "total_minutes": 480
}
```

Version-2 saves without this field remain valid and restore to the campaign
start time. Checkpoint and compatibility saves capture the same campaign time,
so loading older safe points rewinds the clock with the rest of mutable state.

## Automated Coverage

- focused campaign clock unit test
- jump smoke verifies each gate jump advances campaign time
- save smoke verifies compatibility save/load restores campaign time
- manual checkpoint smoke verifies in-flight manual backup copies preserve the
  safe checkpoint time, not the live in-flight time

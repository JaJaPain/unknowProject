# Phase 0 Gameplay Regression

Date: 2026-06-13

Baseline:

- Commit: `d5cfe0a`
- Tag: `prototype-baseline-v1`
- Branch: `codex/jumpgate-system`
- Godot: 4.6.3 stable

Result values:

- `PASS`: behavior worked as expected.
- `FAIL`: reproducible defect.
- `BLOCKED`: could not test because another feature or defect prevented it.
- `NOT RUN`: pending hands-on testing.

## Automated Results

| Area | Result | Notes |
| --- | --- | --- |
| Headless import | PASS | Project imported successfully. |
| Startup | PASS | Main scene reached active gameplay. |
| Two-way gate travel | PASS | Both systems loaded and paired arrival markers resolved. |
| Gate state preservation | PASS | Hull and shields survived both jumps. |
| Save-state restoration | PASS | Player, quest, and asteroid state restored. |
| Save validation | PASS | Malformed and unsupported save data rejected. |
| Docking | PASS | All active-system dockables completed automated approach. |
| Restart | PASS | Warm LLM/TTS state no longer leaves loading at 5%. |
| Autopilot obstacle clearance | PASS | Automated geometry checks and hands-on flight confirmed. |
| Gate autopilot staging | PASS | Automated staging check and hands-on side approach confirmed. |
| Mining and economy | PASS | Extraction, cargo limits, storage, sale, and upgrade rules verified. |

## Session A: Core Flight, Mining, Docking, And Restoration

| Test | Result | Notes |
| --- | --- | --- |
| New game reaches playable state | NOT RUN | |
| Pause stops gameplay and resume restores it | NOT RUN | |
| Manual flight and camera controls respond | NOT RUN | |
| Overview targeting selects the intended object | NOT RUN | |
| Approach and orbit controls can be overridden | NOT RUN | |
| Autopilot avoids asteroids on the route | PASS | Predictive avoidance passed automated and hands-on checks. |
| Autopilot keeps safe clearance from planets | PASS | Enlarged celestial safety envelope passed automated and hands-on checks. |
| Mining laser extracts ore | PASS | Automated test mined from a live asteroid through its gameplay method. |
| Cargo amount and capacity update correctly | PASS | Mining topped off the hold at its exact capacity. |
| Full cargo prevents additional mining | PASS | Full and special-cargo holds rejected additional ore. |
| Main-station docking completes | NOT RUN | |
| Ore sale changes cargo and credits correctly | PASS | Station sale path credited the exact ore amount and cleared the hold. |
| Ore can be deposited into station storage | PASS | Deposit moved ore into persistent player storage and cleared the hold. |
| Undocking restores flight controls | NOT RUN | |
| Gate jump autosaves current state | NOT RUN | |
| Closing and reopening restores the autosaved state | NOT RUN | |
| Restart Game deletes progress and starts fresh | PASS | Confirmed in normal game window. |

## Session B: Combat, Damage, Death, And Reputation

| Test | Result | Notes |
| --- | --- | --- |
| Player weapon damages a valid target | NOT RUN | |
| Hostile ships engage under expected reputation rules | NOT RUN | |
| Safe-zone behavior prevents inappropriate attacks | NOT RUN | |
| Hull and shields update correctly under damage | NOT RUN | |
| Destroyed ships produce expected rewards/state | NOT RUN | |
| Faction reputation changes after hostile action | NOT RUN | |
| Death screen appears when the player is destroyed | NOT RUN | |
| Restart from death returns to a fresh game | NOT RUN | |

## Session C: Missions, Dialogue, LLM, And TTS

| Test | Result | Notes |
| --- | --- | --- |
| Kaelen introduction appears and speaks | NOT RUN | |
| Agent board receives a generated or fallback mission | NOT RUN | |
| Mission briefing numbers match objective numbers | NOT RUN | |
| Mission can be accepted | NOT RUN | |
| Kill mission progress updates and completes | NOT RUN | |
| Ore mission supports partial and final delivery | NOT RUN | |
| Mission abandonment removes it and changes reputation | NOT RUN | |
| LLM timeout produces a playable fallback mission | NOT RUN | |
| TTS failure leaves readable dialogue and playable UI | NOT RUN | |
| Non-Kaelen speakers say Indy rather than Shiny | NOT RUN | |

## Session D: Services And Upgrades

| Test | Result | Notes |
| --- | --- | --- |
| Repair service restores hull and charges correctly | NOT RUN | |
| Station storage persists through travel | NOT RUN | |
| Upgrade panel shows current power use | NOT RUN | |
| Valid upgrade purchase applies stats and costs | PASS | Powerplant then engine purchase applied tier, cost, capacity, and speed. |
| Invalid over-budget upgrade is rejected | PASS | Mining upgrade was rejected without charging when power was capped. |
| Upgrade state survives gate travel | NOT RUN | |
| Upgrade state survives autosave and relaunch | NOT RUN | |
| Outposts show the correct limited service menus | NOT RUN | |
| Hear Gossip displays and speaks an NPC line | NOT RUN | |
| Mechanic pickup mission can be accepted | NOT RUN | |
| Pickup occurs only at the assigned outpost | NOT RUN | |
| Returning the part completes the mission | NOT RUN | |

## Session E: Gate Presentation And Edge Cases

| Test | Result | Notes |
| --- | --- | --- |
| Out-of-range gate activation is refused clearly | NOT RUN | |
| Misaligned gate activation is refused clearly | NOT RUN | |
| Jump transition is visually continuous | NOT RUN | |
| Gate autopilot stages in front before entry | PASS | 260-unit staging marker and alignment hold passed automated and hands-on checks. |
| Controls remain locked during transition | NOT RUN | |
| Camera and controls work after arrival | NOT RUN | |
| Arrival does not accidentally trigger a return jump | PASS | Flight back provides natural spacing; technical cooldown remains. |
| Return jump works in normal gameplay | NOT RUN | |
| Docking and ordinary gameplay work after returning | NOT RUN | |

## Known Baseline Issues

- Headless shutdown may report leaked objects/resources when background LLM or
  TTS requests are still active.
- Parallel headless tests can compete over local TTS startup. Run
  service-dependent checks sequentially.
- Save support is currently a single internal autosave. There is no player-facing
  save/load menu or save-slot selection.
- Debug buttons for the special pickup flow are disabled in normal builds, so
  that flow may require a naturally generated mission or a temporary test mode.

## Defects Found During Regression

### Autopilot Obstacle Clearance

Status: FIXED and hands-on verified.

Observed:

- Autopilot could fly directly into an asteroid on a straight route.
- Planet avoidance reacted to physical collision paths but did not guarantee a
  comfortable clearance from the visible edge.

Change:

- Replaced single-hit ray detours with predictive route-segment clearance.
- Added stable avoidance sides to reduce left-right weaving.
- Added safety envelopes for celestial bodies, asteroids, stations, gates, and
  ships.
- Reduced autopilot speed while actively detouring.
- Added `--autopilot-smoke-test` for an asteroid directly on the route and a
  planet route outside the surface but inside the protected clearance.

### Gate Side Approach

Status: FIXED and hands-on verified.

Observed:

- Gate autopilot aimed at the portal center from any angle, allowing awkward
  approaches toward the frame or side of the gate.

Change:

- Added an invisible approach marker 260 units in front of every gate.
- Jump autopilot reaches the marker before targeting the portal center.
- Ships already inside the narrow entry corridor do not fly backward to the
  marker.
- At the staging point, the ship slows and finishes turning toward the portal
  before beginning the final straight run.
- The jump smoke test verifies marker distance and side-approach staging.

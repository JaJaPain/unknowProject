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
| Combat and death | PASS | Hostility, safe zones, projectiles, damage, rewards, reputation, death, and restart verified. |
| Missions and dialogue resilience | PASS | Fallback, objective consistency, mission lifecycle, naming, and TTS failure verified. |
| Station services and persistence | PASS | Repair, upgrade UI, storage, save/load, outposts, gossip, and pickup routing verified. |
| Core controls | PASS | Playable startup, pause, movement, camera zoom, overview targeting, and navigation overrides verified. |
| Dock autosave | PASS | Every current dockable opened its UI, wrote an autosave, and restored flight state on undock. |
| Gate activation safety | PASS | Range, alignment, transition lock, arrival cooldown, and post-arrival control state verified. |

## Session A: Core Flight, Mining, Docking, And Restoration

| Test | Result | Notes |
| --- | --- | --- |
| New game reaches playable state | PASS | Player, system, UI, and camera references initialized in active gameplay. |
| Pause stops gameplay and resume restores it | PASS | Paused movement remained fixed; the same command moved after resume. |
| Manual flight and camera controls respond | PASS | Fly-to movement and camera zoom input changed live player state. |
| Overview targeting selects the intended object | PASS | A real overview row selected the primary station. |
| Approach and orbit controls can be overridden | PASS | Player input changed approach to orbit through the live handlers. |
| Autopilot avoids asteroids on the route | PASS | Predictive avoidance passed automated and hands-on checks. |
| Autopilot keeps safe clearance from planets | PASS | Enlarged celestial safety envelope passed automated and hands-on checks. |
| Mining laser extracts ore | PASS | Automated test mined from a live asteroid through its gameplay method. |
| Cargo amount and capacity update correctly | PASS | Mining topped off the hold at its exact capacity. |
| Full cargo prevents additional mining | PASS | Full and special-cargo holds rejected additional ore. |
| Main-station docking completes | PASS | Automated approach opened the real dock UI. |
| Ore sale changes cargo and credits correctly | PASS | Station sale path credited the exact ore amount and cleared the hold. |
| Ore can be deposited into station storage | PASS | Deposit moved ore into persistent player storage and cleared the hold. |
| Undocking restores flight controls | PASS | Dock state and UI cleared with manual navigation restored. |
| Gate jump autosaves current state | PASS | Gate travel wrote the validated player, quest, system, storage, and upgrade state. |
| Closing and reopening restores the autosaved state | PASS | Dock autosave restored player position and active mission; continued-game UI refreshed without replaying the new-pilot introduction. |
| Restart Game deletes progress and starts fresh | PASS | Confirmed in normal game window. |

## Session B: Combat, Damage, Death, And Reputation

| Test | Result | Notes |
| --- | --- | --- |
| Player weapon damages a valid target | PASS | Player projectile damaged an enemy; same-faction projectile was ignored. |
| Hostile ships engage under expected reputation rules | PASS | Major-faction enemy acquired the player outside station protection. |
| Safe-zone behavior prevents inappropriate attacks | PASS | Ordinary hostility stood down; severe hostility correctly overrode protection. |
| Hull and shields update correctly under damage | PASS | Shields absorbed damage first and excess spilled into hull. |
| Destroyed ships produce expected rewards/state | PASS | Wreck, pool count, entity removal, credits, and quest signal verified. |
| Faction reputation changes after hostile action | PASS | Hit, kill, and enemy-faction reputation changes matched the rules. |
| Death screen appears when the player is destroyed | PASS | Fatal damage opened the real death panel. |
| Restart from death returns to a fresh game | PASS | Death-screen restart reloaded fresh health, credits, quest, and UI state. |

## Session C: Missions, Dialogue, LLM, And TTS

| Test | Result | Notes |
| --- | --- | --- |
| Kaelen introduction appears and speaks | PASS | Confirmed in the normal game window. |
| Agent board receives a generated or fallback mission | PASS | Local procedural fallback produced a complete playable contract. |
| Mission briefing numbers match objective numbers | PASS | Validation reconciled generated dialogue and tracker objectives. |
| Mission can be accepted | PASS | Objective and selected-choice consequences were applied. |
| Kill mission progress updates and completes | PASS | Matching destruction signals advanced and completed the objective. |
| Ore mission supports partial and final delivery | PASS | Partial ore banked correctly; the final shipment paid and cleared cargo. |
| Mission abandonment removes it and changes reputation | PASS | Contract cleared and applied the approved three-point penalty. |
| LLM timeout produces a playable fallback mission | PASS | Failure path produced objective, dialogue, choices, and aligned numbers. |
| TTS failure leaves readable dialogue and playable UI | PASS | Failed speech request ended cleanly without altering displayed text. |
| Non-Kaelen speakers say Indy rather than Shiny | PASS | Tone guard rewrote non-Kaelen speech while preserving Kaelen's nickname. |

## Session D: Services And Upgrades

| Test | Result | Notes |
| --- | --- | --- |
| Repair service restores hull and charges correctly | PASS | Full and partial repairs charged exactly two credits per hull point. |
| Station storage persists through travel | PASS | Stored ore survived outbound and return gate travel without changing. |
| Upgrade panel shows current power use | PASS | Maintenance UI displayed the 300 / 300 MW starter load. |
| Valid upgrade purchase applies stats and costs | PASS | Powerplant then engine purchase applied tier, cost, capacity, and speed. |
| Invalid over-budget upgrade is rejected | PASS | Mining upgrade was rejected without charging when power was capped. |
| Upgrade state survives gate travel | PASS | Engine tier and speed remained intact across outbound and return jumps. |
| Upgrade state survives autosave and relaunch | PASS | Tier, path, power capacity, speed, and stored ore restored. |
| Outposts show the correct limited service menus | PASS | Commerce, agents, repairs, maintenance, and upgrades remained hidden. |
| Hear Gossip displays and speaks an NPC line | PASS | Button path displayed the line and emitted NPC voice routing data. |
| Mechanic pickup mission can be accepted | PASS | Real pickup quest state and destination fields were accepted. |
| Pickup occurs only at the assigned outpost | PASS | Wrong outpost refused; assigned outpost loaded the part. |
| Returning the part completes the mission | PASS | Main-station delivery cleared cargo, completed the quest, and paid credits. |

## Session E: Gate Presentation And Edge Cases

| Test | Result | Notes |
| --- | --- | --- |
| Out-of-range gate activation is refused clearly | PASS | Activation returned the expected move-within-range reason. |
| Misaligned gate activation is refused clearly | PASS | Activation returned the expected alignment reason. |
| Jump transition is visually continuous | PASS | Confirmed in the normal game window. |
| Gate autopilot stages in front before entry | PASS | 260-unit staging marker and alignment hold passed automated and hands-on checks. |
| Controls remain locked during transition | PASS | Physics and world input were disabled while the transition ran. |
| Camera and controls work after arrival | PASS | Camera followed the player and physics/input processing resumed. |
| Arrival does not accidentally trigger a return jump | PASS | Flight back provides natural spacing; technical cooldown remains. |
| Return jump works in normal gameplay | PASS | The paired return gate restored the starting system and player state. |
| Docking and ordinary gameplay work after returning | PASS | Flight and docking worked normally after the return jump. |

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

### Mission Abandonment Penalty

Status: FIXED.

Observed:

- The prototype removed five reputation points when abandoning a mission,
  exceeding the approved small two-to-three-point campaign penalty.

Change:

- Reduced abandonment reputation loss to three points.
- Added mission regression coverage for contract removal and exact reputation
  change.

### Pickup Reward Validation

Status: FIXED.

Observed:

- A pickup mission with a stale `picked_up` flag could grant credits and
  reputation before verifying that the assigned part remained in cargo.

Change:

- Moved special-cargo validation ahead of all payout and reputation changes.
- Added checks proving the wrong part grants nothing and the assigned part
  completes and clears cargo normally.

### Stored Ore Upgrade Purchase

Status: FIXED.

Observed:

- The upgrade engine accepted ore from cargo plus station storage, but the
  maintenance UI rejected the same purchase unless all ore was in cargo.

Change:

- Maintenance purchase validation now totals cargo ore and stored ore using the
  same rule as the upgrade engine.
- Added a UI-path test that buys power and engine upgrades using stored ore.

### Upgrade Save Restoration

Status: FIXED.

Observed:

- JSON restored upgrade tiers as numeric values such as `2.0`, while upgrade
  tables are keyed by integers. Loading a save with upgraded equipment failed
  while applying stats.

Change:

- Loaded upgrade tiers are normalized to integers and paths to strings before
  applying equipment stats.
- Added save/load coverage for storage, powerplant tier, engine tier, power
  capacity, and engine speed.

### Docking Autosave

Status: FIXED.

Observed:

- Gate arrival wrote an autosave, but docking at the main station or an outpost
  did not preserve the player's latest progress.

Change:

- Successful docking now requests an autosave after dock state and position are
  established.
- Added coverage proving every current dockable opens the dock UI, creates the
  save file, and restores manual flight state after undocking.

### Continued Game Presentation

Status: FIXED and hands-on verified.

Observed:

- The debug-run save contained the accepted mission, player position,
  reputation, and system entities.
- On relaunch, the mission tracker did not refresh from restored state and
  Kaelen replayed her new-pilot introduction, making a continued game appear to
  be a fresh start.

Change:

- Startup load now reports whether a valid save was restored.
- Restored credits, cargo, mission tracker, and overview refresh after save
  application.
- Kaelen's new-pilot introduction is skipped when continuing a saved game.

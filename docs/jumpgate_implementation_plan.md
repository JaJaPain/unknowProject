# Jumpgate And Multi-System Implementation Plan

## Goal

Add a second star system containing one planet and a return jumpgate. The
player must be able to travel between the existing system and the new system
through reusable gates while preserving player progress, relevant world state,
quests, and immersion.

## Safety And Workflow

- Baseline commit before implementation: `9cc30ed`.
- Verify the working tree is clean.
- Keep large binary models out of normal Git history. `assets/hypergate.glb`
  remains local and is covered by the repository's existing `*.glb` ignore
  rule.
- Keep Godot's locally extracted `assets/hypergate_*` texture sidecars ignored
  with the external model.
- Treat `assets/hypergate.glb` as an external project prerequisite and document
  its expected path so a fresh checkout fails clearly rather than silently.
- Perform implementation on a dedicated `codex/jumpgate-system` branch.
- Implement one phase at a time.
- After each phase:
  - Run `git diff --check`.
  - Review the complete phase diff.
  - Run relevant Godot parse or runtime checks.
  - Check off the phase only after it passes review.
- Run a final Godot compile/startup verification before requesting playtesting.

## Current Project Findings

- `scenes/main.tscn` currently contains the world, player, and UI.
- `scripts/MainScene.gd` regenerates asteroid rings and NPC populations whenever
  the scene loads.
- Persistent progression already lives in autoloads:
  - Credits, cargo, upgrades, reputation, and global ship stats in
    `GlobalState`.
  - Active quest data in `QuestManager`.
- Hull, shields, ship transform, velocity, active target, and spawned system
  entities are currently scene-local.
- `UIManager` already provides target actions and an overview list, so jumpgate
  controls can extend those existing systems.
- Godot AI `2.5.9` is an editor and testing bridge. It can assist with scene,
  resource, particle, material, and runtime inspection, but it is not gameplay
  AI.
- `assets/hypergate.glb` is a static model with nine meshes, six materials,
  several emissive textures, and no built-in animation.

## Target Architecture

Create a persistent root that owns the player, UI, active system, and transition
effects:

```text
GameRoot
|-- SystemContainer
|   `-- CurrentSystem
|-- PlayerShip
`-- CanvasLayer
    |-- UIManager
    `-- JumpTransitionFX
```

Planned scenes:

- `scenes/game_root.tscn`
  - Persistent player, UI, system container, and transition layer.
- `scenes/systems/system_start.tscn`
  - Existing world content without player or UI.
- `scenes/systems/system_test.tscn`
  - One planet, lighting, a gate, and arrival markers.
- `scenes/jump_gate.tscn`
  - Reusable wrapper around `hypergate.glb`.
- `scenes/jump_transition_fx.tscn`
  - Screen-space hyperspace presentation.

## Jumpgate Design

Each reusable gate will contain:

- A stable gate ID.
- Destination system ID and destination gate ID.
- The centered, scaled, and oriented `hypergate.glb` model.
- Structural collision around the frame.
- A separate activation volume around the gate opening.
- An exit marker pointing away from the gate.
- A portal surface, particles, emissive animation, and lights.
- An arrival cooldown that prevents immediately jumping back.
- Membership in a `jumpgate` group for targeting and UI discovery.

The player will explicitly activate a selected gate rather than automatically
jumping on collision. This avoids accidental system changes during navigation
or combat.

## Player Interaction

1. Select the gate in space or from the overview.
2. The target panel identifies it as a jumpgate and displays its destination.
3. Use `Approach Gate` to engage autopilot.
4. When the ship is close enough and properly aligned, `Initiate Jump` becomes
   available.
5. Activation is refused while docked, destroyed, outside range, misaligned, or
   while another jump is active.
6. Controls and world interactions are locked during the transition.
7. The player arrives beyond the paired gate, facing away from it.

## Hyperspace Sequence

Target duration: approximately four seconds.

1. Autopilot aligns the ship with the gate.
2. Gate lights, emissive materials, particles, and portal energy intensify.
3. Camera field of view widens while the ship accelerates into the opening.
4. A bright flash transitions to a full-screen hyperspace tunnel with moving
   star streaks and subtle distortion.
5. The current system is captured and the destination loads while the screen is
   obscured.
6. The ship is positioned at the paired gate's exit marker.
7. An emergence flash fades, camera settings return to normal, and controls
   unlock.

The tunnel should be implemented as a screen-space shader and supporting
particles so it masks loading without requiring another large model.

Audio hooks should support:

- Engine or reactor spool-up.
- Gate energy pulse.
- Transit rush.
- Arrival impact.

The sequence must degrade gracefully if dedicated sounds are not yet available.

## State Model

### Persistent Player State

- Credits.
- Cargo and special cargo.
- Stored ore.
- Installed upgrades and derived ship stats.
- Reputation and kill counts.
- Active quest and progress.
- Hull and shield values.
- Current system ID.
- Arrival gate ID.

### Per-System State

Store snapshots by stable system and entity IDs:

```text
systems
|-- start_system
|   |-- mined asteroids
|   |-- destroyed persistent entities
|   |-- mission entities
|   `-- important NPC state
`-- test_system
    |-- planet/system state
    `-- destroyed persistent entities
```

Ambient patrols may regenerate initially. Hand-authored objects, quest targets,
mined asteroids, and other meaningful state should persist.

Persistent entities will expose a small state interface:

- `get_persistent_id()`
- `capture_state()`
- `restore_state(state)`

### Disk Save

Use a versioned `user://savegame.json` containing player state, current
location, active quest state, and per-system snapshots.

Autosave after:

- A successful gate arrival.
- Station docking.

Loading must validate the save version and fall back safely when optional fields
are absent.

## Required Refactoring

- Replace gameplay spawning through `get_tree().current_scene` with the active
  system root supplied by the system manager.
- Replace searches for a node literally named `Station` with groups or explicit
  system spawn markers.
- Move hard-coded safe-zone coordinates into system-owned safe-zone nodes.
- Add system IDs to quest objectives that are tied to a location.
- Ensure startup LLM and TTS preparation runs once even though systems change.
- Make restart reload the complete `GameRoot`, not the currently active system.
- Clear `GlobalState.active_target` and scene-node references before unloading a
  system.

## Implementation Checklist

### Phase 0: Git Safety

- [x] Confirm clean working tree.
- [x] Confirm `assets/hypergate.glb` remains excluded by the repository's
      `*.glb` ignore rule.
- [x] Document `assets/hypergate.glb` as a required external asset.
- [x] Create and switch to `codex/jumpgate-system`.
- [x] Commit this implementation plan.
- [x] Review the Phase 0 diff and Git status.

### Phase 1: Persistent Game Root

- [x] Add `GameRoot` with the player, UI, system container, and transition layer.
- [x] Extract the existing world into `system_start.tscn`.
- [x] Preserve current startup behavior.
- [x] Redirect system spawning to the active system root.
- [x] Update restart to reset and reload the full game.
- [x] Run Godot parse/startup checks.
- [x] Review the complete Phase 1 Git diff.

### Phase 2: Reusable Gate And Test System

- [x] Build the reusable `jump_gate.tscn` wrapper.
- [x] Calibrate model center, scale, and orientation.
- [x] Add structural collision, activation volume, portal, and arrival marker.
- [x] Add gate metadata and stable IDs.
- [x] Place an outbound gate in the starting system.
- [x] Build `system_test.tscn` with one planet and a paired return gate.
- [x] Run scene parse and startup checks.
- [x] Review the complete Phase 2 Git diff.

### Phase 3: System Loading And Two-Way Travel

- [x] Add a system manager.
- [x] Load and unload systems beneath `SystemContainer`.
- [x] Preserve the player and UI between systems.
- [x] Clear stale targets and references before unloading.
- [x] Resolve the paired destination gate and arrival marker.
- [x] Place and orient the player safely on arrival.
- [x] Add arrival cooldown protection.
- [x] Verify repeated start-to-test and test-to-start travel.
- [x] Review the complete Phase 3 Git diff.

### Phase 4: Gate UI And Activation

- [x] Show jumpgates in the overview list.
- [x] Add jumpgate target-panel labeling and destination details.
- [x] Add `Approach Gate`.
- [x] Add `Initiate Jump`.
- [x] Enforce distance, alignment, alive, undocked, and transition-state checks.
- [x] Lock navigation, targeting, and combat input during travel.
- [x] Show clear status and refusal messages.
- [x] Review the complete Phase 4 Git diff.

### Phase 5: Hyperspace Effects

- [x] Animate gate portal energy, lights, and emissive intensity.
- [x] Add spool-up and ship acceleration.
- [x] Add camera FOV change and entry flash.
- [x] Add the full-screen hyperspace tunnel shader.
- [x] Load the destination while the tunnel obscures the scene.
- [x] Add emergence flash and restore camera/control state.
- [x] Add audio hooks with fallback behavior.
- [x] Review the complete Phase 5 Git diff.

### Phase 6: Session And Disk State

- [x] Capture and restore hull, shields, transform, and player runtime state.
- [x] Add stable IDs to meaningful system entities.
- [x] Capture mined and destroyed persistent entity state.
- [x] Preserve quest target state across systems.
- [x] Add versioned JSON save and load support.
- [x] Autosave after arrival and docking.
- [x] Verify missing, old, and malformed save handling.
- [x] Review the complete Phase 6 Git diff.

### Phase 7: Final Verification

- [x] Run `git diff --check`.
- [x] Review the final aggregate diff for accidental overwrites.
- [x] Run Godot headless import.
- [x] Run script and scene parse verification.
- [x] Start the project long enough to catch startup runtime errors.
- [x] Verify two-way jumping repeatedly with the automated smoke test.
- [x] Verify save validation and player, quest, and system-state restoration with
      the automated smoke test.
- [ ] Complete the hands-on gameplay pass for restart, pause, targeting, combat,
      cargo, upgrades, quests, docking, autosave, and restored state.
- [x] Confirm final Git status and report anything not committed or pushed.

## Completion Criteria

Implementation is complete only when:

- The player can intentionally travel through either gate.
- Both systems load correctly in both directions.
- The transition looks continuous and hides loading.
- Player progression and runtime health survive travel.
- Meaningful system state survives leaving and returning.
- Saves restore the player in a valid system at a valid location.
- Restart still produces a clean new game.
- Godot parses and starts without errors.
- Every phase has passed its own diff review.

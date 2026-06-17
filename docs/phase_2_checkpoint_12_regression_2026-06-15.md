# Phase 2 Checkpoint 12: Regression And Approval

Date: 2026-06-15

Status: Automated verification complete; hands-on approval pending

Branch: `codex/jumpgate-system`

Godot: 4.6.3 stable

## Automated Regression

The expanded offline baseline passes 31 of 31 steps. It covers:

- storage schemas and ownership
- three isolated campaign slots
- atomic transactions and last-known-good recovery
- safe and manual checkpoint bundles
- chronicle branching and discarded futures
- bounded Kaelen meta-memory and death rollback
- version-2 import and startup resume
- manifest and generated-asset recovery
- consolidated Phase 2 ownership acceptance
- missions, economy, services, combat, restart, death reload, controls,
  navigation, gate travel, cross-system backup restore, docking, and autosave
- station-adjacent real-projectile combat from loaded numeric state

## Exit-Criteria Audit

| Criterion | Result | Evidence |
| --- | --- | --- |
| Permanent canon survives checkpoint loads | PASS | Manifest bytes remain unchanged through discovery, autosave, manual rewind, and recovery fixtures. |
| Mutable state rewinds exactly | PASS | Manual and death reload restore the selected safe checkpoint's credits, mission-compatible state, map knowledge, ship state, and safe location. |
| In-flight saving cannot preserve tactical advantage | PASS | Checkpoint sanitization removes position, velocity, navigation, projectiles, aggro, combat targets, transition state, and death UI state. |
| Interrupted writes recover safely | PASS | Injected transaction failures and damaged active indexes restore validated last-known-good data. |
| Three campaigns remain isolated | PASS | Creation, selection, writes, import, rename, and deletion remain inside stable slot directories. |
| Phase 3 can add universal time without changing ownership | PASS ARCHITECTURE | Permanent canon, append-only chronicle, rewindable checkpoint state, regenerable assets, and restricted meta-memory remain separate validated documents. |

## Storage Measurement

The repeatable measurement fixture created:

- one representative campaign with 120 persisted entities
- 25 rolling autosaves
- two backup copies
- 100 append-only chronicle events

Results:

| Measurement | Result |
| --- | ---: |
| Campaign storage | 551,091 bytes (538.2 KiB) |
| Files | 122 |
| Retained rolling autosave bundles | 2 |
| Campaign creation | 1,182 ms |
| Average autosave commit | 24.0 ms |
| Average chronicle append | 16.1 ms |
| Campaign reopen and validation | 3.1 ms |

Checkpoint 12 found and fixed unbounded rolling-autosave bundle retention.
Successful autosaves now retain only the active bundle and the prior bundle
referenced by last-known-good recovery. Manual checkpoints and append-only
chronicle history remain untouched.

The save screen now presents three independent campaigns. Each campaign has
one protected Continue Point and two Backup Copies. Backup Copies duplicate the
current safe Continue Point and do not update until replaced. The first
generated story supplies the campaign name, with a curated local fallback, and
save labels use `<campaign name> - <timestamp>`.

## Manual-Test Findings Addressed

- Cross-system backup restoration now has an automated regression that creates
  a backup in the starting system, moves to the test system, and restores the
  correct starting-system scene and safe location.
- The frequent ship-kill failure was recovered from the Godot log. Loaded JSON
  kill counters could be floats, and the reinforcement remainder calculation
  required integers. Loaded counters and kill updates are now normalized.
- A station-adjacent combat regression uses real projectiles beside the main
  station and exercises the loaded-state third-kill path through destruction.
- Projectiles resolve only one hit, NPC targets are revalidated before transform
  access, and NPC death is guarded against duplicate execution.
- Runtime combat, checkpoint, and scene-transition events are flushed to
  `user://diagnostics/runtime_trace.jsonl`. The prior session is retained as
  `runtime_trace.previous.jsonl`.

## Rendered Performance

The capture used Vulkan Forward+ at 1920 x 1080 on the existing development
machine with an RTX 5060 Ti. AI and speech service discovery were disabled.

| Scene | Average FPS | Minimum FPS | Godot RAM | Render memory | Texture memory | Draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Main station | 59.3 | 50 | 101.4 MiB | 369.1 MiB | 237.1 MiB | 187 |
| Asteroid field | 60.0 | 60 | 101.5 MiB | 369.1 MiB | 237.1 MiB | 163 |
| Combat | 60.2 | 57 | 102.6 MiB | 369.1 MiB | 237.1 MiB | 212 |

Phase 2 produced no material renderer-memory or frame-rate regression from the
Phase 1 snapshot.

## Hands-On Approval Checklist

1. Open `CAMPAIGNS & SAVES`. Create, rename, and continue campaigns in
   different slots. Confirm each slot shows its own name and checkpoint.
2. Dock, change something persistent such as cargo, credits, repairs, or an
   upgrade, then undock. Confirm one save notification appears. Quit and
   relaunch; confirm the state restores.
3. Travel through a gate and return. Confirm both arrivals work and normal
   docking remains available.
4. While flying, copy the Continue Point into a Backup Copy. Travel through a
   gate, then load the copy. Confirm the correct prior scene and safe dock/gate
   state return rather than the dangerous in-flight position.
5. Die and choose `Load Last Save`. Confirm the living checkpoint returns.
   Die again and choose `Start New Campaign`; confirm a fresh ship and campaign
   manager appear.
6. Delete one campaign. Confirm the other occupied slots still load and retain
   their own names and checkpoints.
7. Confirm the redesigned pause, campaign, and death screens are readable and
   no buttons overlap at 1920 x 1080.

Corruption and interrupted-write recovery are deterministic file-level cases
covered by focused automated fixtures; no live campaign needs to be damaged for
the hands-on review.

## Remaining Known Risks

- Headless shutdown can still report resources alive after test assertions
  finish.
- The intended combined game-and-model behavior on an 8 GB GPU remains a
  release-target measurement.
- Exported-build installation size and Windows process working set remain
  release-target measurements.
- Graphical approval of the current campaign screens and stabilized autopilot
  route feel remains pending hands-on confirmation.
- The LLM fallback still needs tuning: fallback dialogue can describe a
  different client or objective than the rendered contract details.

# Phase 1 Checkpoint 9: Regression And Approval

Date: 2026-06-14

Status: Complete; automated and hands-on approval passed

Branch: `codex/jumpgate-system`

Godot: 4.6.3 stable

## Automated Regression

The expanded offline baseline passes 18 of 18 steps:

1. Static diff check.
2. Godot import and parse.
3. Domain ID and validation foundation.
4. System and gate registry.
5. Persistent world identity.
6. Faction, NPC, ship, portrait, and voice definitions.
7. Unified speech service.
8. Mission definitions and state adapter.
9. Transitional save migration.
10. Mission gameplay lifecycle.
11. Mining, economy, and upgrades.
12. Station services and pickup routing.
13. Combat, damage, death, and restart.
14. Warm-service game restart.
15. Core startup and controls.
16. Autopilot obstacle and planet-circle navigation.
17. Two-way gate travel and save restoration.
18. Docking and dock autosave.

The suite runs model and speech discovery offline. Mission fallback, TTS
failure, save migration, service restart, and gameplay behavior are tested
without requiring Ollama or Kokoro to be available.

## Exit-Criteria Audit

| Criterion | Result | Evidence |
| --- | --- | --- |
| Handcrafted systems load through the registry | PASS | `main.tscn` no longer embeds a system. `GameRoot` resolves and instantiates `system.start` through `SystemRegistry`; a registry test prevents direct system-scene embedding. |
| Persistent entities use stable IDs | PASS | World-identity collection validation runs at startup and before state capture. Stateful entities save through identity envelopes. |
| Current gameplay remains intact | PASS AUTOMATED | The 18-step suite covers startup, controls, navigation, mining, economy, services, missions, combat, death, restart, docking, gates, and save restoration. |
| Existing saves migrate or fail safely | PASS | Version-1 migration, canonical IDs, backup integrity, damaged JSON, and unsupported future versions have deterministic fixtures. |
| Phase 2 does not need scene parsing for campaign state | PASS | System, gate, content, entity, mission, speech, and save boundaries now expose typed or registry-backed data. |

## Registry-Only Startup

The starting system was removed from `main.tscn`. At startup, `GameRoot` now:

1. loads and validates `SystemRegistry`
2. resolves `system.start`
3. loads the registered packed scene
4. attaches it to `SystemContainer`
5. exposes its current compatibility runtime ID

Gate transitions and startup now use the same scene-resolution authority.

## Performance Snapshot

This capture used Vulkan Forward+ at 1920 x 1080 on the existing development
machine with an RTX 5060 Ti. AI and speech service discovery were disabled so
the measurement isolates the rendered game.

| Scene | Average FPS | Minimum FPS | Godot RAM | Render memory | Texture memory | Draw calls | Rendered objects |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Main station | 60.3 | 59 | 97.7 MiB | 369.1 MiB | 237.1 MiB | 185 | 1,007 |
| Asteroid field | 60.1 | 60 | 97.8 MiB | 369.1 MiB | 237.1 MiB | 193 | 1,016 |
| Combat | 58.7 | 57 | 98.9 MiB | 369.1 MiB | 237.1 MiB | 212 | 1,247 |

Compared with Phase 0:

- renderer memory changed from about 367.7 MiB to 369.1 MiB
- texture memory remained about 237 MiB
- station performance improved from 57.1 average FPS to 60.3
- asteroid-field performance remained near the 60 FPS cap
- combat changed from 59.7 average FPS to 58.7

These are small debug-run variations. Phase 1 introduced no material renderer
or VRAM regression. The 8 GB combined game-and-model target still requires
testing on representative 8 GB hardware.

Startup timing from this run is not directly comparable with Phase 0 because
the Phase 1 capture intentionally bypassed external AI and speech discovery.

## Hands-On Approval Route

The remaining review is intentionally short because detailed mechanics are
already deterministic in the automated suite.

1. Launch normally through Godot and confirm the starting system, ships,
   stations, HUD, and Kaelen presentation appear normally.
2. Dock, accept any available mission, undock, quit, and relaunch. Confirm the
   continued game restores the mission and does not replay the new-pilot
   introduction.
3. Travel through the gate, confirm the generated test system loads, then
   return through its paired gate.
4. Dock after returning and confirm station services still open normally.
5. Enter combat and confirm visible shield/hull damage and the death screen.
6. Use `Restart Game` from death and confirm a fresh game begins.

Mission-type-specific completion, abandonment, pickup, ore, and kill behavior
does not need to be obtained randomly for this review; those paths pass the
automated lifecycle tests.

## Hands-On Result

The normal-play approval route passed:

- the registry-loaded starting system presented normally
- docking and mission acceptance remained playable
- autosaved mission state restored after relaunch without replaying the
  new-pilot introduction
- outbound and return gate travel worked
- station services remained available after returning
- combat, death presentation, and fresh-game restart worked

Phase 1 is approved complete.

## Remaining Known Risks

- Headless shutdown can still report resources alive after assertions finish.
- The navigation smoke test excludes randomly placed live belt asteroids only
  during its multi-planet segment; asteroid avoidance is verified separately.
- Player-facing save slots and manual save/load controls remain future work.
- Exported-build size, process RAM, and representative 8 GB GPU behavior remain
  release-target checks rather than Phase 1 blockers.

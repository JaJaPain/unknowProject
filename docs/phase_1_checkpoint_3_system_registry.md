# Phase 1 Checkpoint 3: System And Gate Registry

Status: Complete

## Added

- Canonical JSON definitions for the handcrafted start and test systems.
- Typed `SystemDefinition` and `GateDefinition` domain classes.
- A `SystemRegistry` that resolves canonical and legacy IDs.
- Scene-resource validation.
- Duplicate canonical-ID and legacy-alias validation.
- Destination-system and destination-gate validation.
- Reciprocal gate-pair validation.
- Tests comparing registry gate metadata to the actual Godot scenes.

## Runtime Integration

`GameRoot.SYSTEM_SCENES` was removed. `GameRoot` now asks `SystemRegistry` to:

- confirm a saved system exists
- resolve canonical or legacy system IDs
- load the registered system scene
- translate canonical IDs to current runtime IDs
- resolve arrival-gate IDs

The current scenes and save schema still use:

- `start_system`
- `test_system`
- `start_to_test`
- `test_to_start`

This is intentional. The registry translates these values at its boundary so
travel and existing saves continue to work. Checkpoint 8 will migrate saved
data to canonical IDs.

## Verification

Registry tests cover:

- canonical and legacy ID resolution
- scene loading through either ID form
- registry metadata matching scene gate metadata
- reciprocal gate links
- unknown destination systems
- missing scene resources
- duplicate legacy aliases

The complete baseline suite passes:

1. Static diff check.
2. Godot import and parse.
3. Domain ID and validation foundation.
4. System and gate registry.
5. Core startup and controls.
6. Two-way gate and save restoration.
7. Docking and dock autosave.

No system scene is selected by display name or node name.

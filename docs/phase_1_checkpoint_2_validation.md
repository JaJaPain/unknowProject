# Phase 1 Checkpoint 2: ID And Validation Foundation

Status: Complete

## Added

- Stable authored-ID validation using lowercase dot-separated namespaces.
- Reserved generated-ID construction using campaign and creation keys.
- Legacy aliases for the current systems, gates, and major factions.
- Structured validation errors and warnings with nested field paths.
- A common definition parser for IDs and schema versions.
- JSON object parsing, file loading, serialization, and deep-copy helpers.
- A standalone headless domain test runner.
- A domain-foundation step in the baseline verification suite.

## Validation Rules

- IDs require at least two segments.
- IDs allow lowercase ASCII letters, digits, and underscores.
- Leading or trailing whitespace is rejected.
- Callers may require a specific namespace.
- Schema versions must be whole numbers.
- Missing, malformed, and unsupported schema versions fail clearly.
- JSON definition roots must be objects.
- Malformed JSON reports its parser message, source, and line.

## Compatibility

The following legacy values currently translate at domain boundaries:

- `start_system` to `system.start`
- `test_system` to `system.test`
- `start_to_test` to `gate.start.to_test`
- `test_to_start` to `gate.test.to_start`
- `zenith` to `faction.zenith`
- `aurelia` to `faction.aurelia`
- `vanguard` to `faction.vanguard`

No gameplay caller uses the new IDs yet. Checkpoint 3 introduces the first
runtime adapter through the system and gate registry.

## Verification

The baseline suite passed all six steps:

1. Static diff check.
2. Godot import and parse.
3. Domain ID and validation foundation.
4. Core startup and controls.
5. Two-way gate and save restoration.
6. Docking and dock autosave.

No gameplay scripts or scenes were changed in this checkpoint.

# Phase 1 Checkpoint 8: Transitional Save Migration

Status: Complete

## Purpose

The prototype now has a versioned save boundary that can upgrade the existing
version-1 save without asking gameplay systems to abandon their proven runtime
IDs. Version 2 remains one save file; Phase 2 will split campaign state into
separate stores.

## Version 2 Contract

Version-2 saves store canonical registry IDs for:

- the current system
- the arrival gate
- each system-state dictionary key
- the active mission's system

For example, `start_system` is written as `system.start`, while
`start_to_test` is written as `gate.start.to_test`.

The loader converts those canonical IDs back to the current runtime aliases
before applying state. Existing scene, gate, mission, and UI behavior therefore
continues to use the compatible runtime shape.

## Migration Sequence

When a version-1 save is opened:

1. The source JSON is parsed without changing the file.
2. Legacy mission state receives deterministic typed identity metadata.
3. Legacy system and gate aliases are resolved through `SystemRegistry`.
4. The complete version-2 result is validated in memory.
5. The original file is copied to a timestamped version-1 backup.
6. The migrated save is written to a temporary file and read back.
7. The temporary file must pass current-schema validation.
8. Only then does it replace the active save.

If final replacement fails, the original is restored from its backup.

Backup names follow:

`savegame.json.v1.<unix timestamp>.backup`

A numeric suffix is added if a backup with the same timestamp already exists.

## Failure Rules

- Damaged JSON is rejected without rewriting the source.
- Missing required save sections are rejected.
- Unknown system or gate IDs are rejected.
- Version-2 data containing legacy IDs is rejected.
- Unsupported future versions are rejected with the expected version.
- Malformed active mission state is rejected.
- Save loading does not invoke an LLM, speech provider, or generator.

## Automated Coverage

The focused migration fixtures verify:

- in-memory version-1 to version-2 migration
- canonical top-level, system-state, and mission IDs
- decoding back to compatible runtime IDs
- byte-for-byte preservation of the version-1 backup
- installation and validation of the migrated active save
- damaged source files remain unchanged
- unsupported future source files remain unchanged

The complete baseline passes 14 of 14 steps, including mission gameplay,
autopilot navigation, two-way gate travel, save restoration, docking, and dock
autosave.

During verification, the fallback mission consistency guard was also expanded
to recognize digits, spelled numbers, and phrases such as `a few`. Randomized
combat objectives now remain aligned with both displayed dialogue and speech.

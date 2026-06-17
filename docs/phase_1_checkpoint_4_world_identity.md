# Phase 1 Checkpoint 4: Persistent World Identity

Status: Complete

## Added

- A shared world-identity contract.
- A separate stateful-entity contract for objects with mutable saved state.
- Stable IDs for current stations and gates.
- Explicit IDs for authored, ambient, incoming, and reinforcement NPC ships.
- Mission-specific IDs and monotonic spawn sequences for mission targets.
- State schema, entity ID, and entity type metadata in saved entity records.
- Duplicate-ID and missing-contract validation before saving or gate travel.

## Identity And State

World identity and saved state are related but separate:

- Stations and gates have stable world IDs but currently have no mutable state.
- Ordinary NPC ships have stable world IDs for their current lifetime.
- Asteroids and mission ships implement the full stateful contract.

Stateful entities provide:

- `get_world_id()`
- `get_world_type_id()`
- `get_state_schema_version()`
- `capture_state()`
- `restore_state(state)`

The old `get_persistent_id()` methods remain as compatibility wrappers.

## Save Protection

Before state is captured, the game validates the complete active-system
identity set. A save is cancelled if it finds:

- an empty identity
- a duplicate identity
- a missing world-type method
- a missing state capture or restore method
- an invalid state schema version

Validation happens before the entity dictionary is modified, preventing one
duplicate key from silently overwriting another entity.

## Mission Target IDs

Accepted missions now receive a runtime identity. Combat targets use a digest
of that identity plus a saved monotonic spawn sequence.

Replacement targets therefore cannot reuse the first target's ID, and a later
mission against the same faction does not inherit the previous mission's
entity keys.

## Transitional Asteroid IDs

The existing asteroid keys, such as `GasGiantBelt_Asteroid_0`, remain unchanged
for current-save compatibility. They are now assigned explicitly at creation
and are no longer inferred inside `Asteroid.gd` from the node name.

Checkpoint 8 will migrate these legacy save keys to the final canonical ID
format with backup and rollback protection.

## Verification

The world-identity tests cover:

- valid immutable identities
- rejected empty identities
- stateful-contract completeness
- duplicate detection
- state envelope metadata

The live core smoke test validates all station, gate, ship, and asteroid
identities in the starting system.

The complete baseline suite passes all eight steps, including two-way travel,
save restoration, and dock autosave.

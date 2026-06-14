# Phase 2 Checkpoint 4: Campaign Manifest And Asset Registry

Status: Complete on 2026-06-14

## Added

- A permanent `CampaignManifestStore` for campaign canon.
- Immutable, numbered canon generations exposed through `canon_index.json`.
- Append-only registration for generated entities and canon facts.
- Permanent asset records containing:
  - stable asset and owner IDs
  - generator name and version
  - generation seed
  - provenance hash
  - source and fallback paths
  - validation status
  - deterministic rebuild instructions
- Asset auditing that selects an existing fallback or marks an asset for
  rebuilding without changing its identity, seed, or provenance.
- Initial campaign adapters for the existing handcrafted system and content
  registries.
- Atomic creation of canon generation 1 with every new campaign.
- Focused regression coverage and full baseline-suite integration.

## Initial Campaign Canon

New campaigns snapshot the validated Phase 1 registries into their permanent
manifest. This includes:

- systems, stations, and gates
- factions and NPCs
- voice profiles
- ship designs
- portrait definitions

The registry source and a deterministic definition hash are retained for each
identity. Curated system scenes, ship models, and portrait sheets are also
registered as permanent assets.

These records are campaign-local canon after creation. Later changes to the
handcrafted registries do not silently rewrite an existing campaign.

## Append-Only Generations

The active permanent state is selected by `canon_index.json`. Each canon
change writes a new pair:

- `canon/manifest_NNNNNN.json`
- `canon/assets_NNNNNN.json`

The transaction installs both immutable files before replacing the canon
index. Root `manifest.json` and `assets.json` remain current compatibility
snapshots, but the numbered generation selected by the index is authoritative.

Registering the same identity and definition again is idempotent. Reusing a
stable ID with different canon is rejected instead of rewriting history.

## Missing Asset Policy

Asset audits use three operational outcomes:

- `approved`: the original source exists
- `fallback`: the source is missing but its registered fallback exists
- `rebuild_required`: neither path exists, so the preserved seed and
  instructions must be used to recreate it

Only validation status may change during an audit. Asset ID, owner ID,
generation seed, generator metadata, source path, and provenance remain
permanent.

## Regression Coverage

The focused tests verify:

- campaign creation captures the handcrafted registries
- canon starts at generation 1
- generated identities and facts append new generations
- duplicate registration is idempotent
- conflicting reuse of an existing stable identity is rejected
- reading the initial checkpoint cannot rewind permanent canon
- missing sources select registered fallbacks
- fully missing assets request rebuilding
- reopening preserves the original asset IDs, seeds, and provenance

## Scope

This checkpoint stores permanent identities and asset provenance. It does not
yet capture replacement safe gameplay checkpoints or connect generated
systems to an active campaign. Those features begin with Phase 2 Checkpoint 5
and later generation phases.

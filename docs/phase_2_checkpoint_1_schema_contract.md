# Phase 2 Checkpoint 1: Campaign Storage Schema Contract

Status: Complete on 2026-06-14

## Added

- One shared campaign schema catalog for all Phase 2 persistence services.
- Versioned validators for:
  - campaign identity
  - permanent manifest
  - generated asset registry
  - rewindable safe checkpoint
  - rewindable map knowledge
  - append-only chronicle segment
  - Kaelen meta-memory
- Explicit ownership classes for permanent, rewindable, append-only,
  Kaelen-meta, and disposable data.
- Cross-document validation for campaign, entity, checkpoint, timeline, event,
  canon-fact, and asset-owner references.
- Precise validation paths suitable for recovery logs and future player-facing
  error translation.
- A focused headless test suite and baseline-suite integration.

## Enforced Boundaries

- Permanent manifests reject mutable player, mission, reputation, cargo, and
  map-knowledge state.
- Safe checkpoints require a living, non-transitional state and a recognized
  initial, docked, or gate-arrival location.
- Safe checkpoints reject tactical session data at any nested depth, including
  projectiles, aggro, attack targets, autopilot waypoints, jump transitions,
  death screens, transient spawn timers, and active model or speech requests.
- Map knowledge may reference only gates registered in the permanent manifest.
- Chronicle events require ordered sequence numbers and valid timeline and
  checkpoint references.
- Kaelen meta-memory accepts only timeline-tagged, checkpoint-tagged,
  sequence-tagged approved observations. Prohibited rewards, reputation,
  mission progress, cargo, future outcomes, and tactical state are rejected at
  any nested depth.
- Kaelen fact references must exist in the permanent campaign manifest.

## Schema Version

All Checkpoint 1 documents use schema version `1`. Missing, fractional, or
unsupported versions fail validation. Later schema changes must add explicit
migration support rather than silently accepting a different shape.

## Verification

The final baseline suite passed all 19 steps, including the new campaign
storage schema and ownership test.

The focused suite covers:

1. Representative valid documents.
2. A valid seven-document campaign bundle.
3. Missing stable IDs.
4. Incorrect ownership declarations.
5. Mutable fields placed in the permanent manifest.
6. Unsupported schema versions.
7. Disposable tactical fields nested inside checkpoint state.
8. Unknown entity, checkpoint, timeline, event, and fact references.
9. Prohibited Kaelen memory fields.

## Scope

This checkpoint defines and validates storage documents only. It does not
create campaign directories, write saves, migrate `savegame.json`, or alter
gameplay save and load behavior. Those operations begin with the slot registry
and atomic store checkpoints.

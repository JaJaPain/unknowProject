# Phase 2 Checkpoint 2: Campaign Identity And Slot Registry

Status: Complete on 2026-06-14

## Added

- A reusable `CampaignSlotRegistry` persistence service.
- Exactly three stable local slot IDs:
  - `slot_01`
  - `slot_02`
  - `slot_03`
- Campaign create, enumerate, select, reopen, and delete operations.
- First-empty-slot creation with a hard failure when all three slots are full.
- Immutable campaign IDs and 256-bit campaign seeds generated once at campaign
  creation.
- Slot metadata containing display name, creation time, last-played time, game
  version, and latest checkpoint summary.
- A complete initial campaign scaffold containing:
  - campaign identity
  - opening-system manifest
  - empty asset registry
  - living initial checkpoint
  - opening map knowledge
  - first chronicle event
  - initial Kaelen memory
  - checkpoint index
- Campaign directories for checkpoints, chronicle segments, recovery, and
  future transactions.
- Focused headless tests and baseline-suite integration.

## Initial Safe Checkpoint

Creating an occupied campaign slot requires a supplied playable startup state.
The registry validates and writes the initial living checkpoint during the
same create operation. A slot is exposed as occupied only after its complete
seven-document campaign bundle and checkpoint index have been written.

The initial checkpoint:

- is living and non-transitional
- uses source reason `initial`
- records the opening system as a safe initial location
- preserves the supplied player, global, mission, and persistent-system state
- provides a loadable checkpoint before the first dock or gate jump

The future campaign-selection UI will call this service only after startup is
playable. Checkpoint 2 does not add that UI.

## Isolation Rules

- Slot IDs are UI locations and never substitute for campaign IDs.
- Reopening a registry preserves each campaign ID and seed.
- Selecting a campaign updates only slot metadata.
- Deleting one campaign removes only that slot directory.
- Deleting or selecting one slot cannot change another slot's identity.
- An occupied slot's metadata must agree with its `campaign.json`.
- A slot registry must contain exactly the three stable slot IDs.

## Compatibility

The prototype `user://savegame.json` load and save path remains unchanged.
Campaign slots are now available as a parallel persistence foundation, but
they do not yet replace current gameplay saves. Legacy import is handled in
Checkpoint 11, and player-facing slot controls are handled in Checkpoint 7.

## Atomicity Boundary

Checkpoint 2 validates the entire initial bundle before writing and updates
`slots.json` last. If creation fails before slot activation, the new slot
directory is removed.

Full transaction journals, last-known-good indexes, interrupted-write
recovery, and staged atomic replacement belong to Checkpoint 3.

## Verification

The final baseline suite passed all 20 steps.

The focused campaign-slot suite verifies:

1. Exactly three stable empty slots are created.
2. Campaign identity and seed survive registry reopening.
3. Initial checkpoint state is living, safe, and loadable.
4. The complete initial seven-document bundle passes schema validation.
5. Slot selection survives reopening.
6. Creating and selecting one campaign does not alter another.
7. A fourth campaign cannot be created.
8. Deleting one campaign cannot remove or alter another campaign.
9. Persisted selection remains correct when a different slot is deleted.

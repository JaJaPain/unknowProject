# Phase 2 Checkpoint 3: Atomic Store And Recovery

Status: Complete on 2026-06-14

## Added

- One reusable `CampaignTransactionStore` for campaign persistence writes.
- Per-store transaction locking.
- Duplicate autosave request coalescing while a transaction is active.
- Unique transaction directories with JSON journals.
- Staged JSON writes followed by parse and caller-supplied validation.
- Last-known-good backups for authoritative visibility indexes.
- Immutable payload installation before visibility-index replacement.
- Visibility indexes installed last so incomplete payloads remain unreachable.
- Startup cleanup of stale transaction directories.
- Active-index corruption detection and last-known-good restoration.
- Deterministic failure injection at every transaction stage.
- Atomic integration for:
  - campaign `checkpoint_index.json`
  - global campaign `slots.json`
- Focused recovery tests and baseline-suite integration.

## Commit Boundary

Payload files do not become authoritative merely because they exist. A
transaction becomes visible only after its designated index is installed:

- campaign creation uses `checkpoint_index.json`
- campaign slot changes use `slots.json`

If a write stops after payload installation but before index installation, the
previous index still points to the prior valid state. The extra payload is
unreferenced and may be cleaned later without affecting gameplay.

## Transaction Sequence

1. Acquire the store lock.
2. Coalesce duplicate autosave requests.
3. Create a unique transaction directory and journal.
4. Stage every JSON file.
5. Parse and validate every staged file.
6. Preserve the active index as last-known-good.
7. Install non-index payload files.
8. Install the authoritative visibility index last.
9. Mark the journal committed and remove the completed transaction.
10. Release the lock.

All failure paths release the lock. Incomplete transaction directories are
treated as stale and removed during recovery.

## Recovery

Opening the campaign slot registry now:

1. removes stale transaction directories
2. parses and validates the active `slots.json`
3. restores `recovery/last_known_good_slots.json` when the active index is
   damaged
4. fails closed when neither copy is valid

The same recovery API supports campaign checkpoint indexes as later
checkpoints begin replacing the prototype save path.

## Failure Coverage

The focused suite injects failure:

- immediately after lock acquisition
- after journal creation
- after file staging
- after staged validation
- after last-known-good backup
- after payload installation
- immediately before visibility-index installation

For every failure, the prior authoritative index remains readable and the
transaction lock is released.

The tests also verify:

- successful commits become visible only through their index
- damaged active indexes restore the previous committed index
- stale transaction directories are cleaned
- duplicate autosaves are coalesced and retained as one pending request
- actual campaign registry corruption recovers occupied slots

## Scope

This checkpoint provides atomic storage mechanics. It does not yet capture new
gameplay checkpoints, replace `savegame.json`, or display recovery messages in
the player UI. Those integrations occur in later Phase 2 checkpoints.

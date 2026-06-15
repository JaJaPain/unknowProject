# Phase 2 Campaign Storage Contract

Status: Approved on 2026-06-14

## Authority Order

When records disagree, authority is:

1. validated campaign manifest for permanent identity
2. selected checkpoint bundle for mutable state
3. current-timeline chronicle records for historical queries
4. Kaelen meta-memory for approved discarded-timeline references only
5. caches and derived summaries, which may always be rebuilt

No derived file may silently overwrite a higher-authority record.

## Identity Rules

- Campaign IDs are immutable and globally unique on the local installation.
- Slot IDs are fixed UI locations and are not campaign IDs.
- Checkpoint IDs are immutable.
- Timeline IDs are immutable.
- Chronicle event IDs are immutable and ordered within their segment.
- Generated entity and asset IDs include the campaign creation namespace.
- Display names never substitute for IDs.

## Safe Checkpoint Definition

A safe checkpoint is a validated, living, non-transitional gameplay state
captured after:

- docking is complete and station UI/state is established, or
- an undock request is accepted but before station UI/state is cleared, the
  ship is moved, or flight control resumes, or
- gate arrival is complete and player control has been restored

The first dock checkpoint protects players who dock and immediately exit the
game. The pre-undock checkpoint replaces it after station activity so accepted
or completed missions, cargo transfers, purchases, repairs, storage changes,
and upgrades are retained. Both checkpoints restore to the safe dock location;
the pre-undock trigger never stores the first live-flight frame.

It may not contain:

- projectiles
- current attack targets or aggro
- transient spawn timers
- autopilot waypoints
- jump-transition state
- death-screen state
- unsaved in-flight position
- temporary speech or model requests

## Manual Save Semantics

Manual save is a checkpoint-copy operation.

- In flight: copy the latest committed safe autosave.
- Docked: optionally create a fresh safe autosave, then copy it.
- Dead or jumping: reject.
- No safe autosave: reject.
- Existing manual entry: require explicit overwrite confirmation.

The manual checkpoint's name and creation metadata may differ, but its gameplay
payload must hash identically to the source safe bundle.

## Commit Protocol

1. Acquire the campaign transaction lock.
2. Coalesce duplicate pending autosave requests.
3. Capture or copy the intended safe state.
4. Write all new files into a unique transaction directory.
5. Parse and validate every staged file.
6. Verify cross-file IDs and content hashes.
7. Preserve the currently committed index as last-known-good.
8. Move the completed immutable bundle into its final location.
9. Atomically replace the small checkpoint index last.
10. Release the lock.
11. Notify the player only after step 9 succeeds.

On failure, the transaction directory is retained for diagnostics or removed
after logging, while the prior checkpoint index remains authoritative.

## Rewind Contract

Loading checkpoint `C`:

- selects `C` as the current timeline head
- restores only mutable checkpoint state
- restores map knowledge captured by `C`
- leaves campaign manifest and assets unchanged
- does not delete later chronicle events
- compares Kaelen memory timestamps and event sequences with `C`'s chronicle
  head
- moves later Kaelen observations from current memory to the bounded
  discarded-timeline archive
- starts a new timeline branch when new post-load events are recorded
- prevents ordinary NPC and story queries from reading discarded branches
- may increment Kaelen's reversal count through a separate validated write

If the discarded branch ended in player death, its verified death category may
also be retained. Loading an older living checkpoint without a death archives
eligible Kaelen observations but does not invent a death memory.

## Kaelen Memory Clock

Kaelen memory never depends on wall-clock time for story ordering.

Before Phase 3 universal time, each memory uses:

- timeline ID
- checkpoint ID
- chronicle event sequence
- local monotonic creation sequence

After universal time exists, campaign-time timestamp is added while sequence
IDs remain the tie-breaker. Operating-system timestamps may be retained for
diagnostics but never decide canon, ordering, expiration, or rollback.

## Chronicle Contract

Chronicle storage is append-only in immutable segments. An event contains
structured facts, not authoritative prose.

Required fields:

- `event_id`
- `timeline_id`
- `parent_event_id`
- `checkpoint_id`
- `event_type`
- `subject_ids`
- `payload`
- `schema_version`

Summaries and Markdown are derived caches. Deleting them cannot erase history.

## Recovery Contract

At startup:

1. validate slot metadata
2. validate campaign identity
3. validate the selected checkpoint index
4. validate referenced checkpoint bundle hashes
5. fall back to last-known-good index if needed
6. report recovery in player-readable language

Recovery never generates replacement canon. Missing generated assets retain
their IDs and seeds and are marked for later rebuild or curated fallback.

## Notification Contract

Successful rolling autosave:

`SYSTEM: Campaign checkpoint saved.`

Successful manual checkpoint:

`SYSTEM: Manual checkpoint "<name>" saved.`

Failure:

`SYSTEM WARNING: Checkpoint could not be saved. Your previous save is still safe.`

Recovery:

`SYSTEM: The latest checkpoint was damaged. Restored the previous safe checkpoint.`

Notifications:

- never use TTS
- appear only after the result is known
- do not display local paths
- coalesce duplicate autosave successes from one gameplay action
- remain separate from story and NPC dialogue

## Migration Contract

The version-2 legacy save is read-only input during import.

- import targets the first available campaign slot unless the player selects a
  different empty slot
- import never overwrites an occupied slot
- if all three slots are occupied, import is blocked with a readable message
- the original file receives a byte-for-byte backup
- campaign and checkpoint output are validated before slot activation
- failure cannot modify another campaign
- no AI, speech, or asset generation occurs during import

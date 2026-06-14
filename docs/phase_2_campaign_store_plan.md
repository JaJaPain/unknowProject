# Phase 2: Campaign Store And Save Architecture

Status: Approved on 2026-06-14

## Purpose

Phase 2 replaces the prototype's single `savegame.json` with a campaign store
that can preserve generated canon, rewind mutable gameplay safely, recover from
partial writes, and support three player campaigns.

This phase does not generate new systems, add universal time, implement
relationships, or replace the single-active-mission gameplay model. It creates
the storage boundaries those later phases require.

## Approved Player Rules

- The game supports three campaign slots.
- Each campaign has one rolling safe autosave and up to three named manual
  checkpoint copies.
- A fresh safe checkpoint is captured only after docking or successful
  jump-gate arrival.
- A new campaign creates an initial living safe checkpoint after startup is
  fully playable, so quitting before the first dock still leaves a loadable
  campaign.
- A manual save requested during flight copies the latest safe checkpoint. It
  never captures the current flight position or tactical state.
- A docked manual save may refresh the safe checkpoint after docking is fully
  established, then copy it.
- Saving is unavailable while dead, during a jump transition, before the first
  safe checkpoint exists, or while another save transaction is active.
- Loading after death restores the latest living checkpoint. Only Kaelen's
  restricted meta-memory may record the discarded death.
- A successful autosave posts
  `SYSTEM: Campaign checkpoint saved.`
- Save notifications do not use TTS and repeated autosave requests are
  coalesced.
- Failed writes preserve the previous valid checkpoint and show a distinct
  system warning.

## Data Ownership

### Permanent Campaign Canon

These records do not rewind:

- campaign ID and seed
- campaign creation version
- generated system, gate, faction, NPC, ship-design, portrait, and voice
  identities
- generation seeds, provenance, hashes, and validation results
- fixed opening premise and established canon facts
- cached generated assets and system specifications

Later phases may append new canon, but loading an older checkpoint never
removes or rerolls it.

### Rewindable Checkpoint State

These records restore from the selected safe checkpoint:

- current system and safe arrival or docking position
- player hull, shields, cargo, credits, storage, and upgrades
- active mission and mutable mission progress
- reputation and faction-kill state
- per-system entity state
- NPC current location and status
- political, security, and economic conditions
- pending events and current story state
- player-visible map knowledge
- future universal campaign time

### Append-Only Chronicle Ledger

Chronicle events are never physically rewritten or deleted. Each event records:

- event ID
- timeline ID
- parent event ID
- checkpoint ID
- event type and structured payload
- involved stable entity IDs
- campaign-time value when available
- whether it belongs to the current or a discarded timeline

Loading an older checkpoint creates a new timeline branch. Events after the
loaded checkpoint remain available for diagnostics and Kaelen's tightly
restricted meta-memory, but ordinary gameplay and NPC memory query only the
current branch.

### Kaelen Meta-Memory

This campaign-adjacent record survives checkpoint rewind and contains only:

- timeline reversal count
- prior death category when a discarded timeline ended in death
- a bounded list of approved prior-timeline memory fragments

Every Kaelen memory fragment records:

- stable memory ID
- source timeline ID
- source checkpoint ID
- campaign-time timestamp when universal time exists
- monotonic event sequence for ordering before universal time exists
- memory category
- structured fact references
- approved reusable phrase or summary
- current or discarded timeline status

When an older checkpoint is loaded, Kaelen observations newer than the loaded
checkpoint's chronicle head move from current-timeline memory into the
discarded-timeline archive. They are not deleted. Ordinary NPC memory cannot
read that archive.

It cannot store rewards, reputation, mission progress, tactical knowledge,
future outcomes, or facts ordinary NPCs could use.

### Disposable Data

These records may be recreated or deleted:

- TTS audio cache
- temporary generation files
- transient logs
- loading-screen state
- current projectiles, aggro, avoidance waypoints, and other tactical session
  objects

## Proposed Storage Layout

```text
user://campaigns/
  slots.json
  slot_01/
    campaign.json
    manifest.json
    assets.json
    kaelen_meta.json
    checkpoint_index.json
    checkpoints/
      autosave/
        checkpoint.json
        timeline.json
        map_knowledge.json
      manual_01/
        checkpoint.json
        timeline.json
        map_knowledge.json
      manual_02/
      manual_03/
    chronicle/
      index.json
      segments/
        segment_000001.json
    recovery/
    transactions/
  slot_02/
  slot_03/
```

Checkpoint directories are immutable bundles while they are active. A new
bundle is built and validated in `transactions/`, then installed and exposed by
updating `checkpoint_index.json` last.

## Ordered Checkpoints

### Checkpoint 1: Ownership And Schema Contract

Status: Complete on 2026-06-14.

Deliverables:

- campaign, manifest, asset, checkpoint, map-knowledge, chronicle, and
  Kaelen-meta schemas
- required stable IDs and schema versions
- permanent, rewindable, append-only, and disposable ownership tables
- validation result contract shared by every store

Exit test:

- representative valid documents pass
- missing IDs, wrong ownership, unsupported versions, and malformed references
  fail with precise paths

### Checkpoint 2: Campaign Identity And Slot Registry

Status: Complete on 2026-06-14.

Deliverables:

- exactly three stable slot IDs
- campaign ID and seed created once
- slot metadata with display name, creation time, last-played time, game
  version, and checkpoint summary
- campaign create, enumerate, select, and delete operations
- initial living safe checkpoint creation after startup becomes playable

Exit test:

- creating and reopening a campaign returns the same ID and seed
- quitting before the first dock resumes from the initial safe checkpoint
- deleting one slot cannot affect another
- no fourth campaign can be created

### Checkpoint 3: Atomic Store And Recovery

Deliverables:

- one reusable persistence service
- staged writes, validation, backup, replacement, and rollback
- transaction journal and stale-transaction cleanup
- corruption detection and last-known-good recovery
- save transaction lock and request coalescing

Exit test:

- simulated failure at every write stage preserves a loadable prior state
- a valid staged transaction becomes visible only after its commit index

### Checkpoint 4: Campaign Manifest And Asset Registry

Deliverables:

- permanent campaign manifest
- append-only registration of generated identities and canon facts
- asset metadata, hashes, ownership, and validation status
- missing-asset detection and fallback/rebuild instructions
- adapters exposing the current handcrafted registries as initial campaign
  canon

Exit test:

- loading an older checkpoint leaves manifest and asset identities unchanged
- missing assets are reported without rerolling their identity or seed

### Checkpoint 5: Safe Timeline Checkpoint Bundles

Deliverables:

- capture and restore of current version-2 gameplay state
- canonical checkpoint ID, source reason, and safe-location metadata
- docking and gate-arrival autosave triggers
- rolling autosave replacement
- living-state requirement
- no tactical session data in checkpoint schemas

Exit test:

- dock and gate arrival restore correctly
- hull, inventory, mission, reputation, upgrades, and system entities rewind
- projectiles, aggro, current enemies, and in-flight position are never saved

### Checkpoint 6: Manual Checkpoint Copies

Deliverables:

- three named manual checkpoint entries
- in-flight requests copy the active safe autosave bundle
- docked requests may refresh the safe autosave before copying
- overwrite confirmation and sanitized display names
- save availability and block-reason API for UI

Exit test:

- changing tactical state after an autosave, saving manually in flight, and
  loading that manual checkpoint restores the earlier safe state

### Checkpoint 7: Save Notifications And Minimal Slot UI

Deliverables:

- system-chat success and failure notifications
- duplicate autosave-message suppression
- three-slot selection screen
- new campaign, continue, load manual checkpoint, rename checkpoint, and delete
  campaign actions
- no filesystem paths exposed in player messages

Exit test:

- successful commits notify once
- failed commits warn and leave the prior checkpoint loadable
- blocked save actions explain why

### Checkpoint 8: Chronicle Branch Foundation

Deliverables:

- structured append-only event segments
- timeline and parent-event IDs
- checkpoint-to-chronicle-head reference
- branch creation when an older checkpoint loads
- current-branch filtering
- compatibility import of existing quest-history entries as legacy events

Exit test:

- loading an older checkpoint and taking a new action creates a branch
- discarded events remain stored but are absent from ordinary current-history
  queries

### Checkpoint 9: Map Knowledge Partition

Deliverables:

- permanent physical gate graph stays in the manifest
- player-visible known, rumored, hidden, blocked, and damaged route state lives
  in checkpoint map knowledge
- current handcrafted gate discovery adapter

Exit test:

- loading an older checkpoint can hide a later discovery without deleting the
  destination, route, or generated assets

### Checkpoint 10: Kaelen Meta-Memory And Death Reload

Deliverables:

- restricted meta-memory schema and bounded retention
- timestamped and timeline-tagged Kaelen memory fragments
- rollback classification that moves observations after the selected
  checkpoint into discarded-timeline memory
- death-category recording only when the discarded branch ended in death
- timeline reversal counter
- latest-living-checkpoint load path
- validator rejecting prohibited gameplay fields

Exit test:

- death and reload rewinds gameplay completely
- loading an older non-death checkpoint archives only Kaelen observations newer
  than that checkpoint
- only approved Kaelen fragments survive
- ordinary NPC and mission queries cannot access discarded timeline events

### Checkpoint 11: Version-2 Save Import

Deliverables:

- detect the current `user://savegame.json`
- preserve a byte-for-byte migration backup
- import it into the first empty campaign slot
- refuse import when all three slots are occupied; never overwrite a campaign
- validate the new campaign and checkpoint bundle before activation
- retain clear recovery instructions if import fails

Exit test:

- the current prototype save resumes from the campaign store
- failed import leaves both the legacy save and existing slots untouched

### Checkpoint 12: Phase Regression And Approval

Deliverables:

- focused schema, slot, transaction, recovery, rewind, branch, and migration
  tests
- expanded gameplay baseline
- hands-on slot, dock, gate, in-flight manual save, death reload, corruption
  recovery, and campaign-deletion review
- storage and performance measurements

Phase 2 exit criteria:

- permanent canon survives all checkpoint loads
- mutable state rewinds exactly
- in-flight saving cannot preserve tactical advantage
- interrupted writes recover safely
- three campaigns remain isolated
- Phase 3 can add universal time without changing storage ownership

## Compatibility Strategy

`GameRoot.save_game()` and `load_game()` remain temporary compatibility entry
points while their implementation delegates to the campaign store. Existing
docking, gate, death, and restart callers migrate one at a time.

The old `savegame.json` is not deleted automatically after import. It remains a
migration backup until the player explicitly removes old data in a later
maintenance UI.

## Non-Goals

- procedural system generation
- multiple active missions
- full relationship simulation
- universal time
- LLM-written chronicle prose
- generated asset production
- cloud saves
- cross-device synchronization

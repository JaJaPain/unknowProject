# Phase 1 Checkpoint 5: Typed Game Content Registry

Status: Complete

## Added

- Typed definitions for factions, NPCs, ship designs, portraits, and voice
  profiles.
- One read-only game content registry for resolving those definitions.
- Stable IDs for all current handcrafted factions, NPCs, voices, ships, and
  portraits.
- Separate provider mappings so game content does not depend on Kokoro voice
  names.
- Compatibility adapters for the current gameplay and UI code.

## Content Sources

The registry loads authored content from `data/content`:

- `factions.json`
- `npcs.json`
- `ship_designs.json`
- `voices.json`
- `portrait_sheets.json`
- `voice_provider_kokoro.json`

Game-facing definitions use stable IDs such as:

- `faction.zenith`
- `npc.kaelen`
- `ship_design.vanguard.gunner`
- `portrait.minor_npc_02.jenna_kross`
- `voice.kaelen.v1`

Legacy faction names remain accepted at the compatibility boundary.

## Portrait Layouts

Portraits are resolved from explicit pixel bounds, so a sheet does not need a
single fixed grid size.

The registry currently supports:

- six curated 5x5 sheets imported from the existing portrait metadata
- two 2x2 minor-NPC sheets
- one 2x2 quest-giver sheet

This produces 162 individually addressable portraits. New sheets can use any
layout as long as their JSON lists the source image and bounds for each
portrait.

## Voice Independence

NPCs and factions reference stable voice-profile IDs instead of provider voice
names. Kokoro-specific names and speed settings live in a separate provider
mapping file.

Checkpoint 6 will put the current TTS implementation behind one speech
service. Once that is complete, replacing Kokoro or adding another provider
will not require changes to dialogue, NPC, or UI callers.

## Compatibility

The existing handcrafted dialogue remains in its current dictionaries during
this checkpoint. Registry adapters now supply canonical metadata around that
content:

- faction identity and colors
- NPC portrait and voice profile
- provider voice mapping
- ship asset selection and fallback paths

This keeps current gameplay stable while later checkpoints move callers onto
typed services.

## Protection And Validation

Kaelen is explicitly marked as protected content.

The registry rejects:

- malformed or duplicate stable IDs
- duplicate faction aliases, NPC names, or faction-role ship entries
- missing portrait sheets or ship assets
- missing faction, NPC, portrait, voice, or fallback references
- malformed or unknown provider voice mappings

Invalid content therefore fails during registry validation instead of entering
a campaign save.

## Verification

The focused registry test verifies:

- 8 factions
- 12 handcrafted NPCs
- 13 ship designs
- 13 voice profiles
- 162 portraits
- legacy and canonical faction lookup
- Kaelen's protection rule
- faction-agent and voice-fallback references
- 2x2 and 5x5 portrait resolution
- ship path and provider voice resolution

The complete baseline suite passes all nine steps, including startup, two-way
gate travel, save restoration, docking, and dock autosave.

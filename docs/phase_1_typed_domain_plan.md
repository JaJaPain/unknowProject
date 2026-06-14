# Phase 1: Typed Domain Data And Stable IDs

Status: Approved; implementation in progress

## Purpose

Phase 1 gives every persistent part of the game a stable identity and a
validated data shape.

This is the foundation needed before campaign history, procedural systems,
generated NPCs, background workers, or long-term saves can be trusted.

This phase does not add procedural generation or change the basic gameplay
loop. The current handcrafted systems must continue to work throughout the
phase.

## Goals

- Give persistent game concepts explicit, stable IDs.
- Move system lookup out of hardcoded `GameRoot` tables.
- Define validated data contracts for systems, gates, factions, NPCs, ships,
  missions, and reusable assets.
- Define provider-neutral references for future AI capabilities and voice
  profiles without integrating new models in this phase.
- Define one game-facing speech contract for every spoken character and system.
- Load the existing handcrafted content through the new contracts.
- Preserve current saves through a clear, backed-up migration path.
- Create focused domain tests instead of continuing to grow `GameRoot`.

## Non-Goals

- Generating new solar systems.
- Running an LLM or ship builder in the background.
- Building the campaign chronicle or eulogy system.
- Simulating remote-system political changes.
- Adding multiple active missions.
- Assigning generated portraits or voices to generated NPCs.
- Reworking combat, flight, mining, or station gameplay.
- Refactoring the current LLM and TTS implementations before their replacement
  contracts and regression coverage are approved.

## Proposed Data Rules

### Stable IDs

Persistent IDs are immutable after an object is created.

Authored content uses readable IDs:

- `system.start`
- `faction.zenith`
- `npc.kaelen`
- `station.start.main`
- `gate.start.frontier`

Generated content will later use IDs derived from the campaign seed and the
generator's creation record. Runtime node names and display names are never
used as persistent identity.

### Canonical Data Format

Proposed default: JSON is the canonical stored format for domain definitions.

Typed GDScript classes parse, validate, and expose that JSON to the game.
Scene paths remain references inside the definitions rather than becoming the
definition itself.

This keeps handcrafted and future generated content on the same data path.

### Model-Agnostic References

Domain data may refer to a capability or profile ID, but never directly to a
provider URL or a branded model name.

Examples:

- `capability.story_director.v1`
- `capability.dialogue_writer.v1`
- `capability.image_review.v1`
- `voice.kaelen.v1`

The actual provider and model selection remain deployment configuration. A
future model can replace the current one after passing the same capability
contract without changing NPC, mission, or campaign schemas.

Generated results will eventually record provenance for diagnostics and
reproducibility, but saved campaigns will not require the original model to be
installed.

### Unified Speech Boundary

Every dialogue source will eventually call one `SpeechService` contract. No
character-specific UI or mission system should know the TTS provider URL,
request payload, output format, or provider-specific voice name.

The game-facing request uses:

- dialogue text
- stable voice-profile ID
- playback mode: play, queue, or pre-cache
- priority and interruption policy
- optional interaction ID for diagnostics

Stable voice profiles remain part of character identity:

- `voice.kaelen.v1`
- `voice.mechanic.jenna.v1`
- `voice.agent.zenith.01`
- `voice.npc.<stable_npc_id>`

A provider mapping translates each profile to Kokoro today or another TTS
engine later. Provider-specific fields such as `af_aoede`, speed values, URLs,
and WAV response details do not belong in NPC definitions or UI code.

Phase 1 defines the contract and voice-profile data. Migration of all current
call sites should be its own compatibility checkpoint so existing dialogue,
pre-caching, tone guard, cancellation, playback, and audio ducking can be
regression tested together.

### Definitions And State

A definition describes what something is:

- NPC identity and role
- faction identity
- ship design
- system layout
- gate connection
- portrait metadata

State describes what happened to it:

- reputation
- current location
- mission status
- depleted asteroid composition
- ownership changes
- relationship changes

Phase 1 defines the boundary. Phase 2 builds the campaign store that owns the
mutable state.

## Proposed Types

### SystemDefinition

- stable system ID
- display name
- scene reference
- system tags
- station IDs
- gate IDs
- faction IDs present
- authored or generated origin
- definition schema version

### GateDefinition

- stable gate ID
- owning system ID
- destination system ID
- paired destination gate ID
- scene placement reference
- travel availability flags

### FactionDefinition

- stable faction ID
- display name
- faction class
- visual references
- default relationship rules
- authored or generated origin

### NpcDefinition

- stable NPC ID
- display name
- faction ID or independent status
- role tags
- portrait asset ID
- voice profile ID
- major/minor importance
- protected-story flags

Kaelen receives an explicit protected flag. Story systems may not kill or
retire her.

### ShipDesignDefinition

- stable design ID
- scene or generated asset reference
- ship class
- faction compatibility
- capability tags
- generation provenance

### MissionDefinition

- stable mission ID
- mission type
- giver NPC ID
- faction ID
- objective descriptors
- reward descriptors
- consequence descriptors
- timing rules

This phase only defines and validates the contract. Existing mission behavior
continues through an adapter until the mission phase.

### AssetDefinition

- stable asset ID
- asset type
- source path
- metadata
- provenance

The curated portrait sheets and their JSON metadata enter through this
contract. Portrait assignment logic comes later.

Portrait sheets may use different layouts. The registry must support the
existing 2x2 NPC sheets, the curated 5x5 sheets, and future layouts through the
same schema.

- Each sheet declares its own source dimensions and optional grid dimensions.
- Each portrait has a stable ID and explicit pixel bounds.
- Runtime cropping uses the explicit bounds rather than assuming a global grid.
- Existing 2x2 NPC portraits will be appended to the portrait metadata during
  the portrait-registry checkpoint.
- NPC definitions reference portrait IDs, never sheet positions such as
  `top_left`.

### CapabilityReference

- stable capability ID
- contract version
- required input and output schema versions
- required modalities
- fallback policy ID

This is only a domain reference in Phase 1. Provider adapters, model profiles,
benchmarking, and runtime scheduling remain in the later AI worker phase.

### VoiceProfileDefinition

- stable voice-profile ID
- speaker ID or reusable voice archetype ID
- profile version
- delivery traits
- language
- provider-neutral style tags
- fallback voice-profile ID

Provider-specific voice names and synthesis controls belong in replaceable
deployment mappings, not this definition.

## Implementation Checkpoints

Each checkpoint should be implemented, tested, reviewed, committed, and pushed
before the next begins.

### Checkpoint 1: Domain Contract And Ownership Map

Deliverables:

- document the definition/state ownership boundary
- approve ID formats and naming rules
- approve canonical definition storage format
- approve the boundary between capability IDs and replaceable model profiles
- list existing data sources and their future owners
- identify compatibility adapters needed for current gameplay

Exit test:

- every persistent concept has one proposed owner
- no runtime behavior changes

### Checkpoint 2: ID And Validation Foundation

Status: Complete

Deliverables:

- ID validation helpers
- schema validation result and readable error reporting
- typed base definition contract
- serialization helpers
- focused automated tests

Exit test:

- malformed IDs and definitions fail with useful messages
- valid authored IDs round-trip without changing

Implementation record:

- `scripts/domain/DomainId.gd`
- `scripts/domain/ValidationResult.gd`
- `scripts/domain/DomainDefinition.gd`
- `scripts/domain/DomainJson.gd`
- `tests/domain/run_domain_foundation_tests.gd`
- domain tests added to `tools/run_baseline_checks.ps1`

### Checkpoint 3: System And Gate Registry

Status: Complete

Deliverables:

- `SystemDefinition` and `GateDefinition`
- registry that resolves stable IDs to definitions and scenes
- authored definitions for the existing systems
- paired-gate validation
- compatibility adapter for current `GameRoot` loading

Exit test:

- current systems load and transition through the registry
- bad or unpaired gates fail clearly during validation
- no system scene is selected by a display name or node name

Implementation record:

- `data/systems/system_registry.json`
- `scripts/domain/SystemDefinition.gd`
- `scripts/domain/GateDefinition.gd`
- `scripts/registry/SystemRegistry.gd`
- `tests/registry/run_system_registry_tests.gd`
- `GameRoot` scene selection and save validation routed through the registry

### Checkpoint 4: Persistent Entity Identity

Status: Complete

Deliverables:

- common persistent identity contract
- stable IDs for stations, gates, NPC ships, mission ships, and asteroids
- duplicate-ID detection
- compatibility with current asteroid and mission-ship persistence

Exit test:

- leaving and returning to a system resolves the same entities
- duplicate IDs are caught before they can corrupt a save

Implementation record:

- `scripts/domain/WorldIdentity.gd`
- stable world IDs for stations, gates, NPC ships, mission ships, and asteroids
- state schema metadata added to persistent entity records
- duplicate and incomplete identity validation before travel and saving
- `tests/domain/run_world_identity_tests.gd`
- live identity validation added to the core startup smoke test

### Checkpoint 5: Faction, NPC, Ship, And Portrait Definitions

Status: Complete

Deliverables:

- faction, NPC, ship design, and asset definition contracts
- stable voice-profile definitions and provider mapping schema
- adapters for current handcrafted factions and NPCs
- curated portrait metadata registry
- explicit Kaelen protection rule
- validation for broken cross-references

Exit test:

- existing NPC and faction content resolves by stable ID
- every assigned portrait exists in the portrait registry
- invalid faction, portrait, or ship references fail clearly

Implementation record:

- `scripts/registry/GameContentRegistry.gd`
- typed faction, NPC, ship-design, portrait, and voice-profile definitions
- provider-neutral voice profiles with separate Kokoro mappings
- adapters preserving current faction, NPC, portrait, and ship behavior
- mixed portrait-sheet support for the curated 5x5 sheets and existing 2x2 sheets
- explicit protected status for Kaelen
- cross-reference, duplicate, asset-path, and provider-mapping validation
- `tests/registry/run_game_content_registry_tests.gd`

### Checkpoint 6: Unified Speech Compatibility Adapter

Status: Implementation complete; manual audio approval pending

Deliverables:

- one `SpeechService` game-facing contract
- current Kokoro implementation behind a provider adapter
- stable voice-profile resolution for Kaelen, agents, minor NPCs, and mechanic
- compatibility wrappers for current play and pre-cache calls
- centralized tone guard, queueing, cancellation, caching, playback, and audio
  ducking
- migration of direct TTS call sites

Exit test:

- every current speaking character still uses the intended voice
- Kaelen says `Shiny` and other speakers say `Indy`
- cached and uncached dialogue match the displayed text
- changing a provider mapping does not require changing any dialogue caller
- no gameplay or UI class calls a TTS endpoint directly

Implementation record:

- `scripts/speech/SpeechService.gd`
- `scripts/speech/KokoroSpeechProvider.gd`
- stable voice-profile routing for Kaelen, faction agents, minor NPCs, and
  Jenna Kross
- centralized text cleanup, Shiny/Indy tone guard, play, pre-cache, stop,
  readiness, and cache completion API
- compatibility use of the existing TTS transport beneath the provider adapter
- gameplay and UI callers migrated away from provider voice names
- `tests/speech/run_speech_service_tests.gd`
- source guard preventing direct gameplay/UI TTS or provider-voice calls
- complete automated baseline passing 11 of 11 steps
- deterministic procedural second-system prototype for runtime generation,
  stable identity, save restoration, and multi-obstacle navigation testing

### Checkpoint 7: Mission Contract Adapter

Status: Complete

Deliverables:

- typed mission definition and state boundary
- objective, reward, consequence, and timing descriptors
- adapter from current mission dictionaries
- no change to current one-mission gameplay rules

Exit test:

- existing missions accept, update, abandon, complete, and reload normally
- malformed mission data cannot silently enter the save

Implementation record:

- `MissionDefinition` with stable definition identity and giver/faction IDs
- typed objective, reward, consequence, and timing descriptors
- `MissionState` validation for active runtime missions
- `MissionAdapter` conversion from current generated and handcrafted
  dictionaries into the existing single-mission runtime shape
- legacy mission-state normalization for current version-1 saves
- validated mission capture and restoration through `QuestManager`
- save writes fail closed if active mission state is malformed
- malformed mission offers are rejected before credits, reputation, or active
  state can change
- the station mission board reports rejected contract data instead of showing a
  false acceptance
- deterministic contract tests for kill, ore delivery, and special pickup
- deterministic gameplay lifecycle coverage for acceptance, partial delivery,
  kill progress, pickup validation, completion, abandonment, fallback
  generation, and TTS failure
- complete automated baseline passing 13 of 13 steps

### Checkpoint 8: Transitional Save Migration

Status: Complete

Deliverables:

- one-time migration from the current save schema
- automatic backup before migration
- clear error for unsupported or damaged saves
- stable IDs stored instead of node or display names where applicable
- save-schema regression fixtures

This remains a single-file transitional save. Phase 2 will separate the
campaign manifest, world state, timeline, and chronicle.

Exit test:

- an existing save migrates and resumes correctly
- the original save remains available as a backup
- a failed migration never overwrites the source save

Implemented:

- version-2 saves store canonical system and gate registry IDs
- runtime compatibility aliases are restored only at the load boundary
- version-1 saves receive deterministic mission normalization
- the original version-1 file is copied to a timestamped backup
- migrated output is written and validated through a temporary file before
  replacement
- replacement failure restores the source from its backup
- damaged and unsupported saves fail clearly without rewriting their source
- focused migration fixtures cover canonicalization, backup integrity,
  runtime decoding, damaged JSON, and unsupported future versions
- fallback combat dialogue synchronization recognizes digits, number words,
  and quantity phrases
- complete automated baseline passing 14 of 14 steps

### Checkpoint 9: Phase Regression And Approval

Deliverables:

- run the existing offline baseline suite
- run focused domain, registry, and migration tests
- manually test start, dock, mission, save, restart, gate travel, return travel,
  combat, death, and restart
- record performance and behavior differences
- update architecture documentation

Phase 1 exit criteria:

- handcrafted systems load exclusively through the registry
- persistent entities use stable IDs
- current gameplay remains intact
- current saves migrate or fail safely and clearly
- Phase 2 can build campaign persistence without parsing scene internals

## Proposed File Layout

```text
data/
  systems/
  factions/
  npcs/
  ships/
  assets/

scripts/
  domain/
  registry/
  persistence/

tests/
  domain/
  registry/
  persistence/
```

Exact filenames and class boundaries will be chosen after inspecting the
existing implementation at the start of each checkpoint.

## Review Decisions

The following decisions were approved before Checkpoint 1:

1. Use JSON as the canonical format for both handcrafted and generated
   definitions.
2. Use readable stable IDs for handcrafted content and deterministic generated
   IDs for procedural content.
3. Include portrait metadata ingestion in Phase 1, but defer portrait
   assignment logic.
4. Automatically back up and migrate current saves rather than intentionally
   resetting them.
5. Keep Phase 1 compatibility-focused and defer the campaign manifest and
   multi-file save architecture to Phase 2.
6. Store capability IDs in game data and keep provider names, model names,
   endpoints, and inference settings in replaceable deployment profiles.
7. Route Kaelen, agents, minor NPCs, mechanics, and every future speaker through
   one provider-neutral `SpeechService`.

# Phase 1 Domain Contract And Ownership Map

Status: Approved architecture; Checkpoint 1 implementation record

## Purpose

This document fixes the ownership boundaries and dependency direction for
Phase 1. It is the contract used to judge later implementation checkpoints.

Phase 1 is a compatibility migration. Existing gameplay remains operational
while responsibilities move out of `GlobalState`, `GameRoot`, `UIManager`,
`LLMInterface`, and `TTSInterface` one boundary at a time.

## Dependency Direction

Dependencies flow in this direction:

```text
UI and gameplay scenes
        |
        v
game-facing services
        |
        v
domain definitions and mutable state
        |
        v
registries, codecs, and provider adapters
        |
        v
JSON, Godot scenes, local AI services, and local TTS services
```

Rules:

- Domain classes do not depend on UI nodes, scene-tree lookups, HTTP, Ollama,
  Kokoro, or provider-specific response formats.
- UI code displays resolved domain data. It does not select system scenes,
  crop portraits by hardcoded coordinates, or select provider voice names.
- Gameplay systems request work through game-facing services.
- Registries resolve stable IDs to definitions and assets.
- Mutable campaign state references stable IDs rather than display names,
  node names, or scene paths.
- Provider adapters translate neutral requests into external API calls.
- Generated outputs are validated before entering authoritative game state.

## Stable ID Contract

### Storage Type

IDs are serialized as JSON strings and exposed to GDScript as `StringName`
where practical. GDScript does not provide nominal string-ID types, so
validation and typed definition classes enforce the distinction.

### Authored ID Grammar

Authored IDs use lowercase ASCII dot-separated segments:

```text
namespace.segment[.segment...]
```

Allowed segment characters:

```text
a-z 0-9 _
```

Rules:

- minimum of two segments
- no spaces or uppercase characters
- no empty segments
- immutable after assignment
- globally unique within its ID namespace
- display names never substitute for IDs

Examples:

```text
system.start
system.test
gate.start.to_test
station.start.main
station.start.iron_reach
faction.zenith
npc.kaelen
npc.jenna_kross
ship_design.indy_miner
portrait.minor_npc_02.jenna_kross
voice.kaelen.v1
mission.start.generated_0001
capability.story_director.v1
```

### Generated IDs

Generated IDs use an entity namespace, a campaign-specific creation namespace,
and an immutable creation sequence or deterministic seed digest.

Proposed shape:

```text
system.gen.<campaign_key>.<creation_key>
npc.gen.<campaign_key>.<creation_key>
ship_design.gen.<campaign_key>.<creation_key>
```

The campaign key and creation key are created once and stored. They are never
recomputed from a mutable display name, current location, or current model
output.

The exact campaign-key generator belongs to Phase 2. Phase 1 validates the
shape and reserves the namespace.

### Legacy ID Translation

Current IDs remain accepted only at compatibility boundaries:

| Legacy ID | Canonical ID |
| --- | --- |
| `start_system` | `system.start` |
| `test_system` | `system.test` |
| `start_to_test` | `gate.start.to_test` |
| `test_to_start` | `gate.test.to_start` |
| `zenith` | `faction.zenith` |
| `aurelia` | `faction.aurelia` |
| `vanguard` | `faction.vanguard` |

Adapters may translate these values during Phase 1. New domain data must use
canonical IDs.

## Definitions Versus State

Definitions describe durable identity and authored or generated content:

- system layout and scene reference
- gate links
- faction identity and presentation
- NPC identity, role, portrait, and voice profile
- ship design
- portrait and other asset metadata
- mission structure
- AI capability references

Mutable state describes campaign events and current conditions:

- player inventory, credits, upgrades, health, and location
- reputation and kill history
- active and completed missions
- entity damage, depletion, destruction, and location
- political ownership and shortages
- relationships and remembered events

Definitions may be cached permanently. Mutable state belongs to the campaign
store introduced in Phase 2. The transitional Phase 1 save codec continues to
store mutable state in one file.

## Canonical Definition Storage

- JSON is canonical for handcrafted and generated definitions.
- Every definition document includes `schema_version`.
- Typed GDScript classes parse and validate JSON before it reaches gameplay.
- Scene and asset paths are references inside definitions.
- Runtime state is never written back into definition files.
- JSON object key order is not meaningful.
- Unknown required schema versions fail with a readable error.
- Optional unknown fields may be retained by migration tools but ignored by the
  current runtime.

## Ownership Map

### Content Definitions

| Responsibility | Current Owner | Target Owner | Migration |
| --- | --- | --- | --- |
| system scene lookup | `GameRoot.SYSTEM_SCENES` | `SystemRegistry` | Checkpoint 3 |
| gate links | exported fields in system scenes | `GateDefinition` resolved by `SystemRegistry` | Checkpoint 3 |
| station identity | node/display names | `StationDefinition` and stable scene identity | Checkpoints 3-4 |
| major factions | matches and dictionaries across scripts | `FactionDefinition` and `FactionRegistry` | Checkpoint 5 |
| minor factions | `GlobalState.MINOR_FACTIONS` | `FactionDefinition` and `FactionRegistry` | Checkpoint 5 |
| minor NPCs | `GlobalState.MINOR_NPCS` | `NpcDefinition` and `NpcRegistry` | Checkpoint 5 |
| ship designs | scene paths and faction matches | `ShipDesignDefinition` and registry | Checkpoint 5 |
| portrait sheets | hardcoded UI cropping plus portrait JSON | `AssetDefinition` and `PortraitRegistry` | Checkpoint 5 |
| voice identity | Kokoro IDs in NPC/UI data | `VoiceProfileDefinition` | Checkpoints 5-6 |
| mission structure | loose dictionaries | `MissionDefinition` compatibility adapter | Checkpoint 7 |
| AI task identity | methods on `LLMInterface` | versioned capability IDs | later AI worker phase |

### Mutable Runtime State

| Responsibility | Current Owner | Transitional Owner | Long-Term Owner |
| --- | --- | --- | --- |
| player economy and cargo | `GlobalState` | typed save state plus compatibility access | campaign store |
| ship upgrades and derived stats | `GlobalState` | typed player/ship state | campaign store |
| reputation and faction kills | `GlobalState` | typed relationship state | campaign store |
| current system | `GlobalState` and `GameRoot` | navigation state using canonical system ID | campaign store |
| active target and scene references | `GlobalState` | runtime session service | not persisted directly |
| per-system entity state | `GameRoot.system_states` | typed system-state records | campaign store |
| active mission | `QuestManager.active_quest` | typed mission-state adapter | campaign store |
| quest history Markdown | `QuestManager` | compatibility chronicle source | campaign chronicle |

### Runtime Services

| Responsibility | Current Owner | Target Boundary | Migration |
| --- | --- | --- | --- |
| system loading and travel | `GameRoot` | navigation service using `SystemRegistry` | Checkpoint 3 |
| entity state capture | `GameRoot` plus entity methods | persistent-entity contract | Checkpoint 4 |
| NPC/mission ship spawning | `GlobalState` | spawn service using definitions | after Checkpoint 5 |
| portrait resolution | `GlobalState` and `UIManager` | `PortraitRegistry.get_texture(id)` | Checkpoint 5 |
| speech synthesis/playback | `TTSInterface` and direct UI calls | `SpeechService` | Checkpoint 6 |
| mission lifecycle | `QuestManager` | mission service with typed adapter | Checkpoint 7 |
| save encoding and validation | `GameRoot` | save codec and migrator | Checkpoint 8 |
| LLM request transport | `LLMInterface` | capability service and provider adapters | later AI worker phase |

## System And Entity Ownership

### System Registry

`SystemRegistry` owns:

- known system definitions
- canonical-to-legacy ID aliases during migration
- scene resolution
- system-definition validation
- gate-pair validation
- cross-reference validation

`GameRoot` remains responsible for transition presentation and attaching the
resolved scene during Phase 1. It stops owning the list of systems.

### Persistent Entities

A persistent entity must expose:

- canonical persistent ID
- entity type ID
- capture-state operation
- restore-state operation
- state schema version

Node names may be used for debugging but never as fallback persistent IDs after
Checkpoint 4.

Duplicate IDs within a system are fatal validation errors for persistence. They
must be reported before a save overwrites either entity's state.

## Portrait Contract

The portrait registry supports mixed sheet layouts through explicit bounds.

Each sheet records:

- stable sheet ID
- source path
- source width and height
- optional row and column counts
- sheet metadata version

Each portrait records:

- stable portrait ID
- sheet ID
- explicit pixel bounds
- gender presentation tags
- age-group tags
- role and visual tags
- curation status

The six `P001`-`P006` sheets remain 5x5. The existing `MinorNPC01.png` and
`MinorNPC02.png` sheets enter the same registry as 2x2 sheets. NPC definitions
reference portrait IDs and never `top_left`, `bottom_right`, or raw crop
coordinates.

## Speech Contract

Every speaking system calls one provider-neutral `SpeechService`.

Game-facing operations:

- play a speech request
- pre-cache a speech request
- stop or cancel current speech
- query readiness
- observe queue/cache completion

A speech request contains neutral data:

- text
- voice-profile ID
- playback mode
- priority/interruption policy
- optional interaction ID

`VoiceProfileDefinition` stores identity and neutral delivery traits. A
replaceable provider mapping stores Kokoro voice names, speed, and other
engine-specific controls.

The initial compatibility adapter preserves:

- existing voice assignments
- text cleanup
- Shiny/Indy tone guard
- pre-caching
- request cancellation
- WAV decoding
- audio playback and ducking
- offline behavior

No new gameplay caller may call `TTSInterface`, its URL, or a provider voice ID
directly after Checkpoint 6.

## AI Capability Contract

Game and domain systems reference versioned capabilities:

```text
capability.story_director.v1
capability.dialogue_writer.v1
capability.campaign_summary.v1
capability.image_review.v1
```

Capabilities define input/output schemas and validation rules. Deployment
profiles choose the provider and model. Generated results store provenance, but
saved campaigns never require the original model to remain installed.

The current `LLMInterface` remains a compatibility implementation during Phase
1. Provider extraction is deferred until the background-worker phase to avoid
mixing two large migrations.

## Save Compatibility Contract

Checkpoint 8 introduces a transitional schema:

- current saves are read through a versioned migrator
- the source save is copied to a timestamped backup before replacement
- canonical IDs replace legacy IDs in migrated data
- migration writes to a temporary file and validates it before replacement
- failed migration leaves the source untouched
- unsupported versions produce a clear message
- save loading never invokes an LLM, TTS engine, or asset generator

Phase 1 retains a single save file. Phase 2 introduces the campaign manifest,
world-state partitions, timeline, and chronicle.

## Compatibility Rules

- Every checkpoint must pass the Phase 0 baseline suite.
- Existing public calls remain available until all known callers migrate.
- Compatibility wrappers log deprecated usage in development builds.
- No checkpoint may silently regenerate established content.
- No checkpoint may change balance, mission rewards, faction reputation rules,
  or travel timing unless required to fix a regression.
- New schemas fail closed with actionable validation errors.
- Existing gameplay is the behavioral reference during Phase 1.

## Checkpoint 1 Exit Decision

The seven architecture decisions are approved:

1. JSON is canonical for definitions.
2. Authored IDs are readable and generated IDs are deterministic and stable.
3. Portrait metadata is registered now; assignment logic comes later.
4. Existing saves are backed up and migrated.
5. Procedural generation is deferred until its foundations are ready.
6. AI integrations use capability IDs and replaceable provider profiles.
7. All spoken dialogue routes through one provider-neutral speech service.

Checkpoint 2 may begin after this document and the Phase 1 plan pass the
offline documentation/baseline checks and are committed.

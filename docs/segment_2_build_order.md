# Segment 2 Build Order: Mission Framework And Branching Contracts

Date: 2026-06-16

Status: Segment 2 complete, baseline 42/42

Branch: `codex/jumpgate-system`

## Design Decisions

- Active mission limit: 2 (one agent-brokered contract, one public-board job).
- Capabilities are monolithic per-type classes, not decomposed into
  trigger/objective/consequence components yet. Decomposition deferred until a
  later segment needs it.
- Encounter trigger system (proximity, zone entry, transmission, scan) is
  deferred entirely. Segment 2 handles mission mechanics only.
- `TARGET_WITH_COMMS_REVERSAL` branch triggers when the player has 1 kill
  remaining — the final target hails with a counter-offer.

## Current Code Reality

QuestManager holds one `active_quest: Dictionary` with ~35 string-keyed
fields. Progress is handled by `match` blocks on `objective_type` in
QuestManager, UIManager, and MissionAdapter. The MissionDefinition,
MissionObjectiveDefinition, MissionTimingDefinition, MissionRewardDefinition,
MissionConsequenceDefinition, MissionState, and MissionAdapter classes already
validate at accept time but do not persist as runtime objects — the flat dict
is the authority.

UIManager reads `QuestManager.active_quest` directly by string key for
tracker formatting, turn-in routing, and briefing display.

Saves store the quest as a flat dict under `"quest"` in the checkpoint
bundle. Legacy and version-2 saves both normalize through MissionAdapter.

LLMInterface generates quests with a 3-choice structure and reconciles
numbers post-generation. PublicBoardOfferBuilder and
PublicBoardTextGenerator handle slot-first generation for board postings.

## Checkpoint 1: MissionInstance And State Machine

### Goal

Replace the raw dictionary with a typed `MissionInstance` class that owns an
explicit state machine, while keeping the external API compatible so all 36
baseline tests pass unchanged.

### Deliverables

- `scripts/domain/MissionInstance.gd`:
  - Enum `State`: `OFFERED`, `ACCEPTED`, `ACTIVE`, `READY_TO_TURN_IN`,
    `COMPLETED`, `FAILED`, `EXPIRED`, `ABANDONED`, `RESOLVED_BY_BRANCH`.
  - Properties: `runtime_id`, `definition_id`, `state`, `objective_type`,
    `source_lane` (`AGENT` or `BOARD`), and all fields currently in the flat
    active-quest dict.
  - `transition_to(new_state) -> bool` with validation: only legal
    transitions succeed.
  - `to_dict() -> Dictionary` and `static from_dict(source) -> MissionInstance`
    for serialization.
  - `get(key, default)` compatibility method so existing string-key reads
    still work during the transition.
- QuestManager internally stores a `MissionInstance` instead of a raw dict.
  - `active_quest` property returns `_active_instance.to_dict()` for backward
    compatibility. Direct dict writes (`QuestManager.active_quest["key"] = v`)
    that exist in smoke tests still work through the dict — the instance is
    updated on the next `capture_active_quest()` call.
  - `accept_quest()` creates a MissionInstance from the adapted state.
  - `complete_quest()`, `abandon_quest()`, `check_active_quest_expiration()`
    use state transitions.
  - `capture_active_quest()` serializes the instance.
  - `restore_active_quest()` deserializes into an instance.
- Focused tests for state machine transitions (legal and illegal).

### Verification

- `run_mission_contract_tests.gd` passes.
- `--mission-smoke-test` passes.
- `--services-smoke-test` passes.
- Full baseline passes.

## Checkpoint 2: Mission Capability Registry

### Goal

Replace the hardcoded `match objective_type` blocks with registered
capability classes so new mission types can be added without editing the
mission manager.

### Deliverables

- `scripts/domain/MissionCapability.gd` (base class):
  - `capability_id() -> String`
  - `supported_objective_types() -> Array[String]`
  - `validate_state(instance: MissionInstance) -> ValidationResult`
  - `handle_event(instance: MissionInstance, event: String, data: Dictionary)`
  - `is_completed(instance: MissionInstance) -> bool`
  - `format_tracker_text(instance: MissionInstance) -> String`
  - `on_cleanup(instance: MissionInstance)`
  - `save_fields(instance: MissionInstance) -> Dictionary`
  - `restore_fields(instance: MissionInstance, data: Dictionary)`
- `scripts/domain/MissionCapabilityRegistry.gd` (singleton or static):
  - `register(capability: MissionCapability)`
  - `get_for_type(objective_type: String) -> MissionCapability`
  - `has_type(objective_type: String) -> bool`
- Four capability implementations:
  - `DeliverOreCapability.gd` — handles partial delivery tracking, ore
    deduction on completion, amount validation.
  - `KillShipsCapability.gd` — handles ship_destroyed event subscription,
    kill counting, target spawning request, combat multiplier scaling.
  - `PickupSpecialCapability.gd` — handles outpost handoff, cargo loading,
    cargo validation on completion, cargo cleanup on expiration.
  - `RecoverCombatDropCapability.gd` — handles ship_destroyed with drop
    chance roll, ship-log flag, cargo-free turn-in.
- QuestManager delegates to registry:
  - `_on_ship_destroyed()` routes through capability `handle_event`.
  - `is_quest_completed()` delegates to capability `is_completed`.
  - `complete_quest()` delegates cleanup to capability.
  - `_cleanup_expired_quest()` delegates to capability `on_cleanup`.
- UIManager's `_update_quest_tracker()` calls capability
  `format_tracker_text` instead of its own `match` block.
- Extension test: register a `TestOnlyCapability` for objective type
  `TEST_ECHO`, accept a mission with it, verify handle_event and
  is_completed work without editing QuestManager or UIManager.

### Verification

- `run_mission_contract_tests.gd` passes.
- Extension test passes.
- `--mission-smoke-test` passes.
- `--services-smoke-test` passes.
- Full baseline passes.

## Checkpoint 3: Mission Collection

### Goal

Replace the single-mission constraint with a bounded collection supporting
three active missions across three lanes: one agent-brokered contract, one
public-board job, and one NPC-initiated station errand (e.g. Jenna's fetch).

### Design: Three-Lane Model

- **AGENT** — faction contract from a dialogue agent (1 max).
- **BOARD** — public board posting (1 max).
- **STATION** — NPC-initiated errand like the mechanic pickup (1 max).
  Game-controlled: the offer is simply not presented if the lane is
  occupied. No player-facing "lane full" UI needed.

`MissionInstance.SourceLane` enum gains a `STATION` value. Lane detection:
- `public_board == true` → BOARD
- `station_errand == true` → STATION
- otherwise → AGENT

The mechanic pickup in UIManager (line ~5166) currently gates on
`not QuestManager.is_quest_active()`. This becomes
`not QuestManager.is_lane_occupied("STATION")` (or equivalent).
`GlobalState.roll_pickup_offer()` is unchanged — only the gating logic
in UIManager moves to a lane check.

### Deliverables

- `scripts/domain/MissionCollection.gd`:
  - Holds an `Array[MissionInstance]`.
  - `add(instance) -> bool` respects the 3-mission limit and lane rules
    (one per lane).
  - `remove(runtime_id)`, `get_by_id(runtime_id)`, `get_all_active()`.
  - `get_focused() -> MissionInstance` — the mission currently shown in
    the expanded tracker.
  - `focus(runtime_id)` — switch focused mission.
  - `is_lane_occupied(lane: SourceLane) -> bool`.
  - `get_by_lane(lane: SourceLane) -> MissionInstance` (or null).
  - `to_array() -> Array[Dictionary]` and
    `static from_array(source) -> MissionCollection`.
- `MissionInstance.SourceLane` enum: `AGENT`, `BOARD`, `STATION`.
  - `from_dict()` detects STATION via `station_errand` flag.
  - `create_active()` detects STATION the same way.
- QuestManager internally uses MissionCollection:
  - `accept_quest()` adds to collection instead of replacing.
  - `complete_quest()` removes the specified mission.
  - `active_quest` compat property returns the focused mission's dict.
  - `is_quest_active()` returns true if any mission is active.
  - `is_lane_occupied(lane_name: String) -> bool` for UI gating.
  - Time-change handler checks expiration on all timed missions.
- UIManager mechanic offer gating: `_mechanic_pickup_offer` buttons check
  `QuestManager.is_lane_occupied("STATION")` instead of
  `QuestManager.is_quest_active()`.
- UIManager `_on_mechanic_pickup_accept_pressed`: sets
  `"station_errand": true` on the quest_data dict so MissionInstance
  assigns STATION lane.
- Save format: checkpoint `"quest"` key accepts either a single dict
  (legacy) or an array of dicts (new). `restore_active_quest()` handles
  both.
- Legacy save import: single-mission dict wraps into a one-element
  collection.

### Verification

- Focused test: accept three missions (one per lane), verify all are
  active, complete one, verify the others remain.
- Lane rejection test: adding a second AGENT mission fails.
- Legacy save import test: single dict restores into a one-element
  collection.
- Full baseline passes.

## Checkpoint 4: Multi-Mission UI

### Goal

Wire the mission collection into the player-facing HUD and dock UI so the
player can see and interact with multiple active missions.

### Deliverables

- Quest tracker HUD shows all active missions in a compact list:
  - Focused mission shows full tracker text (objective, progress, countdown).
  - Other missions show a one-line summary (title + status icon).
  - Click/tap a summary to focus that mission.
- Dock UI changes:
  - Agent contract section and public-board section are visually separated.
  - If the agent lane is full, agent briefing shows "Contract active" and
    blocks acceptance.
  - If the board lane is full, board offers disable acceptance and explain
    the limit.
- Turn-in routing:
  - Each active mission that is `READY_TO_TURN_IN` shows its own turn-in
    button in the tracker or dock context.
  - Public-board turn-in routes through Kaelen/local agent as before.
  - Agent turn-in routes through the faction agent UI.
- Abandon: player can abandon either mission independently from a mission
  details panel or pause menu.

### Verification

- `--services-smoke-test` updated for multi-mission UI.
- Gameplay smoke: accept agent mission + board mission, see both in tracker,
  focus-switch between them, complete one, see the other remain.
- Full baseline passes.

## Checkpoint 5: Bounded Template Generation

### Goal

Generalize the slot-first LLM text generation from public-board-only to a
universal mission template system usable by both board postings and
agent-brokered contracts.

### Deliverables

- `scripts/domain/MissionTemplate.gd`:
  - `template_id`, `objective_type`, `tone_card`,
    `required_placeholders: Array[String]`,
    `write_fields: Array[String]`, `allowed_branch_ids: Array[String]`,
    `allowed_consequence_ids: Array[String]`.
  - Templates for existing types: `DELIVER_ORE_PUBLIC`,
    `PICKUP_SPECIAL_PUBLIC`, `RECOVER_COMBAT_DROP`,
    `TARGET_WITH_COMMS_REVERSAL`, plus agent-brokered variants
    `DELIVER_ORE_AGENT`, `KILL_SHIPS_AGENT`, `PICKUP_SPECIAL_AGENT`.
- Rename/generalize `PublicBoardTextGenerator` into `MissionTextGenerator`:
  - `build_generation_request(template, offer)` works for any template.
  - `validate_payload(template, offer, payload)` rejects missing
    placeholders, invented mechanics, Kaelen authorship drift (board only),
    and unsupported branch IDs.
  - `fallback_payload(template, offer, salt)` for each template.
  - `apply_payload_to_offer(template, offer, payload, is_fallback)`.
- Retry-with-critique for one failed attempt (generalize the existing
  public-board pattern).
- Agent-brokered missions can now use template-validated text instead of
  the current freeform LLMInterface generation.
- `PublicBoardOfferBuilder` and `PublicBoardTextGenerator` become thin
  wrappers or are inlined into the general system.

### Verification

- Focused template validation tests.
- `run_public_board_validation_tests.gd` still passes (or is updated to use
  the general system).
- `--mission-smoke-test` passes.
- Full baseline passes.

## Checkpoint 6: `TARGET_WITH_COMMS_REVERSAL`

### Goal

Build the first branching public-board mission to prove that mid-mission
state changes, branch choices, and branch-resolved cleanup all work.

### Template Design

- Posted on the public board as a kill contract against a hostile faction.
- Objective: kill N hostile ships (3 by default).
- After kill N-1, the final target hails the player via system chat.
- Combat pauses for that target (it stops firing, holds position).
- The comms message reveals information that reframes the job (the target
  was a whistleblower, the poster lied, the cargo is stolen, etc.).
- The player sees 2-3 branch choices. Only choices with implemented
  mechanics appear:
  - **Finish the kill**: complete as normal. Full payout. Issuing faction
    rep +5. Target faction rep -2.
  - **Accept bribe**: target pays a smaller amount. Mission resolves as
    `RESOLVED_BY_BRANCH`. Issuing faction rep -3. Target faction rep +2.
  - **Walk away**: abandon variant. No payout. Issuing faction rep -1.
    Target escapes.
- Branch choice records a structured chronicle event.
- After resolution: spawned targets, map markers, and mission UI are
  cleaned up by the capability.
- Save/load preserves mid-branch state (comms triggered but not yet
  chosen) and post-branch resolution.

### Deliverables

- `CommsReversalCapability.gd` registered for objective type
  `TARGET_WITH_COMMS_REVERSAL`.
- Extends KillShipsCapability behavior up to the trigger threshold.
- Adds `comms_triggered`, `branch_chosen`, `branch_id` fields to mission
  state.
- System-chat comms message when trigger fires.
- Branch choice UI (can reuse the existing agent-choice panel pattern).
- Chronicle event for the chosen branch.
- Cleanup on each resolution path.
- Template with required placeholders for the comms message and branch
  choice text, plus slot-filler fallback.

### Verification

- Focused test: accept reversal mission, reach trigger, verify comms fire,
  choose each branch, verify consequences.
- Save/load mid-branch test.
- Full baseline passes.

## Checkpoint 7: Segment 2 Regression

### Deliverables

- Add focused tests for:
  - MissionInstance state machine transitions.
  - Capability registry extension proof.
  - Mission collection add/remove/focus/lane limits.
  - Template validation across all template types.
  - Branch choice consequences for each TARGET_WITH_COMMS_REVERSAL path.
- Add gameplay smoke tests:
  - Accept two missions simultaneously, complete one, abandon the other.
  - Accept reversal mission, trigger comms, choose a branch.
- Verify legacy save import into mission collection.
- Run the full baseline suite.
- Update the Segment 2 checklist in `phase_3_to_7_development_plan.md`.

## Implementation Notes

### Migration Safety

The key risk is breaking the 36-step baseline during refactoring. The
checkpoint order is designed so that each step preserves backward
compatibility:

1. MissionInstance wraps behind the dict API — external code unchanged.
2. Capability registry delegates from the same QuestManager entry points —
   external code unchanged.
3. Collection adds multi-mission behind compat properties — tests that set
   `active_quest` directly still work through the focused mission.
4. UI changes are additive — existing smoke tests verify the same behaviors.

### What Gets Deferred

- Encounter/trigger system (proximity, zone entry, scan, transmission).
- Composable trigger/objective/consequence/cleanup components.
- Cross-system mission support (missions that span gate travel).
- Prerequisite and follow-up mission chains.
- Dynamic encounter scheduling.
- LLM-directed mission creation (story director proposes missions).

These belong in Segments 3-5 and Phase 5+ of the architecture doc.

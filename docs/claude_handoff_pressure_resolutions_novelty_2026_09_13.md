# Claude handoff: pressure, durable consequences, campaign resolutions and novelty

This is an implementation prompt for a **new Claude session** in
`C:\CodingProjects\SpaceGame`. Implement in the order below. Do not replace this
with another design exercise. Preserve existing work and leave a precise checkpoint
of completed and unfinished slices if the session ends.

## 1. User intent and authority

The user wants each campaign to feel different after the tutorial: different
systems, local factions, desires, mission reasons, directions and outcomes. Read
`docs/design_end_goal.md` in full. Names and different epilogues over identical
actions are not sufficient. Choices need a real reason; do not manufacture extra
branches. **Never change Kaelen or N.O.V.A.'s personality, soul, canon, voice or
reviewed banks.** The fixed cast anchors the generated world.

The user has deferred player testing and authorized further implementation. Build
and run automated tests now; do not require a player session before starting P3.
The user has explicitly kept `transmitter_lure` and `unstable_archive` as
prototypes: do not expose either as playable, including indirectly through pressure
cards. Do not use that restriction to stop independent pressure/persistence work.

This handoff specifies the next implementation scope, not a claim that it already
exists. Numerical P3 rules below come from the earlier plan. Items labeled
**integration decision** resolve gaps/conflicts for this restricted two-recipe
slice; they are instructions for this handoff, not previously implemented behavior.

Read, in order:

1. Root `AGENTS.md`, `CLAUDE.md`, `PROJECT_MAP.md` (navigation only).
2. `docs/whileYouWasSleeping.md`, newest entry first; older next-step statements
   are historical and may already be complete.
3. `docs/design_end_goal.md`.
4. `docs/investigation_playable_loop_2026_09_13.md`.
5. `docs/plan_replayability_local_inference.md`, P2 contracts and all of P3.
6. `docs/plan_campaign_uniqueness_and_dialogue_quality.md`, sections 3, 8, 9 and
   the newest continuation entries. Its older status tables are historical.
7. Actual source at the touchpoints below before editing.

The repository contains substantial uncommitted work. Record `git status` first;
do not reset, clean, overwrite unrelated edits, commit or push without instruction.
The critic is diagnostic/unqualified. These mechanics tests cannot establish
natural dialogue, subjective novelty, performance or hardware qualification.

## 2. Current implementation: start here, do not rebuild it

The first two recipes now run through the visible board, persisted publication,
acceptance checkpoint, discovery, scans, evidence decisions and assigned-station
settlement. The base investigation budget is 400 SC, a code-owned reward policy,
not a simulated faction account balance.

Relevant source:

| File | Existing responsibility / extension point |
|---|---|
| `scripts/domain/InvestigationBoardLifecycle.gd` | Pure prepare/publish/release; persistent owner, selector, frozen posting and cause retirement. `_candidates()` currently accepts only coherent `dispatch_backlog` causes: survey-data need, or filed claim evidence + clear-salvage-claim goal + two local factions. `_posting()` intentionally sets no completion effects yet. |
| `scripts/domain/InvestigationOfferBuilder.gd`, `InvestigationSelector.gd` | Seeded site/truth/branch generation and exposure-aware shape selection. Preserve saved truth and bag state. |
| `scripts/domain/InvestigationRuntime.gd`, `InvestigationStateValidator.gd` | Real scan hold, command revision/idempotency, consumed items, evidence, resolution and payout validation. |
| `scripts/domain/InvestigationWorldRuntime.gd`, `InvestigationWorldPlacement.gd` | Transient discovered markers; actual navigation obstacle validation. No general overview integration is claimed. |
| `scripts/QuestManager.gd` | Real mission acceptance and all terminal paths. `complete_quest()` currently pays/removes/emits before a dedicated consequence checkpoint: this is an integration gap to fix, not an atomic API already provided. Audit expiry/failure and nonfocused missions too. |
| `scripts/story/StoryManager.gd` | `accept_local_investigation_board_offer()` stages mission + posting retirement, checkpoints, then announces acceptance. Reuse that ordering principle for terminal effects. `record_mission_outcome_consequence()` currently appends prose-derived entries, not mechanical pressure effects. `advance_outcome_activity()` also advances on visits: DO NOT reuse it as P3 activity. |
| `scripts/UIManager.gd`, `scripts/ui/InvestigationPanel.gd` | Visible board/card/action handlers. Investigation cards bypass the generic board rewrite request. Turn-in uses neutral Contract Settlement, not Kaelen's completion speech. |
| `scripts/persistence/StoryStateStore.gd` | Additive story-state validation/defaults; stores investigation board and outcome memories. |
| `scripts/persistence/SaveMigrator.gd` | Canonical/runtime mapping for active and posted investigation sites, owner/reservation IDs and causal contracts. Extend for every new system reference. |
| `scripts/persistence/CampaignCheckpointStore.gd`, `CampaignSchemaCatalog.gd`, `scripts/GameRoot.gd` | Authoritative coherent snapshots. Permanent investigation site positions have exact structural-path exceptions to tactical cleanup. Do not widen those exceptions. `investigation_accepted` is a supported docked checkpoint reason. |
| `scripts/persistence/GeneratedFactionDesire.gd`, `GeneratedDesireConstraints.gd`, `CampaignGeneratedFactionStore.gd` | Saved per-system coherent desires. A generated textual success condition is NOT proof of an implemented effect. Preserve identities and saved generation. |
| `scripts/domain/QuestCausalContract.gd`, `QuestCausalContractCompiler.gd`, `QuestPlausibilityValidator.gd` | Typed causes, public/private facts, executable binding checks. Existing semantic signature is a starting point, not the full planned novelty history. |
| `scripts/domain/PublicBoardOfferBuilder.gd`, `scripts/story/StoryAgentOfferBuilder.gd` | Real ordinary offer builders. A generic ore card or textual cause attachment alone does not prove a specific desire needs ore. |
| `scripts/persistence/CampaignBibleStore.gd`, `scripts/story/StoryManager.gd` | Existing bible generation/storage and chapter progression. `_check_chapter_advance_after_hook_resolution()` explicitly refills forever; there is no completed campaign-resolution engine here. Extend deliberately without breaking legacy chapter flow. |

Latest completed verification: checkpoint storage, schema, migration, investigation
board and runtime suites passed; all **370 scripts** compiled. Broader regressions
also ran in the previous slice. This is a baseline, not permission to skip testing
your changes.

## 3. Deliverable A: pure P3 pressure reducer

Add `scripts/story/LocalPressureDirector.gd`, owned by StoryManager, and validated
`data/content/local_pressure_tracks.json`. Closed dispatch only; no generic effect
language and no model-generated mechanical state.

Implement the original P3 state contract:

```text
story_state.local_pressures = {
  version: 1, activity_step: int, rng_state: int,
  tracks: Array, applied_outcome_ids: Array[String],
  recent_accepted_families: Array[String]
}
track = {
  id, kind, system_id, station_id,
  level: 0..3, untouched_steps: 0..1, cooldown_until_step,
  revision, last_outcome_id,
  faction_id, desire_id, cause_id
}
```

The last three track fields are an **integration decision** required to connect
P3 to generated interests. Validate all references against their campaign/system;
do not derive them from names or assume `quest.faction` is the requester (current
investigation postings use `neutral` there). Read causal metadata instead.

Required APIs: `apply_outcome(state, outcome) -> Dictionary` and
`offer_constraints(state, system_id) -> Array[Dictionary]`. Use pure copies and
explicit `{ok, changed, state, deltas, reason}` results for mutation operations.
Version and strictly validate persisted data. Missing field in an old save means
uninitialized; malformed existing data is a recoverable load error, not a reset.

Rules:

- At tutorial completion initialize at most two distinct eligible pressure kinds.
  Select with persisted campaign RNG, in stable candidate order, and bind to a
  discovered system/station. No active track before the tutorial-completion latch.
- **Integration decision:** “two” is a maximum until two genuine supported causes
  exist. Leave missing slots pending and retry eligibility on normal system entry
  or board preparation. Never fabricate factions/needs or copy tutorial identities
  to fill slots. With no eligible cause, publish no pressure job.
- Each track starts at level 1 and untouched count 0. An activity step is exactly
  one terminal outcome for an accepted, non-tutorial mission: completed, abandoned,
  failed or expired. Opening/declining offers, docking, scans, objective readiness,
  pause, dialogue, visits and callback delivery are not pressure steps.
- Outcome ID is `<runtime_mission_id>:<terminal_state>`. Retain all applied IDs for
  this campaign. Also reject a second, conflicting terminal outcome for the same
  runtime mission; different terminal suffixes must not bypass idempotency.
- Apply a bound track's delta first: relief −1, worsening +1, clamped 0..3. Either
  resets untouched count. Do not also escalate it from inactivity on that event.
- A neutral outcome advances untouched count; at two, increase level by one and
  reset count. Other active tracks receive one neutral activity step, regardless
  of which system the accepted mission was in. Cooldown entries do not escalate.
- Level zero resolves that track; cooldown ends at current activity step +4.
  Do not count the resolving event again toward cooldown. A replacement uses the
  least-recently-active eligible kind, ties by saved RNG, in the player's current
  eligible system. No duplicate active kind, at most two active tracks and six
  retained track records; keep historical recency separately if pruning needs it.
- Expired cooldown with no valid current cause remains pending. No offscreen
  spawning, taxes, closures, combat changes, tutorial changes or gate restrictions.

### Exact effect table for this deliverable

| Track | New offers by level | Completed outcome | Other terminal outcome |
|---|---|---|---|
| signals | Survey at levels 1–3. No lure, no forced forged site. | Correct certification −1; incorrect certification +1; report 0 even if both sites were scanned. | Abandon/fail/expire 0 direct delta, then normal inactivity. |
| claims | Claims at levels 1–3, two actual local claimants. Level 3 preserve payout ×5/4. No liquidation. | Preserve −1; report 0. | Abandon/fail/expire 0 direct delta, then normal inactivity. |
| supply | One existing genuinely bound ore delivery: level 1 ×1, level 2 ×5/4, level 3 ×3/2. No archive alternative. | Complete the marked delivery −1. | Abandon/fail/expire the marked relief job +1. |

**Supply eligibility decision:** require a validated ore-consumption need/effect
and the real receiving station. Current `a clean ore assay` does not qualify:
delivering raw ore does not perform an assay. Neither coolant jokes nor generic
need prose qualifies. If no current generated cause meets this requirement, test
supply with typed fixtures and leave it runtime-ineligible. Do not add a new ore
need, resource simulation or assay mechanic just to activate supply.

The original lure/archive/liquidation rules remain documented future work. Do not
enable them, advertise elevated fraud, or promise unavailable alternatives.

## 4. Deliverable B: terminal outcomes and durable effects

Build a code-owned MissionOutcome from the actual accepted mission and capability
result, before removing it. Use the P3 fields: id, mission_id, pressure_id, shape_id,
objective_type, terminal_state, branch_id, outcome_tag, verified, forged,
credits_paid, consumable_id, at_minute. Add campaign/system/desire references and
actual effect records as necessary; normalize and validate them. Do not accept a
UI-supplied payout, verification flag, consumed-item flag or consequence sentence.

Commit pressure on settlement, not when investigation becomes ready. A kit already
consumed at resolution must not be consumed again at settlement or retry. All
accepted terminal types count, including ordinary and story missions; tutorial
missions are explicitly excluded. Unbound missions advance inactivity only.

Refactor actual QuestManager terminal entry paths into a guarded transaction:

1. Validate transition and capability guards; capture relevant before-state.
2. Stage inventory/cargo cleanup, payout/reputation, mission removal, board
   cooldown/ownership, pressure/outcome IDs, desire progress and resolution state
   as one in-memory result. Do not emit completion/reward UI or invoke model work
   halfway through staging.
3. For docked settlement, add a dedicated terminal checkpoint reason to GameRoot,
   store and schema. It uses the actual docked station and does **not** advance
   dock-service time. Checkpoint the coherent result before success signals.
4. On failed docked checkpoint, restore staged state, leave the mission retryable,
   show failure and avoid duplicate hints, rewards, memory and hook side effects.
5. On success emit terminal notifications and schedule optional prose from committed
   facts. Audit existing `on_quest_completed`, hook/knowledge promotion and memory
   callbacks so they cannot apply the same effects again or save a contradictory
   independent projection. Preserve existing chapter/hook behavior.

**Integration decision for abandonment/failure/expiry in flight:** keep the game's
safe-checkpoint policy. Apply the terminal change once in the running state and
retain a pending consequence-save record/dirty flag until the next legal safe
checkpoint. Do not pretend an in-flight save is docked or persist tactical pose.
That next checkpoint includes the whole result. If the process ends before then,
the preceding authoritative checkpoint restores both mission and consequences
together. Do not replay newer loose story-cache effects into it. Report a pending
save truthfully; retry only at a legal safe boundary. Test this rollback explicitly.

Restore must use checkpoint mission/inventory/story data together, even when an
independent StoryStateStore cache has a newer revision. Keep applied IDs in the
same snapshot. No bounded recent list may replace the campaign deduplication
ledger. Compatibility-save failure after a successful authoritative checkpoint
must not roll back a successful payout or cause it to be paid again.

### What a desire consequence may actually mean

Add a versioned campaign-owned progress projection keyed by `(system, faction,
desire)` in story state; do not reroll or rewrite GeneratedFactionDesire identities.
Track actual records, e.g. verified survey evidence submitted, recorder preserved
and delivered to its verified owner, marked ore delivered, pressure relieved,
and the source outcome IDs. These are closed, validated effect kinds.

**Integration decision:** use `open`, `progressed`, `satisfied`, `failed` states,
but mark `satisfied`/`failed` only when a typed bound predicate proves that exact
interest condition. A preserved recorder does not automatically clear a faction's
name. A survey certification does not automatically file a legal survey or reopen
a route. Unsupported textual success conditions stay open/progressed. A wrong
answer or an abandoned job does not permanently fail an entire desire.

Effects may retire the exact fulfilled collection cause, change relevant future
offer availability/reward, and expose a fact to a real recipient. Do not close
unrelated missions or optional leads. A new dependency must reference an existing
validated fact/lead; no automatic emergency after every success.

## 5. Deliverable C: pressure cards and broader cause coverage

Keep ordinary board work. Add no more than one pressure card per active local
track (maximum two); retain the existing single BOARD acceptance slot. A card
shows the actual local interest, level, last public change and
“Escalates after N resolved jobs” (N=2−untouched_steps). Cooldown is explicitly
counted in resolved jobs, not minutes. Do not imply offscreen social/economic
damage that is not implemented.

Persist `pressure_id`, `pressure_revision`, `level_at_offer`, relief designation
and rational payout modifiers through posting → adapter → active mission → save
→ terminal record. One outstanding posting per track. Reopen must not redraw.
Unaccepted level-stale offers may be replaced transactionally; accepted terms are
immutable. A retired fulfilled cause must not be resurrected under a new ID.

Use the existing selector over **implemented and causally eligible** shapes only.
Do not count hidden preparation as publication. Avoid duplicating the same causal
posting in generic and pressure sections. If no fresh valid cause exists, show
the track without an actionable posting; do not mint a reskin. This restricted
catalog cannot promise permanent unlimited relief work: record that limitation.

Reward policy: snapshot an integer payout for each supported branch at publication,
using integer floor of its ordinary branch payout times the applicable maximum
modifier. Do not multiply modifiers together or reapply them at settlement. Claims
base 400: preserve at level 3 pays 500, report remains 200. Survey remains 400 for
correct certification, 100 incorrect, 200 report. For supply compare the existing
applicable urgency multiplier with pressure and take the maximum. Display the
frozen final terms. Update runtime/state validators together.

Track the last four **accepted discretionary** families. Before appending a
candidate family, inspect the last three retained families; adding it must not
make more than two of that family in the resulting four. Withhold only the extra
pressure card when ordinary eligible work remains. Accepted/required work remains
visible. **Integration decision:** if this cap alone would hide the sole supported
combat-free relief offer, retain it and log `pacing_relief_exception`. Novelty
must not manufacture combat or strand an otherwise valid relief path.

### Broader causes: a bounded compatibility audit, not new ideas

Audit current GeneratedDesireConstraints against the implemented verbs, cargo
items, recipients, sites and effects. Add a table/document listing each supported
edge and each rejected edge with reason. Expand runtime eligibility only for an
edge whose action supplies the stated need and whose location/resource/recipient
checks pass. Preserve `dispatch_backlog` investigation eligibility until another
edge has that proof. The other blockers mostly describe moving existing cargo;
they do not establish a need to collect fresh scans.

For delivery needs already supported by the ordinary builders, bind the real
item, origin, destination and accepting local contact, then record delivery of
that item as the consequence. Keep the existing docking recipient repair and
destination checks for generated outposts. Do not claim delivery completed a
legal appeal, ownership transfer, assay or route reopening. When an edge cannot
be implemented with existing capabilities, leave it unavailable with a diagnostic.
Do not add new needs, enemies, hazards, recipes or dialogue branches for coverage.

## 6. Deliverable D: campaign resolutions, after durable effects work

The earlier plan defines the intent but not a complete ending schema. The following
is the **integration decision** for a minimal executable implementation. Do not
create a fixed “finish N jobs” campaign ending or treat all pressures resolving as
automatic campaign victory.

Add a pure `CampaignResolutionCompiler.gd` and reducer (one file is fine), with a
versioned structured resolution proposal in the existing bible-generation path.
Use the existing director model/generation lifecycle; no second planner or model
family. The director selects bound references from code-provided valid candidate
interests/effects/locations; it does not invent executable predicates.

```text
resolution_plan = {
  version: 1, id, premise_fact_ids,
  status: pending_bindings | active | resolved,
  interests: [{id, system_id, faction_id, desire_id, supported_effect_ids}],
  alternatives: [{id, result: success|partial|failure,
    all_of: [typed_predicate], public_fact_ids: [String]}]
}
typed_predicate =
  {kind: effect_committed, effect_id: String}
  OR {kind: desire_state, desire_id: String, system_id: String,
      state: satisfied|failed}
  OR {kind: fact_known, fact_id: String}
resolution_record = {
  plan_id, alternative_id, result, source_outcome_ids,
  achieved_effect_ids, unresolved_interest_ids, known_fact_ids,
  committed_at_step
}
```

All predicates are AND within an alternative; alternatives provide only justified
distinct outcomes. Unknown predicates/IDs, empty success conditions, unreachable
stations and unsupported effects are rejected before plan activation. Validate
desire IDs within their owning faction/system. `fact_known` uses the existing
knowledge ledger and cannot promote itself. No freeform code, expression strings,
unbounded conditions, arbitrary numeric scores or model-authored effects.

At initial creation generated frontier references may not yet exist. Persist a
validated pending proposal, then bind/activate it when the existing generation
path has created the referenced local interests and reachable locations. Freeze
active predicates. Do not conjure a whole new frontier system just to satisfy a
missing reference. A new generated proposal must explain how its selected concrete
interests serve the campaign premise; a generic list of unrelated jobs is invalid.
Mechanical validation proves bindings, not prose quality; keep that distinction.

Evaluate after every committed mechanical/knowledge transaction, not panel opening
or elapsed time. Stage the resulting record in the same checkpoint as the triggering
effects. Preserve source outcome IDs and unresolved interests for a factual ending.
If two alternatives can overlap, require an explicit supported distinction before
activating the plan; do not pick the first arbitrary array element. Do not force
multiple alternatives: one supported resolution is preferable to invented failure.
Partial/failure alternatives are allowed only when a committed supported effect
actually establishes the loss or remaining limitation. Reaching level 3 or refusing
a mission alone is not campaign failure.

When a plan resolves, show a factual campaign-resolution summary; optional generated
narration can describe only the public committed record. No final choice menu is
needed if prior actions decide the outcome. **Integration decision:** preserve free
play after resolution. Stop refilling the resolved primary arc, while leaving
unrelated optional work and accepted missions intact. Do not terminate the game,
lock travel or pretend every local problem disappeared.

For old campaigns without a plan, preserve existing chapter/hook progression and
mark resolution planning unavailable/pending. Do not reinterpret the old logline
as executable conditions or rewrite an accepted story. Invalid/failed new generation
uses existing failure/retry reporting, not a generic authored ending. Extend the
bible's public allowlist carefully: director secrets and private alternatives stay
private; the small model gets only discovered public facts.

Direction/lead integration must reference actual generated faction interests and
reachable registered stations/systems through existing story/knowledge/navigation
paths. An optional lead closes only when its exact bound condition is fulfilled;
required story gates and accepted missions retain their established behavior.
Do not add a second gate discovery or campaign navigation system.

## 7. Deliverable E: novelty history

Reuse and extend `QuestCausalContract.semantic_signature()`. The current function
normalizes some IDs and hashes motive/event/verb/beneficiary/evidence count/effects;
it does not yet represent all planned dimensions or track exposure.

**Integration decision:** introduce signature version 2 with normalized semantic
tokens for goal/motive kind, triggering-event category, obstacle binding,
dependency/need category, beneficiary relationship, resolution method, evidence
pattern and consequence kind. Derive from validated structured facts, never
names, prose, coordinates, quantities, random suffixes or private evidence values.
Do not assume all motive IDs ending in `f0` mean the same motivation. An evidence
pattern is “two-site comparison,” not the secret A/B truth. Retain v1 compatibility;
do not silently treat incomparable versions as fresh proven content.

Persist campaign offered and accepted ledgers separately with publication/acceptance
IDs and signatures. Record successful visible publication once, not prefetch,
failed save, reload, panel refresh or the writer starting. An acceptance updates
accepted sequence once. Keep investigation bag exposure distinct from novelty
exposure if their existing semantics differ.

Original opening history remains `user://run_opening_history.json`, versioned,
last **two other campaigns**, storing campaign ID, pressure pair in activation
order and first two **accepted** investigation shapes. Upsert the current campaign
entry; retries/restores do not create another opening. Filter recent pairs from
the six ordered pairs only when currently eligible. With zero/one eligible kind,
record the incomplete opening honestly; never activate an unsupported track to
make a unique pair. Reuse the saved selection on reload. This is limited opening
separation, not guaranteed unique campaigns.

**Integration decision:** add a separate versioned/resettable
`user://quest_novelty_history.json`, capped at 128 most recent published signatures
and 64 accepted signatures, plus consecutive accepted pairs/triples derivable from
that bounded sequence. Store only structural signatures, exposure IDs, campaign
IDs and sequence order. No dialogue, names, secrets, companions' memories, voices
or relationships. Reset only these two history files through a narrow settings
action; never delete campaigns or existing companion memory stores.

Rank eligible candidates before prose generation: fewer recent repeated triples,
then pairs, then least recently offered signature, then least recently accepted,
then stable campaign-seeded tie-break. No signature matching can bypass capability,
cause, payment, recipient or navigation validation. Log exhausted variety and offer
less work instead of inventing new branches/hazards. Required/accepted missions
must not disappear. Novelty history failure does not invalidate a durable mission
checkpoint; log degraded selection and retry idempotent history updates.

Missing histories start empty; corrupt histories produce a diagnostic and a fresh
bounded history without damaging saves. Use atomic file replacement and injectable
test paths. A restored checkpoint must not apply cross-run history as gameplay
facts; it influences future selection only. Previously seen openings can remain
marked seen after rollback because the player actually saw them.

## 8. Tests required before calling a slice complete

Use meaningful reducer tests AND actual consumers. A passing fake reducer test
without the board/QuestManager/checkpoint paths is not completion.

- Same seed + terminal sequence → identical normalized state; different valid
  action sequences change actual next builder output, not only level numbers.
- All delta-table rows, clamp boundaries, two-step inactivity, four-step cooldown,
  pending slots, sparse eligibility, replacement RNG save/load and tutorial guard.
- Duplicate and conflicting terminal IDs, all terminal paths, nonfocused expiry,
  unbound activity, decline/reopen/visit/clock/readiness not counting.
- Both supported investigation recipes complete through real board and UI handlers;
  prototype recipes remain unavailable at all pressure levels and after restore.
- Level-3 claims preserve pays exactly 500 once; report 200; survey 400/100/200;
  modifiers never stack, accepted terms survive level change and save/load.
- Same fulfilled cause cannot reappear at another station or after cooldown;
  unavailable/freshness-exhausted causes do not become reskinned replacements.
- Failed settlement save before/after staged inventory/credits/pressure, retry,
  reentrant signal, compatibility-cache failure, stale story-cache restore and
  in-flight pending terminal rollback all preserve a coherent mission/world pair.
- Real disk checkpoint roundtrip through canonical IDs, including generated
  systems, nested new state, ledger IDs, board terms and mission site coordinates.
- Exact supported desire effects only; recorder preservation does not assert legal
  ownership clearance; raw ore never counts as assay; unknown binding fails closed.
- Resolution compiler rejects invented effects, unknown facts, ambiguous alternatives
  and unreachable destinations. Two action traces produce different eligible
  records only when actual consequences differ. Legacy campaigns keep progression;
  resolved primary arc does not refill; unrelated accepted work survives.
- Novelty: renamed identical reasons collide; materially different dependencies or
  effects differ; A/B secret does not affect public signature; repeated sequences
  detected; prefetch/reopen/duplicate acceptance excluded; caps, reset, corruption,
  sparse opening pairs and I/O failure work without damaging campaign saves.
- Existing tutorial revisit, delivery recipient/route, station roster and fixed-cast
  soul regressions pass when their consumer paths are touched. No bank edits.

Starting existing suites:

```text
tests/domain/run_investigation_board_lifecycle_tests.gd
tests/domain/run_investigation_runtime_tests.gd
tests/domain/run_investigation_selector_tests.gd
tests/domain/run_public_board_validation_tests.gd
tests/persistence/run_campaign_checkpoint_store_tests.gd
tests/persistence/run_campaign_schema_tests.gd
tests/persistence/run_save_migration_tests.gd
tests/persistence/run_story_state_migration_tests.gd
tests/story/run_outcome_reaction_projector_tests.gd
tests/story/run_mission_card_delivery_route_tests.gd
tests/story/run_board_delivery_recipient_tests.gd
tests/story/run_intro_offer_revisit_tests.gd
tests/parse_check_scene_scripts.gd
```

Add focused `tests/story/run_local_pressure_tests.gd`, consumer/transaction tests,
resolution tests and novelty-history tests. Run Godot **sequentially** with unique
workspace-local absolute log paths. Example:

```powershell
$pressureLog = Join-Path (Get-Location) '.tmp_godot_user/test_logs/pressure_01.log'
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/story/run_local_pressure_tests.gd --log-file $pressureLog -- --baseline-offline --llm-live-fire
```

Inspect `SCRIPT ERROR`, parse errors and exit status; printed PASS alone is not
evidence. Do not run headless tests concurrently (Godot log rotation crashes).
Fixture directories must be workspace-local/injectable and cleanup must verify
resolved paths before recursive deletion. Run
`git -c core.safecrlf=false diff --check`; refresh maps after new systems with
`python generate_repo_map.py`.

## 9. Work order and completion report

Land coherent slices in this order: A reducer/schema → B real terminal transaction
and effect ledger → C cards and proven cause bindings → D resolution compilation,
evaluation and summary → E selection/history. Opening-pair history may land with
A if needed for selection; do not delay persistence correctness for prose work.

After each slice update `docs/whileYouWasSleeping.md` and the newest status section
of both plans with exact completed behavior, tests and remaining limits. Do not
mark the full plan complete while unsupported recipes, subjective quality and
hardware qualification remain open. Final report must distinguish implemented
runtime behavior, fixture-only behavior (especially supply), deferred human review
and unsupported cause/ending proposals. Include changed files and log paths.

Do not ask the user routine implementation questions already settled here. If an
existing saved promise or required story gate conflicts with a new rule, preserve
that accepted behavior, fail closed for new unsupported content, document the
specific conflict and continue independent work. Do not solve missing capabilities
by inventing a new game system or altering the fixed cast.

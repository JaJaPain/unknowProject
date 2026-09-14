# Fresh-session implementation handoff — Claude or Gemini

Work in `C:\CodingProjects\SpaceGame`. This prompt is for either model in a new
session. Implement the specified work in order; do not invent new activities,
story systems, models, branches or success conditions. This supersedes the
implementation-status claims in the earlier P3 handoff and changelog. It does not
declare the full campaign uniqueness plan complete.

## User requirements

Read `docs/design_end_goal.md` in full. After the tutorial, generated local
factions and their actual interests must drive different mission reasons,
destinations and recorded outcomes. Renaming the same mission does not meet the
goal. Choices exist only when mechanically and causally justified.

Kaelen and N.O.V.A.'s personality, soul, voice, canon and reviewed banks must not
change. Do not write new fallback character speech. The user has deferred player
testing; continue implementation and automated tests without asking for a playtest.
`transmitter_lure` and `unstable_archive` remain prototypes and unavailable in
all live offer paths. Supply remains runtime-ineligible: raw ore is not an assay.

Read root `AGENTS.md`/`CLAUDE.md`, `PROJECT_MAP.md`, newest
`docs/whileYouWasSleeping.md`, this document, and actual source before editing.
Use the map for navigation, not behavior claims. Preserve unrelated uncommitted
work; no reset/clean/commit/push. Older plans are background:

- `docs/plan_campaign_uniqueness_and_dialogue_quality.md`, sections 3, 8, 9.
- `docs/plan_replayability_local_inference.md`, P2 and P3.
- `docs/claude_handoff_pressure_resolutions_novelty_2026_09_13.md` for the unchanged
  pressure numbers, vocabulary and original integration contracts.
- `docs/review_claude_p3_and_next_plan_2026_09_14.md` is historical evidence of
  defects; several have now been corrected as listed below.

## Current baseline: preserve these fixes

1. QuestManager snapshots before completion hints remove ore, special cargo or
   inventory. Failed docked settlement restores resources and mission readiness;
   retry pays once. GlobalState signals are blocked during completion staging and
   restored afterward. Ore, purchased-item and courier regressions exercise this.
2. Board preparation no longer invents a central campaign resolution. With no
   persisted proposal, `ensure_resolution_plan()` returns
   `awaiting_campaign_proposal`. Existing active/resolved plans stay frozen across
   system visits. The old `_compose_resolution_plan()` helper remains for tests;
   do NOT reconnect it as automatic campaign authorship.
3. Resolution candidate and pressure-slot generation use the investigation board's
   coherent cause filter, rather than need text alone. This is not complete
   reachability validation for a future campaign proposal.
4. Resolution evaluation reads cumulative unique effect IDs from desire-progress
   records. Resolution summaries retain IDs in data but do not print raw effect
   IDs to players. The board displays the factual summary, and resolved primary
   arcs stop the existing hook-driven chapter refill.
5. GameRoot evaluates resolution before a safe checkpoint and rolls back that
   projection if saving fails. This covers knowledge changes by the next legal
   save boundary. A successful safe checkpoint clears pending consequence-save
   state. Do not fake a dock or persist ship pose for an in-flight terminal event.
6. SaveMigrator now converts pressure tracks, desire-progress entry systems AND
   composite keys, resolution interests and desire predicates. Unknown systems
   fail. Keep permanent investigation-site position exceptions narrow.
7. Compiler validation rejects missing required lists, mutually compatible ending
   alternatives, and treating an arbitrary successful effect as proof of loss.
   Currently a proven failed desire is the supported loss predicate; do not
   invent an irreversible failure mechanic to create more endings.
8. Novelty history has monotonic exposure sequence numbers after capacity, bounded
   opening retention (current plus two previous campaigns), entry-shape checks,
   dirty-history retry for investigations, and replacement without first deleting
   the old file. First accepted shapes can legitimately repeat.
9. Investigation preparation consults novelty ranking BEFORE choosing its cause
   within the selected shape. The existing shape bag remains authoritative.
   **Limit:** currently eligible causes within one shape often have identical
   semantic signatures; this is not a claim of broad new variety. Shape selection
   and ordinary jobs still need the integration below.
10. Initial pressure selection consults recent opening pairs. Cooling-down tracks
    occupy their slots until four resolved jobs have elapsed. Investigation
    acceptance records its family in the same acceptance checkpoint. Pause menu
    has a narrow “Reset remembered quest variety” action for the two histories.

The critic remains diagnostic/unqualified. Automated mechanics tests are not
proof of natural speech, fresh campaigns, low-end performance or visual quality.

## Implementation order and scope

Complete six bounded work packages. Do not expand the investigation catalog.
If a candidate fails its declared checks, withhold it and report the exact reason;
do not invent a substitute. Do not stop independent work for optional taste choices.

### Package 1 — Finish terminal transaction coverage and consistency

Files: `scripts/QuestManager.gd`, `scripts/story/StoryManager.gd`,
`scripts/GameRoot.gd`, existing persistence stores and transaction tests.

The completion rollback defect is fixed. Remaining audit/implementation is the
whole terminal lifecycle, especially failure/expiry/abandonment and story callbacks:

- Use one per-mission terminal guard for completion, abandonment, expiry and
  failure. A nonfocused mission expiring must restore the original focus on failed
  settlement. Synchronous cargo/reputation callbacks cannot reenter settlement.
- Capture BEFORE any capability cleanup or mutation. Stage cargo/inventory,
  credits/reputation, mission state/removal, cooldowns, pressure, deduplication and
  story consequences together. Do not add another independent outcome database.
- Move deterministic completion knowledge/hook bookkeeping needed for durable
  progress into staging. Split pure state mutation from notification, screenshots,
  optional generation and chapter presentation. Do not invoke a model or take a
  screenshot inside staging. Existing hook IDs remain authoritative; only close
  the hook attached to the mission. Keep tutorial completion gating unchanged.
- Post-commit callbacks must not repeat staged mutations. Persist an outcome-ID
  marker for any callback whose state effect would otherwise replay. Completion
  fact promotion, callback memories and mission history must either be in the
  checkpoint or deterministically reconstructed from its committed record.
- An in-flight terminal change stays live/pending until the next safe checkpoint.
  Restoring the previous checkpoint restores the prior mission and all prior
  effects together. Newer loose StoryStateStore data must not override it.
- Do not return `durable:true` merely because building a new-style outcome failed.
  Preserve legacy mission termination, but distinguish compatibility handling and
  actual successful checkpoint persistence. Invalid new typed data fails closed.

Required tests: actual ore/item/courier completion failure and retry; abandoned
courier cleanup; nonfocused expiry; conflicting terminal state; reentrant signal;
failure after state staging but before disk commit; successful checkpoint plus
failed compatibility cache; reopen old checkpoint with newer story cache; tutorial
revisit/turn-in; accepted story hook resolved once after reload.

### Package 2 — Make novelty selection complete without breaking shape cycles

Files: `InvestigationSelector.gd`, `InvestigationBoardLifecycle.gd`,
`PublicBoardOfferBuilder.gd`, `StoryAgentOfferBuilder.gd`, `StoryManager.gd`,
`UIManager.gd`, `NoveltyHistoryStore.gd`, `RunOpeningHistoryStore.gd`.

Keep these rules: eligibility before ranking, publication before exposure, accepted
and offered histories separate, no generated names/secret truth in signatures,
accepted terms immutable, required/accepted work never hidden by freshness.

**Explicit selection design:** extend InvestigationSelector's persisted bag record
with optional `remaining_shape_ids:Array[String]` and `cycle_index:int`. Use this
only for investigation selection; do not modify TauntBag or taunt content.

1. Migrate an existing bag once by replaying a COPY of its seed/cursor against the
   same sorted pool to extract the unconsumed suffix. Do not commit a draw or
   change an outstanding reservation while migrating. Empty suffix opens the
   next complete cycle. Keep pool signature and last-shape semantics.
2. On reserve, intersect the actual remaining shape IDs with validated candidates.
   Rank the eligible causes with the existing v2 ranker, then pick the best ranked
   candidate whose shape remains. Exclude immediate last-shape repetition only
   if another remaining shape is available. Do not burn excluded entries.
3. Reservation carries the next remaining list/cycle and seed but does not apply
   them. Only publication consumes the selected shape. Reopen/reload reuses the
   reservation and frozen posting. Release of a shown offer keeps exposure.
4. If an eligibility set changes, retain the existing separate-bag policy; no
   promise of no repetition across different pools. Unsupported shapes never
   enter the pool. Test migration mid-cycle and outstanding reservations.

Ordinary jobs need stable exposure ownership before history calls are added.
Persist published ordinary posting ID + signature + immutable objective/terms
through the existing board ownership machinery, extending its schema to accept
ordinary kinds rather than creating another board manager. Keep a discriminator
`posting_kind: investigation|ordinary`; missing means legacy investigation.
Do not run investigation-site validation on ordinary objectives. Dispatch to
the existing objective/cause/recipient validators for ordinary jobs.

An ordinary publication ID is a campaign-owned monotonically allocated ID persisted
with its posting; acceptance records the real runtime mission ID. Reopening a
posting never allocates another ID. Its signature remains semantic, separate from
identity. Generate/validate eligible candidates, rank before prose, then publish
the selected frozen candidate. A failed writer/save must not record exposure.
Unknown/legacy signatures are incomparable, not proven fresh.

Record accepted families for all discretionary jobs, once, in their acceptance
transaction. Family mapping is fixed: `investigation` for INVESTIGATE_SIGNAL,
`delivery` for DELIVER_ORE/DELIVERY_COURIER/PURCHASE_DELIVERY/PICKUP_SPECIAL,
`combat` for KILL_SHIPS/TARGET_WITH_COMMS_REVERSAL/RECOVER_COMBAT_DROP. Tutorial
and required story jobs do not enter discretionary pacing. Before adding a family,
inspect the last three: withhold an extra pressure offer if adding it would make
more than two of that family in four AND ordinary alternatives exist. Preserve
the sole supported combat-free relief offer and log `pacing_relief_exception`.

History integrity tasks: use actual campaign identity rather than a reusable slot
label; avoid cross-campaign pair/triple concatenation; opening upserts must retain
activation order and the first two accepted occurrences, including a duplicate
shape. Opening write failures need a dirty retry path just like novelty. Reset
must clear cached selection inputs and pending history writes, not campaign facts,
published postings or companion memories. Malformed entries/oversized lists must
not crash ranking. On I/O failure keep gameplay usable and record degraded history.

Acceptance: same seed/eligible set but different histories changes the selected
semantic reason when a genuine alternative exists; shape cycle still exhausts
before repetition; declined exposure counts once; prefetch does not; retry/reload
does not duplicate publication/acceptance; capped records remain ordered; reset
does not change a published mission; no hidden truth reaches signatures.

### Package 3 — Bind existing delivery-shaped needs, without asserting legal outcomes

Read `docs/cause_coverage_audit_2026_09_14.md`. Use its eight existing delivery
edges as the implementation queue. Do not add new needs or verbs. For each edge,
compile this record from actual generated world data:

```text
collection_contract v1 = {
  id, campaign_id, system_id, faction_id, desire_id, cause_id,
  need_binding_id, item_id_or_special_name, quantity,
  source_station_id, destination_station_id, recipient_id,
  action: pickup|courier|purchase_delivery,
  completion_kind: item_delivered
}
```

The source must actually supply the item through its existing pickup/store path;
destination must be registered/reachable; recipient must be a generated local
contact there. Reuse existing delivery-recipient creation/repair on docking, with
stable NPC identity and station ownership. Never substitute a tutorial resident.
If no real source/recipient/path exists, withhold the edge and log which binding
is missing. An item label in the desire vocabulary is not an inventory source.

Persist the collection contract through posting, adapter, active mission and save.
On delivery record exact item/quantity/destination/recipient/cause/outcome ID in
DesireProgressLedger. Add a closed `item_delivered` effect kind; this proves only
the delivery. It does not prove ownership clearance, lease transfer, appeal success,
survey filing, assay, route opening or faction-bank payment capacity.

Retire the exact fulfilled collection cause. Pressure/reward relief applies only
when a declared existing track rule supports that action; otherwise the completed
job is neutral activity. Do not broaden supply or invent pressure rules for every
delivery need. Ordinary job payout and receiving-person checks remain authoritative.

Acceptance: real offer→source acquisition→travel→local recipient→settlement→save
reload for each supported edge; missing-source/recipient cases withhold; duplicate
delivery pays/applies once; returning after abandoning cannot create duplicate
items; no success sentence claims a broader effect.

### Package 4 — Define campaign collection milestones separately from faction goals

Files: `CampaignResolutionCompiler.gd`, `DesireProgressLedger.gd`,
`MissionOutcome.gd`, `StoryStateStore.gd`, `SaveMigrator.gd`, tests.

Do not resume the old shortcut that sets a faction desire to `satisfied` simply
because an ending plan listed an effect kind. The generated desire's broad goal
and a completed collection are different facts.

Add one closed predicate kind to resolution schema version 2:

```text
{kind: collection_satisfied, collection_id: String}
```

An interest in v2 has `{id, collection_id, system_id, faction_id, desire_id,
station_id, recipient_id, completion_kind}`. Valid completion kinds are exactly
`verified_survey_evidence_submitted`, `recorder_preserved_and_delivered`, and
`item_delivered`. The first two refer to actual existing investigation receipts;
the third is package 3. Each collection ID belongs to one persisted accepted
contract or validated available collection opportunity, not a prose phrase.

The evaluator looks up the matching committed receipt, scoped by collection ID,
faction, system and recipient. A recorder handed to a different verified owner
must not satisfy the requester's ownership claim. Store who actually received it.
Survey wrong certification/report does not satisfy a verified-evidence milestone.
An ordinary report/abandon/failure still follows existing pressure activity rules.

Version 1 saved plans remain loadable with their original predicates; do not
silently reinterpret them. Mark them `legacy_resolution` for diagnostics. Do not
generate any new v1 auto-composed plans. Only an independently implemented typed
predicate proving the broad goal may set a faction desire to satisfied/failed;
otherwise keep it progressed and record the fulfilled collection separately.

Record only matching receipts and their source outcomes in the ending provenance,
not every unrelated mission from the campaign. Public fact IDs in summaries must
be known in the knowledge ledger. Reject ambiguous alternatives. No implemented
loss effect currently justifies manufacturing partial/failure alternatives; one
supported success is acceptable. Maintain free play and accepted unrelated jobs.

Acceptance: delivery resolves its collection but not its faction's legal goal;
wrong recipient/cause cannot satisfy another interest; cumulative receipts from
separate jobs survive canonical conversion; v1 saves load unchanged; no unsupported
effect can activate v2; ending provenance excludes unrelated actions and secrets.

### Package 5 — Author direction through the existing director, using only bound candidates

Files: existing campaign bible generation in `LLMInterface.gd`/StoryManager,
`CampaignBibleStore.gd`, new pure `scripts/story/CampaignDirectionContract.gd`
if a separate validator keeps the compiler focused. No new model family or planner.

Do not derive campaign objectives by choosing the first two sorted local needs.
The code supplies a private director packet of at most 8 verified collection
opportunities: IDs, public premise facts, faction interests/relationships, real
locations/recipients, supported completion kind, known prerequisites and route.
Filter unsupported/unreachable candidates before sending. Do not expose hidden
site truth or fixed-cast mysteries to the small dialogue model.

Director output schema is exactly:

```text
{
  version: 1,
  premise_fact_ids: [String],
  selected_collection_ids: [String],
  links: [{from_collection_id: String, to_collection_id: String,
           dependency_fact_id: String}],
  public_direction: String
}
```

Select 1–3 distinct supplied collection IDs. This is a cap, not a required three-job
campaign. Every cited premise/dependency fact must exist in the supplied facts.
Links must already be supported by a real dependency: one collected item/evidence
is required by the next existing opportunity. Reject cycles, invented links,
unknown IDs, empty premise references, unsupported promises and disconnected
claims. Do not force links when none exist. Do not accept a generated dramatic
claim merely because referenced IDs are structurally valid.

Compile an accepted proposal into a frozen v2 resolution plan: one success
alternative ANDs the selected `collection_satisfied` predicates. Its public goal
is completion of those specific campaign-relevant collections, not an unimplemented
legal/political outcome. Retain broader unresolved faction goals in the summary.
The unique reason must come from its premise and local dependencies, not a shared
authored finale. Do not claim this finite supported vocabulary guarantees infinite
novelty; report repetition through the existing signature system.

Generation lifecycle: existing director request/validation budget and explicit
failure reporting; one proposal plus at most one schema/binding repair. No retry
storm. If none validates, persist `direction_pending` and keep ordinary accepted
gameplay usable. No generic static ending fallback. Retry when new supported
world opportunities exist or the player uses the existing retry UI. Record failure
reason and proposal provenance. No bible regeneration or active-plan reroll.

Legacy campaigns without an explicit compatible direction remain on their existing
chapter/hook progression. Only new campaign generation or an explicitly stored
pending direction proposal enters this authoring path. A board visit is a consumer,
not authorization to replace an existing story.

For travel, use existing lead/knowledge/gate interfaces with registered destinations
and actual route IDs. Announce the local faction's verified reason for the lead;
do not generate gates or NPCs to repair an invalid proposal. Pending remote
references bind against persisted generated systems, not current-scene nodes.

Acceptance: two reproducible multi-system campaign traces produce distinct selected
causal opportunities and supported records; optional dependencies alter eligible
next jobs; unsupported writer claims rejected; no existing accepted plot rewritten;
save/reload preserves proposal, bindings, route, progress and final record.

### Package 6 — Automated evaluation and exact status reporting

Use the existing narrow writer/fact-packet/quality pipeline on the live-produced
causes. Do not change the diagnostic critic to authoritative just to increase
pass rates. Record separately structural validity, factual support, provenance
and unqualified prose quality. Do not change Kaelen/N.O.V.A. to solve small-model
writing problems. No player test is required now, but do not mark subjective gates
passed without one.

Add `tests/story/run_campaign_direction_trace_tests.gd` with fixed seeds and
offline director response fixtures. Exercise actual builder, QuestManager,
StoryManager, knowledge and disk checkpoint paths. Trace: tutorial completion,
two generated systems, valid courier acquisition/recipient, both supported
investigations, resolved activity pressure, novelty publication/acceptance and v2
campaign collection resolution. Include a failed save/retry and a restored
checkpoint with a newer loose cache. Trace output reports IDs/effects/semantic
signatures; different names alone do not count as divergence.

## Verification and working rules

Run headless Godot tests sequentially, each with a unique workspace absolute log:

```powershell
$runLog = Join-Path (Get-Location) '.tmp_godot_user/test_logs/session_next_01.log'
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/story/run_terminal_transaction_tests.gd --log-file $runLog -- --baseline-offline --llm-live-fire
```

Inspect SCRIPT ERROR/parse failures as well as exit codes and PASS. Workspace-local
test fixtures only; check resolved cleanup paths. Keep real user saves intact.
Run affected tests, then `tests/parse_check_scene_scripts.gd`, then diff whitespace
check. Refresh project maps after new files/systems. Do not broaden repeated test
runs without changed code or new failure evidence.

Existing core regressions: terminal transaction, campaign resolution, novelty
history, local pressure, pressure cards, investigation board/runtime/selector,
save migration/checkpoint/schema/story state, tutorial revisit, delivery recipient
and route, and fixed-cast souls. Expand these rather than testing only pure helper
dicts. The baseline fixes were exercised against 383 compilable project scripts.

At each package boundary update `docs/whileYouWasSleeping.md`, the current todo
and the latest plan status. Say what actually reaches the player, what remains
fixture-only, what is blocked by missing supported world bindings, and which
human/model/hardware gates are pending. Do not say all A–E is complete because
helper APIs exist. If the session ends, leave the next exact package/test failure
and modified files so another fresh session can resume without guessing.

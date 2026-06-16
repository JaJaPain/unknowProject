# Phase 3 To 7 Development Plan

Status: Draft working checklist

Date: 2026-06-15

Branch: `codex/jumpgate-system`

## Planning Progress

- [x] Reviewed long-term campaign architecture and checkpoint docs.
- [x] Cross-checked completed Phase 0, Phase 1, Phase 2, jumpgate, autopilot,
      mission-flow, lore, contacts, upgrade, pickup, and procedural-test-system
      docs.
- [x] Confirmed Phase 3 universal campaign time has an initial implementation
      footprint.
- [x] Captured public contract board direction: interstellar Craigslist, dark
      humor, mechanically real jobs, and code-owned mission rules.
- [x] Captured slot-first/Mad Libs mission generation rule for tiny local LLMs.
- [x] Captured first public-board combat variant:
      `RECOVER_COMBAT_DROP`.
- [x] Captured later branching reversal mission pattern:
      `TARGET_WITH_COMMS_REVERSAL`.
- [x] Captured non-traversable generated-system suns, directional lighting, and
      subtle animated starfields.
- [x] Began Segment 1 implementation planning from current code seams.
- [x] Began Segment 1 implementation.
- [x] Segment 1 Checkpoint 1 code slice: optional timed/urgent mission
      metadata, validation, QuestManager helpers, and focused tests.
- [x] Segment 1 Checkpoint 2 code slice: expiration checks, tracker countdown,
      expiration system chatter, and smoke coverage.
- [x] Segment 1 Checkpoint 3 code slice: public board UI skeleton with
      placeholder postings.
- [x] Segment 1 Checkpoint 4 code slice: code-owned public offer builder.
- [ ] Segment 1 Checkpoint 5 code slice: slot-first LLM request/validation and
      procedural fallback text.

## Purpose

This document turns the current long-term roadmap into the next five practical
development segments for SpaceGame. It assumes Phase 0, Phase 1, and automated
Phase 2 verification are complete, and it starts from the current Phase 3
universal campaign-time work.

The plan keeps the existing roadmap order, but pulls a few player-facing ideas
forward so the game gains useful loops before the full procedural campaign
director exists.

## Current Foundation

Already complete or implementation-complete:

- stable domain IDs and registries for systems, gates, factions, NPCs, ships,
  portraits, voices, missions, and assets
- registry-backed two-way jumpgate travel
- deterministic procedural test system with planets, asteroid rings, stations,
  outposts, stable asteroid IDs, and route tests
- campaign store with three slots, safe checkpoints, manual backup copies,
  recovery, version-2 import, map knowledge, chronicle branching, and Kaelen
  meta-memory
- provider-neutral speech service and stable voice-profile references
- current single-active-mission adapter for kill, ore delivery, and special
  pickup work
- initial universal campaign clock saved in global state and advanced by gate
  travel, docking, and undocking

Still pending from prior phases:

- hands-on Phase 2 approval of campaign/save/death screens
- hands-on confirmation of repaired station and jumpgate right-click selection
- release-target measurements on representative 8 GB GPU hardware
- LLM fallback tuning where fallback dialogue can still describe a different
  client or objective than the rendered contract details

## Core Mission Generation Rule

SpaceGame should not become a library of canned joke missions. The target is
that most mission flavor is generated, while code owns the mechanics.

Mission generation is slot-first, not prose-first.

The code builds the complete mechanical contract first:

- mission template
- objective type
- target faction, target count, drop chance, or item
- valid source and turn-in locations
- reward and urgent payout multiplier
- deadline and expiration behavior
- allowed branch choices
- consequence IDs
- required NPC, item, faction, and location placeholders
- allowed tone card

The LLM then fills bounded text fields using required placeholders. This is
intentionally closer to Mad Libs than freeform authorship.

Example required placeholder flow:

```json
{
  "template_id": "RECOVER_COMBAT_DROP",
  "tone_card": "dark_humor_public_board",
  "required_placeholders": [
    "{TARGET_FACTION}",
    "{ITEM_NAME}",
    "{TURN_IN_LOCATION}"
  ],
  "write_fields": [
    "posting_title",
    "posting_body",
    "acceptance_line",
    "completion_line"
  ]
}
```

Generated text is accepted only if:

- every required placeholder remains present exactly where needed
- the JSON schema is valid
- the text does not invent unsupported mechanics
- objective, reward, deadline, faction, location, and item details do not
  contradict the code-owned mission contract
- PG-13 and tone rules pass
- Kaelen's protection and Shiny/Indy speaker rules remain intact

If generation fails, code may retry with a short critique or use a procedural
slot-filler fallback for the same template. Fallback content should preserve
the same placeholders and mechanics, not switch to a different mission premise.

## Public Contract Board Tone

Kaelen and faction agents remain curated, voiced, faction-aware sources of
important work.

The public contract board is different. It is interstellar Craigslist:

- posted by locals, anonymous accounts, crews, shop techs, outpost workers,
  family members, failed entrepreneurs, nervous couriers, angry miners, or
  people clearly omitting context
- mechanically real, but narratively suspicious, petty, darkly funny, or
  morally awkward
- grounded in SpaceGame's cynical tone rather than pure meme chaos
- still validated into supported mission templates

The board can make the player think, "What did I just agree to help with?"
without letting the LLM invent impossible gameplay.

## Segment 1: Universal Time And Public Board Foundation

### Purpose

Make campaign time player-visible and useful by connecting it to urgent public
contract postings, deterministic deadlines, higher payouts, and future
time-based systems.

This segment keeps the current one-active-mission limit. It proves timed work
and public-board generation before the full mission framework is replaced.

### Player-Facing Gameplay Loop

- The player docks at a station or eligible outpost.
- The player can talk to Kaelen or open a public contract board.
- The board shows a small set of sketchy public postings.
- Most postings are normal supported contracts; rare postings are urgent.
- Urgent postings show a campaign-time countdown and higher payout.
- Accepting a posting still creates one active mission.
- Time advances through existing controlled actions such as gate travel,
  docking, and undocking.
- Finishing before the deadline pays the urgent reward.
- Missing the deadline expires or fails the mission cleanly.

Initial board mission templates should stay small:

- `DELIVER_ORE_PUBLIC`: deliver validated ore amount to a valid station.
- `PICKUP_SPECIAL_PUBLIC`: pick up a named part or package from an outpost and
  return it to a valid destination.
- `RECOVER_COMBAT_DROP`: destroy hostile ships from a valid faction until the
  missing data pack is recovered into the ship log, then turn it in.

The combat-drop template should not use physical cargo. The recovered data is a
ship-log flag so cargo capacity and special-cargo conflicts do not block the
first version.

### Implementation Checkpoints

- [x] Reconfirm current campaign-time behavior for gate travel, docking,
      undocking, saves, loads, and manual checkpoint copies.
- [x] Inspect current code seams for Segment 1:
      `CampaignClock`, `GameRoot`, `QuestManager`, `MissionAdapter`,
      `MissionState`, `LLMInterface`, and `UIManager`.
- [ ] Add or verify player-facing campaign time display where it is useful:
      HUD, mission panel, map, or campaign/save screen.
- [ ] Define timed mission fields: accepted time, deadline time, remaining
      time, urgency flag, expiration behavior, and urgent payout multiplier.
- [ ] Add deterministic countdown formatting using campaign time, not wall
      clock time.
- [ ] Add rare urgent variants for public-board postings.
- [ ] Add higher payout for urgent postings.
- [ ] Add expiration checks whenever campaign time advances.
- [ ] Add clear system messaging when a timed contract expires.
- [ ] Create the first public contract board UI using generated or fallback
      posting text while preserving the one-active-mission rule.
- [ ] Add slot-first LLM request and validation for public-board posting text.
- [ ] Add procedural slot-filler fallback that uses the same placeholders as
      the LLM request.
- [ ] Add `RECOVER_COMBAT_DROP` as the first public-board combat variant:
      hostile kills roll or deterministically resolve data recovery, then set a
      ship-log mission flag.
- [ ] Record timed accept, completion, expiration, failure, and abandonment as
      structured events where the current chronicle path supports it.
- [ ] Add placeholder hooks, without full behavior yet, for store refreshes,
      random events, and off-screen simulation on campaign-time advancement.

### Current Code Findings

- `CampaignClock` already provides `total_minutes`, `advance_minutes`,
  `capture_state`, `restore_state`, `formatted_datetime`, and
  `format_duration`.
- `UIManager` already displays campaign time in the HUD through
  `_on_campaign_time_changed`.
- `GameRoot` already advances campaign time by 45 minutes for gate travel,
  10 minutes for docking checkpoints, and 5 minutes for undocking checkpoints.
- Save, checkpoint, manual-backup, and jump smoke coverage already verifies
  campaign-time persistence and the in-flight manual-save time rule.
- `QuestManager` still owns one active mission dictionary, which is acceptable
  for Segment 1.
- `MissionAdapter` and `MissionState` currently support `KILL_SHIPS`,
  `DELIVER_ORE`, and `PICKUP_SPECIAL`.
- `UIManager` builds station, dock, agent, briefing, and tracker UI in code;
  the public board can be added beside existing dock services before the
  larger Segment 2 mission-board rewrite.
- `LLMInterface` already has objective validation, fallback mission templates,
  and contradiction rewriting. Segment 1 should extend that pattern rather
  than create a second freeform generation path.

### Segment 1 Build Order

#### Checkpoint 1: Timed Mission Metadata

- [x] Extend mission definitions and active mission state with optional timed
      metadata:
      - `is_timed`
      - `is_urgent`
      - `accepted_time_minutes`
      - `deadline_time_minutes`
      - `expires_after_minutes`
      - `expiration_policy`
      - `base_reward_credits`
      - `urgent_reward_multiplier`
- [x] Preserve compatibility for older missions without timed fields.
- [x] Add helper methods to `QuestManager` for remaining time, expiration
      checks, and urgent reward calculation.
- [x] Update mission validation tests for timed and untimed states.

#### Checkpoint 2: Expiration And Tracker UI

- [x] Recheck active mission expiration whenever campaign time advances.
- [x] Show remaining time in the quest tracker for timed missions.
- [x] Show urgent status and final payout clearly in the briefing and tracker.
- [x] Expire or fail timed missions deterministically, with system-chat
      messaging and cleanup.
- [x] Ensure completing, abandoning, loading, and restoring timed missions all
      leave the tracker consistent.

Verified:

- [x] `run_mission_contract_tests.gd` passes.
- [x] `--mission-smoke-test --no-save-load --baseline-offline` passes.
- [x] `--core-smoke-test --no-save-load --baseline-offline` passes.

#### Checkpoint 3: Public Board UI Skeleton

- [x] Add a `Public Contract Board` dock-service button where appropriate.
- [x] Create a board panel/list that can display several offers while still
      allowing only one active mission.
- [x] If a mission is already active, disable acceptance and explain the
      one-active-contract limit.
- [x] Show each posting's generated flavor text separately from the verified
      objective summary.
- [x] Include urgent countdown and urgent payout on urgent postings.

Verified:

- [x] `--core-smoke-test --no-save-load --baseline-offline` passes.
- [x] `--services-smoke-test --no-save-load --baseline-offline` passes.

#### Checkpoint 4: Code-Owned Public Offer Builder

- [x] Build public-board offers from code-owned templates first, before LLM
      text is requested.
- [x] Support initial templates:
      - `DELIVER_ORE_PUBLIC`
      - `PICKUP_SPECIAL_PUBLIC`
      - `RECOVER_COMBAT_DROP` as a disabled preview until Checkpoint 6 adds the
        recovery objective.
- [x] Choose target faction, item, location, reward, urgency, and deadline in
      code where the current template supports those fields.
- [x] Store required placeholders for generated text.
- [x] Convert accepted public-board offers into the current single active
      mission runtime shape.

Verified:

- [x] `run_mission_contract_tests.gd` passes.
- [x] `--mission-smoke-test --no-save-load --baseline-offline` passes.
- [x] `--services-smoke-test --no-save-load --baseline-offline` passes.
- [x] `--core-smoke-test --no-save-load --baseline-offline` passes.
- [x] Godot MCP connects, runs the project, and reports live UI elements.

#### Checkpoint 5: Slot-First LLM And Fallback Text

- [ ] Add a public-board posting text request that sends the model only the
      selected template, tone card, required placeholders, and fields to fill.
- [ ] Require valid JSON and exact placeholder preservation.
- [ ] Add validation that rejects missing placeholders or invented mechanics.
- [ ] Add retry-with-critique for one failed generation attempt.
- [ ] Add procedural slot-filler fallback for each initial public template.
- [ ] Keep fallback text darkly funny but mechanically aligned.

#### Checkpoint 6: `RECOVER_COMBAT_DROP`

- [ ] Add a new active mission objective type or compatible variant for combat
      data recovery.
- [ ] Spawn or mark eligible hostile targets from a valid faction.
- [ ] On eligible kills, deterministically resolve whether the data pack is
      recovered.
- [ ] Store recovered data as a ship-log mission flag, not cargo.
- [ ] Update tracker text from hunting to ready-to-turn-in when recovered.
- [ ] Turn in recovered data for payout and chronicle/history records.
- [ ] Ensure abandon, expiration, save/load, and target cleanup do not strand
      the mission.

#### Checkpoint 7: Segment 1 Regression

- [ ] Add focused tests for timed mission metadata and expiration.
- [ ] Add public-board fallback/placeholder validation tests.
- [ ] Add gameplay smoke coverage for accepting and completing an urgent public
      posting.
- [ ] Add combat-drop smoke coverage.
- [ ] Run the full baseline suite.

### Risks And Unknowns

- Urgent missions can feel unfair if ordinary travel consumes too much of the
  deadline.
- The single-active-mission model limits board usefulness until Segment 2.
- LLM text can imply the wrong objective, deadline, reward, or client unless
  validation owns the final objective summary.
- Expired missions must not leave spawned targets, special cargo, ship-log
  flags, or trackers in broken states.
- Manual backup copies must continue preserving safe checkpoint time rather
  than live in-flight tactical time.
- The board tone needs dark humor without becoming random nonsense or breaking
  the PG-13 setting.

### Suggested Tests

- [ ] Gate travel advances campaign time by the expected amount.
- [ ] Dock and undock advance campaign time by the expected amounts.
- [ ] Loading an older checkpoint rewinds campaign time.
- [ ] Manual backup made in flight preserves the safe checkpoint time.
- [ ] Public board displays several postings without allowing multiple active
      missions yet.
- [ ] Urgent posting displays a countdown.
- [ ] Completing before deadline pays the urgent reward.
- [ ] Missing the deadline expires or fails the mission cleanly.
- [ ] Expired mission cleanup removes or disables all related runtime state.
- [ ] `RECOVER_COMBAT_DROP` recovers data into the ship log and turns in
      without using cargo.
- [ ] LLM unavailable fallback creates a valid public-board posting whose
      objective, reward, item, faction, and deadline match the mission state.
- [ ] LLM output missing a required placeholder is rejected or retried.

### Done Criteria

- [ ] A player can browse public-board postings while docked.
- [ ] A rare urgent posting can be accepted, completed in time for higher pay,
      or missed for deterministic expiration.
- [ ] The public-board posting text is generated or procedurally slot-filled
      from code-owned mission data.
- [ ] The first combat recovery loop works: kill eligible hostiles until a data
      pack is added to the ship log, then turn it in.
- [ ] Saves, loads, manual backups, and fallback text all obey the same
      campaign clock.

## Segment 2: Mission Framework, Generated Templates, And Branching Contracts

### Purpose

Replace the prototype single-mission shape with a mission framework that can
support multiple offers, multiple active missions, reusable capabilities,
branching consequences, and generated-but-bounded mission text.

### Player-Facing Gameplay Loop

- The player sees several possible postings or agent contracts.
- The player can accept more than one mission when rules allow.
- Missions can branch when new information appears.
- Public-board jobs can start ugly and simple, then reveal complications.
- The player's choice affects payout, reputation, contacts, or future hooks.

### Implementation Checkpoints

- [ ] Replace `QuestManager.active_quest` as the gameplay authority with a
      mission collection while preserving compatibility adapters.
- [ ] Define mission states: offered, accepted, active, ready-to-turn-in,
      completed, failed, expired, abandoned, and resolved by alternate branch.
- [ ] Add a mission capability registry. Each capability owns validation,
      runtime handling, progress formatting, save schema, event subscriptions,
      cleanup, and completion rules.
- [ ] Port existing kill, ore delivery, special pickup, and combat-drop
      missions into registered capabilities.
- [ ] Add support for multiple board offers at once.
- [ ] Add a clear active-mission limit and UI selection behavior.
- [ ] Define LLM mission-template requests with required placeholders, tone
      cards, branch IDs, and schema validation.
- [ ] Add retry-with-critique for missing placeholders or contradictions.
- [ ] Add deterministic slot-filler fallback for each supported template.
- [ ] Add `TARGET_WITH_COMMS_REVERSAL` as the first branching proof case.
- [ ] Add branch choices such as finish job, take bribe, walk away, report the
      truth, or escort to safety only when their mechanics are implemented.
- [ ] Add cleanup for branch-resolved targets, spawned ships, temporary map
      markers, and mission UI.
- [ ] Add extension tests proving a new mission capability can be registered
      without editing the mission core.

### Risks And Unknowns

- Multiple active missions can create confusing target ownership and cleanup.
- Branching missions need careful UI so players understand consequences.
- The LLM must not be allowed to invent a branch choice that has no runtime
  handler.
- Existing save compatibility must survive the transition from one active
  mission to a mission collection.
- Public-board humor can undercut stakes if every mission twists too hard.

### Suggested Tests

- [ ] Legacy saves with one active mission import into the new collection.
- [ ] Multiple missions can coexist, update, complete, expire, and abandon.
- [ ] New capability registration works without mission-manager edits.
- [ ] Invalid generated template output fails closed.
- [ ] Branching target mission pauses combat at the trigger threshold and
      presents only implemented choices.
- [ ] Taking a bribe, finishing the kill, walking away, or alternate resolution
      each records different deterministic consequences.

### Done Criteria

- [ ] The game supports multiple active missions and multiple public-board
      offers.
- [ ] Mission mechanics are registry-driven rather than hardcoded through one
      central match block.
- [ ] Generated mission flavor uses bounded templates and required placeholders.
- [ ] At least one branching public-board mission proves mid-mission reversal
      without breaking saves or cleanup.

## Segment 3: Economy, Stores, Random Events, And Interceptors

### Purpose

Use campaign time to make stores, trade, and local danger change in bounded,
explainable ways without direct LLM control.

### Player-Facing Gameplay Loop

- The player checks stores and markets over time.
- Stock, prices, and local needs refresh gradually.
- Urgent, valuable, illegal, or suspicious jobs may attract trouble.
- Outbound and return-trip interceptors create risk around public-board work.
- Old systems remain useful through stock refreshes, stored goods, contacts,
  and changing opportunities.

### Implementation Checkpoints

- [ ] Define store inventory refresh intervals using campaign time.
- [ ] Add bounded stock recovery and depletion for station stores.
- [ ] Add regional supply and demand hooks for first resource types.
- [ ] Add random event scheduler driven by campaign time, seed, cooldowns,
      location, recent events, and pacing budget.
- [ ] Add interceptor templates for outbound departure and return-trip arrival.
- [ ] Make interceptors eligible from mission risk data rather than LLM direct
      spawn requests.
- [ ] Add urgent-job risk modifiers for specific public-board templates.
- [ ] Add early mixed-resource and material planning hooks if needed for later
      upgrade tiers.
- [ ] Add event records for store refresh, shortage, encounter, and interceptor
      outcomes where chronicle support exists.

### Risks And Unknowns

- Store refreshes can become exploitable if waiting is too cheap.
- Interceptors can feel punitive if the player cannot predict risk.
- Time-based random events must be seeded and persistent enough to prevent
  reload farming.
- Economy changes should be visible and explainable, not invisible math.

### Suggested Tests

- [ ] Store stock changes only after enough campaign time passes.
- [ ] Loading a checkpoint restores store state to that checkpoint.
- [ ] Repeating one trade loop cannot produce unlimited risk-free profit.
- [ ] Interceptor eligibility is deterministic from mission state and time.
- [ ] Reloading before an eligible event cannot reroll rare outcomes.
- [ ] Ignored, defeated, escaped, and return-trip interceptors clean up safely.

### Done Criteria

- [ ] Stores refresh through campaign time.
- [ ] Random events and interceptors are scheduled by deterministic code.
- [ ] Urgent or suspicious work can create outbound or return-trip danger.
- [ ] Leaving and returning after controlled time creates bounded, explainable
      changes.

## Segment 4: Gate Discovery, Repair, Branches, Suns, And Starfields

### Purpose

Turn jumpgates into a discovery and campaign-branching system, then prepare
generated destinations before the player can choose them.

### Player-Facing Gameplay Loop

- The player hears rumors, takes a job, or receives a Kaelen hint about a gate.
- The player investigates coordinates, scans, repairs, unlocks, or opens a
  route.
- The player compares at least two viable onward branches.
- Each destination is already generated and committed before it is advertised.
- New systems feel like solar systems through a visible, non-traversable sun
  and living starfield.

### Implementation Checkpoints

- [ ] Expand map knowledge UI and state for known, hidden, rumored, blocked,
      and damaged routes.
- [ ] Define gate discovery actions: scan, investigate coordinates, learn from
      NPC/contact, complete prerequisite, repair damage, receive Kaelen deal,
      or construct/open a rare story gate.
- [ ] Define what each gate action means mechanically and narratively.
- [ ] Add delayed Kaelen gate-reveal eligibility using campaign time, local
      relationships, mission history, and current branch readiness.
- [ ] Generate and validate two branch destinations before showing either as a
      real choice.
- [ ] Keep the development test system as a fixture, not the permanent
      production second system.
- [ ] Add one seeded, non-traversable sun per generated system.
- [ ] Use the sun as the main directional lighting anchor.
- [ ] Add a seeded distant starfield or skybox with sparse low-cost animated
      shimmer.
- [ ] Ensure sun and starfield visuals never become targetable, dockable,
      mineable, or saved as mutable mission objects.
- [ ] Add branch map UI that shows confirmed, rumored, blocked, damaged, and
      unknown routes clearly.

### Risks And Unknowns

- Gate discovery can feel fake if destinations are not prepared before reveal.
- Gate repair can become an arbitrary blocker unless required materials and
  steps come from established economy and geology.
- Starfield animation must be cheap and must not create motion sickness or
  visual noise during combat.
- Kaelen should invite travel without forcing departure or feeling like a menu.

### Suggested Tests

- [ ] Loading an older checkpoint can hide later gate knowledge without
      deleting permanent route or generated system records.
- [ ] Damaged, blocked, rumored, hidden, and known routes render correctly.
- [ ] A branch is not offered until both destination systems validate.
- [ ] Gate repair consumes only valid resources or prerequisites.
- [ ] Sun and starfield appear in generated systems and do not enter targeting,
      navigation, mission, or save-state ownership.
- [ ] Travel to either branch preserves active missions, campaign time, store
      state, and chronicle continuity.

### Done Criteria

- [ ] The player can discover and open gates through clear mechanics.
- [ ] At least two branch destinations can be compared and chosen.
- [ ] Generated systems include seeded sun lighting and a subtle animated
      starfield.
- [ ] Gate knowledge rewinds correctly while permanent system identities remain
      stable.

## Segment 5: Chronicle, Relationships, Persistent Contacts, And Kaelen Deals

### Purpose

Create the social and memory layer that makes generated systems, recurring
contacts, and Kaelen's long-arc mystery matter across time.

### Player-Facing Gameplay Loop

- The player completes, betrays, abandons, or twists missions.
- NPCs and factions remember meaningful actions.
- Minor locals can become recurring contacts.
- Kaelen routes travel deals through prior relationships or unresolved debts.
- The chronicle tracks what the player actually did for later summaries,
  dialogue, legacy records, and eventual eulogies.

### Implementation Checkpoints

- [ ] Expand structured chronicle events for mission choices, branch outcomes,
      urgent completions, expirations, interceptors, gate discoveries, first
      arrivals, relationship changes, and major purchases.
- [ ] Add player-to-NPC relationship records.
- [ ] Add player-to-faction and faction-to-faction relationship reason records.
- [ ] Add NPC memory retrieval against current timeline only.
- [ ] Add summary compaction so LLM prompts receive relevant facts without full
      history dumps.
- [ ] Add dynamic minor-to-major NPC promotion when story or repeated player
      interaction warrants it.
- [ ] Assign persistent contact IDs, portrait IDs, voice-profile IDs, and
      fallback presentation data.
- [ ] Define generated contact creation rules for public-board posters,
      outpost workers, recurring clients, and mission survivors.
- [ ] Add Kaelen travel deal records: offered, refused, delayed, revised,
      alternate, completed.
- [ ] Seed rare non-repeating hints about Kaelen's origin and travel method
      without confirming the final truth.
- [ ] Preserve Kaelen protection and bounded discarded-timeline references.
- [ ] Add groundwork for later death, eulogy, and legacy campaign closure using
      verified chronicle facts only.

### Risks And Unknowns

- Relationship values can become meaningless if every small action changes too
  much.
- NPC memory prompts can grow too large without summary compaction.
- Generated portraits and voices need fallback identity rules before full asset
  production is online.
- Kaelen mystery hints must remain rare so they feel intentional.
- Death/eulogy work should not arrive before chronicle facts are reliable.

### Suggested Tests

- [ ] Mission choices append structured chronicle events with correct subjects.
- [ ] Loading an older checkpoint hides future current-branch history from NPC
      memory queries.
- [ ] Relationship changes include reason records and survive save/load.
- [ ] A minor NPC can be promoted without losing portrait, voice, or prior
      facts.
- [ ] Kaelen deal offers can be delayed, refused, revised, and completed.
- [ ] Generated dialogue receives only current-timeline, relevant memory.
- [ ] Death records can select verified chronicle facts without inventing
      unsupported details.

### Done Criteria

- [ ] Contacts and factions remember meaningful player history across travel
      and return.
- [ ] Chronicle-derived summaries replace prose-only quest history for new
      mission and dialogue prompts.
- [ ] Kaelen can offer travel deals that reference real prior events without
      forcing the player forward.
- [ ] The campaign has the memory substrate needed for persistent generated
      NPCs, portraits, voices, and eventual eulogy/legacy closure.

## Working Order

The intended implementation order is:

1. Universal time and public board foundation.
2. Mission framework and generated template validation.
3. Economy, stores, random events, and interceptors.
4. Gate discovery, generated branches, suns, and starfields.
5. Chronicle, relationships, persistent contacts, and Kaelen deals.

This order keeps the next step small enough to build, but each segment leaves a
clear hook for the systems that follow.

# Plan: campaign uniqueness, believable quests and natural dialogue

Status: proposed implementation plan, 2026-09-11. No gameplay changes in this document.
Owner intent: Abe wants each campaign to feel new after the tutorial system, a small
local model to sound like a person, and options to exist only for a valid reason.
Player testing remains deferred. This plan provides automated development gates;
it does not label unreviewed dialogue as human-approved.

## 1. Product contract

Follow [design_end_goal.md](design_end_goal.md). Preserve Kaelen and N.O.V.A.'s
personalities, canon, soul projections and voice banks. Generated people must not
be copies of them. Tutorial gates and tutorial completion remain code-owned.

A campaign should differ in what people want, what caused their problems, what the
player can accomplish, how those actions change later work, where that work leads,
and what finally happens. Names, layouts and colorful wording support that
difference; they cannot substitute for it.

Familiar verbs are allowed: fly, deliver, mine, recover, investigate and fight.
Repetition of the same causal story with renamed nouns is the failure to prevent.
Absolute uniqueness across unlimited campaigns cannot be guaranteed. Measure and
reduce recognizable repetition rather than presenting distinct seeds as proof.

**A quest does not need a branching decision.** A clear job with one sensible
completion path is valid. Accept, decline, leave, and optional clarification are
interaction controls, not evidence of meaningful branching. Never manufacture a
betrayal, moral dilemma, hazard or second claimant to fill a menu.

## 2. What exists and what still needs work

Verified against the source on 2026-09-11:

| Existing component | Build on it; address this limitation |
|---|---|
| `CampaignGeneratedFactionStore.generate_system_factions()` | Saved local identities and opinions work, but desires currently draw from four goal templates. Two-faction systems always receive the same forced hostility pattern. |
| `SystemConfig._apply_faction_story()` and `PublicBoardOfferBuilder` | Local desires feed causes, but selecting a cause by mission verb is too coarse to justify every particular cargo, target or destination. |
| `MissionConversationGeneration`, compiler and worker | Narrow requests, partial retention, stale-response guards and retry budgets exist. Reuse this pipeline. |
| `DialogueBundleValidator` | Checks fields, lengths, repeated lines, forbidden facts and answer anchors. Passing these checks is not proof of realism or natural speech. |
| `LocalModelGateway` | Default small model is configured as `qwen3:4b`; use the configured model, not a newly assumed hardware requirement. |
| Investigation prototype and outcome callbacks | Domain work exists; runtime offer/site/action integration and evolving pressures remain incomplete. |

This plan coordinates the existing mission-conversation and replayability plans.
It does not restart completed work. Where older plans require a fixed number of
branches, ask-why/risk/connection buttons, or shape rotation regardless of context,
this user instruction takes precedence: eligibility and credibility come first.
P2/P3 remain useful implementation contracts, but their fixed catalogs are an
initial supported action vocabulary, not the finished diversity solution.

## 3. Build a causal campaign, then express it

### Campaign identity

At campaign creation, persist a versioned campaign premise with a concrete dispute,
scarce resource or dependency, an unresolved question, and possible resolution
conditions. Generate a small structured proposal, not an entire novel. Compile it
against supported game capabilities before accepting it as campaign truth.

Every proposed consequence must map to something the game can actually record or
do: an offer becomes available, a reward changes, an existing access condition is
resolved, evidence is delivered, an NPC's known facts change, or an ending predicate
becomes true. Reject unsupported station destruction, simulated population deaths,
market collapse, or other dramatic promises the game cannot enact.

Generate a few credible future directions, not a mandatory sequence of identical
chapters. Choose later beats from committed outcomes and still-open interests.
Keep existing authored dependencies authoritative during migration; do not replace
an active campaign's accepted plot or invalidate its current missions.

### Local factions with specific interests

Extend each saved local faction with:

- A desired change and observable success condition.
- Its current obstacle and the event that caused it.
- What it controls, needs, and can credibly pay or offer.
- A relationship to each relevant local peer, with a concrete supporting event.
- A public explanation, separately stored private motive, and who knows each fact.
- A limit it will not cross and a condition under which its position could change.

Allow cooperation, dependency, indifference, rivalry and asymmetric opinions.
Do not force everyone to hate someone. Two factions can need each other while
disagreeing over one specific matter. Relations must cite actual local facts;
random standing numbers alone are insufficient.

The model proposes specific motivations using the campaign premise and local world
facts. Code binds resources, people, locations, capabilities and effects. A draft
becomes authoritative only after those bindings validate. Once published, identities
and established facts stay stable across revisit and reload.

### Reasons to travel

Give a frontier lead a dependency on the next system: evidence originated there,
the required expertise is there, or a named local party has a verified connection.
Prepare the destination's own roster before publishing that lead. The next system
has its own interests; it does not inherit tutorial factions to carry the plot.

Validate the lead against the actual gate graph, accessibility prerequisites and
destination services. Exploration can remain voluntary. Never announce that the
player must visit an ungenerated or unreachable place.

## 4. A quest must make sense before anyone writes its dialogue

Introduce a versioned `QuestCausalContract`, compiled into the existing mission
definition and narrative metadata. Proposed fields:

```text
id, revision, campaign_id, system_id
requester_id, beneficiary_id, desire_id, triggering_event_id
problem_fact_ids, public_fact_ids, private_fact_ids
objective_binding              # actual capability, item, target, quantity, location
why_this_action_fact_ids       # how doing the objective helps this particular problem
why_player_fact_ids            # credible delegation, not mandatory flattery
urgency_fact_ids               # empty when there is no genuine urgency
reward_source_fact_ids
recipient_binding             # required for delivery
completion_effect_ids, failure_effect_ids
branch_contracts              # empty is valid
semantic_signature
```

Do not require NPCs to recite every field. This is the internal explanation needed
to make a believable request, not an exposition checklist for their opening line.

Implement `QuestPlausibilityValidator` with two layers:

1. **Authoritative checks:** entity ownership, active capability, real cargo and
   quantities, reachable location, appropriate recipient, evidence prerequisites,
   affordable/supported reward, supported effects and compatible deadlines.
   Revalidate changing conditions at publication, acceptance, docking and turn-in.
2. **Causal review:** does the action actually address the problem; why would this
   person ask this pilot; does the alleged risk follow from established facts; does
   the promised outcome follow from completion? Use constrained model review for
   ambiguities that code cannot settle. An uncertain review requires repair or
   withholding a new optional offer, not inventing a missing fact.

For deliveries, require a recipient role that can plausibly accept the object,
not just any resident. Persist the binding with the cargo assignment and mission.
Docking reconciliation may restore/create a mission contact from that validated
binding, in the correct location only, with a stable ID. Never clone a random
resident, move a protected character, consume cargo early or lose the recipient
after a reload. An inaccessible recipient produces a recoverable mission state.

Distinguish a character's lie from broken quest logic. A lie is valid only when the
contract records the belief/deception and supported evidence or consequences.
The model must not invent a lie to explain a contradiction it introduced.

## 5. Only offer choices that deserve to exist

Introduce `QuestChoicePolicy` before conversation planning and UI publication.
Each branch requires:

```text
id, action_id, eligibility_predicates
motivation_fact_ids             # why a reasonable player might take it
public_information_fact_ids     # what the player can know at this point
costs, effect_ids, outcome_id
distinct_from_branch_ids        # different supported result or method
```

The policy checks that the action is supported, its motive is grounded, the player
has enough information to understand it, and it differs meaningfully from the
other actions. No fixed branch count, no mandatory good/evil pair, no requirement
that every branch have a numerical cost. A believable preference or allegiance
can justify an option if the game records and honors it.

Equivalent buttons collapse to one action. A blatantly worse action with no
credible motive is removed. Do not arbitrarily balance away a legitimate easy
answer; some situations should be straightforward. A hidden difference cannot
rescue two otherwise identical buttons unless the uncertainty itself is supported
and understandable to the player.

Filter follow-up questions separately. Offer “Why?” only when there is additional
useful explanation; “What is the risk?” only with a supported risk/uncertainty;
and a connection question only when a real connection is known and relevant.
If the opening already fully answers a question, omit it. Avoid an identical
three-question menu on every mission. Never fabricate danger to enable a button.

Recheck action eligibility when clicked. Show a disabled explanation for a
temporarily unavailable, previously disclosed option. Do not silently remove a
promised resolution from an accepted mission because a later prose review dislikes it.

## 6. Help the small model speak naturally

The model's main dialogue job is to express a settled situation as one person
speaking to another. Separate world proposal, quest compilation, line writing and
line review. Do not ask one response to invent the economy, solve quest mechanics,
write six branches and roleplay the whole cast.

Build a compact `DialogueFactPacket` for each slice:

- Speaker's approved voice guidance; protected cast uses existing soul projection.
- Who they are speaking to, what they want right now, and their immediate attitude.
- Only facts this speaker knows and can disclose.
- The current player question or conversational purpose.
- Accepted opening/relevant preceding line, plus the facts required in this answer.
- A small recent-phrase sample to discourage habitual openings and repeated jokes.

Use one opening or one answer per request when quality needs it; retain the current
two-answer batching only if the evaluation corpus shows no loss. Start with existing
length limits and flat JSON. Tune generation settings through recorded comparisons
on the actual configured model; do not assume a new temperature fixes prose.

Writing guidance: plain spoken language, concrete nouns, contractions where natural,
and one clear thought before optional detail. Let people be direct, reserved, annoyed
or warm for a reason. Do not enforce slang, filler, swearing, verbal stumbles, jokes,
or eccentric metaphors as a universal “human” style. Not every person is a comedian.

Use short developer-reviewed examples for each conversational purpose as teaching
material, not a bank of lines to paste into campaigns. Keep examples outside the
player-visible fallback path. Protect fixed-cast guidance from edits made to improve
generic NPC scores.

The current exact-anchor requirement can make natural paraphrases fail. Retain exact
IDs, quantities and protected names where necessary; migrate causal checks toward
supported fact references plus semantic review. Keyword overlap and a model's
claimed fact IDs do not prove that a sentence actually states those facts.

## 7. Publication quality gate

Add `DialogueQualityGate` alongside the existing validator, not in place of it.
Apply the same contract to agent offers, board descriptions, recipient dialogue,
relevant lounge questions and completion lines so a weak path cannot bypass it.

| Gate | Check | Failure behavior |
|---|---|---|
| Mechanics and knowledge | Existing validation plus causal contract, valid option, no unsupported promise or secret leak | Reject; repair the relevant draft only |
| Conversation coherence | Answer addresses the actual question; opening and answer agree; no already-spoken facts change | Reject contradiction; retry only unpublished content |
| Natural speech | Clear spoken phrasing, appropriate specificity, no unexplained jargon, robotic restatement, forced joke or irrelevant flourish | Constrained editorial review and local repair |
| Repetition | Reused causal pattern, opening structure, distinctive phrase or joke | Prefer another eligible cause or rewrite unpublished prose |
| Protected character | Existing fixed-cast rules and regression examples | Never relax canon to improve a general style score |

The review request receives the proposed text and the small public fact packet in
a fresh context. It returns a tiny schema: `pass|repair|uncertain`, issue codes,
field names and offending spans. It does not generate replacement facts or approve
mechanical changes. Text under review is data, not instructions to the reviewer.

Use a separate review prompt through the same local gateway initially. The same
small model can miss its own mistakes: this is an imperfect filter, not independent
proof. Measure false passes and false rejections against a held-out labeled corpus.
If review adds cost without measurable value, retain it offline until improved;
hard checks stay in the runtime path. A larger reviewer is optional development
equipment, never a hidden requirement for players.

Initial budget per slice: one draft, one review, at most one targeted rewrite and
one final review; every candidate also runs hard checks. Share this budget with the
existing worker rather than nesting retry loops. Count tokens/time across all calls,
persist attempts, honor existing concurrency, cancellation and stale-state guards.
Prefetch work; never run model inference inside a branch execution or delivery commit.

Record `quality_pending`, `quality_passed`, `quality_rejected` and `quality_unknown`
separately from generated/partial/fallback provenance. A valid template does not
count as natural generated dialogue, and a critic's pass is not human approval.

Roll out in diagnostic mode first. Then gate **new discretionary offers** on an
accepted causal contract and opening. Pending optional speech can remain absent;
offer fewer good jobs instead of filling every slot with weak ones. Keep existing
accepted jobs functional through factual objective/recipient UI and the existing
compatibility path. Essential navigation/tutorial instructions cannot depend on
model availability. Never play or replace a line after it was already presented.

## 8. Consequences and endings that make campaigns diverge

Integrate the two-shape investigation prototype into real offers, placement, scans,
resolution commands and saves before expanding shape count. Apply the choice policy
to those shapes; a recipe does not earn branches automatically.

Implement the existing P3 reducer next, linked to desire IDs and deduplicated mission
outcomes. Start with supported offer availability, reward and evidence effects.
Count resolved activity, not time spent reading, as specified in P3. Keep pressure
activity separate from the callback delivery clock. Save both with the same checkpoint
as cargo, credits and mission state; replaying an outcome must not duplicate effects.

Then extend the reducer with validated desire success/failure transitions. Relieving
one interest can expose another problem, change a dependency or close an optional
lead. Show only consequences that were actually applied. Do not constantly escalate
everything or require every completed mission to create another emergency.

Compile campaign resolution conditions from its premise and supported effects.
Persist several possible resolutions where justified, including legitimate partial
success/failure. The player's actual sequence determines eligible outcomes; the model
only narrates the resulting record. Endings must name supported changes, unresolved
interests and the contribution of recorded actions. A different epilogue over the same
unchanged world does not satisfy the end goal. Do not force a final menu of choices
if prior actions already resolved the campaign.

## 9. Detect repetition below the wording

Persist a semantic signature for each published quest: motive, triggering event
category, obstacle, dependency, beneficiary relationship, resolution method, evidence
pattern and consequence. Normalize away names and decorative details. Compare both
individual missions and short sequences so renamed courier chains count as repeats.

Track offered and accepted content separately. Do not count speculative prefetch as
player exposure. In a bounded local cross-campaign history, retain signatures and
opening patterns only, never carry cast memories or secret campaign facts into a new
run. Make history resettable and handle missing/corrupt history without breaking saves.

Select the least-recent eligible causal situation before writing prose. Structural
checks catch obvious reskins; offline semantic comparisons flag subtler ones. No
branch, hazard or unsupported objective may be added solely to meet novelty targets.
When variety is exhausted, expose diagnostics and prefer fewer offers to fake variety.

System identity must also affect travel and play: station roles, resource placement,
route lengths, safe approach geometry and mission dependencies. Vary within validated
navigation constraints. Audit local residents, docking voices, ship naming, factions
and HUD labels so tutorial identities cannot leak into new systems.

Reputation proposal: preserve local faction standing keyed by stable IDs across
revisits, show the current system's standings, and defer portable notoriety until it
has a separate behavior contract. Do not reset standing at every jump or propagate
tutorial opinions automatically. This proposes a direction for the end-goal document's
open reputation question; implementation should document the chosen behavior explicitly.

## 10. Implementation sequence and completion evidence

Each phase is a reviewable change with migration and regression tests. No player
testing is required to begin these phases; subjective acceptance remains pending.

| Phase | Deliverable and likely files | Automated completion evidence |
|---|---|---|
| A — Baseline and contracts | New causal/choice contract validators; `MissionDefinition`, `MissionAdapter`, `NarrativeMetadata`; quality fixture corpus | Existing missions roundtrip unchanged; impossible deliveries, unsupported consequences and meaningless options reject; one-path quest passes |
| B — Believable options | New `QuestChoicePolicy`; conversation plan/controller, builders, `UIManager` | No mandatory question trio; redundant branches collapse; missing information prevents misleading choices; click-time checks and saved terms hold |
| C — Natural dialogue gate | New fact-packet builder and `DialogueQualityGate`; compiler/generation/worker, gateway, diagnostics | Hard contradiction/leak fixtures reject; bounded retries and review failures work; held-out quality report produced; no cast regression |
| D — Rich local causes | Extend faction store and `SystemConfig`; builders compile causal contracts rather than attach reasons by verb alone | Distinct motives and relationship patterns across seeds; cargo/action matches reason; local IDs persist; no tutorial leakage |
| E — Playable consequences | Finish P2 runtime integration, then P3 reducer in `StoryManager`, `QuestManager`, saves and UI | Real entry-path smoke; scans/branches/deliveries commit once; outcome changes next eligible offers; rollback restores world and story together |
| F — Campaign direction and endings | Extend campaign generation/validation, frontier lead generation and story resolution | Reachable destination leads; supported end predicates; different action sequences produce different recorded outcomes; no invented epilogue claims |
| G — Freshness and performance qualification | Signature history, batch runner, diagnostic report, regression corpus | Cross-seed and sequence comparisons; source-rate, retry, latency and memory measurements; remaining subjective findings explicitly listed |

Start A–C with three vertical examples: a straightforward courier job, an investigation
with one justified decision, and an investigation whose proposed second option is
correctly removed. Prove the full offer→speech→accept→complete→save path before widening
the corpus. Reuse existing scheduler, cache, capability and persistence systems;
do not build another parallel quest engine.

## 11. Quality evaluation without requesting player tests now

Create a versioned corpus of at least 120 situations covering simple jobs, genuine
tradeoffs, no-risk work, ambiguous evidence, deceit with recorded support, unavailable
recipients, long names, follow-up questions, reloads and protected-cast interactions.
Include good concise lines that should pass, awkward-but-factual lines, fluent lies,
irrelevant answers and artificial choices. Hold out at least 30 cases from prompt
tuning; use different names/situations, not trivial copies of training examples.

Store model identifier/digest, settings, prompt/validator versions, generation seed,
fact packet, output, reviewer verdict, hard failures, repairs, source and elapsed time.
Separate synthetic fixture responses from real local inference results. Keep raw
diagnostics outside player-facing dialogue. Human-written fixture labels can guide
development now; later blind review must test whether those labels match actual
player impressions. No fake confidence percentages.

Initial release targets, to be measured rather than claimed:

- Zero accepted invalid bindings, unsupported effects, leaked secrets or duplicate
  payouts in deterministic and failure-injection suites.
- Every published branch has a supported action, grounded motive and distinct
  result/method; straightforward fixtures remain one-path missions.
- At least 90% of held-out openings and answers score 4/5 or better for clarity,
  conversational phrasing, relevance and believability in later blind human review;
  zero severe protected-character violations. Report per dimension and speaker.
- Report critic false-pass/false-rejection counts with sample sizes, including
  disagreement and `uncertain`; do not ship the critic as a hard style filter until
  calibration supports it.
- Batch 20 campaigns, at least 5 generated systems and 20 exposed quest candidates
  each. Detect renamed duplicates and repeated opening sequences. Aim for no exact
  normalized causal repeats in the first 10 discretionary offers per campaign;
  record shortages instead of weakening plausibility to hit the target.
- Measure p50/p95 publication latency, generated versus fallback exposure, retries,
  total model calls and peak combined memory on the 8GB target budget. Preserve
  responsive UI and bounded queues. No numerical performance claim before a run.

Run Godot headless suites sequentially with unique workspace log files. Compile all
project scripts and inspect SCRIPT ERROR output even if a suite prints PASS. Include
offline model absence, invalid critic output, cancellation, full retry exhaustion,
save/reload, stale world revision and checkpoint failure in integration tests.

The deferred final question is experiential: does a returning player understand why
this particular person wants this particular thing, and does the exchange sound like
a person asking for it? Automated evidence supports that review; it cannot replace it.

---

## Implementation status

Updated as work lands. Each row states what is IMPLEMENTED, what is covered by
DETERMINISTIC tests, what has been measured against a REAL model, and what is
still awaiting human review. These are different things and are not merged.

### Phase A — baseline and contracts

| Item | State |
|---|---|
| `scripts/domain/QuestCausalContract.gd` — versioned contract, normalization, structural validation, name-free semantic signature, public/private fact split | Implemented; deterministic tests pass (mutation-checked) |
| `scripts/domain/QuestPlausibilityValidator.gd` — layer 1 authoritative checks (objective support, capability, quantity, reachability, recipient role/presence/protection, reward funding/affordability, supported effects, explained deadlines) staged at publication/acceptance/docking/turn-in | Implemented; deterministic tests pass (mutation-checked) |
| `causal_contract` persisted inside existing narrative metadata (no second persistence system) | Implemented; save/load roundtrip and legacy-safety tested |
| `tests/fixtures/QuestContractFixtures.gd` — the three vertical examples plus rejection fixtures | Implemented |
| Real-model measurement | Not applicable to this phase (no inference involved) |
| Human review | Pending |

Deliberate design notes:

- The validator takes a plain `world` snapshot rather than reaching for
  autoloads, so it is testable headless and callable from any entry point.
- A missing key in that snapshot means UNKNOWN, not invalid. Affordability and
  reachability only fail when the caller actually supplied the facts to fail on.
- Recipient PRESENCE is only enforced at docking and turn-in. A job posted
  honestly does not retroactively become invalid because a resident moved; it
  becomes a recoverable mission state at the dock.
- An empty `urgency_fact_ids` and an empty `branch_contracts` are both CORRECT
  and are asserted as such by fixture 1. Nothing in the gate pushes a quest to
  grow a deadline or a menu.
- The semantic signature deliberately drops display names, quantities, prose and
  the campaign-specific instance suffix of desire/event IDs, so a renamed
  courier chain collides with the original instead of reading as new content.

### Phase B — believable options and question eligibility

| Item | State |
|---|---|
| `scripts/story/QuestChoicePolicy.gd` — branch filtering (unsupported action, ungrounded motive, player cannot know, ineligible, equivalent-collapse) and question filtering (opening already answers it, no supported risk, no known connection) | Implemented; deterministic tests pass |
| Wired into `MissionConversationPlan.build_plan()` — the single point every offer builder already passes through, so no second quest engine | Implemented; existing plan/compiler/controller/flow/validator suites still pass |
| Three vertical examples proven through the real plan builder | Implemented and tested |
| Real-model measurement | Not applicable (policy is deterministic) |
| Human review | Pending |

Behavior decisions worth recording:

- **No contract means no policy.** An offer without a causal contract — every
  existing saved offer — gets the exact menu it had before. A later policy must
  never silently withdraw a resolution the player was already promised. This is
  asserted directly by `_test_plan_without_contract_is_unchanged`.
- **The policy only ever REMOVES.** There is no path by which a shortage of
  options causes one to be invented. `single_path: true` is a normal, reported
  outcome, not an error state.
- Two bugs were found by the vertical fixtures rather than by the unit tests:
  `_has_risk()` could not see a risk recorded in the contract (so a genuinely
  hazardous courier job lost its risk question), and the "why" check treated
  problem facts as a *fallback* for action-justification facts rather than as
  part of the same question, which let a fully-explanatory opening keep a
  button that could only restate it. Both are fixed and pinned by tests.
- Every drop is reported with a reason in `policy_dropped`, so a quest ending up
  with fewer options is visible as a decision rather than as silence.

### Phase C — compact fact packets and a measured quality gate

| Item | State |
|---|---|
| `scripts/story/DialogueFactPacket.gd` — one speaker, one purpose, bounded public facts, priority ordering per purpose, recent-phrase sample, prompt rendering | Implemented; deterministic tests pass |
| `scripts/story/DialogueQualityGate.gd` — hard checks (private leak, invented number, repeats/contradicts opening, does-not-answer, missing required fact, reused habitual phrase, robotic restatement) | Implemented; deterministic tests pass (mutation-checked) |
| Constrained reviewer: fresh-context prompt, text presented as data, tiny verdict schema, conservative parsing | Implemented; deterministic tests pass |
| `quality_passed` / `quality_unknown` / `quality_rejected` recorded separately from generated/partial/fallback provenance | Implemented; asserted by test |
| Bounded budget (1 draft + 1 rewrite, 2 reviews) sharing the worker's existing attempt accounting | Implemented as a policy function; **worker wiring still pending** |
| Real-model measurement | **Not measured.** Held-out corpus, critic false-pass/false-rejection rates and latency are not yet run |
| Human review | Pending |

Decisions worth recording:

- **Private facts are withheld, not guarded.** They never enter the prompt at
  all. The leak detector still exists and is tested, but it is the second line
  of defence, not the first — detecting a leak after the fact is strictly worse
  than never supplying the secret.
- **`quality_unknown` is not `quality_passed`.** When no reviewer is available
  the line still publishes (it passed every check the game can make alone) but
  it is recorded as unreviewed. A critic's pass is likewise never described as
  human approval.
- **An `uncertain` verdict publishes rather than rejects.** The critic is the
  same small model and is imperfect by construction; treating its confusion as
  a fault would throw away good lines. Hard failures always reject regardless of
  what the reviewer said, and that precedence is pinned by a test.
- **Only digits are policed for invented numbers.** Written-out small numbers
  are how people actually speak and are not a claim the player can be misled by.
- The contradiction check is deliberately narrow — a claim the speaker made being
  directly negated. Broader disagreement is left to the reviewer, because code
  guessing at meaning produces false rejections, which cost good dialogue.

### Phase A–C integration through real entry points

A helper the game never calls is not a delivered feature. These are the live
wirings, not test-only paths:

| Wiring | State |
|---|---|
| `scripts/domain/QuestCausalContractCompiler.gd` — compiles a contract from the local faction desire, rival relationship and real objective the system already holds | Implemented |
| `PublicBoardOfferBuilder._attach_story_cause_metadata()` now also compiles, validates and attaches a contract — one seam covering **all five** board offer types | Implemented; integration-tested through the real builder |
| `MissionConversationPlan.build_plan()` applies `QuestChoicePolicy` to every offer that carries a contract | Implemented; integration-tested |
| Contract survives `MissionAdapter.build_active_state()` into live mission state and back out of JSON | Implemented; asserted in the board integration test |
| `DialogueFactPacket` / `DialogueQualityGate` into `MissionConversationGeneration.accept_response()` and the worker's attempt accounting | **Not yet wired — next step** |

What the integration test actually found, recorded because these are behaviours
rather than bugs:

- **`RECOVER_COMBAT_DROP` compiles no contract in that seed, and that is right.**
  No local faction in that system wants recovery work, so there is no desire to
  cause it. The offer publishes on its template. Inventing a cause to fill the
  slot is exactly the failure this work exists to prevent.
- **A delivery whose recipient cannot be resolved yet gets no contract**, and
  still publishes as a complete, acceptable job. Withholding it would empty the
  board for no player benefit. The test asserts this fallback explicitly rather
  than assuming it.
- Rejected contracts are reported to `GenerationDiagnostics`
  (`mission_causal_contract` / `contract_rejected`) so a shortage is visible.

One real latent bug was fixed on the way: `GlobalState.get_system_root()`
dereferenced `get_tree()` without a null check, so any caller reaching it
outside a live tree produced a `SCRIPT ERROR` beneath a passing suite.
`get_ui_manager()` immediately below it already guarded correctly; both it and
`get_primary_station()` now match that idiom.

Verification for this slice — 13 suites, run sequentially, each with its own
workspace log file, all `pass=1 fail=0 script_errors=0`:
quest causal contract, quest choice policy, dialogue quality gate, narrative
metadata, public board validation, mission contract, mission state transition,
board delivery recipient, mission conversation plan/compiler/controller/flow,
dialogue bundle validator. The contract, policy and gate suites were
mutation-checked (breaking the implementation makes them fail).

### Phase C wiring — the gate in the real generation path

`MissionConversationGeneration.accept_response()` now runs
`DialogueQualityGate.hard_checks()` over every line a slice produced, after the
existing structural, fixed-cast and causal-visibility validators and never
instead of them. `StoryAgentOfferBuilder` carries the causal contract into the
mission plan so the gate and the choice policy have grounded facts to judge.

Two decisions that shape the runtime cost:

- **The model review is NOT called from `accept_response`.** That function runs
  on the response path the player is waiting behind. Putting a second inference
  call inside it would be model work on an interaction path. Hard checks are
  deterministic and cheap; the constrained review is scheduled against the
  worker's existing budget instead of nesting a retry loop inside a retry loop.
- **No contract means the gate abstains**, recording `quality_pending`. An offer
  from an older save is not newly rejected because a later system has no facts
  to judge its prose against. Asserted by test.

Proven in `tests/story/run_mission_conversation_generation_tests.gd`, driving the
real `accept_response`: a clear opening passes and records `quality_unknown`
(not `passed`); an invented deadline number is rejected with its issue code; a
leaked private motive is rejected; the private motive never appears in the
generation prompt; an uncontracted offer behaves exactly as before. Bypassing
the gate makes four of those assertions fail.

Whole-project compile: **352 scripts, 0 failed, 0 SCRIPT ERRORs.** The parse
harness itself had to be fixed first — loading scripts from `_init` compiles
them before autoloads are registered, which produced a wall of
"Identifier not found: GlobalState" beneath an otherwise clean run. It now
defers a frame, matching the existing suites.

### Not yet done

- **D — rich local causes.** Desires still come from four goal templates and
  two-faction systems still get a forced rivalry. The contract compiler is
  ready to consume richer desires; the generator has not been widened yet.
- **E — playable consequences.** P2 investigation runtime integration and the
  P3 pressure reducer are untouched by this slice.
- **F — campaign direction and endings.** Not started.
- **G — freshness and performance qualification.** `semantic_signature` exists
  and is tested, but no cross-campaign history store, batch runner or
  measurement run exists yet.
- **Real-model evaluation.** No inference was run in this session. The held-out
  corpus, critic false-pass/false-rejection rates, generated-vs-fallback
  exposure, latency percentiles and the 8GB memory figure are all **unmeasured**,
  not merely unreported. The reviewer prompt/parser are implemented and unit
  tested against fixtures only.
- **Human review.** Deferred by Abe. Nothing in this session is described as
  player-approved.

### Phase D — richer local causes and relationships

| Item | State |
|---|---|
| `scripts/persistence/GeneratedFactionDesire.gd` — twelve-dimension desire (goal, observable success condition, need, obstacle, triggering event, holdings, payment source, limit, change condition, private motive, intents, stake), each drawn on its own seed | Implemented; deterministic tests pass |
| Full relationship spectrum — dependency, cooperation, indifference, friction, rivalry — directed and asymmetric, each citing a concrete local fact | Implemented; deterministic tests pass |
| `CampaignGeneratedFactionStore.generate_system_factions()` uses both | Implemented; store suite passes |
| `QuestCausalContractCompiler` consumes obstacle, triggering event, holdings, limit, payment source and private motive from the desire | Implemented |
| Save compatibility | `_normalize_faction()` only fills missing fields, so existing saved rosters load unchanged and simply lack the new ones |
| Real-model measurement | Not applicable (generation is deterministic) |
| Human review | Pending |

**The forced-rivalry rule is gone.** The old generator hard-set standing to -65
between each faction and its neighbour, so every system was a ring of enemies.
Relationships are now weighted so dependency, cooperation and indifference
together outnumber friction and rivalry, and how A sees B is drawn separately
from how B sees A — one side can depend on a party that is indifferent to it.
What is still guaranteed is **one** adversarial pair per system, because a system
with no tension has no story to hang a mission on. That is a different claim from
"everyone has an enemy", and the store's regression test was updated to assert
the new contract rather than the old one.

**Intents now follow the NEED, not the goal.** The old code drew goal, need and
mission intents from four parallel arrays at one shared index, so a system had
four possible stories. What the player is asked to do now follows from the thing
that is actually missing.

#### A bug the variety test caught that review would not have

The first version of the per-dimension draw used `String.hash()`. Godot's string
hash is **linear**, so two seeds of the same length differing only in a short
suffix (`"…|goal"` versus `"…|need"`) keep a *constant* difference modulo the
option count. The result: `need` perfectly predicted `goal` across all 60 sampled
seeds — the exact locked-template failure the class was written to remove, just
hidden one layer down, and invisible to inspection because the code looked
correct. Every draw now uses a sha256 digest. This is the argument for measuring
variety with a test that counts distinct outcomes rather than asserting that a
generator "looks random".

Measured across 40 seeds / 80 generated factions: at least 60 distinct
goal/need/obstacle situations, at least 4 distinct intent sets, and all three
non-hostile relationship kinds present with hostile relations under 60% of the
total. These are thresholds set below the observed values so the suite fails on
a regression rather than on luck. **This is variety measurement, not a
uniqueness guarantee**, and it says nothing about whether the prose reads well.

### Phase E, first slice — justifying the specific item, not the category

`QuestCausalContractCompiler` now writes `fact.action_helps` from the objective's
**actual** item, quantity, target, origin and destination, rather than from its
verb. This was the plan's named gap: "attaching a cause based mainly on mission
verb is not enough to justify each specific item, target and destination."

It returns empty when the objective lacks the detail to make a real claim. A
sentence that would fit any cargo is worse than no fact at all, because the fact
packet presents whatever it carries to the model as grounding.

#### Four bugs found by printing the real compiled facts and reading them

None was visible in the code; all four would have been spoken to the player.
They were found by dumping every fact from the real board builder across two
seeds — not by any test that existed at the time.

1. **A raw faction hash reached player-visible text.** `target_faction` holds a
   generated key (`gen_3753748b9ca0_f1`), and the existing display helper would
   have title-cased it into "3753748b9ca0 F1". Now resolved through the real
   faction identity table, and if it cannot be resolved the sentence omits the
   name entirely rather than printing a prettified hash.
2. **A faction was named as the thing obstructing itself** — "What X is running
   in that lane is what stands between X and …" — because the recovery target
   picker can land on the requester. Guarded in the compiler, so it holds
   whatever the caller picks.
3. **Two mangled sentences.** The stake read "X is trying to nobody local will
   take the run at the price it can pay", from gluing an obstacle to a change
   condition and wrapping it in a goal phrase. The limit began lowercase in the
   middle of its own sentence.
4. **A false causal claim.** The ore job asserted "45 m3 of ore is what X needs
   to cover survey data from a drift it cannot reach." Ore does not produce
   survey data. It now says the ore is being sold to *pay for* the need, and two
   `INTENTS_BY_NEED` entries that mapped a need to a verb which cannot serve it
   were corrected at the source.

`tests/domain/run_causal_fact_text_tests.gd` pins all four by shape rather than
by wording — no raw identifiers in any public fact, no faction named twice in
its own obstruction, every fact sentence capitalised and terminated, and ore
never claiming to satisfy an immaterial need. Mutation-checked: reverting the
guards produces 26 failures.

**The lesson worth keeping: read the generated content, not just the tests.**
Every one of these passed structural validation, and the quality gate's hard
checks would have passed them too, because they are all *grounded* — they are
faithful renderings of facts the contract genuinely holds. They are simply
badly written or untrue, and only reading them shows that.

### Verification for this session

27 suites run **sequentially**, each with a unique workspace-local `--log-file`:
all `pass fail=0 script_errors=0`. Whole project: **355 scripts, 0 failed, 0
SCRIPT ERRORs**. Mutation-checked suites: quest causal contract, quest choice
policy, dialogue quality gate, the gate's wiring into `accept_response`, and
causal fact text.

Not verified, and not claimed: any real-model inference, any latency or memory
figure, and any human judgement of whether the dialogue sounds like a person.

### Codex follow-up — 2026-09-12

The subsequent critic correction removes legacy unbound approval, adds strict
review coverage and qualification guards, and preserves unknown quality metadata.
Seven relevant regression suites pass; whole-project compilation covers 357
scripts with zero failures. Real local-model measurements now exist, but they
fail qualification: semantic review remains diagnostic. This supersedes any
earlier implication that a passing structural suite establishes critic accuracy.

See [correction and measured limits](critic_fix_2026_09_12.md) and the
[next implementation handoff](claude_handoff_after_critic_fix.md). Writer packet
integration, lifecycle enforcement, real choice consumers and later campaign
phases remain unfinished; follow that handoff rather than marking the plan done.

---

## Implementation status — 2026-09-12 (Claude), after Codex's critic correction

### C integration: writer and validator now share one packet (P1 from the review)

| Item | State |
|---|---|
| `DialogueFactPacket.prompt_block()` has a **production writer caller**: `MissionConversationGeneration.prompt_for_job()` renders one block per output field | Implemented; tested |
| Question-aware fact selection — facts that bear on the actual question rank first, so the answering fact is not truncated away by the cap | Implemented; tested (mutation-checked) |
| `DialogueFactPacket.fingerprint()` recorded at dispatch, re-derived and verified at response | Implemented; tested |
| Packets are PURE and deterministic (`slice_packets(context, slice)`), so writer and validator derive them independently rather than passing a mutable dictionary | Implemented; tested |
| Fixed-cast soul projection, stale-response guards and retry budgets | Unchanged |
| Real-model measurement of writer output | **Not yet run** |

Design notes:

- The packet is derived, never handed over. Both paths call the same pure
  function on the same immutable context; a divergence shows up as a fingerprint
  mismatch rather than as silently different facts. A mismatch returns
  `stale_fact_packet` and does **not** spend a rewrite attempt, because the
  writer was grounded in something that is no longer true — a rewrite cannot fix
  that.
- The fingerprint deliberately covers facts, question, preceding line and
  required facts, but **not** `recent_phrases` or `attitude`. Those are writing
  nudges that do not change what is true; letting them move the fingerprint
  would strand in-flight slices for no reason. Pinned by a test.
- Question ranking **only reorders**; it never removes a fact. A missed keyword
  costs position, not grounding.
- A private fact stays out even when the question asks about it directly. Pinned
  by a test that asks about the secret by name.
- No contract now reports `quality_pending` with an explicit
  `reason: no_causal_grounding`, rather than implying a review was scheduled.

### Correction to an earlier claim in this document

An earlier entry stated the deterministic hard checks already caught the
"eleven hours" invented deadline from `problem_critic_always_passes.md`. **That
was wrong.** `_check_numbers()` inspected digits only, so a spelled-out number
passed. Codex verified this against the live code and has since added
written-number and duration-role checks. The claim is withdrawn.

### Causal publication states and lifecycle validation (P1 from the review)

| Item | State |
|---|---|
| `QuestPlausibilityValidator` distinguishes a MISSING resident roster (unknown) from an explicitly EMPTY one (nobody there → delivery fails) | Fixed; tested |
| Explicit publication states on every built offer: `validated`, `uncaused_legacy_compatible`, `withheld_invalid_contract` | Implemented; tested |
| Offers whose contract FAILS validation are withheld from the board rather than published contractless | Implemented; tested |
| `scripts/domain/QuestWorldSnapshot.gd` — one authoritative world snapshot shared by every stage | Implemented; tested |
| Revalidation wired into acceptance (`QuestManager.accept_quest`) and turn-in (`UIManager._try_local_board_delivery`) | Implemented; lifecycle regressions pass |

Decisions:

- **"No local cause" and "contract failed validation" are different states.** The
  board has always posted work nobody in particular wants done; that publishes as
  `uncaused_legacy_compatible`. A contract that fails its checks has broken
  mechanics or an unbound cause, and publishing it anyway is how an impossible
  job reaches the player — so it is withheld.
- **Withholding is a publication decision, never data corruption.** An already
  accepted mission keeps its saved objective, recipient and terms and stays
  completable even if today's rules would no longer generate it. Pinned by a test
  that adapts a withheld-shaped job into active state and asserts it validates.
- **The snapshot reports only what it can resolve.** `capabilities` and
  `requester_funds` are deliberately NOT populated, because nothing in the live
  game currently owns either as authoritative data. Faking them would turn "we do
  not know" into "we checked", manufacturing both false passes and false
  rejections. A test asserts they stay absent.
- **A failed turn-in check leaves cargo and contract untouched.** A recipient who
  is not there is a recoverable mission state, not a failed delivery.
- `check_mission()` returns `checked:false` for contractless missions, so a caller
  cannot mistake "we did not look" for "we approved".

### Branch policy now has a gameplay consumer (P2 from the review)

| Item | State |
|---|---|
| Surviving branch contracts become selectable terminal intents the controller renders | Implemented; tested (mutation-checked) |
| A branch terminal carries `action_id`, `effect_ids` and `outcome_id` forward, so choosing it commits something | Implemented; tested |
| Click-time eligibility recheck; an unavailable option is EXPLAINED and names what is missing | Implemented; tested |
| Capability validation asks `MissionCapabilityRegistry`, not a parallel allowlist | Implemented; verified against the live registry |
| Fixtures' invented `INVESTIGATE_SITE` corrected to the real `INVESTIGATE_SIGNAL` | Fixed |

Decisions:

- **A single surviving branch renders NO menu.** Fewer than two branches folds
  into the ordinary accept path. One completion path must not *look* like a
  decision, so Abe's rule is enforced at render time and not only at policy time.
  Pinned by a test; weakening the guard to `< 1` fails it.
- **Unknown eligibility never revokes a promised option.** An empty
  `satisfied_predicates` snapshot means the caller did not say what is true —
  which is not the same as a predicate being false. A promised resolution must
  not vanish because the caller failed to supply data.
- **An ineligible option does not dead-end the conversation.** It reports
  `mode: unavailable` with the missing predicate named, and the conversation
  stays open so the player can choose something else.
- `selected_branch_id`, `selected_action_id`, `unavailable_reason` and
  `unavailable_predicate` are surfaced on the returned SCREEN, not only on
  internal state, so a UI consumer does not have to reach into state.

Verification for this slice: **31 suites** run sequentially with unique workspace
log files, all pass / fail=0 / script_errors=0. Whole project: **361 scripts,
0 failed.** `git diff --check` clean. Mutation-checked this session: writer packet
guidance, question ranking, empty-roster distinction, branch intent rendering,
single-path guard.

### D coherence: the compiler stops asserting what it cannot prove (P1/P2)

| Item | State |
|---|---|
| `ITEMS_BY_NEED` — cargo that genuinely satisfies each recorded need | Implemented |
| Board courier offers prefer need-bound cargo, so the strong claim is true by construction | Implemented |
| Compiler makes the strong "this is what they are short of" claim ONLY for bound cargo; unbound cargo gets a weaker claim that is still true | Implemented; tested (mutation-checked) |
| Delegation cites the faction's own recorded obstacle instead of inventing "no free hull" from the objective type | Implemented; tested |
| Unchecked superlatives removed ("the only way", "the only record") | Implemented; tested |
| Universal adversarial-pair requirement removed; its regression test replaced | Implemented; tested |

Why this matters more than it looks: **a critic cannot catch an invented reason
that the compiler supplied as truth.** Once "this crate is the thing they lack"
enters the contract, it *is* the record — every downstream check, including the
model reviewer, treats it as ground truth and validates dialogue against it. So
the fix has to be at the point of manufacture, not in review.

- Cargo that actually satisfies the need earns *"X is what they are short of"*.
- Arbitrary cargo gets *"they are paying to get X to Y while their own hulls are
  tied up"* — supported by the objective and the obstacle, and claiming nothing
  about what the crate contains.
- Bypassing the binding check makes the test fail with the exact bad sentence,
  so the distinction is pinned rather than assumed.

**The forced adversarial pair is gone.** The old rule guaranteed one rivalry per
system on the theory that a system without enemies has no story to hang a mission
on. That theory was wrong: a faction's obstacle, triggering event and unmet need
generate work whether or not anyone is hostile, and forcing hostility made every
system read the same way. The replacement test asserts that peaceful systems
actually occur across 60 seeds, and that every faction still has an obstacle, a
triggering event and a need — the real engine of work.

### Still not done

- **E (playable consequences):** P2 investigation runtime integration and the P3
  pressure reducer are untouched. This is the largest remaining gap.
- **F, G:** not started.
- **Writer measurement against the real model:** still not run. The packet now
  reaches the writer, which is exactly what makes that measurement worth doing —
  but it has not been done, and nothing here claims prose quality.
- **Semantic judging stays diagnostic.** No critic is qualified; nothing was
  relabelled or threshold-weakened to change that.

---

## First real WRITER measurement — 2026-09-12

`tools/quality_eval/run_writer_eval.gd`. Drives the **real** dispatch path: real
contracts (2 fixtures + 6 compiled from generated desires), real packets via
`slice_packets()`, the real prompt, and the real `accept_response()` acceptance
chain. Model `qwen3:4b`, the game's own writer settings (temperature 0.95,
`num_predict` 520, `num_ctx` 8192, `think:false`), seed 12345.

**Measured, not claimed:**

| Metric | Value |
|---|---|
| Slices attempted | 24 |
| Accepted through the full real path | 12 (50%) |
| Rejected by the **existing** validators | 7 |
| Rejected by the **new** quality gate | 2 |
| Parse failures | 1 |
| Latency | p50 633 ms, p95 962 ms, max 1050 ms |
| Recorded provenance | `quality_unknown` × 12 (correct — no critic is qualified) |

Rejection reasons, by layer: `missing_answer_anchor:ask_why` ×3,
`too_long:decline_response` ×3, `too_long:ask_why_response` ×2,
`unsupported_urgency` ×2, `parse_failed` ×1.

**Latency is not the problem.** At p95 under a second on a prefetch path with a
25-second budget, generation cost is comfortable. The constraint is acceptance
rate and prose quality, not speed.

**The new gate is not the bottleneck — the existing validators are.** Only 2 of
10 rejections came from the quality gate. The largest single cause is
`missing_answer_anchor`, which is the exact-anchor requirement this plan already
flagged as a known hazard ("can make natural paraphrases fail"). It is recorded
here as measured evidence, **not** worked around: weakening it to raise a score
is exactly what section 11 forbids.

### Three defects this run found that no test would have

1. **A bug I introduced.** Branch intents were being given generated reply lines,
   which came back identical to the accept reply — the difference between
   branches is mechanical, not conversational, so the model had nothing different
   to say. Branch options are now code-labelled actions and no reply is requested
   for them. Fixed; `duplicate_line` went to zero.
2. **Invented urgency.** The model appended "before it's too late" to jobs with
   no deadline and no urgency fact, in several independent generations. That is
   an invented stake and the player acts on it. New `unsupported_urgency` hard
   check, deliberately narrow — impatience is characterisation, "before the
   window shuts" is a claim about the world. Both cases pinned by tests.
3. **An encoding artifact reached an ACCEPTED line** — a U+FFFD replacement
   character mid-sentence. TTS reads that aloud as a glitch. Same class as the
   curly-apostrophe defect found during the taunt work. New
   `encoding_artifact` hard check; legitimate em dashes and apostrophes pass.

### What the accepted prose actually looks like

Recorded honestly, because "12 of 24 accepted" would otherwise read as a
quality result. It is not one. Reading the accepted lines shows:

- Role confusion — an accept-path line opening *"We don't need your help right
  now."*
- Direction confusion — *"deliver … to Blacklist Yard"* rendered as *"pick up
  the cargo from Blacklist Yard"*, and *"will reach Blacklist Yard before we
  need it"*.
- **Goal/need incoherence, empirically confirmed.** One contract paired the need
  *"fuel it can afford"* with the goal *"prove a rival's manifest is fiction"*,
  and the model dutifully wrote *"We need this fuel to prove the rival's manifest
  is fake."* The dimensions are drawn independently and can contradict each
  other — exactly the Phase D joint-generation gap the integration review named.
  This is now measured rather than predicted, and it is the strongest argument
  for constraining the draws before widening anything else.

**No prose quality claim is made.** Passing the hard checks means a line is
grounded and well-formed. It does not mean it is good, and several accepted lines
above are plainly not. Human review remains pending.

### Codex continuation: compatible joint draws — 2026-09-12

The recorded fuel/manifest source-fact defect is now addressed for new generation.
Goal/need edges include explicit explanations; obstacles/events/remedies and
holdings/payment sources are paired. Versioned bindings are checked before new
board publication. Existing saved desires are not rerolled. See
[implementation and evidence](desire_coherence_2026_09_12.md).

16 regression suites pass; 362 scripts compile. A fresh writer measurement at
seed 67890 accepts 11/24 slices, all quality_unknown; accepted prose still makes
unsupported claims. No prose-quality, critic qualification or 8GB claim follows.
Phase D's complete action/world coherence and E/F/G remain unfinished. Next work
must bind actual executable actions/effects and investigation gameplay, rather
than treating a controller's stored branch selection as a committed world effect.

### Codex continuation: investigation runtime — 2026-09-13

The first two recipes now have an actual QuestManager command path, live scan
holds, inventory/revision checks, idempotent resolution, assigned-station turn-in
and branch-based payouts. Mission acceptance and save validation support their
objective type; nested site system IDs survive canonical/runtime save conversion.
13 suites pass; 365 scripts compile. See
[implementation scope and remaining integration](investigation_runtime_2026_09_13.md).

E/P2 remains incomplete: connect automatic offer ownership and real navigation
placement, mission-owned world sites/discovery, and the evidence/choice UI next.
The command tests do not constitute a playable investigation loop, player review,
pressure reduction or completed campaign consequences.

### Codex continuation: live placement acceptance — 2026-09-13

Investigation acceptance now checks published sites against PlayerShip's actual
navigation obstacle snapshot and live station/gate positions. It rejects missing
navigation, missing turn-in station and blocked sites without rerolling evidence
or applying mission effects. Five relevant suites pass; 366 scripts compile.
This closes the acceptance safety part of P2 placement. Optional cause-backed
offer publication/selector persistence, world-site discovery and evidence UI
remain unfinished, followed by P3 pressure and campaign consequences.

### Codex continuation: persistent investigation postings — 2026-09-13

Preparation/publication now has a persisted ownership lifecycle and StoryManager
entry points deriving local campaign/world inputs. Publication is committed to
StoryStateStore before success and survives checkpoints. Eligibility binds a
supported subset of coherent needs to the first two recipes. Fixed the selector's
unseeded first draw. Six suites pass; 368 scripts compile. See
[scope and integration requirements](investigation_board_lifecycle_2026_09_13.md).

The visible board is not wired yet. Its presenter, world-site discovery, evidence
controls, terminal ownership handling and canonical system mapping still need
integration before new investigations can be offered to players. P2 and the full
campaign plan remain incomplete; no player test is required for this slice.

### Codex continuation: connected investigation loop — 2026-09-13

The preceding integration tasks are now implemented for the first two recipes:
visible board publication, checkpointed acceptance/retirement, mission-owned site
discovery, evidence/scan controls and assigned-station settlement. Canonical
ownership mapping and actual checkpoint preservation of site coordinates are
covered. Failed acceptance checkpoints do not consume the offer; repeated turn-in
does not pay twice. Five final affected regression suites pass; all 370 scripts
compile. See [scope and evidence](investigation_playable_loop_2026_09_13.md).

Next: P3 activity-based faction pressure and durable job consequences, then
campaign resolutions and novelty history. The other two investigation recipes,
broader cause coverage and human evaluation remain unfinished. Player testing
stays deferred; automated checks do not qualify the critic or generated prose.
Kaelen and N.O.V.A.'s protected characterization remains unchanged.

# 0. Implementation progress

_Maintained by the implementing agent. Update as each slice lands so work can
resume exactly here after a session limit. Newest entries at the bottom._

**Decisions taken (Abe, 2026-09-06):**
- Start order: **the plan's own order — P2 investigation prototype first.**
  Not infrastructure-first. The riskiest question is whether the verbs are
  interesting, and it should be answered before funding the rest.
- Hardware gates: **build it, measure later.** I implement and ship a
  measurement harness with instructions; Abe runs it on the real GPU and reports
  numbers. No invented performance figures.
- Section 5 recommendations are taken as executable defaults, per the plan's own
  instruction, except the two flagged as real sign-off gates (hardware
  qualification, voice preset audition).

**Awaiting a human — do not block on these, collect them here:**
| # | Needs | Blocks |
|---|---|---|
| H1 | Play the two-shape prototype and decide whether the verbs merit expansion | Phase 5 (more shapes, P3 pressure tracks) |
| H2 | Verify the game stays inside the 8GB VRAM budget (see note below) | P1 shipping gate, final release sign-off |
| H3 | Confirm the qualification test hardware (CPU/RAM/GPU) | Phase 0 acceptance targets |
| H4 | Audition and approve any new voice delivery presets | P5 preset work only; caching/timing unaffected |
| H5 | Freshness playtest sessions (three two-hour) | Release sign-off |

**Why 8GB (Abe, 2026-09-10):** the budget is a TARGET SPEC, not a description of
the dev machine. 8GB is the most common configuration in the Steam hardware
survey, and the goal is that the game runs on most gaming PCs. This matters for
how H2 gets done: it does NOT require owning an 8GB card. The dev box is a 16GB
RTX 5060 Ti, and the budget can be verified there by capping or instrumenting
allocation rather than waiting on hardware. Treating H2 as hardware-blocked was
my misreading and cost the gate nothing but delay.

**Slice log:**

| Slice | State | Notes |
|---|---|---|
| P4-3 conversation slicing | **DONE** | `MissionConversationCompiler` gains `plan_slices`, `required_output_keys_for_slice`, `build_slice_prompt`, `merge_slice`, `missing_keys` + `tests/story/run_conversation_slicing_tests.gd`. The bundle was ONE request (opening + a label and a response per intent), so one malformed field discarded all of it including the good parts, and the retry paid for that work again. Now: opening first (if only one slice lands, it should be the one the player sees), then intents batched 2 at a time. `merge_slice` NEVER overwrites an accepted key -- that is what makes partial failure cheap. `missing_keys` asks only for what is genuinely absent, so a repair costs the field not the conversation. Slice keys DROP `*_player`: button labels are machine-owned and already in the approved intent list, so asking a model to restate one spends inference to introduce a chance of getting it wrong; legacy bundles keep `*_player` and stay readable. The slice prompt REPLACES the OUTPUT section rather than appending, since two sets of instructions is how a model answers the wrong question. **Mutation testing caught a tautology in my own test** -- the cap was asserted against the constant that produced it, so raising it to 99 passed; now pinned to a literal and a slice count. |
| P4-2 outcome reaction projector | **DONE** | `scripts/story/OutcomeReactionProjector.gd` + `tests/story/run_outcome_reaction_projector_tests.gd`. Projects a TYPED outcome into the few facts dialogue may use, replacing keyword-inferred world effects: the outcome tag is the truth and text is derived from it, never the reverse. Classifies each of `InvestigateSignalCapability`'s terminal tags as public or private. **`mistaken` is PRIVATE** and carries no summary text at all -- a mistaken certification is one the player was PAID for and never corrected on, so they may not know they were wrong; an NPC referencing it would tell them by accident, in a bark, instead of through the beat that should. An unrecognised tag is REFUSED rather than guessed, because a new outcome must be classified by a person. Payout is projected as a BAND, never a figure: an NPC quoting exact credits reads as omniscient, and invites arithmetic a model cannot check. A refusal returns the full shape so callers need no special case. Mutation-checked (letting private outcomes through: 5 fails; unknown tags defaulting to public: 2). |
| P4-1 dialogue field contract | **DONE** | `scripts/story/DialogueFieldContract.gd` + `tests/story/run_dialogue_field_contract_tests.gd`. The two shapes from the plan (`DialogueFieldRequest v1`, `PreparedDialogueField v1`) as a PURE module: build, validate, and check applicability. Budgets come from the PURPOSE, not the caller, so no two callers can disagree -- roomy for opening/answer, tight for the rest, capped on words AND characters (a model can satisfy a word count with very long words and still overflow the panel). A prepared field is validated AGAINST its request, because a line can be well formed and still answer a question nobody asked. Three refusals matter most: a fact referenced but not supplied (the model would invent one, confidently), a stale `context_fingerprint` (a line spoken with full confidence after the world moved on), and `attempt_count` beyond 2 (an unbounded repair loop is how a local model turns one bad line into a hang -- a failure mode this codebase has already seen). `line_id` hashes owner+field+fingerprint+text, so the same words prepared for a different situation are a different line and consumption records stay trustworthy. Mutation-checked (accepting stale context: 1 fail; removing the attempt cap: 2). |
| P2-9 gate discovery + dev-panel dials | **DONE** | Gate visibility follows DISCOVERY (Abe's call): `known`/`blocked`/`damaged` gates are LARGE landmarks that never drop off; `unknown`/`rumored`/`hidden` gates are a new **SIZE_TINY** class detected at 0.25x normal range, so a new route is found rather than handed over on arrival. `UIManager._gate_knowledge_state` reads the real state via `GameRoot.get_gate_knowledge_state`, defaulting to "known" for non-gates so nothing else is accidentally hidden. Feel values moved from consts to **static vars** with `get_tuning`/`set_tuning`/`reset_tuning` accessors -- Godot cannot reach a static var through `get()`/`set()` on a script class. New **dev panel > Sensors** tab: enable toggle (`GlobalState.sensor_reveal_enabled`), live nudges for range scale / drop / mission bonus / unfound-gate multiplier, a metre readout of what the dials currently mean, and reset. Dials floor at 0.05x so a zero scale cannot blind sensors and read as a broken game. Mutation-checked (all-gates-visible: 3 fails; dead range dial: 2). **Still default OFF pending playtest** -- H1 now has dials to fly with. |
| P2-8 overview wiring (reveal) | **DONE, DEFAULT OFF** | `SiteRevealModel.size_class_for_groups` classifies from entity groups (station/celestial/**jumpgate** = large; ship/wreckage/asteroid/anomaly/salvager = small; ungrouped defaults to SMALL so nothing becomes an always-visible landmark by accident). Wired into `UIManager._should_show_overview_entity` via `_passes_sensor_reveal`, with a per-entity `overview_seen` meta giving the hysteresis its state. **Gated behind `_overview_sensor_reveal`, default false.** Reason: the plan's 600/900/1200 were written without this game's scale, and placements here sit within a few hundred units with `nova_warn_distance` at 600 -- so those ranges would reveal nearly everything and the feature would look broken-or-pointless rather than tuned. Needs the dev-panel dials (P2-9) and a playtest before it can default on. Note: `class_name` globals are NOT registered in headless runs, so this had to preload the model rather than reference `SiteRevealModel` bare -- worth remembering for any future domain module used from a scene script. |
| P2-7 sensor-range site reveal | **DONE** | `scripts/domain/SiteRevealModel.gd` + `tests/domain/run_site_reveal_tests.gd`. Visibility is driven by OBJECT SIZE, not just scan state (Abe's call). LARGE objects (planets, stations) are never hidden and never fade -- they are landmarks, and needing sensors to notice a planet would be absurd. SMALL objects (ships, wrecks) are hidden beyond sensor range, leak no label while hidden, appear as an anonymous "Signal contact" fading in over the final 50 units, and earn their real name only once scanned; once known they persist out to a DROP range of 2x detection before falling off. That gap is hysteresis -- without it an object parked at exactly sensor range flickers as the ship drifts. MISSION ships get 1.5x detection and drop range (Abe's call): hunting one hull among identical contacts is tedium, not difficulty. Unknown sensor tier falls back to basic rather than zero. Effective basic-tier ranges: ordinary 600/1200, mission 900/1800, large always visible. Mutation-checked three ways (no hysteresis: 3 fails; large treated as small: 9; mission bonus removed: 3). The 1.5x is a FEEL VALUE for playtest tuning. |
| P2-6 scan hold gate | **DONE** | `scripts/domain/ScanHoldController.gd` + `tests/domain/run_scan_hold_tests.gd`. Pure state machine (distance/speed/combat in, UI state out) so the rules gating evidence are testable without flying a ship. Cancelling costs only progress and never locks out a retry. Progress cannot be banked across sites or across a save. Completion issues a ONE-SHOT token, and each blocking condition is asserted separately so a change to one rule cannot hide behind another. Mutation-checked (HOLD_SECONDS 3.0 -> 0.5) to confirm the suite actually fails when the gate is weakened. |
| P2-5 shape selection + persistence | **DONE** | `scripts/domain/InvestigationSelector.gd` + `tests/domain/run_investigation_selector_tests.gd`; `TauntBag` gained an optional injected RNG (taunts unchanged, still global randi). Retires a shape when SHOWN, not accepted -- a declined offer already read is not new content. Reservations carry their seed AND the resulting bag, committed only on publication, so prefetch cannot burn unseen shapes. Campaign-wide `last_shape_id` stops a pool change replaying the shape just offered. Cycle survives a JSON round trip. Two of my own bugs found here: peek-then-re-derive desynced and offered a shape twice (now one derivation), and the suite printed PASS over a "function not found" error until a real call was added as a guard. |
| P2-4 offer builder (mission truth) | **DONE** | `scripts/domain/InvestigationOfferBuilder.gd` + `tests/domain/run_investigation_offer_tests.gd`. Truth is generated in CODE from the seed and never rerolled: primary always reports A, verification is a seeded coin flip, and what equality MEANS is per-recipe (survey = codes match, lure = beacon genuine). Claims name an owner only on the verification site so it must be travelled to; the archive uses neither codes nor owners. Reward mirrors the approved budget rather than inventing one. A failed placement yields NO offer, carrying `no_safe_sites` to the caller. Mutation-checked: removing the coin flip fails two assertions. |
| P2-3 site placement | **DONE** | `scripts/domain/InvestigationSitePlanner.gd` + `tests/domain/run_investigation_site_planner_tests.gd`. Pure and seeded, so a re-place at acceptance reproduces its own layout instead of rerolling. Hazards arrive in TangentNavigator's own `{center, radius, physical}` shape and the radius is READ, never recomputed -- a second formula is how a site ends up inside a body the autopilot refuses to cross. Reports `no_safe_sites` rather than shrinking margins (the plan's flagged assumption); falls through to the next station when the first is unusable. |
| P2-2 InvestigateSignalCapability | **DONE** | `scripts/domain/capabilities/InvestigateSignalCapability.gd` + `tests/domain/run_investigate_signal_tests.gd`, registered in `MissionCapabilityRegistry`. PURE -- no scene access -- so branch rules, payouts and consumable spend are testable headless. Invariants pinned by test: completion is never inferred from "both scanned" (mutation-checked); verification site locked until the primary scan; prerequisites revalidated at execution not button-enable; commands idempotent by id so a replay never double-spends; stale revisions refused; extraction commits (spawning a forged beacon's hostile) but only completes on reaching the cache, with no retreat to a safer branch afterwards. |
| P2-1 shape catalog + registry | **DONE** | `data/content/mission_shapes.json` (4 shapes), `scripts/domain/MissionShapeDefinition.gd`, `scripts/domain/MissionShapeRegistry.gd`, `tests/domain/run_mission_shape_registry_tests.gd`. Catalog is rejected WHOLESALE on any bad shape; `report` branch is mandatory so a missing consumable cannot strand a contract; eligibility filters before pool formation. Note: `class_name` type annotations do not resolve in `--script` mode, so the registry uses preloaded consts and `Variant` returns. |

# 1. Executive summary

Fund five bounded changes: enforce exclusive model residency; add investigation contracts with genuinely different decisions; make their outcomes alter subsequent local opportunities; compile smaller, state-specific dialogue packets; and turn generated speech into persistent, correctly timed assets.

The gameplay investment is **four investigation shapes and three local pressure tracks**, not a general procedural mission language. Players will locate signals, compare evidence, decide whether to approach a suspected trap, and sacrifice recoverable value to preserve information. Those decisions change what work becomes available next. Existing kill, ore, courier and pickup contracts remain familiar anchors. N.O.V.A. and Kaelen remain exactly themselves, with more concrete consequences to notice and remember. Their identities, voices, protected mysteries and existing relationship machinery are not generation variables.

The inference investment makes the existing stack behave like a shipping subsystem. One owner admits every Ollama request; gameplay has only qwen3:4b resident, Kokoro runs on CPU, and qwen3:8b gets exclusive preparation gates. Dialogue preparation extends the existing compilers, scheduler, knowledge projections and retirement ledgers. Persistent speech caching removes repeated synthesis across launches; playback IDs make portraits, captions and completion signals refer to the actual utterance.

**Budget:** 288–400 engineering hours, including focused tests and integration; 16–24 hours of author/playtest review; add 25% engineering contingency for a funding envelope of **376–524 hours**, roughly 10–13 full-time person-weeks. No new end-user runtime is proposed. Bundle the existing Ollama and Python/Kokoro stack with its offline assets. Allow 512 MiB for generated audio cache, plus separately measured authored audio and model installation size.

The smallest visible slice is a 16–24-hour, two-contract investigation prototype inside proposal P2. Play it before funding the other two shapes or the pressure director. **The biggest risk is that investigation becomes another approach-and-click routine.** If players do not make materially different decisions in the prototype, stop expanding its content. Faster inference cannot rescue uninteresting actions.

If funding halves, retain P1, P2's first two shapes, P4's investigation packets, and P5's cache identity/persistence/playback IDs. Cut P3, the other two shapes, broad authored-pool migration and new delivery presets. Do not cut residency enforcement, save correctness, voice ownership or failure reporting.

# 2. Diagnosis

## Evidence and limits

This plan was grounded in `PROJECT_MAP.md`, all of `docs/todo.md` and `docs/bugs.md`, the recent session catch-up, and the source files named below. The checkout contains unrelated uncommitted changes; this deliverable neither incorporates nor modifies them. Paths below are repository-relative unless prefixed `user://`. **NEW** means a proposed file or symbol, not an existing one. No runtime benchmarks or game playtests were performed for this document; performance figures below are acceptance targets, not measured claims.

| Finding in actual source | Implication |
|---|---|
| `MissionCapabilityRegistry._ensure_defaults()` registers seven types, including `DELIVERY_COURIER`, `PURCHASE_DELIVERY` and `RECOVER_COMBAT_DROP`. `StoryAgentOfferBuilder.TEMPLATE_ONLY_OBJECTIVES` includes all seven. | The four-type premise understates the available nouns and variants. Nevertheless, courier/purchase add acquisition logistics, and recovery currently rolls a drop after eligible kills. They do not supply a sustained new decision loop. |
| `PublicBoardOfferBuilder.build_offers()` builds the same broad list each time. `StoryAgentOfferBuilder.build_offer()` realizes approved objective types from story candidates. | More generated premises alone will keep producing familiar activity sequences. Variation must enter the executable offer and objective state. |
| `SpaceAnomaly._physics_process()` activates at 50 units; `_execute_action()` runs rewards, damage and hostile spawns. `AnomalyRegistry.generate_for_system()` places 0–2 objects and supports a forced anomaly. | The project already has exploration objects and persistence. The missing step is player-directed investigation and resolution, not another random reward table. Do not use the unimplemented `grant_temp_buff` action. |
| `StoryManager.record_mission_outcome_consequence()` records visible prose, facts and revisions. | Consequence narration exists. The proposed director must change executable opportunities, rather than add another consequence paragraph. This is not a claim that no other existing action changes the world. |
| `LocalModelGateway.generation_body()` pins contexts to 8192/16384 and uses large `keep_alive: 0`. `LLMInterface` has numerous direct `HTTPRequest.request()` sites; the handoff batch even builds its own body. | Unloading after a request does not prove the small model was evicted before it. Scheduler concurrency one covers scheduler jobs, not every caller. Large job sequences also repeatedly unload/reload. |
| `select_installed_model()` can ultimately select an arbitrary installed model. Small readiness source retries failed probes despite an older comment saying it releases the gate. | Shipping must pin model identity and explicit state transitions. Do not turn stale comments into bug claims, or “fix” the already-present probe retry by allowing unverified gameplay. |
| `MissionConversationCompiler` already generates flat bundles. `ContextBlockBuilder` has capability entry points, but these share a broad public projection. | Reuse the compiler and safety boundary; narrow each request's facts, fields and invalidation dependencies. A second dialogue planner would waste money. |
| `KokoroSpeechProvider.resolve_delivery()` currently exposes voice and speed. `TTSInterface._delivery_cache_key()` includes speed/pause but not style. `baked_stream_for()` looks up only voice/text. | Some delivery controls are lost or can alias the wrong audio. Persistent caching requires a single resolved render identity, not simply saving the present dictionary. |
| `SpeechService` has an ambient queue, `ambient_line_started(text)` and global `playback_finished()`. The server constructs the complete WAV before replying. | “Started” can still mean a request was dispatched, rather than audio began. Identity and actual playback timing matter before introducing more speech concurrency. |

The second objective should not mean “ask the local models to generate more.” The successful authored taunt pool demonstrates the opposite for short, exposed barks. Keep it. Spend inference on state-dependent reactions, dialogue and existing story preparation where generation earns its cost. Conversely, baking every line cannot remove Kokoro from a game with novel spoken dialogue.

## Tracker reconciliation

| Existing tracker work | Treatment here |
|---|---|
| Investigate contracts; rumor-instanced anomalies/derelicts; sensor/visual reveal; search zones; discovery outcomes | P2 absorbs the anomaly/search/investigate subset. Separate derelict models, rare salvage, illegal goods and broad discovery catalogs remain deferred. Supersedes the suggested canned reveal fallback. |
| Station-aware precaching; Kaelen return/no-work/completion/abandon lines and availability ping | P4 extends existing preparation for these exact interactions. Do not reintroduce generation on click. Preserve existing implementations where already wired; acceptance is measured at consumers. |
| Quiet-moment recency “save integration pending” | Source already has `QuietMomentDirector.to_save_dict()/load_from_dict()` and `GameRoot._capture_prepared_runtime_state()` includes `quiet_moments`. Regression-test restoration; do not fund a duplicate persistence system. |
| Quiet-moment word-boundary validation, packet-derived anchors, budget floor, arbitration and voice audition | P4 absorbs applicable validation/budget work; P5 supplies playback arbitration. Kaelen steering remains a human decision; this plan does not change her soul rules. |
| Extend prebaked audio beyond taunts; subtitle layer | P5 absorbs render identity, export validation and a thin timed caption route. Bake approved authored content only; procedural greetings becoming generated under P4 are not newly promoted to authored defaults. |
| Shipping model choice, model pulls, static offline mode, optional cloud provider, larger quiet-moment models | P1 supersedes incompatible portions: qwen3:4b/8b only, bundled offline assets, no runtime pull/cloud/static replacement. The obsolete 14B/35B research is not a shipping option. |
| Cause taunt playtest, tactical taunts, low-health escalation, boss/squad story hooks | Preserve the cause pool; human fight review remains outstanding. P2 uses one ordinary hostile in its optional trap, not new bosses/squads. Tactical taunt expansion is not funded here. |
| Fine payment UI; pickup trade bug; active-target/wreck retargeting | Independent work. P2 does not depend on fines, a pickup trade, or retargeting. Its observation events can later serve N.O.V.A.'s target-loss request without replacing that request's resolved behavior. |
| Nickname guard, loading filler suppression, first-dock latch, tangent autopilot | Already fixed per tracker/source. Keep regression protection. Do not resurrect the dead avoidance functions described in old bug text. |

# 3. Proposals

## P1 — One inference owner: make 8GB residency a checked invariant

**Claim:** Serialize access to the actual inference transport, and amortize large-model work within exclusive preparation sessions. **Objective:** model-and-TTS.

### Mechanism and integration

Keep `LocalModelGateway` responsible for model profiles and bodies. Add **NEW** `scripts/ai/LocalInferenceCoordinator.gd`, a Node owned by `LLMInterface`, as the only owner of Ollama HTTP generation, warmup and unload requests. The existing `NarrativeCacheScheduler` still decides *what content is needed*. The coordinator decides *whether hardware can run a request*. It is not a second content scheduler.

| Existing file/symbol | Required change |
|---|---|
| `scripts/LLMInterface.gd`: all HTTP generation sites, `_verify_small_model_ready()`, `warm_small_model_after_story_gate()`, `_start_kaelen_handoff_batch_request()` | Route through coordinator; preserve callback signatures at the public boundary. Route watchdog probes through it too. Inventory every `/api/generate` and `/api/chat` call, including raw bodies. Reset readiness on eviction. |
| `scripts/ai/LocalModelGateway.gd`: `generation_body()`, `model_for_capability()`, `select_installed_model()` | Reject unknown capabilities and non-shipping model identities in release. Keep `think:false` and pinned contexts. Accept a coordinator-owned session lease; callers cannot set residency or context. |
| `scripts/GameRoot.gd`: `_pause_narrative_cache_scheduler()`, `_resume_narrative_cache_scheduler()`, campaign/chapter preparation, `_change_system()` | Own visible gate lifetime. Queue large requests from flight/dock callbacks until a real preparation screen owns control. Merely selecting “Fly to gate” or opening a dock menu is not permission to load 8B. |
| `scripts/story/StoryManager.gd`: `_request_story_horizon_expansion()`, `_ensure_nova_glitch_hints()`, `generate_handoff_pool()` | Submit requests to the next eligible gate. Retain previous valid content until replacement is committed. |
| `scripts/diagnostics/GenerationDiagnostics.gd`: `record_event()`, `record_lifecycle_timestamp()`, percentile reporting | Correlate queue, residency, generation and parsing with one request ID. |
| **NEW** `data/content/local_inference_policy.json`; **NEW** `tests/ai/run_local_inference_coordinator_tests.gd` | Frozen shipping policy and fake-transport tests. |

State sequence:

1. `SMALL_READY`: one small generation in flight. Kokoro is CPU-only under P5. No large dispatch.
2. `DRAINING_SMALL`: gate acquired; stop admitting small jobs, finish the current one within its existing timeout, cancel obsolete queued work. Do not assume HTTP cancellation stopped server execution.
3. `UNLOADING_SMALL`: send empty generation with `keep_alive:0`; require a successful unload response and absence of the small model in `/api/ps`. Poll every 250 ms for at most 15 seconds. Clear `small_model_verified` and warmup latches.
4. `LARGE_READY`: run only the gate's frozen finite job list, serially. Retain 8B for 120 seconds between its jobs; explicitly unload at gate exit. This coordinator-only lease replaces `keep_alive:0` for those requests, not for arbitrary callers. The lease watchdog unloads after gate cancellation too.
5. `UNLOADING_LARGE`: same confirmation rule. Never warm small until large absence is confirmed.
6. `WARMING_SMALL`: warm with the same 8192 context, then the existing real generation probe. Require nonempty valid response, not merely HTTP 200. Only then resume the scheduler and enter gameplay.
7. `SERVICE_ERROR`: readable technical status, Retry and Return to menu. Never call readiness success on failure.

The empty-prompt unload mechanism, residency endpoint and server concurrency controls are supplied by Ollama; their existence does not establish a VRAM fit for this game. Pin and test the bundled version. Use `OLLAMA_NUM_PARALLEL=1` and `OLLAMA_MAX_LOADED_MODELS=1` for a **game-owned** server, alongside the coordinator checks. Do not kill unrelated models/processes on a shared server; report the conflict and offer the configured game service instead. [Ollama API](https://docs.ollama.com/api/generate), [Ollama FAQ](https://docs.ollama.com/faq).

At startup, gate order is existing campaign bible → names/factions/system pack as required → chapter/horizon dependencies → protected N.O.V.A. hints → handoffs. Skip already valid artifacts. Freeze the gate list; arrivals during it queue for a later gate. Gate timeout is 900 seconds overall, with existing per-capability timeouts; show elapsed time and real stage names. Player can cancel to menu without committing incomplete story state. Routine jumps with adequate prepared content use no large-model gate.

### Contracts

The following are typed record specifications, not executable code. All fields are required unless marked optional. Persist no `Callable`, Node, HTTP object or monotonic timestamp.

```text
InferencePolicy v1 (build-owned JSON)
  version: int = 1
  small_model: String = "qwen3:4b"
  large_model: String = "qwen3:8b"
  small_num_ctx: int = 8192
  large_num_ctx: int = 16384
  max_in_flight: int = 1
  large_session_keep_alive_seconds: int = 120
  unload_timeout_ms: int = 15000
  gate_timeout_ms: int = 900000
  allow_runtime_download: bool = false

InferenceRequest (runtime only)
  request_id: String
  capability: String                 # must be registered
  owner_id: String                   # cache job or story preparation owner
  context_fingerprint: String
  gate_id: String                    # empty for small jobs
  priority: int                      # scheduler's existing 0/10/20/30
  prompt: String
  response_format: String            # "json" or existing explicitly textual contract
  options: Dictionary               # coordinator strips forbidden overrides
  max_queue_ms: int                  # P0 30000; others 120000
  attempt: int                      # 0 or 1

InferenceResult (runtime callback envelope)
  request_id: String
  status: String                    # ok|failed|canceled|stale|queue_expired
  reason: String
  response_text: String
  model: String
  context_fingerprint: String
  queue_ms: int
  load_ms: int
  prompt_tokens: int
  output_tokens: int
  generation_ms: int
```

**NEW signatures:** `submit(request: Dictionary, callback: Callable) -> String`, `begin_preparation(gate_id: String, owner_id: String) -> Dictionary`, `end_preparation(gate_id: String) -> void`, `cancel_owner(owner_id: String) -> void`. Queue ordering is priority, then enqueue sequence. Deduplicate identical owner/context/capability jobs. Max queue length 64; evict oldest P3 first, otherwise refuse new background submission with a diagnostic. P0 requests must not be silently discarded. Request timeout begins at dispatch; queue expiry is a separate result. Permit one transport retry, within the owner's overall deadline. No five-attempt optional quiet-moment storms.

**Prompt contract:** P1 changes transport, not existing content schemas. Existing capability parsers remain authoritative. Readiness prompt is `Reply with the single word: ready`; expect trimmed `ready`, case-insensitive. Reject reasoning markup, extra prose, empty response and truncation. New gameplay contracts are specified in P4.

### VRAM and offline shipping contract

| Mode | Initial budget to validate on the 8GB target |
|---|---|
| Gameplay | 4B including KV/runtime ≤4.25 GiB; renderer ≤2.25 GiB; OS/driver/headroom ≥1.5 GiB. Kokoro GPU allocation zero. |
| Large preparation | Small allocation zero; large inference allocation ≤6.25 GiB; loading renderer ≤0.5 GiB; reserve ≥1.25 GiB. Release the 3D scene's disposable assets before measuring. |

These are allocation ceilings, not promises that current profiles fit. Preserve current contexts for the first measurement. If 8B at 16384 exceeds the gate budget, qualify **one global 8192 large profile** after reducing its compiler input; rerun all large-story validators. If it still fails, qualify a fixed partial CPU-offload large profile for gates, with `num_gpu` frozen per hardware profile at startup. Do not change it per request or quietly alter gameplay's model. Failure of 4B gameplay budget blocks 8GB sign-off; reduce renderer memory or context inputs and requalify a single profile. There is no justified simultaneous residency design here.

Installer work bundles exact tested Ollama/model digests, Kokoro weights, every used voice pack, Python packages and language assets already required by the server. A **NEW** `tools/offline_asset_manifest.json` records `{version:int, files:Array<{path:String, sha256:String, bytes:int}>, model_digests:Dictionary[String,String]}`. Model/license review and installer authoring already belong to the shipping tracker; P1 supplies their functional contract, not a legal conclusion. Disable runtime model pulls and any implicit first-use Kokoro downloads. Missing asset names appear in setup diagnostics; no built-in dialogue mode is offered as a substitute.

### Failure and acceptance

- Every generation rejection/timeout carries request ID, capability, model, attempt, reason and context fingerprint into diagnostics. Exhausted required content also records `record_fallback`, even when no replacement line is played. Do not count a cache hit from valid generated content as fallback.
- Large failure commits none of its unfinished artifact. Continue using an older validated horizon only if it actually covers the requested progression; otherwise the preparation gate stays actionable with Retry/menu. Never send protected work to 4B.
- Fake transport test holds a canceled request alive server-side: 8B must not dispatch until confirmed small unload. Assert zero simultaneous small/large residency across 100 randomized request/gate sequences.
- A source audit fails release if any generation transport bypasses the coordinator. Include handoffs, watchdog probes, anomaly calls and optional quiet moments.
- Resume after service crash, cancel, gate failure and checkpoint load: each callback resolves once, no stale content accepted, no unverified `small_model_ready`.
- On an actual 8GB GPU, record 60 minutes of flight/combat/docking, two preparation gates, GPU memory, prompt/eval/load durations and renderer frame times. Zero 8B gameplay dispatch; no observed simultaneous residency; no normal gameplay model reload after warmup; p95 frame time regression from concurrent 4B work ≤10% against the same scene without inference. Record hardware, driver, quantization digest and build.
- Offline exported-build test on a clean Windows account with network blocked: complete tutorial and two procedural contracts. No download request, missing voice asset or use of an arbitrary installed model.

**Effort/risk:** 48–64 hours. Risk is callbacks tied to private per-call HTTP nodes, and incomplete scene resource release during gates. **Dependencies:** none for transport; P5's CPU policy for full VRAM acceptance. **Unblocks:** safe runtime generation and all later latency measurements.

## P2 — Investigation shapes: add evidence and recovery decisions

**Claim:** A new capability lets the player gather evidence and choose a resolution instead of merely approaching an auto-trigger. **Objective:** freshness.

### Mechanism and anchors

Add `INVESTIGATE_SIGNAL`, backed by four authored, validated shapes. These are executable content, not model-authored scripts. The model supplies only bounded dialogue. Start after the existing tutorial-completed event that initializes `FixedCastRapport`; persist a dedicated `post_tutorial_unlocked` flag from that event. Do not use first dock or the Kaelen briefing flag as a substitute. Existing post-tutorial saves may initialize from `fixed_cast_rapport.initialized_after_tutorial`; ambiguous older saves remain unchanged until the tutorial completion path proves eligibility.

Reuse anomaly geometry, world identity, state capture and target panels. Add a mission-owned mode to `SpaceAnomaly`: disable its 50-unit auto-activation and legacy LLM event replacement. Mission sites execute only commands accepted by `InvestigateSignalCapability`. Existing ambient anomalies retain their behavior. No boarding, crew, stealth simulation, new planet surfaces or escort AI.

**New player verbs:** Scan, Verify, and Resolve a mutually exclusive recovery choice. Scanning is a three-second in-world hold at ≤300 units, outside combat, with speed ≤10 units/s. Losing range, moving too fast or combat cancels without cost or progress. At completion add a machine-readable evidence record and its unambiguous UI fields. No skill check or model judgment determines success.

Each contract has an initial regional search circle of radius 1500 units. Hidden sites are absent from overview and target acquisition until distance ≤600/900/1200 for sensor tier 0/1/2; show generic “Signal contact” then. Rendering is fully hidden beyond this radius, fading in over its final 50 units. A completed scan identifies the site. Sensor upgrades reduce search travel; they never bypass necessary evidence.

The second evidence site is explicitly marked by the first scan. Its route length is 1000–2000 units from the first site. It supplies a deterministic comparison field, not another paragraph of vague prose. At least one legitimate conclusion can be inferred from the displayed records. No ambiguous language puzzle.

### Exact launch catalog

All rewards use the existing approved offer budget `B = reward_credits`; multiply once with integer floor at turn-in. No extra credits at the site. `report` is always available after the first scan, so missing consumables cannot strand a contract. Survey/recovery evidence lives in the mission log and uses no cargo capacity.

| Shape ID | Situation and actual decisions | Terminal branch IDs and effects |
|---|---|---|
| `survey_discrepancy` | First beacon reports `route_code A`; second reports A or B, seeded 50/50. After first scan, submit an unverified survey or fly to verify. After both scans, choose “Codes match” or “Codes differ”; UI shows both values side by side. | `report`: 0.5B, unverified. `certify_match` or `certify_mismatch`: B if correct, 0.25B if wrong. Both conclusions remain selectable; wrong evidence assessment matters. No hostiles. |
| `competing_claims` | One wreck-like anomaly has a recorder and a valuable salvage bus sharing one power source. First scan reveals both. Player can preserve recorder evidence or liquidate the bus. A second scan verifies which **named major faction** owns the recorder; the contract faction and a different major faction claim it. | `report`: 0.5B. `preserve`: B, recorder evidence enters log; requires second scan, no item cost. `liquidate`: 1.5B, recorder becomes irrecoverable; requires one `salvage_drone`, consumed once. Named claimants are transient business contacts, not companions. No combat. |
| `transmitter_lure` | Long-range first scan shows a beacon code; second scan compares the issuer's valid code, revealing match or forged. The site contains a cache. Player can report without approach or commit to extraction. Half of instances are forged; this is fixed before offer. | `report`: 0.75B after any scan, no attack. `extract`: 1.5B after first scan and explicit “Approach and extract” confirmation; a forged beacon spawns one hostile on crossing 150 units. Secure cache at ≤50 units only outside combat. Fight or use existing flee; returning later remains possible. Hostile spawns once, never auto-respawns. |
| `unstable_archive` | First scan reveals two mutually exclusive ways to recover an archive: feed the recorder with a repair kit, or travel to a second relay and reconstruct a lower-value copy. There is no real-time expiry. Keeping the kit preserves the player's emergency resource. | `report`: 0.5B. `stabilize`: 1.25B, consume one `repair_kit` once; original evidence preserved. `reconstruct`: B, requires second scan; copy evidence preserved. No combat. |

The lure's hostile comes from the existing generated hostile faction in the system, otherwise `reavers`, at the normal system tier, capped at the player's hull tier +1. Bind its persistent ID to the mission. Do not give a generated minor faction a friendly negotiation role. Use existing cause derivation/taunt selection; do not insert a bribe offer into combat barks. Preview explicitly states “Extraction may attract a hostile; verification is available.” The scan reveals the forged status before the player accepts that risk if they investigate.

The **first slice** is `survey_discrepancy` plus `competing_claims`, with real UI, save/load and two different resolution paths. They test information versus travel, and information versus money. The second two shapes are gated on that playtest. Four shapes are not infinite novelty; P3 makes their context and consequences persist.

### Selection, offer ownership and data

Shape catalog is **NEW** `data/content/mission_shapes.json`. Loader **NEW** `scripts/domain/MissionShapeRegistry.gd` uses `ValidationResult` and the existing domain-data pattern. Reject bad content during export validation and development startup; never partially apply a broken shape.

```text
MissionShapeCatalog
  version: int = 1
  shapes: Array<MissionShape>
MissionShape
  id: String                         # exactly one of the four IDs above
  objective_type: String = "INVESTIGATE_SIGNAL"
  recipe: String                     # same four-value enum; closed dispatch
  requires_second_site: bool = true
  can_spawn_hostile: bool            # true only for transmitter_lure
  branch_ids: Array[String]          # exactly the row's branches
  requires_flags: Array[String]      # ["post_tutorial_unlocked"]
  weight: int = 1                    # not used inside a no-repeat cycle

Investigation objective (within the existing offer.objective)
  type: String = "INVESTIGATE_SIGNAL"
  shape_id: String
  mission_site_ids: Array[String]    # exactly two stable WorldIdentity IDs
  turn_in_station_id: String
  reward_credits: int                # mirror existing validated offer budget
  investigation: InvestigationState

InvestigationState v1 (copied explicitly through MissionAdapter into active state)
  version: int = 1
  seed: int                         # positive 31-bit seed
  phase: String                     # search|identified|ready|closed
  scanned_site_ids: Array[String]
  evidence: Array<Evidence>
  branch_id: String                 # empty until terminal choice
  outcome_tag: String               # empty|unverified|verified|mistaken|preserved|liquidated|extracted|copied
  payout_numerator: int             # default 1
  payout_denominator: int           # default 1; use 1/2,1/4,3/4,3/2,5/4 as above
  consumable_spent: bool
  hostile_spawned: bool
  hostile_id: String                # empty unless spawn committed
  outcome_event_id: String          # empty until resolution
  sites: Array<InvestigationSite>
InvestigationSite
  id: String
  system_id: String
  position: Array[float]            # exactly x,y,z; finite
  reveal_state: String             # hidden|contact|identified
  role: String                     # primary|verification
  code: String                     # A|B; mission data, not plot secret
  owner_faction_id: String          # existing faction ID or empty
Evidence
  id: String                       # "<mission_id>.evidence.<site_role>"
  site_id: String
  observed_code: String
  observed_owner_id: String
  observed_minute: int

InvestigationCommand (UI → QuestManager → capability)
  mission_id: String
  action: String                   # scan_complete|resolve|extract_complete
  site_id: String
  branch_id: String                # empty for scanning
  expected_revision: int
```

`phase=identified` after first scan, `ready` only after a terminal choice or successful extraction. Existing `MissionInstance` remains ACTIVE until ready, then READY_TO_TURN_IN → COMPLETED. Do not infer completion from “both scanned.” Wrong certification also goes through turn-in at its reduced payout. Abandonment uses the existing terminal state; cleanup removes mission sites and mission-owned remaining hostiles, not unrelated ships. The lure's confirmed extraction intent is stored as `branch_id=extract` while ACTIVE; `outcome_tag=extracted` and phase ready are set only on completion.

Truth generation is entirely code-owned: primary code is A; verification code is A or B from the seeded coin flip. For survey, equality means match; for lure, inequality means forged. P3's forced-forged offer writes B before publication. For claims, the verification site's `owner_faction_id` is one of the two preselected named claimants, seeded equally; `preserve` hands evidence to that verified owner through the original broker at turn-in. The primary owner field stays empty. For archive, codes and owner fields are empty; verification yields the copy. Never let a generated label overwrite these fields. Map correct certification to `verified`, incorrect to `mistaken`, any report to `unverified` (with the separate `verified` outcome boolean indicating whether both sites were scanned), preserve/stabilize to `preserved`, liquidate to `liquidated`, reconstruct to `copied`. This keeps “a verified lure report” distinguishable from “unverified report.”

Certify requires both scans; liquidate/stabilize/extract require primary scan; preserve/reconstruct require both. After committing `extract`, only scanning, extraction completion or abandonment remain; no branch switch after triggering its hostile. Entering the lure radius without that commitment does not spawn its mission hostile or award its cache. Ordinary world hostiles remain unaffected. Resolve commands use current authoritative player pose/inventory/combat state; never trust a UI-supplied scan-complete event without the scan controller's completed hold token.

Runtime scan progress is not saved; restart the hold after load. Persist evidence and terminal decisions. Revalidate range, combat state, expected revision, inventory and branch eligibility at command execution, not just button enable time. Command IDs are derived as `<mission_id>:<site_id>:scan` or `<mission_id>:resolve`; duplicates produce the original result and no new item spend. Revision is an added `investigation_revision:int`, initialized zero and incremented on accepted mutation.

Generate candidate site positions with a seeded RNG around a registered station in the current system: primary distance 2000–4000 units, verification 1000–2000 from primary. Reject positions within any active navigation keep-out sphere plus 300 units or within 800 units of a station/gate. Use the actual sphere records consumed by `TangentNavigator`, not a second planet-radius formula. Try 32 candidates; then choose another eligible station, once each. If none work, return `no_safe_sites` and leave the unshown shape unused. Do not spawn inside a hazard to satisfy a variety quota. **Assumption to validate in slice one:** every intended system has enough usable space for these bounds; if not, exclude that system from investigation offers and show the diagnostic, not silently shrink margins.

The search-circle center is the primary site's position plus a seeded offset of at most 900 units; persist `search_center:Array[float]` and `search_radius:float=1500.0` in `InvestigationState`. Verification stays hidden and unmarked until primary scan, even if encountered first; it becomes sensor-eligible and gets its exact route marker afterward. These positions are ordinary mission secrets, not campaign-plot knowledge. Revalidate placement at acceptance against moving bodies; if unsafe, re-place the unvisited pair with the saved RNG sequence before activating the mission. Once accepted, never reroll its truth or branch terms.

Extend the existing `TauntBag` with **NEW** optional injected RNG support for cycle seeds, preserving default taunt behavior. Build one bag per eligible shape-set signature, with entries `{id:String, text:String}` where `text=id`; keep stable ordering. A cycle is selected once and persisted. Filter eligibility before forming that pool, not by skipping draws inside it. Carry an explicit campaign-wide `last_shape_id` so a pool change cannot immediately replay it when another eligible shape exists. Do not promise no repetition across different eligibility sets.

Persist `story_state.investigation_selection = {version:int, bags:Dictionary[String,Dictionary], last_shape_id:String, outstanding_offers:Array<{offer_id:String, shape_id:String, seed:int}>}`. Draw/record when an offer is first **shown**, not during speculative prefetch; repeated panel opens return the same offer. Retire a shown shape even if declined. Reservations prepared before display hold their seed but do not advance the bag until publication. Reset to a new campaign seed on new game; checkpoint restore restores the bag and outstanding offers with the mission state.

### Files, generation and failure

| Files/symbols | Work |
|---|---|
| **NEW** `scripts/domain/capabilities/InvestigateSignalCapability.gd` | Implement existing `supported_objective_types()`, `handle_event()`, `is_completed()`, tracker and cleanup hooks. No scene searches inside the pure capability. |
| `scripts/domain/MissionObjectiveDefinition.gd`, `MissionState.gd`, `MissionDefinition.gd`, `MissionAdapter.gd`, `MissionCapabilityRegistry.gd`, `MissionTemplateRegistry.gd` | Register, validate and explicitly preserve every new field through offer→active→save round trips. Add investigation agent/board templates without converting legacy types. |
| `scripts/story/StoryAgentOfferBuilder.gd`: `can_build()`, `build_offer()`; `scripts/domain/PublicBoardOfferBuilder.gd`: `build_offers()` | Add one eligible investigation offer alongside current work. Story offers use it only when the candidate explicitly supports investigation; never mutate an authored story beat's objective. |
| `scripts/QuestManager.gd`: `accept_quest()`, capture/restore, completion/cleanup | **NEW** `dispatch_investigation_command(command: Dictionary) -> Dictionary`; validate authoritative state, apply capability result and publish progress. |
| `scripts/SpaceAnomaly.gd`, `scripts/AnomalyRegistry.gd` | Mission-site mode, reveal query, capture/restore, mission-owned creation. Persist IDs and reconcile missing sites once on restore. |
| `scripts/PlayerShip.gd`: `_navigator_obstacles()` | Add **NEW** `investigation_obstacle_snapshot() -> Array[Dictionary]`, projecting its existing `center/radius/physical` records without Nodes, for site placement. Do not change navigation steering. |
| `scripts/UIManager.gd`; **NEW** `scripts/ui/InvestigationPanel.gd` | Existing target panel opens a compact evidence/choice panel; code renders evidence fields, requirements and payout consequences. Disable buttons with a reason. No new large scene/art dependency. |
| `scripts/GameRoot.gd`: `_capture_prepared_runtime_state()` and restore; `scripts/persistence/StoryStateStore.gd`, `SaveMigrator.gd` | Save/migrate selection and mission state. Add schema versions; old missions keep their old capability. |
| **NEW** `tests/domain/run_investigation_contract_tests.gd` | Pure state tests plus in-engine entry-path smoke. |

**Prompt contract:** Use P4's `opening` and one-field `line` contracts. Inputs are shape ID, actually disclosed evidence, code-owned objective and branch summary, existing speaker card and safe context. Neither model selects site position, truth value, branch effect, target faction, payout or spawn. Prefetch the offer's opening before publishing it; branch reactions are optional and cannot block an executed choice. Existing authored UI evidence labels are mechanics presentation, not replacement character dialogue. Log missing/rejected generated speech and leave the character silent; do not call `MissionConversationCompiler.fallback_bundle()` as a successful generated result.

The new dispatch returns `{ok:bool, reason:String, revision:int, phase:String, outcome_tag:String}`. The capability's effect hints extend the existing convention with `{progress_changed:bool, consume_item_id:String, consume_count:int, spawn_mission_hostile:bool, payout_numerator:int, payout_denominator:int}`; empty item ID/count zero mean no spend. The command owner validates and applies them once before emitting progress. A failed command leaves every field and resource unchanged. Scan hold tokens remain runtime-only, scoped to mission/site/revision and consumed once.

**Failure:** Invalid shape/placement withholds the unshown offer and reports its reason. If a saved site is missing, reconstruct from its saved data/ID, not a new random draw. Invalid active investigation data fails restoration with the existing recoverable load-error UI; do not erase a mission or pay it out. Technical generation failure must not change its mechanically chosen truth. No model calls from scan completion or branch command execution.

### Acceptance, effort and dependencies

- With all four eligible, 20 shown offers contain five complete four-shape cycles; no repeat within a cycle. Panel reopen, rejected prefetch, declining and restart do not create extra draws. Test pool changes separately against the weaker explicit guarantee.
- Each recipe has tests for every branch, wrong certification, item insufficiency, interrupted scan, combat, double click, command replay and save/load before/after each transition.
- Inventory spend, payout and outcome event happen once. After loading a checkpoint before a decision, the entire state rewinds together; after it, neither credits nor story consequence can duplicate.
- Hidden objects are absent from overview, target selection and rendering outside the same sensor radius. First scan exposes a route to verification. No generated prose required to understand the evidence.
- A 100-seed placement suite validates keep-out and separation constraints. Real engine flight reaches both sites using the live autopilot path; do not test dead helper functions in isolation.
- **Human funding gate:** play both first-slice shapes in two seeds. Ask the player to explain the tradeoff before choosing. At least one voluntary verification trip and one deliberate value-versus-evidence decision must occur without coaching. If every player scans everything automatically because it is always best, retune costs/rewards before adding shapes. This cannot be proved by a headless test.

**Effort/risk:** 80–112 hours total, including the 16–24-hour first slice. New UI/ownership persistence are the risks; four recipes are intentionally a closed set. **Dependencies:** existing mission and anomaly systems; P1 before shipping generated content; P4's minimal contract can land with the slice. **Unblocks:** P3 and concrete new fixed-cast reaction material.

## P3 — Local pressure tracks: make a choice change the next jobs

**Claim:** Two active local pressures respond to results and elapsed activity, producing different work sequences and consequences. **Objective:** freshness.

### Mechanism

Do not regenerate the campaign bible or add an autonomous faction simulation. Add **NEW** `scripts/story/LocalPressureDirector.gd`, a pure data reducer owned by `StoryManager`. It consumes committed mission outcome records. The existing chapter plan and authored plot remain higher priority. A pressure may modify discretionary offers only; it cannot alter gates, tutorial beats, canon reveals, faction identity, hostility alignment or authored story prerequisites.

At tutorial exit choose two distinct pressures from `supply`, `claims`, `signals`; assign each to a discovered system with a station. In the starting system, unlock only after tutorial completion. If only one valid system exists, both may operate there. At most two active pressures campaign-wide. A resolved track cools down for four activity steps, then its slot takes the least recently active kind; tie-break by the campaign RNG. Bind replacement to the player's current eligible system. No offscreen spawning or taxes.

One **activity step** is a completed, abandoned, failed or expired non-tutorial mission that the player accepted. Declining or reopening offers does not advance it. Use a deduplicated outcome ID. This explicitly avoids real-time and campaign-clock expiry: reading dialogue and leaving the game paused cannot punish the player. Show “Escalates after N resolved jobs” on pressure cards.

Each pressure starts at level 1, unresolved count zero. A relieving outcome reduces level by one; worsening increases by one; other outcomes leave it unchanged. Clamp to 0–3. After each two activity steps without a relieving outcome for that pressure, raise it by one and reset the counter. A relieving outcome resets its counter. Apply the outcome change first, then inactivity; do not double-escalate a worsened pressure on that same event (reset its counter on worsening too). Level zero resolves the track and starts cooldown.

### Exact effects

| Pressure | Level 1 | Level 2 | Level 3 | Relief / worsening |
|---|---|---|---|---|
| `supply` | Mark one existing ore-delivery offer as local relief. | Relief payout ×1.25; offer an `unstable_archive` job as an alternative source of infrastructure evidence. | Relief payout ×1.5; keep both alternatives. | Complete marked ore delivery, `stabilize` or `reconstruct`: −1. Abandon/expire/fail a marked relief job: +1. Reporting archive only: no change. |
| `claims` | Prioritize `competing_claims`; ownership uncertainty is visible. | Add a second named-faction claim to its public situation, already represented by its two claimants. | New claim job `preserve` payout ×1.25; `liquidate` stays its P2 payout. | `preserve`: −1. `liquidate`: +1. `report`: no change. |
| `signals` | Prioritize `survey_discrepancy`. | Also offer `transmitter_lure` with normal P2 truth odds. | New lure instances are always forged, advertised as elevated beacon fraud; survey remains a combat-free relief option. | Correct certification or reporting a lure **after verification**: −1. Incorrect certification or extracting a forged lure: +1. Other branches: no change. |

Multipliers apply only to new offers, are snapshotted when shown, never rewrite accepted terms, and never stack: choose the applicable maximum multiplier for the branch. Supply affects the marked ore offer only, not global ore prices. No station closure, route blockade or simulated civilian suffering is implied by these numbers. UI reports “Relief contracts pay more” or “Verified ownership contracts available,” not a restored trade lane that no code restored.

Each discretionary offer contains a `pressure_id`; only that track receives its relief/worsening delta. Other active pressures see one inactivity step. Terminal `report` still counts as activity, but has no relief except the verified lure rule. Payout happens through the existing quest turn-in once; pressure outcome commits at turn-in, not first objective readiness. Abandon/failure/expiry commits immediately through existing terminal paths.

Offer publication policy: keep existing board work. Add at most two pressure cards, one per active track in the current system. Each card owns one persistent offer at a time; choices refresh only after acceptance/resolution, or on a level change while unaccepted. P2's shape bag still applies. If the preferred shape was already used in its current cycle, choose another unused compatible shape: `supply=[unstable_archive]`, `claims=[competing_claims]`, `signals=[survey_discrepancy,transmitter_lure]`. A single-shape track necessarily repeats after its cycle; expose that limitation, do not fake a four-shape guarantee. Existing discretionary investigation offers use the four-shape pool. Cap any one family at two of the last four **accepted** discretionary missions by withholding that extra pressure offer while other ordinary work remains available. Never hide an accepted job or a required story offer to satisfy pacing.

Between campaigns, persist only the last two opening signatures in **NEW** `user://run_opening_history.json`: two pressure kinds in activation order, plus the first two investigation shapes. Choose from the six ordered pressure pairs, excluding recent pairs; seed remains per-campaign. This offers deliberate opening separation, not a claim that all future runs are unique. If history is missing, create it; if corrupt, record a diagnostic and start empty. Do not share cast memories or personality state between campaigns.

### Data, persistence and narrative contracts

```text
story_state.local_pressures
  version: int = 1
  activity_step: int
  rng_state: int
  tracks: Array<PressureTrack>        # at most two active; at most six including cooldown entries
  applied_outcome_ids: Array[String] # retain all this campaign; not only a recent window
  recent_accepted_families: Array[String] # last four
PressureTrack
  id: String                        # stable campaign-owned ID
  kind: String                      # supply|claims|signals
  system_id: String
  station_id: String
  level: int                        # 0..3
  untouched_steps: int              # 0..1
  cooldown_until_step: int          # 0 for active
  revision: int
  last_outcome_id: String

MissionOutcome (code-owned; generated text is never an input)
  id: String                        # "<runtime_mission_id>:<terminal_state>"
  mission_id: String
  pressure_id: String                # empty if unbound
  shape_id: String                   # empty for legacy objectives
  objective_type: String
  terminal_state: String
  branch_id: String
  outcome_tag: String
  verified: bool
  forged: bool                      # projected to dialogue only after learned
  credits_paid: int
  consumable_id: String              # empty or actual consumed item
  at_minute: int

pressure_offer (additional offer/active-state metadata)
  pressure_id: String
  pressure_revision: int
  level_at_offer: int
  relief: bool
  payout_multiplier_numerator: int
  payout_multiplier_denominator: int

RunOpeningHistory
  version: int = 1
  openings: Array<{campaign_id:String, pressure_pair:Array[String], first_shapes:Array[String]}>
```

**NEW signatures:** `apply_outcome(state: Dictionary, outcome: Dictionary) -> Dictionary`, `offer_constraints(state: Dictionary, system_id: String) -> Array[Dictionary]`. Each returned constraint has `{pressure_id:String, preferred_shape_ids:Array[String], ore_relief:bool, forced_forged:bool, payout_numerator:int, payout_denominator:int}`; the builders validate all referenced shapes and stations.

Use `StoryStateStore` validation/default/migration and existing checkpoint capture for these records. Add a public outcome adapter in `StoryManager.record_mission_outcome_consequence()` that records the actual mechanical delta before generating its prose. Preserve its chapter/hook resolution path. `GameRoot`'s checkpoint must capture player inventory/credits, quests, sites and story state as one logical snapshot. Stage the new branch mutation in memory; on persistence failure report it and keep a retryable pending save. Never report a durable success for a failed checkpoint. On restore, checkpoint data wins over newer cached story projections; rebuild pressure effects from restored tracks, not from independent caches. Add failure injection around this boundary.

Files touched: `scripts/story/StoryManager.gd`, `scripts/persistence/StoryStateStore.gd`, `scripts/persistence/SaveMigrator.gd`, `scripts/GameRoot.gd`, `scripts/QuestManager.gd`, both offer builders, `scripts/domain/MissionAdapter.gd`, `scripts/UIManager.gd`; **NEW** `data/content/local_pressure_tracks.json` stores the fixed tables above as validated records, and **NEW** `tests/story/run_local_pressure_tests.gd` tests the reducer. Catalog records use `{kind:String, max_level:int=3, escalation_steps:int=2, cooldown_steps:int=4, shape_ids:Array[String]}`; level effects remain closed code dispatch for these three kinds. Do not invent a generic condition/effect scripting language.

**Prompt contract:** no model-generated pressure state. P4 writes optional reactions from the committed `MissionOutcome` and resulting public delta. The exact single-field output is `{"line":"..."}`. It must not claim an unimplemented consequence. Only public evidence becomes knowledge; no faction-pressure prompt sees the campaign's hidden truths.

**Failure:** invalid data withholds that new track/offer and logs; it does not mutate an accepted mission. Missing generated reaction leaves recorded mechanics and UI intact, with a logged generation failure. Existing ordinary missions continue. Save corruption is a recoverable load failure, not permission to silently reset active pressures.

### Acceptance, effort and dependencies

- Same seed and same terminal event sequence produce byte-equivalent normalized pressure state. Duplicate events, panel reopen, load notifications and declined offers cannot advance activity.
- Two tested sequences from the same initial seed—preserve/certify versus liquidate/mistake—produce different levels and different eligible next offers by the third terminal event. Assert the actual builder output, not just the reducer dictionary.
- Every pressure has an always-available combat-free relief path when its station can offer work. No track blocks a tutorial, story gate or already accepted job.
- Displayed offer payout equals turn-in payout across intervening level changes and save/load. Never multiply the P2 branch payout twice.
- Checkpoint fault injection cannot duplicate credits, consume a second kit or apply the same pressure event twice.
- Across the six ordered opening pairs, automated traces report recipe order, scans, verification trips, branches and hostile engagements. Different generated names do not count as divergent play.
- **Human:** three two-hour post-tutorial sessions must include at least one remembered consequence that changes the player's next job choice. If players cannot connect the change to their action without developer explanation, revise pressure cards and reaction timing before adding more tracks.

**Effort/risk:** 40–56 hours. Risk is grind disguised as consequence; levels therefore cap, do not tax passive play, and leave ordinary work open. **Dependencies:** P2 and its outcome/save contract; P4 for character response. **Unblocks:** sustained local stories without new fixed cast or a galaxy simulation.

## P4 — Narrow dialogue compilation: prepare exactly what the next interaction needs

**Claim:** Extend current compilers with explicit fact dependencies and small repair units, reducing wasted inference and stale lines while deepening the fixed cast. **Objective:** both.

### Mechanism and files

Reuse `MissionConversationPlan`, `MissionConversationCompiler`, `DialogueBundleValidator`, `KaelenInteractionPacketBuilder`, `ContextBlockBuilder`, `NarrativeCacheScheduler` and `NarrativeCacheStore`. Do not replace them or add another LLM planner. Add **NEW** `scripts/story/DialogueFieldContract.gd` for one validated field request and **NEW** `scripts/story/OutcomeReactionProjector.gd` for a safe projection of P2/P3 events.

| Existing seam | Change |
|---|---|
| `scripts/story/MissionConversationCompiler.gd`: `build_prompt()`, `required_output_keys()` | Emit work in slices: one opening; up to two intent responses per request; retain already validated slices. Machine-owned intent IDs/buttons and mechanics are assembled locally. Migrate consumers away from generated `*_player` labels in these slices; legacy bundles remain readable. |
| `scripts/story/DialogueBundleValidator.gd` | Validate each field and final assembled bundle; one failed response does not discard valid siblings. Keep final knowledge checks. |
| `scripts/ai/ContextBlockBuilder.gd`; `scripts/story/KaelenInteractionPacketBuilder.gd`: `build_packet()` | Select current mission facts, up to two relevant memories and one public local consequence. Do not copy all tensions, hooks and history into each bark. Use exact typed outcomes instead of keyword-inferred world effects for the new mission path. |
| `scripts/GameRoot.gd` narrative-cache preparation/dispatch; `scripts/story/NarrativeCacheScheduler.gd` | Add slice dependencies and semantic fingerprints; P0 opening/visible responses precede P1 future outcomes, P2 lounge, P3 ambient. Continue existing concurrency one through P1. |
| `scripts/persistence/NarrativeCacheStore.gd`: `semantic_cache_key()`, `semantic_context_fingerprint()` | Version keys for exact dependency slices. Add line/field readiness, consumption and provenance; preserve existing retirement records. |
| `scripts/LLMInterface.gd`: quest, Kaelen, bank and quiet-moment requests | New registered capability `dialogue_field` uses 4B. Keep `nova_line_bank` successful flat JSON; do not reinstate `@@label` or generated taunts. |
| `scripts/story/FixedCastSoulRegistry.gd`, `FixedCastLineValidator.gd`, `QuietMomentLineValidator.gd`, `QuietMomentSelector.gd`; `scripts/ai/Nova.gd` | Preserve identity and repetition machinery. Apply word-boundary matching and request-derived anchors where relevant. Keep one-word closer tolerance. Use positive voice instructions/examples, not lists of forbidden phrases in prompts. |
| `scripts/UIManager.gd`: `_kaelen_return_line()`, completion/abandon/availability consumers; `scripts/story/StoryManager.gd`: `get_agent_contract_availability()` | Request/prewarm at state change; consume matching prepared text. Generated greetings replace pending procedural static-default paths. |
| **NEW** `tests/story/run_dialogue_field_contract_tests.gd` | Deterministic parser, invalidation, knowledge and consumption tests. |

### Data and exact prompt contracts

```text
DialogueFieldRequest v1 (runtime/compiler-owned; safe to persist as preparation intent)
  version: int = 1
  owner_id: String                   # mission, station visit or outcome ID
  speaker_id: String
  voice_profile_id: String
  field_ids: Array[String]           # 1..2, one speaker and knowledge slice only
  purpose: String                    # opening|answer|return|availability|outcome|callback
  fact_ids: Array[String]
  facts: Array<{id:String, text:String, revision:int}>
  memory_ids: Array[String]          # at most two
  required_anchor_groups: Array[Array[String]] # parser-only allowed alternatives per fact
  context_fingerprint: String
  eligibility: Dictionary[String,Variant] # only keys defined below
  soul_version: String               # existing version, empty for non-fixed cast
  rapport_band: String
  situation: String                 # existing soul situation
  delivery_preset: String            # P5 closed enum
  max_words_per_field: int           # 36 opening/answer; 28 other fields
  max_chars_per_field: int           # 240 opening/answer; 180 other fields

PreparedDialogueField (NarrativeCacheStore entry payload)
  version: int = 1
  owner_id: String
  speaker_id: String
  field_id: String
  display_text: String
  fact_ids: Array[String]
  context_fingerprint: String
  eligibility: Dictionary[String,Variant]
  delivery_preset: String
  source: String = "generated"
  status: String                     # prepared|reserved|delivered|retired|failed
  attempt_count: int                 # 1..2
  generator_model_digest: String
  compiler_version: int
  validator_version: int
  line_id: String                    # stable hash of owner/field/fingerprint/accepted text
```

Eligibility keys are exactly `mission_id:String`, `mission_revision:int`, `branch_id:String`, `station_id:String`, `visit_id:String`, `pressure_id:String`, `pressure_revision:int`, `requires_fact_ids:Array[String]`. Omit irrelevant keys; unknown keys fail validation. Add these to the semantic identity allowlist. Fingerprint a canonical sorted record of only the values read by the field, including facts/versions, speaker/soul/rapport, selected memories, purpose and branch. A field about payout does not invalidate because an unrelated lounge contact became warmer.

Do not ask the model to echo metadata, invent facts or return arrays. Compile prompt in this order:

1. Speaker's existing positive soul projection and two existing style references, with forbidden-phrase examples excluded from prompt assembly. Other speakers get their existing persona card. Preserve the soul data; change its prompt projection only where negative vocabulary leaks.
2. Purpose and situation, expressed concretely: e.g. “React to the captain preserving a recorder instead of taking the larger salvage payout.”
3. At most four safe fact sentences, two short relevant memories and one public consequence; entire dynamic fact block ≤1200 characters.
4. Exact field keys, length limits and flat JSON example. No banned phrases reproduced in the correction prompt.

**Exact output variants:**

| Work unit | Output; strings only |
|---|---|
| Opening | `{"opening":"..."}` |
| One intent response | `{"<approved_intent_id>_response":"..."}`; the key is literally constructed from the plan, not chosen by the model |
| Two responses | `{"<first_id>_response":"...","<second_id>_response":"..."}` in the plan's order |
| Reaction, greeting, availability, delayed callback | `{"line":"..."}` |

`format:"json"`, `think:false`; context stays profile-pinned. `num_predict=256` for opening/one response, `384` for two responses, `200` for `line`; temperature 0.7, top_p 0.9. Use these as the initial frozen qualification configuration. Prompt UTF-8 budget 6000 bytes for one field, 9000 for two; approximate this conservatively, then record actual `prompt_eval_count` from Ollama. Retain at least 1024 context tokens of safety/output room in qualification traces. If over budget, remove the older memory, then the second style reference, then nonessential public consequence. Never truncate a required fact, identity instruction or schema halfway; split the unit or fail compilation.

Parser rejects: outer text/code fences; reasoning tags; malformed JSON; duplicate keys; missing/extra keys; non-string or nested values; empty/overlength values; stage directions/speaker prefixes; wrong required anchors; references to unknown entities, unsupported mechanics or amounts that disagree with the contract; existing protected-content offenses; exact retired text; existing shared-sentence/closer repetition. Godot JSON parsing alone does not detect duplicate keys: add a small key-aware token precheck for this deliberately flat grammar, not a general JSON replacement. Normalize quotes/whitespace and apply the existing address guard, then revalidate anchors and nonempty text. Non-Kaelen `Shiny` must never survive either displayed or spoken text.

Checking factual entailment of arbitrary English is not deterministically solvable by these rules. Minimize the exposure: UI owns all amounts, destinations, deadlines and choice effects; prompts for optional character reactions omit quantities and request a reaction to the decision rather than a retelling of terms. The existing mechanical-conflict validators remain, and human transcript review is still required. Do not add a second model “judge” call to every field and claim reliability is solved.

### Preparation and consumption policy

- On offer creation, prepare opening and the two visible question responses. Publish only once required fields validate. Additional optional questions keep their button disabled with “Preparing response” until ready; do not remove them without explanation. P2 choices themselves are code-owned and available irrespective of optional character reactions.
- On mission acceptance, prepare its likely terminal reactions. Prepare at most two possible outcomes initially: the ordinary completion and abandon. For investigation, after first scan prepare `report` plus the highlighted resolution; after verification, replace the second prediction with the now-supported resolution. No full combinatorial branch-bank expansion.
- Future ordinary outcome packets are explicitly hypothetical and isolated: the field may be generated for “if preserve occurs,” but carries `branch_id=preserve` eligibility and is never added to public facts until that event actually commits. They never contain N.O.V.A.'s protected mystery or Kaelen's hidden angle. Don't merge hypothetical facts into shared `story_state_context_text`.
- Station entry/route selection uses existing station prefetch triggers for current visit greetings, return state and no-work availability. Quest accepted/completed, station changed, relevant fact changed or rapport band changed invalidates affected fields. Cancel obsolete queued work before it spends inference.
- Availability ping is prepared during the cooldown; `CampaignClock.time_changed` detects one available transition and queues it through existing interaction arbitration. If not ready, show the factual availability badge immediately and record the missed spoken opportunity. Retry speech only while still relevant and not already acknowledged.
- A valid line reserves at selection and retires on first presentation (text reveal or actual audio start, whichever occurs first). If never presented and its context still matches, release the reservation; once partially heard, do not replay the remainder as a new line. Reopening an already visible transcript is not new dialogue consumption. On reload, preserve retired fingerprints and restore/release reservations according to whether presentation was recorded.

### Deepen the fixed cast without changing them

For each P2/P3 outcome, prepare at most one immediate reaction and one later callback. N.O.V.A. reacts to ship exposure, repair resources and repeated behavior; Kaelen reacts to money forgone, claim leverage and whether the deal was honored. Neither is instructed to acquire a new value system.

Store **NEW** `story_state.local_outcome_memories:Array<{id:String, outcome_id:String, speaker_id:String, public_fact_id:String, mission_id:String, system_id:String, kind:String, at_minute:int, callback_delivered:bool}>`, capped at 24 (12 per speaker). `kind` is `risk_taken|resource_spent|evidence_preserved|value_taken|verification_skipped|verification_paid_off`, derived from the exact branch. Evict oldest callback-delivered record first, otherwise oldest; never evict the existing attachment ledger. Project at most two, matching the current mission/pressure/system; newest breaks ties. Feed these through current memory and soul interfaces, not a new rapport score or state machine.

Immediate reaction uses the current N.O.V.A. casual speech budget and quiet-moment cooldown, including combat/cinematic suppression. Kaelen replies at next dock/panel opening, not as a second simultaneous voice in space. A later callback is eligible at the next matching discretionary offer or quiet transit in the same system, at least one activity step later; expires after four steps. At most one callback per outcome and per visit. Gate mysteries continue to use the existing large-only `nova_glitch` path, never this outcome projector.

### Failure, acceptance, effort

Retry only rejected fields, once, with unchanged facts and a terse positive shape reminder. Do not paste the rejected sentence back into the prompt. If required text still fails, preserve the unpublished offer/interaction and show a technical Retry/Back state. Accepted mission mechanics and current transcript remain usable; optional speech can be absent, but it is a logged miss, not counted as a successful quiet moment. Rate-limit reattempt to next relevant state change or explicit Retry. No canned line and no fabricated “nothing available” character explanation.

- Fixture tests prove flat-schema rejection, sibling preservation, duplicate-key detection, repetition retirement across load, fact-specific invalidation and no generated button/effect injection.
- Inject a unique protected-secret sentinel into every private story field: it must never appear in small-model requests, prepared ordinary fields or captions. Changing an unknown story field cannot silently add it to the public projection.
- Replay 100 interactions against a fake delayed model: zero consume paths issue generation on click; required text is ready or a truthful preparation state appears. No stale branch is served after a choice changes eligibility.
- Existing `tests/story/run_player_address_tests.gd` stays green. Voice owner and mystery-routing tests fail on attempted reassignment, including style-donor access under P5.
- Live qualification on 4B: 200 unfiltered requests across the new purposes, including both fixed cast, log every candidate and rejection. Target ≥90% first-pass structurally valid fields and ≥98% after one retry; no canned output or private-content leak. Report semantic/voice rejection separately—do not hide failures inside aggregate success. Compare accepted tokens per delivered line and total requests against the current equivalent flows; target ≥30% fewer generated tokens per delivered interaction.
- Warm, prepared visible interaction text p95 ≤100 ms; newly needed one-field generation p95 ≤8 s on the qualified machine, measured separately from queue wait. Missing the latter is a preparation/budget issue to fix, not permission to inflate all timeouts.
- **Human:** blindly review all 30 consecutive new N.O.V.A. and 30 Kaelen lines, not curated winners. Reject sentimental N.O.V.A., invented Kaelen loyalties and repetitive rhetorical templates. The author must accept at least 24/30 for each before expanding coverage. Preserve the already-approved identity if quality misses.

**Effort/risk:** 64–88 hours. Most risk lies in old consumers treating a fallback bundle as valid prepared content and in partial-bundle UI assumptions. **Dependencies:** P1; P2/P3 only for new outcomes, so the existing Kaelen/station work can proceed independently. **Unblocks:** richer fixed-cast reactions with bounded small-model work.

## P5 — Speech assets and utterance identity: reuse audio without losing performance

**Claim:** Persistent render assets, one delivery contract and actual playback events improve latency and expression without another TTS stack. **Objective:** model-and-TTS, with better character timing.

### Mechanism and exact render identity

Keep Kokoro/FastAPI and its real silence insertion. Explicitly construct its pipeline on CPU for the shipping profile; use one synthesis worker and at most one active synthesis request. Bound Torch CPU threads initially to four, then qualify on the minimum CPU. A shorter CPU request must not compete with two speculative synthesis jobs. Kokoro supports explicit device selection; CPU speed here remains a measurement question. [Kokoro device examples](https://github.com/hexgrad/kokoro/blob/main/examples/device_examples.py).

Create **NEW** `scripts/speech/SpeechRenderSpec.gd` to resolve all preparation exactly once, used by `SpeechService`, `KokoroSpeechProvider`, `TTSInterface` and build baking. Transformation order: existing dialogue cleanup → tone/address guards through `SpeechService.prepare_text()` → display-text finalization → `TTSInterface.normalize_tts_pronunciation()` for speech text → resolved voice/delivery → cache key. Preserve `...`/`..`; display typography may use ellipses but never mutate the speech sequence. Audio uses the final pronunciation-normalized text; captions use the corresponding finalized display text.

```text
SpeechRenderSpec v1
  version: int = 1
  speaker_id: String
  voice_profile_id: String
  provider_voice: String             # resolved immutable blend
  display_text: String
  speech_text: String
  speed_milli: int                   # resolved speed *1000, rounded
  style_milli: int                   # resolved style_scale *1000, rounded
  pause_ms: int                      # resolved full beat; half = /2
  pronunciation_version: int
  preparation_version: int
  renderer_id: String                # pinned Kokoro weights/package/voice-pack digest
  sample_rate: int = 24000
  channels: int = 1
  format: String                    # wav_pcm16|ogg_vorbis

AudioManifestEntry
  key: String                       # SHA-256 described below
  relative_path: String
  sha256: String                    # audio byte digest
  byte_count: int
  duration_samples: int
  format: String
  renderer_id: String
  authored_line_id: String           # empty for generated audio
  last_used_unix: int
```

Hash a canonical UTF-8 JSON array in this fixed order: `[version, speaker_id, voice_profile_id, provider_voice, speech_text, speed_milli, style_milli, pause_ms, pronunciation_version, preparation_version, renderer_id, sample_rate, channels, format]`. Use no floating-point formatting in the identity. `display_text` is excluded because pronunciation can normalize equivalent display spellings; the utterance retains its own display text. GDScript computes the authoritative key; bake tools consume its exported spec/key, rather than reimplementing Godot text guards in Python.

Lookup order: verified memory asset → verified bundled manifest → verified generated disk asset → live synthesis of the **same text and spec**. Format-specific keys mean lookup constructs the OGG candidate for bundled assets and WAV candidate for generated assets. Rebuilding an absent audio recording is not substituting a fallback line. A missing required bundled clip is nevertheless an export bug and logs distinctly.

Persist generated PCM16 mono WAVs under **NEW** `user://speech_cache/v1/<first-two-hash-chars>/<hash>.wav`, with **NEW** `user://speech_cache/v1/index.json` containing `{version:int=1, entries:Dictionary[String,AudioManifestEntry]}`. Use existing Python `soundfile`/response WAV bytes; no runtime OGG encoder dependency. Cap total generated bytes at 512 MiB, LRU by last playback/use; evict only unpinned complete files. Keep memory PCM/assets ≤32 MiB; current playback and imminent required response are pinned. Across campaigns audio may be reused by exact key, but dialogue retirement remains campaign-owned.

Use temporary files and rename only after RIFF header, sample rate, channel count, PCM subtype, size and nonzero duration validate; write/update manifest atomically afterward. Audio without a manifest entry is an orphan, removed on next cache maintenance; a manifest entry without a file is a diagnosed miss. Never trust an arbitrary path from an index: resolve under the cache root. Index corruption rebuilds an empty index and diagnoses the loss; it does not prevent required live synthesis.

### Delivery and voice reservation

`KokoroSpeechProvider` must carry the whole spec, not just speed. Extend `resolve_delivery()` and its play/cache methods; keep legacy callers as adapters to a fully resolved spec. The same spec reaches `/tts`, in-memory keys, baked lookup and disk keys.

Voice ownership is a checked allowlist by **speaker**, not just blend equality: Kaelen alone owns `af_bella`; N.O.V.A. alone owns `bf_emma`; her existing `bf_emma[0.7]+af_bella[0.3]` is the only exception. Exclude these voices from any other speaker's blend and from `style_from`. Do not add style donors at all in this release; preserve `style_from=""`. Do not change current fixed-cast blend weights or choose them per run.

New delivery presets are code-selected from situation, not model-generated:

| Preset | Speed relative to existing profile | Full pause | Style scale | Eligibility |
|---|---:|---:|---:|---|
| `default` | 1.00 | 700 ms | 1.00 | All existing speech |
| `measured` | 0.95 | 800 ms | 1.00 | Evidence/contract explanation |
| `clipped` | 1.03 | 350 ms | 1.00 | Existing threat/status information |
| `dry_beat` | 1.00 | 900 ms | 1.00 | Optional dry observation with an explicit pause marker |

Preserve current per-line taunt speed/pause overrides over these defaults. These preset values are audition candidates: ship `default` until human approval, then enable individually. Style remains 1.0 because the server's style-half steering is labeled experimental; encode it in identity now to prevent future collisions, not to advertise an unproven emotional control. Do not claim speed/pause changes create acting by themselves.

### Playback ownership, synthesis failure and timing

Add an utterance ID end-to-end. Extend `TTSInterface` with **NEW** signals `utterance_started(id: String)`, `utterance_finished(id: String)`, `utterance_failed(id: String, reason: String)`, `utterance_canceled(id: String, reason: String)`. Started fires only after `AudioStreamPlayer.play()` with the matching stream. Keep global signals as temporary compatibility adapters, then move portraits, welcome holds, sequential playback, captions and ducking to identified events. One utterance receives exactly one terminal event, including explicit stop and failed HTTP.

```text
Utterance (runtime only; existing interaction queue routes ownership)
  id: String
  owner_id: String
  line_id: String
  spec: SpeechRenderSpec
  priority: int                     # 0 critical/authored; 10 player reply; 20 ambient
  expires_at_msec: int              # -1 required; now+20000 ambient
  context_fingerprint: String
  source: String                    # authored|generated
```

Preserve ambient queue cap three and 20-second expiry. P0 critical/authored work may interrupt P20, as may a player-initiated P10 reply. Ambient never interrupts. Equal priority queues FIFO. While authored cinematics own speech, defer ordinary replies via `PlayerInteractionQueue` and preserve existing filler suppression. Revalidate eligibility before playback, not merely on enqueue. Combat invalidates unstarted casual observations. Interrupted ambient is retired if any part was presented; never restart it from the beginning.

TTS request timeout stays 10 seconds initially; one resynthesis retry for required content while its owner is still active. A failure shows the **same validated generated text** in the caption/dialogue surface and logs `tts_failed`; this is an explicit audio failure, not a canned-text replacement or a success in voice metrics. Optional ambient failure is logged and omitted. At no point does an unavailable TTS server justify changing speaker voice.

Server rejects invalid speed (outside 0.75–1.3 after resolution), style (outside 0.8–1.2), pause (outside 0–3000 ms), unsupported voice or malformed request before synthesis. Keep segment-to-gap records together. If Kokoro returns no audio for any nonempty segment, fail the **entire utterance** rather than silently omit its words. Leading/trailing/repeated pause markers must not shift gaps onto the wrong segment. Preserve exact half/full pauses as integer sample counts.

Do not add token-streaming LLM→TTS. An incomplete or unvalidated sentence cannot be retracted after speech. Do not add chunk-streaming playback in this scope: persistent pre-rendering is the lower-risk latency lever, and the queue's ownership bugs must be resolved first.

### Baking, files, acceptance

Extend `tools/bake_taunt_audio.py` to consume exported render specs; add **NEW** `tools/export_speech_render_specs.gd` and **NEW** `tools/bake_authored_audio.py` as build-only tools. Keep existing reviewed taunt text/delivery. Migrate only genuinely authored tutorial/intro pools needed for baking from `scripts/ai/Nova.gd` and `scripts/UIManager.gd` into **NEW** `data/content/authored_speech.json`:

`{version:int, lines:Array<{id:String, speaker_id:String, voice_profile_id:String, text:String, delivery_preset:String, speed_milli:int, pause_ms:int}>}`; use `-1` for an absent per-line speed/pause override, resolve before hashing. Extract data without changing selection order, eligibility or text. Procedural static fallback pools stay failure sources until P4 removes their default use; do not bake them into a new successful default.

Bundled audio lives under existing `assets/audio/taunts/` and **NEW** `assets/audio/authored/`, with manifest v2 `{version:int=2, clips:Dictionary[String,AudioManifestEntry]}`. Extend export filters and validate the exported artifact, not only the source tree. Re-bake or fail the build when approved source/delivery and manifest hashes disagree. Authoring/audition is build time and can use development tooling; shipped speech remains Kokoro output in the reserved voices. No cloud generation is required by this plan.

Other files: `scripts/tts_server.py`, `scripts/TTSInterface.gd`, `scripts/speech/SpeechService.gd`, `scripts/speech/KokoroSpeechProvider.gd`, `scripts/UIManager.gd`; **NEW** `scripts/speech/PersistentSpeechCache.gd`, **NEW** `tests/speech/run_speech_asset_tests.gd`, **NEW** `tests/tools/test_tts_render_contract.py`. The Python test is build/development-only and uses the existing environment.

- Same text with different speed, pause, style, pronunciation version or renderer digest cannot return the same render key. Reserved voices/style donors fail for every other speaker.
- A second launch with identical requested specs performs zero synthesis for those cached lines. A 200-line scripted route achieves ≥95% audio-ready hits on replay; separately report first-run hit rate. This does not mean the player hears retired dialogue again—use replay fixtures to measure audio identity, and fresh campaign fields to test retirement.
- Cached audio starts p95 ≤100 ms after playback eligibility on the qualified SSD; eligible prepared spoken interactions start p95 ≤250 ms. Measure queue waiting separately.
- Corrupt/truncated file, full disk, canceled request, missing bundle clip, stale response and service restart all terminate ownership exactly once and allow the next line to run. Disk-full caching may continue required live audio, with a logged cache failure.
- Silence fixtures assert `...` inserts `pause_ms*24` zero samples and `..` half that at 24 kHz, between the correct nonempty segments. A missing middle segment fails rather than yielding partial speech.
- Test two identical text strings from different speakers and two utterances with the same text: only the matching ID controls portrait/caption/welcome release. Existing intro dock gating and speech service tests remain green.
- On an exported offline build, all required authored clip IDs resolve with correct post-processed speech text. Missing clip is a release validation failure even though runtime can resynthesize it.
- Qualify CPU TTS with 100 10–28-word lines while gameplay and 4B run: p95 synthesis ≤5 seconds, no audio dropouts, renderer p95 frame regression ≤10%, GPU allocation for Kokoro zero. If not met, first reduce speculative TTS work and enlarge preparation lead time; do not silently move Kokoro onto the gameplay GPU.
- **Human:** audition presets using the same line and reserved voice, then listen during a real combat/dock session. Confirm dry delivery, intelligibility, natural half/full pauses and lack of interruption. Do not equate synthetic silence tests with acting quality.

**Effort/risk:** 56–80 hours. Risk is inconsistent old text-normalization paths and global playback listeners. **Dependencies:** cache identity and IDs are independent; P4 supplies novel prepared fields; CPU allocation participates in P1 qualification. **Unblocks:** lower startup/return latency and future voice improvements without cache poisoning.

# 4. Sequencing

Estimates above include these phases; do not add phase estimates to proposal totals. Commit small integrated slices with matching tests, rather than landing unused frameworks first.

| Phase | Ordered slices | Gate / independence |
|---|---|---|
| 0 — Baseline and contract pinning | Record current model digests/config, current relevant parser and cache tests, offline asset inventory and 8GB trace. Freeze voice/mystery/nickname assertions. List raw inference call sites. | Required before performance claims. Read-only measurement can accompany P2 prototyping. No unrelated tracker cleanup. |
| 1 — First visible decision loop | P2 first two shapes, explicit scans/evidence, branch costs, tracker and save/load. Use P4's smallest flat opening/reaction contract through existing request path until P1 is ready. | **16–24-hour first slice.** Human decides whether the verbs merit expansion. Development prototype only until P1 shipping gate passes. |
| 2 — Hardware ownership | P1 coordinator with fake transport → route all callers → gated large sessions → offline setup failure flow → real 8GB measurements. | Strict prerequisite to shipping any new generation path. Independent of P2 gameplay content. |
| 3 — Speech asset foundation | P5 resolved identity → persistent WAV cache → utterance IDs/consumer audit → CPU server qualification. | Independent of P2/P3; can occur before or after phase 2, but final VRAM sign-off requires both. |
| 4 — Prepared interaction quality | P4 sliced compiler/validator → key dependencies → current Kaelen/station consumers → outcome projection and callbacks. | P1 before live stress qualification. Existing station work independent of remaining P2 recipes. |
| 5 — Broader gameplay slice | Finish lure/archive; test hostile ownership/flee/revisit, restore, placement and selection. Then P3 reducer → pressure cards/builders → real consequence traces. | First-slice human approval strictly gates new recipes. P2 outcome contract gates P3. Do not implement new fronts before this boundary stabilizes. |
| 6 — Export and author review | P5 authored extraction/bakes, captions and approved presets; end-to-end no-network test; 8GB 60-minute run; three two-hour freshness sessions. | Cache identity must be frozen before baking. Human cast/voice approval and measurable hardware constraints gate release. |

For each code slice the executing agent runs the affected deterministic tests and one consumer-path smoke test. Godot headless tests run **sequentially**, each with a unique workspace-local absolute `--log-file` under `.tmp_godot_user/test_logs/`. A suite must prove scripts load and expected callables exist, count assertions, and fail on script errors; a printed PASS after a GDScript parse failure is not evidence. Extend `tests/domain/run_mission_state_transition_tests.gd` and run the existing nickname, speech, intro-gating and relevant live-fire suites when their paths change. Do not rerun unrelated suites repeatedly after passing without new evidence.

At phase boundaries update the affected existing tracker items with the precise shipped subset and remaining human gates. This planning deliverable itself does not close tracker items. Refresh `PROJECT_MAP.md`/JSON after the eventual new systems land with `python generate_repo_map.py`.

# 5. Decisions the human must make

Recommendations below are the executable defaults unless explicitly rejected. Choices affecting hardware qualification or narrative taste remain real sign-off gates; no agent should invent different answers during implementation.

| Decision | Defensible options | Recommendation and downstream effect |
|---|---|---|
| Is investigation the next new activity? | Evidence/recovery decisions here; sub-surface mining minigame; EW combat lane. | **Investigation first**, because anomalies, mission capabilities and rumor surfaces already exist. Human gate after two shapes. If rejected, stop P2/P3; P1/P4/P5 retain value. Mining/EW require separate mechanical designs. |
| Full budget or half slice? | 376–524-hour envelope; approximately half. | Fund phase 1 and P1/P5 foundations first, then release remaining funds on results. Half-budget cuts are stated in section 1; no discretionary feature substitutions. |
| Accept activity-based pressure escalation? | Resolved-job steps; wall-clock/campaign-time deadlines. | **Job steps**, explicitly labeled. Avoids punishing dialogue reading and saves. Real-time urgency would require separate balance, pause/load and accessibility contracts; excluded here. |
| How much financial punishment? | Proposed fractional payouts; no wrong-answer reduction. | Keep 0.25B mistaken survey and 1.5B liquidation initially. All terms visible; consumables optional. If human review finds verification automatic, retune travel/value tradeoffs before scaling catalog, not hidden penalties. |
| Remember recent run openings across campaigns? | Last two opening signatures; fully independent seeds. | **Remember signatures only.** This deliberately avoids repeating the opening pair; no shared companion memory. Disabling removes a deterministic inter-run difference guarantee but changes no campaign mechanics. |
| What happens when required generation remains unavailable? | Wait with Retry/Back; display code-owned mission terms without a character response. | **Retry/Back for new required dialogue; keep already accepted mechanics usable.** Optional reactions may be silent and logged. Never static replacement speech. A broader text-only play mode would be a separate UX choice, not an inference success. |
| Minimum CPU, RAM and installation budget? | Choose a qualified low-end PC; leave “8GB GPU” as the only minimum. | **Qualify provisionally on Ryzen 5 3600-class CPU, 16GB RAM, SSD and an 8GB GPU.** This is a proposed test floor, not an established supported specification. Confirm exact test hardware before phase 0. CPU TTS and possible gate offload make CPU/RAM material; raise minimum only after measurements, not by assumption. |
| Large preparation latency versus context? | Keep 16K with lower renderer memory/partial offload; globally qualify 8K; skip required story features. | Keep **16K initially**, measure, then use P1's global 8K qualification if needed. Do not silently skip story or downgrade protected writing to small. Human accepts measured gate latency before release; over 120 s for a routine transition requires redesign/reduction of that gate's workload. Startup retains the explicit longer ceiling. |
| Bundle both models for offline new campaigns? | Both pinned models; optional manually installed large pack. | **Bundle both**, because required story generation cannot download later. An optional pack adds setup UX and blocks new-campaign preparation until installed; not included in estimates. Record actual install size before marketing requirements. |
| May Kaelen steer toward better-paying future work in quiet moments? | Existing soul restriction; narrowly allow money-minded nudges. | **Preserve restriction for this plan.** This avoids silently deciding the open tracker debate. If author approves nudges, change soul situation rule and validator together in a separate reviewed slice; never political loyalty or hidden-angle disclosure. |
| Enable new voice delivery presets? | Existing defaults only; individually approved presets. | **Default only until audition**, then approve presets one by one. Keep style scale 1.0 and no donor voices. Preset rejection does not block persistent caching or timing improvements. |

# 6. Explicit non-goals

- No randomized companions, re-personalized N.O.V.A./Kaelen, changed souls, voice pooling, new fixed companion, or small-model authorship of their protected mysteries. Quirks color behavior; they never replace identity.
- No engine/language/platform change, C#, cloud runtime, new model family, fine-tuning pipeline, vector database, embedding service, second TTS engine, speculative decoding dependency or end-user GPU-monitor installation. Development profiling tools are not runtime requirements.
- No new campaign bible, chapter planner, line bank, general cache scheduler, lounge system, taunt cause selector or relationship system. Extend the ones already present.
- No freeform model-authored objectives, arbitrary generated condition/effect graphs, natural-language mechanics execution or “LLM game master.” All new mechanics are the closed contracts above.
- No escort AI, boarding, planetary gameplay, ambient civilian economy, station destruction, faction diplomacy overhaul or total market simulation. These would multiply scope and save-state risk before investigation is proven.
- No claim that shuffled shapes alone create limitless replayability. Four shapes are a testable launch vocabulary; pressure consequences must earn further funding through play.
- No canned fallback as a successful recovery, silent speaker substitution, automatic runtime download, hidden generation retry loop, or renaming missing generated content “authored” to improve metrics. Approved tutorial/canon material and the existing reviewed taunts remain authored content by design.
- No revival of runtime opening-taunt generation, blanket one-word closer rejection or prompt-based repetition policing. No changing approved taunt delivery incidentally during cache migration.
- No blanket static-pool extraction/refactor, localization implementation, new title/menu, campaign-ending PDF, general bug backlog clearance or addon changes. Those have their own trackers and budgets.
- No token-to-audio streaming or unreviewed Kokoro style-transfer claims. Cache/preparation and utterance ownership address the evidenced latency and timing failures first.
- No implementation code in this deliverable. Records, interfaces, numerical rules, parser contracts and gates specify the work; implementation belongs to the executing agent.

# Living Narrative “Shining Star” Evolution Plan

> Living implementation checklist for turning post-tutorial NPC dialogue, agent missions, N.O.V.A. reactions, and Kaelen turn-ins into a fast, coherent, campaign-unique narrative experience.
>
> Planning baseline: 2026-07-10. This document was produced from the current source, `PROJECT_MAP.md`, `docs/whileYouWasSleeping.md`, the existing narrative plans, the current fallback summary, and the actual dialogue/mission/persistence code. Historical design documents remain useful context, but this plan treats the current source as truth.

## 0. Product Promise

The narrative layer is not complete when every button works. It is complete when the player feels that:

1. every job exists because something in this campaign made somebody need it;
2. the person offering it has a life, priorities, memory, and a recognizable way of speaking;
3. the player is never expected to know a fact they have not learned;
4. sensible clarification questions are available before commitment;
5. NPC answers alter what the player knows and later conversations respect that knowledge;
6. repeated activity has changing meaning, consequences, and reactions even when the underlying mechanic repeats;
7. post-tutorial interaction text is campaign-specific and is not reused within a campaign;
8. pressing a dialogue option never turns into a visible wait for an LLM;
9. Kaelen and N.O.V.A. comment on what actually happened, not merely the generic event category; and
10. the tone stays immersive, human, dry or darkly funny, and PG-13 without turning every line into a joke.

The large story model remains the director. The small dialogue model remains the performer. Code owns truth, mechanics, disclosure permissions, timing, cache validity, and consequences.

## 1. Scope and Explicit Boundaries

### In scope

- Campaign spine evolution into a causal, playable story plan.
- Story-aware mission selection and anti-streak rules.
- Mission briefing conversations with contextual clarification questions.
- Player-knowledge tracking and spoiler-safe disclosure.
- Persistent generated NPC identity, personality, relationship, and memory.
- Instant interaction through background generation, durable dialogue bundles, and TTS pre-caching.
- Story-aware N.O.V.A. navigation/movement reactions.
- Story- and outcome-aware Kaelen mission handoffs, completion lines, abandon lines, and turn-ins.
- Lounge conversation continuity and latency removal.
- Uniqueness validation, narrative quality scoring, diagnostics, designer tooling, migrations, and automated/playtest gates.

### Out of scope unless separately approved

- Replacing the local Ollama stack or adding a cloud dependency.
- Fully free-text player input.
- Voice cloning or changing the approved voice identities.
- Removing the authored tutorial. The tutorial stays controlled and may use authored lines.
- Letting either model author rewards, reputation numbers, objective legality, quest completion, or secret-disclosure permissions.
- Planet landing, boarding, crew combat, or mechanics that do not exist in the current game.

## 2. Verified Current-State Findings

These findings are implementation constraints, not guesses.

### Narrative truth exists but is too loosely connected

- `CampaignBibleStore`, `NarrativeDirector`, and `StoryManager` already separate player-safe and director-only knowledge.
- `StoryManager.get_story_context_block()` exposes chapter, tensions, player knowledge, foreshadowing, Kaelen mood, open threads, and faction pressure.
- `StoryManager.get_current_because()` returns only the first active tension. It does not select a mission-specific cause.
- Quest generation stamps `story_hook_ref` onto an offer, but `MissionAdapter.build_active_state()` does not preserve that field. Completed active missions therefore cannot reliably resolve the hook that supposedly caused them.
- Story hooks are currently free-form strings. They lack explicit fact IDs, disclosure tiers, involved actors, suitable mission verbs, dependencies, and payoff rules.

### Mission variety is random rather than directed

- `LLMInterface.request_quest_generation()` randomly selects only `DELIVER_ORE`, `KILL_SHIPS`, or `PICKUP_SPECIAL`, unless a soft story hint overrides it.
- There is no recent-type streak cap, pacing budget, player-fatigue score, or causal fitness score.
- The project already supports additional mechanics through `MissionCapabilityRegistry`: `DELIVERY_COURIER`, `PURCHASE_DELIVERY`, `RECOVER_COMBAT_DROP`, and `TARGET_WITH_COMMS_REVERSAL`. Agent generation does not currently use them.
- The current “complication” is chosen from four global strings, independent of the campaign cause, NPC, mission history, or system.

### Quest briefings are offers, not conversations

- The model produces one opening and three choices.
- The prompt trains those choices as accept, request an advance, and demand more pay.
- `UIManager._on_choice_selected()` accepts the mission for every choice. There is no non-accepting clarification state.
- The model is allowed to write choice text and response text, but the code does not validate that a reply is something the player could reasonably know or ask.
- The prompt says the mission’s cause should shape subtext but should not be stated directly. This prevents the player from learning why routine work is urgent.

### Character identity is present but shallow

- `CampaignNpcIdentityStore` persists generated NPC identity, tags, humor style, relationship state, memory summary, and line fingerprints.
- Generated contacts currently receive broad tags such as `frontier`, role, faction, and `deal_minded`; their memory summary is essentially name + workplace + job.
- `CampaignAgentMemorySnippetStore` can retain mission memories, but the quest/history paths do not yet provide a unified relationship ledger or conversation recall contract.
- The fixed major agents have distinct tone prompts, but most other characters are role/faction skins rather than people with tensions, habits, boundaries, contradictions, and personal stakes.

### The cache hides some latency but has correctness and coverage gaps

- One agent quest is generated after docking and cached by system/station only.
- Quest generation is best-of-three **sequential**. The current fallback log shows a selected quest taking about 40 seconds after two 15-second candidate timeouts.
- A quest cache key does not include story revision, hook revision, agent identity, relationship tier, knowledge revision, or recent mission history.
- Quest text, three response lines, and TTS are cached; Kaelen completion/abandon lines are generated after acceptance but are kept only in `UIManager` variables and are lost on reload.
- Lounge conversations make a new model call after each player reply, so the player visibly waits.
- Chatter caches are keyed only by broad type, not by narrative/context revision, and can outlive the context that generated them.
- Kaelen handoff pools already exist and are a good pattern to generalize, but generation contention and pool availability are known concerns.

### N.O.V.A. and Kaelen still rely heavily on stock pools

- N.O.V.A. has good event gating, severity, streak escalation, cooldowns, a campaign quirk, and campaign-specific gate glitches.
- Dock, combat, hull, welcome, tutorial, gate, and arrival lines otherwise draw from small hardcoded pools. Anti-repeat prevents only immediate repetition.
- Kaelen completion/abandon generation knows the original task and faction, but not the mission’s causal purpose, the player’s chosen conversational stance, how cleanly it was completed, what changed in the story, or what the player learned.
- If a completion line is not ready—or the game was reloaded—it falls back to a generic stock line at the most important payoff moment.

### Existing quality telemetry is useful but not yet a narrative quality gate

- Fallbacks and generation events are persistently logged.
- Current validators strongly protect objective consistency and placeholder removal.
- There is no automated measurement for logical reply relevance, knowledge leakage, unexplained proper nouns, causal visibility, persona drift, repeated mission patterns, repeated joke structures, or interaction latency percentiles.

## 3. Non-Negotiable Design Rules

- [ ] **Truth before prose:** code chooses a valid story cause, objective, facts, actors, locations, rewards, and consequences before a model writes a line.
- [ ] **Permissioned disclosure:** every story fact has an ID and disclosure state; player-facing prompts receive only allowed facts.
- [ ] **Questions are intents, not decorative strings:** code owns what each player option does. The model may phrase an allowed intent but may not redefine it.
- [ ] **No click-to-generate:** generation happens before the option is shown or in background dead time. A click consumes cached text.
- [ ] **No false continuity:** stale cache entries are discarded when their truth inputs change.
- [ ] **Mechanical repetition must not equal narrative repetition:** if a mechanic repeats, cause, stakes, wrinkle, giver, location, consequence, and reaction must materially change.
- [ ] **The player can ask for grounding:** a context-sensitive clarify option must appear whenever the brief relies on an unknown or ambiguous referent.
- [ ] **Silence is allowed:** N.O.V.A. and ambient NPCs do not need to comment on every event. A line that fires must be specific and worth hearing.
- [ ] **Humor follows character and pressure:** use dry/dark PG-13 humor as worldview and coping behavior, not as a mandatory punchline.
- [ ] **Fixed cast remains protected:** Kaelen and N.O.V.A. cannot be killed, deleted, permanently removed, or exposed through director-only secrets.
- [ ] **Models never change mechanics:** rewards, counts, targets, reputation deltas, timers, and branch consequences remain code-owned.
- [ ] **Fallbacks remain visible failures:** degraded delivery may protect the player experience, but diagnostics must still record why model-authored content was unavailable.

## 4. Target Architecture at a Glance

The implementation will evolve toward six owned layers:

1. **Campaign Narrative Graph** — large-model-authored causal nodes and fact ledger, validated and persisted.
2. **Living World + Knowledge Ledger** — code-owned chapter state, revealed facts, relationship state, and narrative revision counters.
3. **Mission Director** — code selects the next mechanically valid, narratively causal, non-repetitive contract skeleton.
4. **Character Director** — durable character cards and memories determine how each speaker interprets that skeleton.
5. **Conversation Compiler** — code defines dialogue acts and allowed questions; the small model renders a complete flat dialogue bundle.
6. **Narrative Cache Scheduler** — generates, validates, persists, TTS-caches, invalidates, and serves bundles before the player asks for them.

The runtime path must become:

`story cause -> valid mission skeleton -> allowed disclosure packet -> speaker card -> compiled dialogue bundle -> validation -> durable cache -> instant UI consumption -> outcome + knowledge writes`

## 5. Delivery Strategy

This is deliberately phased so a lower coding agent can complete and verify one safe slice at a time. Do not begin with prompt tuning. First make truth, state, and cache ownership explicit; then improve prose on top of stable contracts.

- [ ] Phase 0 — Baseline capture and feature flags.
- [ ] Phase 1 — Preserve narrative metadata through mission lifecycle.
- [ ] Phase 2 — Fact/knowledge ledger and disclosure-safe questions.
- [ ] Phase 3 — Causal mission director and anti-repetition pacing.
- [ ] Phase 4 — Durable character bibles and relationship memory.
- [ ] Phase 5 — Compiled mission conversations and instant branching.
- [ ] Phase 6 — Narrative cache scheduler and latency SLOs.
- [ ] Phase 7 — Outcome-aware Kaelen handoffs and turn-ins.
- [ ] Phase 8 — Campaign-aware N.O.V.A. movement/navigation reactions.
- [ ] Phase 9 — Instant, knowledge-aware lounge conversations.
- [ ] Phase 10 — Uniqueness/quality validators and designer tools.
- [ ] Phase 11 — Content migration, tuning, soak tests, and release gate.

Detailed file contracts, schemas, checklists, tests, acceptance thresholds, and rollback rules follow in the next sections.

## 6. Target Data Contracts

Use typed helper classes or rigorously validated dictionaries. Do not pass an unowned “context blob” from system to system. Every field below has an owner and a persistence rule.

### 6.1 Chapter Narrative Packet — the causal play plan

Add `scripts/persistence/ChapterNarrativePacketStore.gd` and persist `chapter_narrative_packets.json` inside the active campaign directory. The large story model generates the current packet and, later, the next packet before it is needed. The raw campaign bible remains the source of canon; packets may elaborate but may not contradict it.

Recommended document shape:

```jsonc
{
  "schema_version": 1,
  "document_type": "chapter_narrative_packets",
  "campaign_id": "campaign.x",
  "packets": [
    {
      "id": "chapter_packet.2",
      "chapter": 2,
      "story_revision": 7,
      "premise": "Player-safe one-line chapter pressure",
      "thread_ids": ["thread.convoy_shortage"],
      "facts": [
        {
          "id": "fact.convoy_shortage.visible",
          "subject_ids": ["faction.zenith", "system.start"],
          "aliases": ["the shortage", "missing convoy"],
          "rumored_text": "Freighters have stopped arriving on schedule.",
          "known_text": "A Zenith ore convoy was destroyed.",
          "confirmed_text": "The convoy loss caused the fabrication shortage.",
          "director_truth": "Hidden cause; never sent to the small model until promoted.",
          "question_label": "What happened to the ore convoy?"
        }
      ],
      "threads": [
        {
          "id": "thread.convoy_shortage",
          "surface_problem": "The station is short on fabrication ore.",
          "root_cause_fact_id": "fact.convoy_attack.hidden",
          "stake": "Shield maintenance will stop within two cycles.",
          "stakeholder_ids": ["faction.zenith", "npc.gen.x"],
          "eligible_objective_types": [
            "DELIVER_ORE",
            "DELIVERY_COURIER",
            "RECOVER_COMBAT_DROP",
            "KILL_SHIPS"
          ],
          "failure_consequence": "The shortage escalates; prices and patrol pressure rise.",
          "resolution_condition": "Resolve two required beats plus one reveal beat."
        }
      ],
      "mission_beats": [
        {
          "id": "beat.convoy_shortage.emergency_supply",
          "thread_id": "thread.convoy_shortage",
          "purpose": "Relieve immediate shortage while exposing evidence of the convoy loss.",
          "required": true,
          "eligible_objective_types": ["DELIVER_ORE", "PURCHASE_DELIVERY"],
          "preferred_giver_roles": ["Faction contact", "Station mechanic"],
          "required_fact_ids": [],
          "offer_fact_ids": ["fact.convoy_shortage.visible"],
          "clarify_fact_ids": ["fact.convoy_loss.rumor"],
          "accept_fact_ids": [],
          "complete_fact_ids": ["fact.convoy_shortage.confirmed"],
          "decline_effect": "Advance shortage pressure by one step; keep an alternate beat available.",
          "tone_pressure": "People are masking panic with procedure."
        }
      ]
    }
  ]
}
```

Generation and validation rules:

- Generate the first packet during new-campaign loading after the bible is accepted. The recommended trade is a slightly longer campaign start in exchange for zero interaction-time generation.
- Start generating chapter `N+1` when chapter `N` is roughly 60% consumed, not after it is exhausted.
- Use the proven labeled-block protocol, then assemble dictionaries in code. Do not ask the large model for deeply nested JSON.
- Code creates/normalizes stable IDs and rejects dangling references.
- A packet contains 1–3 active threads and 5–8 mission beats.
- Every active thread must support at least three currently implemented objective types; no thread may require the same objective type for consecutive required beats.
- At least one beat relieves pressure, one reveals information, and one changes the situation. A chapter cannot be six differently worded errands with the same dramatic function.
- Every agent-offered beat must reference the main campaign spine or a consequence of it. Public-board jobs may be local texture, but must still reference a real local pressure.
- Director-only text stays in this store. It is never copied wholesale into `StoryStateStore`, prompts, caches, UI, logs, or screenshots.
- Validation rejects future-faction leaks, plot-armor offenses, unavailable mechanics, empty stakes, missing disclosures, circular dependencies, and beat graphs that can stall if the player declines.
- Chapter packets are immutable campaign canon (`permanent`/append-only preparation). Beat availability/progress/outcome belongs in rewindable story state as `beat_states[beat_id]`; never write runtime status back into the packet.

### 6.2 Knowledge Ledger — what this player can reasonably ask or understand

Create `scripts/story/KnowledgeLedger.gd` as the only service that translates fact catalog entries into player knowledge. Persist only state and provenance in `story_state.json`; fact wording remains in the chapter packet.

```jsonc
{
  "knowledge_revision": 12,
  "knowledge_states": {
    "fact.convoy_shortage.visible": {
      "state": "known",
      "source": "npc.gen.contact_1",
      "learned_at_minute": 84,
      "confidence": "direct"
    },
    "fact.convoy_loss.rumor": {
      "state": "rumored",
      "source": "lounge_rumor",
      "learned_at_minute": 76,
      "confidence": "hearsay"
    }
  }
}
```

Allowed states: `unknown`, `rumored`, `known`, `confirmed`, `contradicted`. State transitions must be monotonic except an explicit contradiction event. The ledger API must include:

- `state_for(fact_id)`
- `can_reference(fact_id, minimum_state)`
- `promote(fact_id, state, source)`
- `public_fact_text(fact_id)`
- `question_candidates(mission_plan, already_asked)`
- `prompt_block(fact_ids)`
- `forbidden_tokens_for_context(allowed_fact_ids)`

Rules:

- Generation does not teach the player anything. Knowledge changes only when the line is actually displayed/heard or an event actually occurs.
- An NPC may mention an `offer_fact_id` in the opening; the UI then promotes it when the briefing is presented.
- Clarification answers can only use `clarify_fact_ids` and already known facts.
- An answer may increase knowledge from unknown to rumored/known, but cannot reveal a `complete_fact_id` early.
- Questions are ranked by actual knowledge gap, mission relevance, and conversational naturalness. Do not show “Who are the Zenith?” if the ledger says the player has completed three Zenith jobs.
- If there is no knowledge gap, replace “What do you mean?” with a more informed question such as “Why did the route fail now?” or “Who benefits if the shortage continues?”

### 6.3 Character Card v2 — identity that can produce consistent surprise

Migrate `CampaignNpcIdentityStore` to version 2. Keep permanent identity/presentation there and add stable inner-life and voice data. Add a separate rewindable `CampaignNpcStateStore.gd` for relationship and current stake. Event memories remain append-only chronicle records; the NPC state stores only current-timeline event references and a bounded projection. Seed ordinary characters with code-side trait axes; use the large model only to connect story-important characters to campaign threads during system/chapter preparation.

```jsonc
{
  "id": "npc.gen.x",
  "display_name": "Ivet Marr",
  "job_role": "Dock controller",
  "home_system_id": "system.x",
  "home_station_id": "station.x",
  "persona": {
    "core_drive": "Keep the crews under her watch alive.",
    "current_want": "Get replacement guidance relays before the next storm.",
    "fear": "Being blamed for a failure she predicted.",
    "contradiction": "Rules-first in public; quietly bends them for exhausted crews.",
    "social_strategy": "Tests competence before offering warmth.",
    "pressure_tell": "Becomes painfully precise.",
    "kindness_tell": "Solves practical problems without admitting it.",
    "verbal_habit": "Uses docking metaphors, never more than one per exchange.",
    "humor_mechanism": "deadpan bureaucratic understatement",
    "taboo": "Does not joke about decompression deaths."
  },
  "voice_rules": {
    "sentence_shape": "short, precise, one dry afterthought",
    "address_rule": "No private nickname; uses pilot rarely.",
    "favored_vocabulary": ["vector", "clearance", "queue"],
    "banned_tics": ["Shiny", "my friend", "as you know"]
  },
  "relationship": { // Runtime joined view; persisted in npc_states.json, not identity.
    "trust": 0,
    "respect": 1,
    "warmth": 0,
    "debt": 0,
    "last_player_stance": "unknown",
    "promises": []
  },
  "current_stake": { // Runtime joined view; rewindable state.
    "thread_id": "thread.convoy_shortage",
    "why_it_matters_to_them": "A failed relay puts six dock crews on manual vectors.",
    "urgency": 2
  },
  "memory_event_ids": [], // Runtime joined view; current-timeline chronicle refs.
  "memory_summary": "", // Bounded rewindable projection, rebuildable from refs.
  "line_memory_fingerprints": []
}
```

Trait rules:

- Pick traits from independent axes using campaign seed + NPC ID, then reject incompatible/duplicate combinations.
- A role is not a personality. Never use “mechanic = sarcastic” as the whole character.
- Each recurring character needs one contradiction, one pressure tell, one boundary/taboo, and one kindness tell. Those four details create more life than a long adjective list.
- Humor mechanisms rotate: deadpan understatement, grim practicality, misplaced optimism, pedantic correction, gallows arithmetic, literalism, weary anecdote, dad-joke deflection, and so on. Do not make every character “sarcastic.”
- The character card may shape phrasing but may not override faction truth, relationship state, or disclosure permissions.
- Update relationship numbers only through code-owned outcomes. Summarize memories after bounded event counts; never feed raw unlimited transcripts.
- Treat the JSON example as a joined runtime card. Permanent identity/persona/voice and rewindable relationship/stake/memory projection must remain separate persistence owners.

### 6.4 Mission Plan — code-owned playable truth

Add `scripts/story/MissionDirector.gd`. It produces a `MissionPlan` before any prose is requested.

Required fields:

```jsonc
{
  "offer_id": "offer.abc",
  "beat_id": "beat.convoy_shortage.emergency_supply",
  "thread_id": "thread.convoy_shortage",
  "story_revision": 7,
  "giver_npc_id": "npc.gen.x",
  "faction_id": "faction.zenith",
  "system_id": "system.start",
  "station_id": "station.start",
  "objective": {"type": "DELIVER_ORE", "amount_required": 45},
  "reward": {"credits": 280},
  "timing": {"timed": true, "duration_minutes": 55},
  "challenge": {
    "target_minutes": 12,
    "risk_band": "pressured",
    "complication_id": "complication.contested_belt"
  },
  "causality": {
    "public_because": "The station shield line has exhausted its ore buffer.",
    "stake": "Shield maintenance stops if the shipment misses this cycle.",
    "visible_consequence": "Shield-part prices and station threat rise.",
    "offer_fact_ids": [],
    "clarify_fact_ids": [],
    "complete_fact_ids": []
  },
  "conversation_intents": ["clarify", "why", "risk", "accept", "advance", "hazard_pay", "decline"],
  "context_fingerprint": "sha256..."
}
```

The plan owns objective values. Remove dummy-value substitution from the new path: the small model receives the actual, already validated facts and is never asked to invent mission data. Keep the old path behind a feature flag until migration completes.

Difficulty rules:

- Derive target workload from chapter, player ship capability, cargo capacity, recent success/failure, travel distance, faction relationship, and desired pacing.
- Keep a target time band for routine/pressured/dangerous jobs. Do not roll `20–300 m³` without regard to cargo capacity or mining rate.
- Complications come from an allowlisted code registry and must be executable by existing mechanics.
- Urgency changes mechanics: shorter deadline, higher pay, different patrol pressure, or a visible world consequence. It cannot exist only as an adjective in the dialogue.
- A cause such as “desperate for ore” must affect quantity, payout, timer, market/world pressure, or follow-up—not merely the opening line.

### 6.5 Mission Conversation Plan and Dialogue Bundle

Add:

- `scripts/story/MissionConversationPlan.gd` — chooses allowed dialogue acts and player intents from the mission plan + knowledge + relationship.
- `scripts/story/MissionConversationCompiler.gd` — builds the small-model prompt and code fallback phrasing.
- `scripts/story/DialogueBundleValidator.gd` — shape, fact, speaker, relevance, and uniqueness checks.

Use a flat output protocol because the current small model has proven more reliable with flat fields. One request writes the whole interaction; no button starts a generation request.

```jsonc
{
  "title": "The Buffer Is Gone",
  "opening": "The shield line is down to filings. I need forty-five cubic meters before the next maintenance cycle notices.",
  "q_clarify": "What do you mean, ‘the buffer is gone’ ?",
  "a_clarify": "The reserve bins are empty. One more repair order and the station starts choosing which decks stay protected.",
  "q_why": "What happened to the scheduled shipment?",
  "a_why": "It never arrived. Officially, a routing error. Unofficially, someone found wreckage and no manifest.",
  "q_risk": "How ugly is the mining route?",
  "a_risk": "Patrols are jumpy and the legal claims overlap. Mine fast, smile slowly.",
  "accept_standard": "Good. Forty-five, clean measure. Bring it here before the cycle turns.",
  "accept_advance": "I can front fuel money. It comes out of your final share, because arithmetic also has survival instincts.",
  "accept_hazard": "The risk is real. The revised figure is attached; so is my expectation that you return breathing.",
  "decline": "Then I ask someone cheaper, slower, and statistically more disposable.",
  "abandon": "The shield line still needs ore. Now it also needs a new pilot and an explanation.",
  "turn_in_clean": "That buys the station breathing room. The foreman may even stop aging visibly.",
  "turn_in_rough": "Ore received. Late, scorched, and still more useful than the procurement office."
}
```

Important: the example above illustrates shape only. It must not become a few-shot line that leaks verbatim into production.

Conversation behavior:

- The opening screen shows one salient knowledge-gap question, one terms/action menu, and standard acceptance. Back remains available as a true decline.
- Selecting a question shows its cached answer, promotes only its allowed fact IDs, records `asked_intents`, then presents remaining relevant questions and terminal choices.
- Asking never accepts the mission, spends credits, changes reputation, or spawns targets.
- Terminal choices are code-owned: standard acceptance, advance, hazard pay, or decline. Their mechanical consequences are computed before prose generation.
- A question disappears after it is answered. An informed follow-up can replace it only if a new fact makes that follow-up logical and its answer is already in the bundle.
- If a bundle field is invalid, use a fact-slot-aware code renderer for that field only and log degradation. Do not discard a valid whole bundle because one optional joke failed.
- The validator rejects answers that do not address their paired question, repeat the opening, claim knowledge not in the disclosure packet, reveal forbidden tokens, use another speaker’s nickname, alter objective numbers, or contain unsupported proper nouns.

### 6.6 Outcome Snapshot — the payoff remembers how it happened

Persist an `outcome_snapshot` on the active mission and update it through existing mission events:

```jsonc
{
  "accepted_choice_id": "hazard_pay",
  "clarification_fact_ids_heard": ["fact.convoy_loss.rumor"],
  "started_at_minute": 84,
  "completed_objective_at_minute": 96,
  "turn_in_at_minute": 102,
  "damage_taken_band": "heavy",
  "targets_destroyed": 3,
  "non_target_kills": 0,
  "partial_deliveries": 1,
  "deadline_band": "early",
  "cargo_overage": 0,
  "abandoned": false,
  "world_effect_ids": ["effect.station_shield_relief"]
}
```

This snapshot selects the correct pre-generated turn-in variant and gives future character memory a concrete event rather than “completed mission.” Never send a full combat log to a model.

### 6.7 Durable Narrative Cache

Add `scripts/persistence/NarrativeCacheStore.gd` with per-campaign `narrative_cache.json`. It is a persisted but disposable/rebuildable acceleration artifact, not canon or checkpoint truth. Every entry is keyed by semantic identity and truth revisions, not by UI screen.

```jsonc
{
  "cache_key": "sha256...",
  "kind": "mission_conversation",
  "subject_id": "offer.abc",
  "speaker_id": "npc.gen.x",
  "system_id": "system.start",
  "story_revision": 7,
  "knowledge_revision": 12,
  "relationship_revision": 3,
  "context_fingerprint": "sha256...",
  "status": "ready",
  "source": "small_model",
  "bundle": {},
  "text_fingerprints": [],
  "tts_ready_fields": [],
  "consume_policy": "once",
  "consumed": false,
  "created_at_minute": 82,
  "expires_at_minute": 180
}
```

Cache-key inputs:

- campaign ID;
- interaction kind and subject ID;
- speaker/NPC ID;
- system/station IDs;
- story/thread/beat revision;
- relevant knowledge fact states;
- relationship tier/revision;
- recent-line fingerprint digest;
- mission objective + code-owned choice consequences; and
- coarse player state bands only when the line explicitly depends on them.

Do not key on raw credits, hull points, or every minute tick unless the generated text includes those exact values. Excessive invalidation is another form of cache miss.

## 7. Runtime Ownership and Event Flow

### New-campaign preparation

1. Large model writes and validates the campaign bible.
2. Large model writes and validates chapter packet 1 while the loading experience is already active.
3. Code seeds fact states, story revisions, mission beats, and character story stakes.
4. Small model warms once.
5. Cache scheduler generates the first post-tutorial agent bundle, Kaelen handoff availability, the starting station’s likely lounge openers, and N.O.V.A.’s first chapter banks.
6. TTS caches all visible-first fields before the loading gate releases.

### Mission offer

1. MissionDirector selects an available beat and mechanically valid objective.
2. ConversationPlan derives allowable questions and terminal choices.
3. Cache scheduler renders/validates/persists the bundle before the agent button advertises ready work.
4. UI consumes cached fields only.
5. On acceptance, MissionAdapter preserves all narrative IDs, disclosure history, and the outcome snapshot.

### Mission completion and turn-in

1. Existing capability reports objective completion.
2. Cache scheduler raises the exact turn-in job to highest priority while the player is still in flight.
3. The selected turn-in line is chosen from the cached bundle/outcome bank at dock; no LLM call occurs at hand-in.
4. Quest completion updates thread progress, knowledge, relationship, pressure, chronicle, agent memory, and cache revisions atomically.
5. StoryManager queues the next beat/packet before the player asks for more work.

### NPC/lounges

1. Character cards and likely openers prepare during system generation/arrival.
2. A complete shallow reply bundle is generated per likely contact before the lounge card is actionable.
3. Reply clicks consume cached branches. If the conversation goes beyond the cached depth, end naturally or offer “talk later”; never display a waiting ellipsis for generation.

### N.O.V.A.

1. At chapter/system preparation, generate event banks from N.O.V.A.’s fixed persona, campaign quirk, current known story state, recent event streak summary, and allowed system facts.
2. Runtime movement events choose from those banks using code-owned severity, cooldown, relevance, and anti-spam logic.
3. Consumption records a fingerprint and schedules replenishment at low priority.

## 8. Implementation Phases and Checklists

Each checkbox should be completed with its tests before the next dependent item. When a phase changes a persisted schema, implement migration and rollback fixtures in the same checkbox—not later.

### Phase 0 — Baseline, flags, and measurable goals

**Goal:** capture how the game behaves now and make the evolution safely switchable. No player-facing behavior change.

Primary files:

- `scripts/diagnostics/GenerationDiagnostics.gd`
- `scripts/test_quest_gen.gd`
- `tests/story/`
- `tests/ai/`
- new `scripts/story/NarrativeRuntimeConfig.gd`
- new `docs/narrative_v2_baseline_YYYY_MM_DD.md`

Checklist:

- [ ] Add a single runtime configuration object with independent flags for `narrative_metadata_v2`, `knowledge_ledger_v2`, `mission_director_v2`, `conversation_bundle_v2`, `narrative_cache_v2`, `nova_bank_v2`, and `lounge_bundle_v2`. Default all flags off until their phase exit gate passes.
- [ ] Record diagnostic timestamps for `job_queued`, `generation_started`, `generation_finished`, `validation_finished`, `text_presented`, `tts_cache_started`, `tts_ready`, and `interaction_clicked`.
- [ ] Add percentile summaries for click-to-text, click-to-audio, queue wait, model generation, cache hit/miss, stale discard, and degraded-field rate.
- [ ] Extend the real-model quest harness to retain, per run: objective type, giver, cause/thread ID if present, title, opening, player options, answer relevance, generation duration, source, and validation repairs.
- [ ] Add a scripted baseline run for 30 agent offers, 12 lounge openers with one reply each, 30 N.O.V.A. eligible events, and 12 Kaelen turn-in scenarios. Do not tune from a three-sample anecdote.
- [ ] Save the worst five examples for each failure category: disconnected cause, assumed knowledge, irrelevant question, persona drift, repeated premise, repeated phrasing, generic turn-in, and visible wait.
- [ ] Record current fallback summary and model/VRAM profile in the baseline document.
- [ ] Add an explicit diagnostic assertion for any player-facing path that begins an LLM request after its button is clicked. Initially report only; Phase 6 converts it to a test failure for V2 paths.

Phase 0 exit gate:

- [ ] Baseline artifact is committed and reproducible.
- [ ] Feature flags can turn on one new subsystem without enabling the others.
- [ ] Diagnostics can answer “was this instant because of a cache hit, or did the UI hide a wait?”

### Phase 1 — Preserve narrative identity through the mission lifecycle

**Goal:** repair the existing continuity break before adding new story logic.

Primary files:

- `scripts/domain/MissionAdapter.gd`
- `scripts/domain/MissionDefinition.gd`
- `scripts/domain/MissionState.gd`
- `scripts/domain/MissionInstance.gd`
- `scripts/QuestManager.gd`
- `scripts/GameRoot.gd`
- `scripts/story/StoryManager.gd`
- `tests/domain/run_mission_contract_tests.gd`
- `tests/domain/run_mission_instance_tests.gd`
- `tests/story/run_story_manager_hook_tests.gd`

Checklist:

- [ ] Define allowed narrative metadata fields: `offer_id`, `story_thread_id`, `story_beat_id`, legacy `story_hook_ref`, `cause_id`, `public_because`, `stake`, `question_fact_ids`, `completion_fact_ids`, `conversation_cache_key`, `conversation_state`, and `outcome_snapshot`.
- [ ] Copy those fields from offer -> definition -> active state -> checkpoint -> restored state -> completed/abandoned/expired detail signal.
- [ ] Add validation for ID shape and dictionary/array types. Treat missing fields as valid legacy data; reject malformed present fields.
- [ ] Add a legacy migration/default path so existing saves load with empty narrative metadata.
- [ ] Add a regression test proving the current `story_hook_ref` survives acceptance and reaches `StoryManager.on_quest_completed()`.
- [ ] Add a regression test proving one completed mission resolves exactly its stamped hook and not the first current hook by accident.
- [ ] Preserve metadata in chronicle payloads and `CampaignAgentMemorySnippetStore` metadata.
- [ ] Replace the global `user://quest_history.md` as a generation source with a per-campaign structured query over chronicle/agent memory. Keep the markdown file only as legacy import/human debug output.
- [ ] Record accepted choice ID—not only player-facing text—so later reactions do not depend on parsing prose.
- [ ] Increment a `mission_history_revision` whenever an offer is accepted, declined, completed, abandoned, or expired.

Phase 1 exit gate:

- [ ] A stamped mission resolves its intended story hook after save/reload.
- [ ] Campaign A history cannot enter Campaign B prompts.
- [ ] Existing saves and the authored tutorial still load and complete.

### Phase 2 — Knowledge ledger and disclosure-safe context

**Goal:** make “what the player knows” executable game state rather than a prose suggestion.

Primary files:

- new `scripts/story/KnowledgeLedger.gd`
- new `scripts/ai/ContextBlockBuilder.gd`
- `scripts/persistence/StoryStateStore.gd`
- `scripts/story/StoryManager.gd`
- `scripts/persistence/CampaignBibleStore.gd`
- `scripts/LLMInterface.gd`
- new `tests/story/run_knowledge_ledger_tests.gd`
- new `tests/persistence/run_narrative_checkpoint_state_tests.gd`
- new `tests/ai/run_context_block_leak_tests.gd`
- `tests/persistence/run_story_state_bible_seed_tests.gd`

Checklist:

- [ ] Bump `StoryStateStore.DOCUMENT_VERSION` and add an explicit `_migrate_legacy_state()` path. Backfill `story_revision = 0`, `knowledge_revision = 0`, `mission_history_revision = 0`, `knowledge_states = {}`, and `beat_states = {}` without losing existing `player_knows`.
- [ ] Validate every new field’s type/range and increment revisions only through owned write methods; callers must not mutate the dictionaries directly.
- [ ] Convert existing `player_knows` strings into legacy fact records with deterministic IDs; keep them readable in prompt projections.
- [ ] Implement monotonic fact promotion and provenance recording.
- [ ] Centralize public context creation in `ContextBlockBuilder`; stop individual callers from reaching directly into raw story/bible dictionaries.
- [ ] Provide separate blocks for mission offers, mission answers, character conversation, ambient chatter, N.O.V.A., Kaelen, and large-model director calls.
- [ ] Make every block allowlist-based. A new schema field is private until explicitly projected.
- [ ] Salt director-only fields with test tokens and assert no small-model block contains them.
- [ ] Add `KnowledgeLedger.question_candidates()` using required facts, current states, aliases, and already-asked intents.
- [ ] Promote a fact only after UI delivery, not after bundle generation or cache fill.
- [ ] Add contradiction support so rumors can be corrected later without deleting the history that the player once believed them.
- [ ] Replace free-form “open story threads” prompt text with public projections by stable thread/fact ID.
- [ ] Keep the old `player_knows` array synchronized during the transition, then deprecate direct writes once all call sites use the ledger.
- [ ] Make rewind ownership real: capture `story_state` (including knowledge/beat/revisions) in safe checkpoint state and apply it before prompt/cache restoration. Add a death-rollback test proving facts and beat progress earned after the restored checkpoint do not survive on the new timeline.

Phase 2 exit gate:

- [ ] A player with no knowledge receives a grounding question; an informed player receives a deeper question.
- [ ] Asking one question promotes only its declared facts.
- [ ] Secret-salted leak tests pass for every small-model capability.
- [ ] Old campaigns load with equivalent player-visible knowledge.

### Phase 3 — Chapter packets, causal mission direction, and challenge pacing

**Goal:** stop rolling disconnected job types and start selecting playable steps in the campaign story.

Primary files:

- new `scripts/persistence/ChapterNarrativePacketStore.gd`
- `scripts/persistence/CampaignSchemaCatalog.gd`
- new `scripts/ai/ChapterNarrativeDirector.gd`
- new `scripts/story/MissionDirector.gd`
- new `scripts/story/MissionHistoryLedger.gd`
- new `scripts/story/ChallengeBudget.gd`
- `scripts/ai/LocalModelGateway.gd`
- `scripts/ai/NarrativeDirector.gd`
- `scripts/story/StoryManager.gd`
- `scripts/GameRoot.gd`
- `scripts/domain/MissionTemplateRegistry.gd`
- `scripts/domain/MissionCapabilityRegistry.gd`
- new `tests/ai/run_chapter_narrative_director_tests.gd`
- new `tests/persistence/run_chapter_narrative_packet_store_tests.gd`
- new `tests/story/run_mission_director_tests.gd`
- new `tests/story/run_challenge_budget_tests.gd`

#### Phase 3A — Packet generation and persistence

- [ ] Add `chapter_plan` as a `large_story` capability with explicit timeout/context/VRAM behavior through `LocalModelGateway`.
- [ ] Build the packet prompt exclusively from director context, validated entities, available mission capabilities, recent player choices, and unresolved story state.
- [ ] Use labeled blocks; implement parser aliases, shape repair, semantic validation, correction retry, and loud failure status.
- [ ] Generate packet 1 before post-tutorial gameplay releases. Report its loading stage separately from the campaign bible.
  - 2026-07-13: Health check found loading could strand at 96% when the large model repeatedly returned invalid chapter packets. Added a code-owned fallback chapter packet commit path after correction retry failure, with fallback diagnostics and normal first-interaction prefetch queuing.
- [ ] Generate packet N+1 when N is 60% consumed. Never wait for the final beat to finish before starting.
- [ ] Persist packets transactionally and append-only. Horizon expansion may add a packet; it may not rewrite completed beats.
- [ ] Register packet ownership in `CampaignSchemaCatalog` as permanent prepared canon; keep mutable `beat_states` in rewindable `StoryStateStore`.
- [ ] Add DevPanel visibility for current/next packet, threads, facts by privacy tier, beat states, and validation failures.

#### Phase 3B — Mission selection

- [ ] Create a feasible candidate for each available beat × supported objective type × eligible local giver.
- [ ] Hard-reject candidates whose mechanics, target, destination, item, or NPC do not exist now.
- [ ] Score remaining candidates with documented weights: causal fit (0–40), beat urgency (0–20), variety/pacing (0–20), character stake (0–10), player preference/ship fit (0–10).
- [ ] Enforce: never three identical agent objective types consecutively.
- [ ] Enforce: no objective type appears more than twice in the last four accepted agent contracts unless no other valid story beat exists. If no alternative exists, withhold the offer and generate/activate an alternate beat; do not silently break the rule.
- [ ] Enforce: no repeated mission premise fingerprint in the last eight agent offers.
- [ ] Enforce: a repeated mechanic must change at least three of cause, stake, giver, location, complication, faction, disclosure, or world consequence.
- [ ] Add agent templates for the already implemented `DELIVERY_COURIER`, `PURCHASE_DELIVERY`, `RECOVER_COMBAT_DROP`, and `TARGET_WITH_COMMS_REVERSAL` capabilities before inventing a new mechanic.
- [ ] Preserve public-board identity: it can remain weird local Craigslist texture, but each posting receives a real system pressure/cause ID when available.
- [ ] Record declined offers and cool them down; do not immediately rephrase and reoffer the same beat.
- [ ] Ensure declining a required beat activates an alternate approach or advances its failure consequence. The campaign cannot stall because the player said no.

#### Phase 3C — Challenge and consequence budget

- [ ] Compute target duration from current ship/cargo/combat capability and chapter pacing.
- [ ] Derive ore amount from cargo capacity, expected mining rate, and target trips—not an unconstrained random range.
- [ ] Derive kill workload from enemy strength/role and player build—not count alone.
- [ ] Derive courier/purchase workload from route length, stores, cargo state, and faction hostility.
- [ ] Tie urgency to code-owned deadline/reward/pressure consequences.
- [ ] Add difficulty bands `routine`, `pressured`, `dangerous`, `story_climax`; constrain how often each can appear.
- [ ] Apply a recovery beat after repeated failure or severe hull loss; challenging must not become a punishment spiral.

Phase 3 exit gate:

- [ ] A deterministic 100-offer simulation produces zero illegal objectives, zero three-in-a-row types, and no unresolved required beat after decline.
- [ ] Every agent offer has a valid thread/beat ID and a player-safe cause.
- [ ] Completing/declining/abandoning a mission produces a visible story-state consequence.
- [ ] Mining twice can happen only when narratively distinct and separated according to the streak rules.

### Phase 4 — Character cards, relationships, and memories that matter

**Goal:** make recurring NPCs recognizable as people, not faction-flavored text generators.

Primary files:

- `scripts/persistence/CampaignNpcIdentityStore.gd`
- new `scripts/persistence/CampaignNpcStateStore.gd`
- `scripts/persistence/CampaignSchemaCatalog.gd`
- `scripts/persistence/CampaignAgentMemorySnippetStore.gd`
- new `scripts/story/CharacterDirector.gd`
- new `data/content/character_trait_axes.json`
- `scripts/GlobalState.gd`
- `scripts/generation/GeneratedSystemNPCManager.gd`
- `data/content/llm_dialogue_content.json`
- `scripts/registry/LLMDialogueContentRegistry.gd`
- `scripts/UIManager.gd`
- `tests/persistence/run_campaign_npc_identity_store_tests.gd`
- new `tests/persistence/run_campaign_npc_state_store_tests.gd`
- new `tests/story/run_character_director_tests.gd`

Checklist:

- [ ] Bump NPC identity schema to v2 with migration from the current broad tags and summary.
- [ ] Keep identity/persona/voice permanent in `CampaignNpcIdentityStore`; do not mutate them for relationship events.
- [ ] Create rewindable `CampaignNpcStateStore` for relationship, current stake, current-timeline memory refs/projection, and revision fields defined in §6.3.
- [ ] Register/document ownership in `CampaignSchemaCatalog`: identity permanent, relationship/stake projection rewindable, underlying events append-only in the chronicle.
- [ ] Build an editable trait-axis registry with incompatibility rules and campaign-wide recent-combination memory.
- [ ] Deterministically generate complete cards from campaign seed + NPC ID so reload never changes a person.
- [ ] Connect story-important NPC stakes to chapter threads during system/chapter preparation.
- [ ] Wire `llm_dialogue_content.json` speaker cards into live prompt construction; remove the current state where they are documentation only.
- [ ] Preserve Kaelen-only `Shiny`, enemy no-name rules, and per-speaker banned tics in validation.
- [ ] Replace name-based lounge warmth keys with stable NPC IDs; migrate existing values where a unique display-name match exists.
- [ ] Update relationship through code-owned events: accepted/refused help, completed/failed work, keeping/breaking promises, conversation stance, drink warmth, and discovered betrayal.
- [ ] Record bounded memory event IDs and periodically rebuild a concise memory summary from structured events. Do not ask the small model to invent what happened.
- [ ] Feed only the relevant 3–6 memories and current stake into an interaction prompt.
- [ ] Use per-NPC line fingerprints to reject exact and near-repeated lines, not just store hashes without enforcement.
- [ ] Add a debug “character card” viewer showing inner-life, public knowledge, relationship, current stake, last memories, and recent lines.
- [ ] Capture/restore `CampaignNpcStateStore` with safe checkpoints (or deterministically rebuild it from the restored chronicle head); test that post-checkpoint trust/debt/stake changes roll back while permanent identity/persona do not.

Phase 4 exit gate:

- [ ] The same NPC retains voice/personality/relationship across reload and system return.
- [ ] Five generated NPCs in one station do not share the same humor mechanism or contradiction.
- [ ] An NPC can naturally recall a real prior event and cannot claim an event absent from memory.
- [ ] Relationship changes alter tone and available information without letting the model change numeric consequences.

### Phase 5 — Compiled mission conversations and logical player questions

**Goal:** replace three disguised accept buttons with an instant, coherent conversation.

Primary files:

- new `scripts/story/MissionConversationPlan.gd`
- new `scripts/story/MissionConversationCompiler.gd`
- new `scripts/story/MissionConversationController.gd`
- new `scripts/story/DialogueBundleValidator.gd`
- `scripts/LLMInterface.gd`
- `scripts/UIManager.gd`
- `scripts/QuestManager.gd`
- `scripts/domain/MissionConsequenceDefinition.gd`
- `data/content/llm_dialogue_content.json`
- new `tests/story/run_mission_conversation_plan_tests.gd`
- new `tests/story/run_dialogue_bundle_validator_tests.gd`
- new `tests/story/run_mission_conversation_controller_tests.gd`

Checklist:

- [ ] Build a code-owned intent registry: `clarify_term`, `ask_why`, `ask_risk`, `ask_connection`, `accept_standard`, `request_advance`, `request_hazard_pay`, `decline`, and optional informed follow-up.
- [ ] Gate each intent by knowledge, relationship, mission facts, and mechanical availability.
- [ ] Generate a flat complete bundle in one small-model request using actual mission values. The model writes prose only.
- [ ] Require each question to name/reference its intended subject and each answer to contain at least one allowed answer anchor.
- [ ] Validate pair relevance, allowed facts, objective consistency, speaker ownership, length, PG-13 safety, persona voice, nickname ownership, and uniqueness.
- [ ] Add field-level repair/degradation so one invalid optional response does not erase valid content.
- [ ] Introduce `MissionConversationController` as a pure state machine. Keep `UIManager` responsible for labels/buttons/portraits/TTS, not conversation rules.
- [ ] Initial screen: show the most important grounding question when one exists, a “terms/other questions” path, and standard acceptance. Preserve a visible Back/Decline path.
- [ ] Question buttons display cached answers and return to remaining choices. They never call `QuestManager.accept_quest()`.
- [ ] Terminal choices pass a stable choice ID plus code-owned consequence to `QuestManager.accept_quest()`.
- [ ] A true decline records a player choice/relationship effect and leaves the mission lane empty.
- [ ] Persist asked question IDs and learned facts on accepted missions so Kaelen/NPC callbacks can reference what the player pressed them about.
- [ ] TTS-cache opening, answers, and terminal responses before making the offer actionable.
- [ ] Remove the UI hard cap’s assumption that the model owns exactly three flat choices. The controller may still show at most three primary buttons per view for controller clarity.
- [ ] Keep the current dummy-substitution quest path behind a flag until V2 bundle soak tests pass; then delete it and its duplicate hardcoded persona/example blocks in a dedicated cleanup commit.

Phase 5 exit gate:

- [ ] Asking “what do you mean?” produces an answer and does not accept the mission.
- [ ] Questions differ correctly between unknown, rumored, and informed player states.
- [ ] All terminal choices apply exactly their code-owned consequences.
- [ ] No bundle answer reveals a completion-only or director-only fact in salted leak tests.
- [ ] Controller navigation is correct by mouse, keyboard, and gamepad focus order.

### Phase 6 — Narrative cache scheduler and “no click-to-generate” guarantee

**Goal:** make post-tutorial conversation feel local and immediate even though local models are doing the writing.

Primary files:

- new `scripts/story/NarrativeCacheScheduler.gd`
- new `scripts/persistence/NarrativeCacheStore.gd`
- `scripts/persistence/CampaignSchemaCatalog.gd`
- `scripts/LLMInterface.gd`
- `scripts/ai/LocalModelGateway.gd`
- `scripts/UIManager.gd`
- `scripts/speech/SpeechService.gd`
- `scripts/GameRoot.gd`
- `scripts/PlayerInteractionQueue.gd`
- new `tests/story/run_narrative_cache_scheduler_tests.gd`
- new `tests/persistence/run_narrative_cache_store_tests.gd`
- new `tests/story/run_narrative_cache_invalidation_tests.gd`

#### Phase 6A — Central job scheduler

- [ ] Route all small-model narrative work through one scheduler queue instead of allowing quest, mechanic, chatter, lounge, and reaction requests to contend independently.
- [ ] Allow at most one small-model generation request in flight by default. Make concurrency a measured configuration, not an accidental side effect.
- [ ] Preserve the campaign-bible/large-model priority gate. Pause small jobs, cancel only safe unstarted work, and resume in priority order after the large job releases VRAM.
- [ ] Define priorities: P0 objective-complete turn-in/current visible station; P1 current-system agent/Kaelen/N.O.V.A.; P2 likely lounge/mechanic/nearby system; P3 ambient replenishment.
- [ ] Deduplicate queued jobs by cache key and fan out callbacks to the one result.
- [ ] Support cancellation by campaign, story revision, system, station, NPC, and subject ID.
- [ ] Log queue starvation, contention, cancellation, retry, and time-to-ready.

#### Phase 6B — Cache lifecycle

- [x] Open/validate `NarrativeCacheStore` with the other campaign stores in `GameRoot`; mark it disposable/rebuildable in the ownership table.
- [x] On death rollback, discard entries whose timeline/context revisions do not match restored state and rebuild them. Never let cache content influence canonical rollback selection.
- [x] Implement semantic cache keys from §6.7.
- [x] Invalidate unconsumed offers when their story beat, giver, destination, objective, allowed facts, or relationship tier changes.
- [x] Do not invalidate an accepted mission’s conversation/turn-in bundle merely because the global story revision advanced; accepted mission truth is frozen and travels with the mission.
- [x] Mark one-shot lines consumed after actual display, not when read from disk.
- [x] Bound cache by entry count and bytes. Recommended first limits: 256 text bundles and 8 MB JSON; evict consumed/expired lowest-priority entries first.
- [x] Store text fingerprints even after text eviction so a long campaign cannot immediately regenerate the same line.
- [x] Clear all campaign-specific cache entries on new campaign/restart; never share exact line caches across campaigns.

#### Phase 6C — Generation and retry policy

- [x] Replace sequential best-of-three quest calls with one tightly constrained bundle call.
  - 2026-07-13: Legacy live quest generation now makes one constrained quest-bundle model call instead of a sequential best-of-three candidate batch; validation/scoring still gates the returned bundle before display, and failures now log as `quest_bundle_failed`.
- [x] If validation fails, retry once in the background with precise field errors. Do not expose the offer until valid or degraded.
  - 2026-07-13: Narrative cache workers now pass validation/build errors through the scheduler's one-retry path before `degraded_required`; failed payloads are not marked ready or exposed.
- [x] Build a deterministic, fact-slot-aware emergency composer for required fields. Its output must still include the real speaker, cause, stake, objective, and relationship; it is logged as degraded content.
  - 2026-07-13: Template-safe story-agent offers now stamp deterministic fallback conversation bundles as degraded/fallback content and record them in generation diagnostics, while preserving speaker, cause, stake, objective, and relationship coverage.
- [x] Never show “checking requests…”, “Listening…”, or `...` while a model call runs on a V2 interaction. If content is not ready, either keep the button in a non-intrusive “work pending” state before selection or serve a validated degraded bundle instantly.
  - 2026-07-13: Agent-board contact offers now show an actionable no-ready-contract state with Back available instead of “checking client contract requests...” while cache/generation finishes.
  - 2026-07-13: Lounge opener/reply and stranger-offer model waits now show actionable pending states with Step away / Walk away choices instead of “Listening...” or `...`.
- [x] Do not use a generic Kaelen line as fallback for a different NPC.
  - 2026-07-13: Cleaned-empty choice responses now use a voice-aware fallback: Kaelen may use Kaelen fallback lines, while non-Kaelen quest givers receive neutral contract text; source guard coverage prevents direct reuse from returning.

#### Phase 6D — TTS readiness

- [x] Cache audio immediately after a text bundle validates, in the same priority order as text.
  - 2026-07-13: Narrative cache workers now extract the actual visible text bundle fields, queue same-priority `tts_cache` jobs immediately after validation, and start those cache requests without blocking text readiness.
- [x] Track TTS readiness per field, voice profile, and text fingerprint.
  - 2026-07-13: Runtime `tts_cache` jobs now persist field-level audio status (`pending`, `ready`, or `failed`) through `NarrativeCacheStore.mark_tts_status()`, keyed by field and voice profile with the store-owned text fingerprint.
- [x] Add pre-recorded non-semantic filler clips for N.O.V.A. and Kaelen (`um`, `oh`, `well`, `ahh`) that can play only during short quiet waits for LLM/TTS readiness. Treat them as latency masking, not dialogue content: they must never replace required text, advance state, reveal facts, or count as a generated line.
  - 2026-07-13: `SpeechService` now pre-caches and safety-gates Kaelen/N.O.V.A. latency fillers before playback; agent-board/lounge waits can use Kaelen fillers, and campaign/chapter loading waits can use N.O.V.A. fillers without counting them as dialogue/generated content.
- [x] Make the UI actionable when required visible fields are text-ready; prefer to wait for their audio during natural pre-entry time, never after the click.
  - 2026-07-13: Guarded the ready-offer ordering so generated/cached offer text reaches the agent board before any loading-screen audio-cache wait; audio waits remain limited to natural pre-entry/loading gates, while selected interactions use actionable pending states or ready text.
  - 2026-07-13: Fresh-campaign loading now blocks only on a bounded starter subset of Kaelen/N.O.V.A. line-bank TTS, then warms the full startup banks after loading releases.
  - 2026-07-13: Narrative cache writes now auto-enforce the default 256-entry / 8 MB bounds on every upsert, while preserving text fingerprints for evicted lines.
  - 2026-07-13: Checkpoint restore now discards disposable narrative-cache entries whose timeline/story/knowledge/mission revisions do not match the restored checkpoint, while truth-frozen accepted bundles are preserved.
- [x] Prevent obsolete TTS jobs from delaying current P0 fields.
  - 2026-07-13: Scheduler coverage now locks `tts_cache` work into an `audio_pending` state after cache start, so it no longer consumes the generation lane or blocks fresh P0 text jobs; same-priority queued text still dispatches before queued audio.
- [x] Preserve subtitles if TTS fails; record the audio failure separately from text-source degradation.
  - 2026-07-13: `tts_failed` is now a first-class diagnostics lifecycle event for TTS parse/request failures, while scheduler/store coverage keeps ready text/subtitles separate from audio failure/degradation state.

#### Phase 6E — Prefetch triggers

- [x] New campaign: first post-tutorial offer, its player questions/answers, Kaelen handoff, and first likely N.O.V.A. banks before loading release.
  - 2026-07-13: With Phase 6D readiness complete, the existing `new_campaign_loading` planner/worker path now covers the startup station offer, its mission-conversation bundle fields, Kaelen handoff bank, N.O.V.A. bank, and first chapter interaction bundle before release; tests guard the six-job startup bundle.
  - 2026-07-12: `4cbfd54`/`9da52eb` added a central `new_campaign_loading` prefetch event and queues it before fresh-campaign loading release. Existing opening-contract/TTS generation still handles the first visible offer; remaining work is a real scheduler worker/ready gate for the new Kaelen/N.O.V.A. bank jobs.
  - 2026-07-12: Added worker and consumer support for template-safe current-station offer jobs. The background agent-board path can now use a ready station-offer payload before fresh generation, while Kaelen/N.O.V.A. startup banks remain open.
  - 2026-07-12: Added the first safe Kaelen/N.O.V.A. line-bank worker path. The scheduler can now turn startup/system Kaelen and N.O.V.A. bank jobs into ready `story_line_bank` payloads using public context only. Follow-up: consume those banks at runtime and replace the template seed lines with richer validated model-authored banks.
  - 2026-07-12: Fresh-campaign loading now asks for the ready Kaelen/N.O.V.A. startup line banks and pre-caches their TTS before releasing the loading overlay when there is audio work to do.
  - 2026-07-12: Kaelen's agent-handoff intro now consumes a ready `agent_handoff` line from the current-system Kaelen line bank before using the older canned fallback. A unique LLM handoff still wins if it is already ready.
  - 2026-07-12: Added the pure `FallbackLineBank` foundation for quality Kaelen/N.O.V.A. fallback banks: target size defaults to 20, consumption marks fallback use, and later generated lines replace used fallback slots without being mislabeled as fallback content. Follow-up: wire this into runtime bank storage and generation refresh.
  - 2026-07-12: Upgraded the Kaelen/N.O.V.A. line-bank cache worker to emit real `fallback_bank` payloads with 20 quality fallback lines, fallback-bank metadata, and public-context-only speaker blocks. Follow-up: persist consumption and replace used fallback slots with validated generated lines.
  - 2026-07-12: Runtime Kaelen and N.O.V.A. speech paths now consume one ready fallback-bank line through `consume_cached_narrative_line_bank`, while TTS warmup continues to read without spending bank entries. Follow-up: persist this consumption across save/load and feed used slots into generated replacement refresh.
  - 2026-07-12: Added the generated-line replacement hook: successful Kaelen unique handoff generation now offers the line back to the current-system Kaelen fallback bank, replacing a used fallback slot when one exists without relabeling generated content as fallback.
  - 2026-07-12: Added behavior coverage proving ready scheduler payload updates fan out to every requester on a deduped job, protecting fallback-bank consume/replace state sharing.
  - 2026-07-12: Added a `NarrativeCacheStore.update_result_payload()` persistence foundation and coverage showing fallback-bank result payload state can survive reopen. Follow-up: call it from the live scheduler/GameRoot consume and replacement paths.
  - 2026-07-12: Wired GameRoot ready-payload persistence: successful cache workers now upsert ready payloads into `NarrativeCacheStore`, and fallback-bank consume/replace mutations update the persisted result payload when a campaign cache store is loaded.
  - 2026-07-12: Restored persisted ready narrative cache payloads into the scheduler when a campaign cache store opens, so saved fallback-bank state can be used after load instead of starting from an empty in-memory scheduler.
  - 2026-07-12: Added fallback-bank replacement cap coverage proving generated lines do not overfill a full unused 20-line fallback bank.
  - 2026-07-13: Extended scheduler diagnostics with ready payload content-type/source counts plus fallback-use and generated-replacement totals, so cache health can show whether line banks are being consumed or refreshed.
  - 2026-07-13: Surfaced the narrative cache payload-source summary in the DevPanel story bridge line, including ready payload count, content/source counts, fallback uses, and generated replacements.
  - 2026-07-13: Added ready-cache lookup hit/miss counters to scheduler diagnostics so manual and automated checks can distinguish cache hits from misses.
  - 2026-07-13: Added ready-cache hit/miss counts to the DevPanel narrative cache summary line.
  - 2026-07-13: Added `interaction_clicked` stamping for ready cached contact/station offers and consumed line-bank speech, plus `ready_to_click` timing in scheduler diagnostics. Read-only TTS warmup still does not stamp clicks.
  - 2026-07-13: Added interaction click count and ready-to-click average to the DevPanel narrative cache summary.
  - 2026-07-13: Added p50/p95 seconds to scheduler duration summaries, giving Phase 6 a direct percentile metric for queue, generation, validation, ready, and ready-to-click timing.
  - 2026-07-13: Added ready-to-click p95 to the DevPanel narrative cache summary line.
  - 2026-07-13: Added degraded job count/rate to scheduler diagnostics so fallback/degraded delivery remains measurable.
  - 2026-07-13: Added degraded job count/rate to the DevPanel narrative cache summary line.
  - 2026-07-13: Mirrored ready cached narrative interaction clicks into GenerationDiagnostics so existing report-only click-to-generate detection can see cached narrative UI/runtime consumption.
- [x] On target/fly-to station: current station agent offer, mechanic greeting, likely lounge openers.
- [x] On system arrival: one valid offer for each available story-relevant contact, plus system N.O.V.A./ambient banks.
  - 2026-07-12: `ff99985`/`6bdbfe0` added planner/runtime wiring for system-arrival current-system agent, Kaelen, N.O.V.A., and visible-station prefetch jobs. Full valid-offer-per-contact generation remains open.
  - 2026-07-12: `6ad647c`/`a3ec983` added contact-profile aware system-arrival jobs for registered faction agents and generated station faction contacts. Follow-up remains: execute/validate those queued contact-offer jobs into ready mission offers.
  - 2026-07-12: Added the first scheduler worker/ready gate for system contact offers. It consumes queued contact-offer jobs only when the deterministic story-offer builder can produce a validated template offer, then marks the scheduler job ready with a cached quest payload. Follow-up remains: broader worker coverage for non-template offer candidates plus Kaelen/N.O.V.A./ambient bank content.
  - 2026-07-12: Wired the agent board to ask for a ready cached contact offer before starting fresh quest generation. The lookup is requester-specific, so talking to one contact does not consume another contact's queued prefetch work.
  - 2026-07-12: Added scheduler worker coverage for current-system Kaelen and N.O.V.A. bundle jobs. These now become ready `story_line_bank` payloads with speaker, voice, line IDs, and safe public context for later runtime consumption.
  - 2026-07-12: N.O.V.A.'s system-arrival path now consumes a ready current-system `story_line_bank` line before falling back to stock arrival text, while preserving existing chance/cooldown/silence behavior.
  - 2026-07-12: System-arrival UI notification now warms Kaelen/N.O.V.A. current-system line-bank TTS in the background after arrival prefetch jobs are queued.
  - 2026-07-13: Added a guarded system-arrival batch drain for `system_contact_offer_bundle` jobs, so contact-aware arrival bursts can build one ready deterministic offer per contact when chapter-packet context is available.
  - 2026-07-13: Added low-priority system-arrival ambient pool jobs and a safe `ambient_chatter` fallback-bank worker, giving ambient refill work real ready payloads without outranking offers, Kaelen, or N.O.V.A.
  - 2026-07-13: Extended the deterministic story-agent offer builder to cover every objective type the chapter director can assign (`KILL_SHIPS`, `DELIVER_ORE`, `PICKUP_SPECIAL`, `DELIVERY_COURIER`, `PURCHASE_DELIVERY`, `RECOVER_COMBAT_DROP`, `TARGET_WITH_COMMS_REVERSAL`). This closes the remaining non-template contact-offer skip path for system-arrival prefetch.
- [x] On mission acceptance: persist baseline abandon and likely outcome variants.
- [x] On objective progress >= 70%: refresh outcome snapshot and queue likely turn-in variants.
- [x] On objective completion: P0 exact turn-in generation while the player travels back.
- [x] On chapter 60% consumed: next chapter packet and its first interaction bundles.
- [x] On cache pool below threshold: refill only when no higher-priority work exists.

Phase 6 exit gate / service-level objectives:

- [ ] 0 post-tutorial dialogue-option clicks start an LLM request in automated V2 flow tests.
  - 2026-07-13: Added `GenerationDiagnostics.assert_no_click_to_generate_reports()` so automated V2 flow tests have a direct fail/pass gate once report-only click-to-generate detection is promoted.
  - 2026-07-13: Surfaced the current click-to-generate report count in the DevPanel story bridge narrative-cache summary for manual V2 flow checks.
  - 2026-07-13: Added an automated cached dialogue-option V2 flow fixture that records contact-offer, station-offer, clarify-question, and accept-choice clicks, presents ready cached/bundled text, and fails through `assert_no_click_to_generate_reports()` if any generation starts after the click. Full gate remains open until broader runtime smoke coverage exercises the real UI paths end-to-end.
- [ ] p95 click-to-text <= 100 ms on a warm local run.
  - 2026-07-13: Added `GenerationDiagnostics.assert_percentile_slo()` so warm-run tests can fail directly when `click_to_text_ms.p95` exceeds the 100 ms target. The checkbox remains open until fed by real warm local flow samples.
- [ ] p95 click-to-cached-audio start <= 300 ms on a warm local run.
  - 2026-07-13: The same SLO helper can now gate `click_to_audio_ms.p95` against the 300 ms target and fails loudly when no samples exist. The checkbox remains open until warm cached-audio samples are collected.
- [ ] >= 99% required-field cache readiness at interaction time in a 2-hour soak.
  - 2026-07-13: Added `NarrativeCacheScheduler.assert_cache_readiness_slo()` so soak tests can fail on missing samples or ready-cache hit rate below 99%. The checkbox remains open until exercised by a 2-hour interaction run.
- [x] No stale bundle survives a relevant story/knowledge/relationship mutation.
  - 2026-07-13: Extended invalidation coverage so disposable store entries and queued scheduler jobs are removed for stale story beats, allowed-facts fingerprints, and relationship tiers while accepted/frozen truth survives. Rewind/context discard coverage remains in the store/scheduler restore path.
- [x] Model contention cannot reproduce the current ~40-second sequential quest path.
  - 2026-07-13: Re-verified the two guards that close this failure mode: `LLMInterface` uses a single constrained quest-bundle call instead of sequential best-of-three attempts, and `NarrativeCacheScheduler` keeps small-model work bounded to one in-flight generation by default with contention/starvation diagnostics.

### Phase 7 — Kaelen as the campaign’s connective tissue

**Goal:** make Kaelen sound like she brokered this exact situation, watched how it played out, and remembers the player—without revealing her protected angle.

Primary files:

- `scripts/LLMInterface.gd`
- `scripts/story/StoryManager.gd`
- `scripts/UIManager.gd`
- `scripts/persistence/KaelenHandoffStore.gd`
- `scripts/persistence/CampaignKaelenMemoryStore.gd`
- `scripts/persistence/NarrativeCacheStore.gd`
- `scripts/QuestManager.gd`
- `scripts/GameRoot.gd`
- new `tests/story/run_kaelen_interaction_bundle_tests.gd`
- `tests/persistence/run_campaign_kaelen_memory_store_tests.gd`

Checklist:

- [x] Define Kaelen interaction kinds: `agent_handoff`, `offer_comment`, `acceptance_afterthought`, `objective_complete_pending_turn_in`, `turn_in_clean`, `turn_in_rough`, `turn_in_late`, `partial_delivery`, `abandon`, `decline`, `chapter_comment`, and `first_system_arrival`.
  - 2026-07-13: Added `KaelenInteractionKinds` as the Phase 7 registry, including turn-in grouping and completion-safe aftermath reveal gating. Existing Kaelen handoff bank paths now use `AGENT_HANDOFF` from the registry.
- [x] Keep the existing handoff pool, but key/refill it by story revision + agent + system + relationship band. Do not draw a line generated for a prior chapter’s pressure.
  - 2026-07-13: `KaelenHandoffStore` now supports scoped draw/refill/pool-size by agent, story revision, system, and relationship band while preserving legacy unscoped methods. `StoryManager` uses the scoped path for handoff pool refill/draw so prior chapter/system lines are not consumed for the current context.
- [x] Make `request_kaelen_intro()` consume a valid pooled/cached line first and route any refill through the central scheduler.
  - 2026-07-13: `request_kaelen_intro()` continues to draw scoped prepared handoff lines before making a live LLM call, UI consumes ready cached line-bank handoffs before canned fallback, and scoped Kaelen handoff pool refills now queue through `NarrativeCacheScheduler` via `GameRoot.queue_kaelen_handoff_pool_refill()` instead of forcing direct refill work during story events.
- [x] Include mission cause, stake, giver, player’s asked questions, accepted terms, relevant prior memory, and safe Kaelen mood/style in handoff/turn-in prompt packets.
  - 2026-07-13: Added `KaelenInteractionPacketBuilder` as the safe packet foundation. It projects mission cause/stake/giver, asked question intents, accepted terms, relevant Kaelen memories, safe story context, and Kaelen mood/style. Follow-up: route live handoff/turn-in generation through this packet.
  - 2026-07-13: `request_kaelen_intro()` now appends the safe Kaelen interaction packet to the live handoff prompt path, giving the small model allowed mission/story/style context without exposing director-only fields. Follow-up: wire the turn-in/completion path through the same packet.
  - 2026-07-13: `request_kaelen_reaction()` now includes separate safe packets for `turn_in_clean` and `abandon`, with completion-only earned aftermath rules and no raw director context.
- [x] Exclude `kaelen_hidden_angle`, undelivered hints, `kaelen_never_reveal`, and raw director truths from every small-model Kaelen packet.
  - 2026-07-13: Added salted leak coverage for the Kaelen packet builder. Completion packets can expose safe earned aftermath, while pre-completion packets cannot, and hidden angle/hints/director notes are rejected from the serialized packet.
  - 2026-07-13: The live Kaelen handoff prompt now consumes the safe packet builder instead of assembling extra story data ad hoc.
  - 2026-07-13: Turn-in/completion and abandon generation now consume safe packets too.
  - 2026-07-13: Added a source-level audit guard confirming live Kaelen prompt code does not directly read `kaelen_hidden_angle`, `player_does_not_know_yet`, undelivered hidden hints, or `kaelen_never_reveal`; remaining Kaelen prompt paths use mission-local details, safe packets, public context, or derived mood only.
- [x] Replace `cached_completion_line` / `cached_abandon_line` UI globals with mission-keyed, persisted bundle fields.
  - 2026-07-13: Removed the UI-only completion/abandon globals. Kaelen reaction lines now store as `kaelen_reaction_bundle` on the active mission, keyed by `mission_runtime_id`; UI reads the line before completion/abandon removes the mission, and late callbacks are discarded if they no longer match the active runtime id.
- [x] Trigger exact completion generation when the objective becomes complete, not only at the hand-in click. Persist it through save/reload.
  - 2026-07-13: `QuestManager` now stamps and emits a one-time `quest_objective_completed_details` snapshot when mission progress first satisfies the objective. `UIManager` refreshes the mission-keyed Kaelen reaction bundle from that objective-complete snapshot, so the completion line can be generated from the final state and persisted on the mission before hand-in.
- [x] Select turn-in variant from the outcome snapshot: early/late, clean/damaged, standard/advance/hazard terms, partial delivery history, and story fact learned.
  - 2026-07-13: Kaelen safe packets now include an `outcome_profile` that classifies turn-in variant (`turn_in_clean`, `turn_in_rough`, `turn_in_late`), timing label, partial delivery history, accepted term variant, and learned story facts; live completion generation selects the turn-in interaction kind from this profile.
- [x] Have Kaelen name the visible effect when appropriate: the shield line restarts, the convoy route reopens, the contact is safe, the evidence changed the case. Do not reduce payoff to “credits wired.”
  - 2026-07-13: Completion-safe Kaelen packets now expose a gated `visible_effect` projection when safe outcome text names concrete infrastructure, routes, people, or case evidence. The completion prompt tells Kaelen to name that effect once before her profit deflection, and to invent no visible payoff when the packet lacks one.
- [x] Let Kaelen reveal earned aftermath/background after completion without spoiling protected truth beforehand. Example: after the player kills ships for Agent X, Kaelen may reveal those ships were preparing to hit the agent's home city/family, framing the job as meaningful while still keeping director-only secrets hidden.
  - 2026-07-13: Completion-only `earned_aftermath` packets now include a bounded `earned_background` block sourced from safe public cause/stake/outcome text plus completion fact IDs. The prompt allows one short plain-language explanation of what the job prevented, while explicitly blocking secret motives, identities, origins, hidden causes, and director-only facts.
  - 2026-07-13: Added a player-clarity guard for Kaelen reaction lines after a tutorial turn-in produced unexplained next-task language (`now fix Zenith's relays...`). Completion lines may imply a generic resolved offscreen benefit, but must not make the pilot responsible for unseen infrastructure or name specific offscreen details unless they are in the mission's safe context.
  - 2026-07-13: Tuned Kaelen turn-in style toward "heart for one beat, then profit": she may acknowledge someone is safer or a problem got easier, then mask it with the important part being that everyone got paid.
- [x] Let abandon/decline change relationship and future handoff tone. Keep professional continuity; Kaelen does not reset to generic irritation next mission.
  - 2026-07-13: Story state now persists a code-owned Kaelen relationship record. Completed contracts raise respect; declined/failed/expired contracts lower it; abandoned contracts lower it more. The derived band scopes future handoff pools, appears in safe public context, and feeds Kaelen packet style with last contract outcome/title for continuity.
- [x] Public-board turn-ins remain disgusted with the board, but must reference the actual poster/job/outcome and current story pressure.
  - 2026-07-13: Public-board offer text now carries `{POSTER_HANDLE}` and `{STORY_PRESSURE}` placeholders. Kaelen board turn-ins must include the actual poster, at least one real job placeholder, and current story pressure when available; contextual fallbacks are upgraded to the same contract.
- [x] First arrival in a new system gets one campaign/system-specific Kaelen line prepared during gate travel. Kaelen may know broker-level information, not omniscient details of the player’s live piloting.
  - 2026-07-13: Gate travel now queues/processes the current-system Kaelen line-bank requester after the destination system loads but before arrival finishes. Kaelen first-arrival hails prefer `first_system_arrival` bank lines from the current-system bank, then fall back to the existing broker-level template if no prepared line is ready.
- [x] Add speaker/secret leak/line uniqueness validation and field-level degraded composition.
  - 2026-07-13: `DialogueBundleValidator` now rejects speaker-prefix drift, explicit director-only/secret token leaks, and exact repeated NPC response lines. `degrade_bundle()` maps those failures back to individual fields so deterministic fallback composition can replace only the unsafe/repeated field. Mission conversation fallback wording now varies by intent to satisfy uniqueness without losing safe anchors.
- [x] Store the delivered Kaelen line fingerprint and event memory after actual playback.
  - 2026-07-13: Actual Kaelen playback paths now record delivered handoff, completion, abandon, and first-system-arrival lines through `GameRoot.record_kaelen_line_playback()`. Each delivered line appends a `kaelen_line_delivered` chronicle event plus a Kaelen observation memory with `line_fingerprint` and `event_kind` metadata after speech/chatter delivery.

Phase 7 exit gate:

- [ ] Turn in the same mechanical objective under three different causes/outcomes; Kaelen produces three materially different, factually correct reactions.
- [x] Completion reactions can reveal safe newly-earned context, but never reveal `kaelen_hidden_angle`, undelivered hints, or director-only facts.
  - 2026-07-13: Automated evidence passes: `run_kaelen_interaction_bundle_tests.gd`, `run_context_block_leak_tests.gd`, `run_campaign_schema_tests.gd`, and `parse_check_scene_scripts.gd`.
- [x] Save after accepting, reload, complete, and turn in: the contextual line remains ready and correct.
  - 2026-07-13: Proven by dedicated sim coverage in `tests/persistence/run_kaelen_reaction_bundle_persistence_tests.gd`: accepts a real mission through `QuestManager.accept_quest`, stores the acceptance-time reaction bundle, saves through `capture_all_quests` → `SaveMigrator.prepare_for_save` → JSON on disk → `load_for_runtime` → `restore_all_quests` (with a `reset_for_restart` between to simulate an app restart), asserts the mission-keyed lines survive intact, rejects a stale runtime-id overwrite, completes the objective through the real `deliver_partial` progression path, refreshes the bundle from the `quest_objective_completed_details` snapshot, and reads the refreshed contextual line at turn-in before `complete_quest` removes the mission.
- [ ] No generic stock completion line appears in 50 successful V2 turn-ins.
- [x] Secret-salted Kaelen leak tests pass.
  - 2026-07-13: Automated leak evidence passes through the Kaelen packet/source guards and shared context-block leak tests; manual gameplay smoke gates remain separate.

### Phase 8 — N.O.V.A. movement and navigation reactions that stay fresh

**Goal:** keep N.O.V.A. responsive to how the player flies without making her noisy, repetitive, or omniscient.

Primary files:

- `scripts/ai/Nova.gd`
- new `scripts/story/ShipBehaviorObserver.gd`
- `scripts/PlayerShip.gd`
- `scripts/GlobalState.gd`
- `scripts/GameRoot.gd`
- `scripts/UIManager.gd`
- `scripts/story/NarrativeCacheScheduler.gd`
- `tests/ai/run_nova_tests.gd`
- new `tests/story/run_ship_behavior_observer_tests.gd`

#### Phase 8A — Semantic movement events

- [x] Add explicit signals/events for boost activated/rejected, autopilot started/cancelled/retargeted, evasive maneuver, gate departure, system arrival, dock/undock, major route replan, and severe hull impact. Do not infer narrative events by polling every frame in N.O.V.A.
  - 2026-07-13: Added `ShipMovementEvents` registry (12 event ids) and a validated `GlobalState.ship_movement_event` channel via `emit_ship_movement_event()`. PlayerShip emits boost activated/rejected (with reason), autopilot started/retargeted/cancelled (with mode + safe target category), evasive maneuver, stall-driven route replans, and severe hull impacts (single hit ≥ 10% max hull); dock/undock emit from the `is_docked` setter so every GameRoot/UIManager assignment site routes through one choke point. GameRoot emits gate departure and system arrival around the jump transition. Covered by `tests/story/run_ship_movement_event_tests.gd` (behavioral for the registry, channel validation, dock/boost-rejected/hull paths; source-level for tree-dependent emitters).
- [x] Aggregate repeated low-level actions in `ShipBehaviorObserver` into semantic events such as `boost_again_quickly`, `changed_mind_again`, `returned_to_same_station`, `clean_long_transit`, and `rough_arrival`.
  - 2026-07-13: Added `ShipBehaviorObserver` (created by GameRoot, subscribed to `GlobalState.ship_movement_event`). It folds raw events into the five semantic events with tunable windows: re-boost inside 90s, ≥3 retarget/cancel churn events inside 60s (tally resets on fire), re-dock at the station left within 10 minutes (dock identity from the DOCK autopilot target), and departure→arrival classified rough (any severe hull/evasive/replan en route or within 45s) or clean-long (≥20s, trouble-free). Time is injected through `observe()`; deterministic coverage in `tests/story/run_ship_behavior_observer_tests.gd`. Rate limiting before N.O.V.A. is the next checkbox, not claimed here.
- [x] Rate-limit semantic events before they reach N.O.V.A.; the observer reports state, N.O.V.A. decides whether speech is worth it.
  - 2026-07-13: `ShipBehaviorObserver` now gates every semantic emission behind a 30s global spacing and a 180s per-event cooldown. Suppressed events still update aggregation state and are tallied in `suppressed_counts`, and `state_snapshot()` exposes the observer's current state (churn tally, transit/rough flags, last dock station, emit/suppression history) so N.O.V.A. can consult it instead of being pushed every observation. Deterministic coverage added to `run_ship_behavior_observer_tests.gd`.
- [x] Carry safe context: target category/display name if known, current mission beat, hull band, recent action streak, new/returning system, and whether the player is deviating from a selected mission route.
  - 2026-07-13: Raw events already carry target category/display name from the emitters. Semantic events are now enriched at emission: the observer stamps a `recent_actions` streak (last 6 raw event ids) and merges an injectable `context_provider` dictionary without overwriting event fields. GameRoot supplies the live provider: hull band (healthy/worn/critical), the active mission's public beat (`title (objective_type)`), new/returning system (visited `system_states`), and `route_deviation` (`no_mission` / `in_mission_system` / `off_mission_system` from the mission's system vs the current one). Only player-visible knowledge; covered in `run_ship_behavior_observer_tests.gd` including field-collision precedence.
- [x] Never call a model on movement. Movement only consumes a prepared line bank.
  - 2026-07-13: Tripwire in place — `run_ship_behavior_observer_tests.gd` audits the movement path (`ShipMovementEvents.gd`, `ShipBehaviorObserver.gd`) for any model-layer reference.
  - 2026-07-13 (later): Consumption wired. GameRoot routes `semantic_movement_event` to `Nova.on_semantic_movement_event`, which maps the event through `NovaLineBankCategories.for_semantic_event()` and draws only from the prepared current-system bank (`_ready_line_bank_text`); no prepared line means silence — there is no stock fallback and no model path on movement. `run_nova_tests.gd` proves the silence behavior with no bank available and trips if `Nova.gd` ever references the model layer.

#### Phase 8B — Campaign-aware line banks

- [x] Define line-bank categories for the semantic events above plus existing combat/hull/welcome/gate/arrival beats.
  - 2026-07-13: Added `NovaLineBankCategories` — the five ShipBehaviorObserver semantic events plus `system_arrival` (accepts the legacy `startup_navigation` kind so existing cached banks stay consumable), `gate_transit`, `gate_glitch` (marked protected: only StoryManager's large-model path may write it), `hull_critical`, `welcome_back`, `docked`, and the three combat-end beats. `for_semantic_event()` maps observer events to banks; unknown events map to none (silence by design). Covered by `tests/story/run_nova_line_bank_category_tests.gd`, including a mirror check against `ShipBehaviorObserver.all_semantic()`.
- [ ] Generate small flat banks in 6–10 field batches during chapter/system preparation; validate each line independently.
- [ ] Prompt with N.O.V.A.’s fixed persona, campaign quirk, allowed known facts, current system tone, and a bounded recent-event summary.
- [x] Preserve current severity/preemption/cooldown rules and improve them with a global “N.O.V.A. has spoken enough recently” budget.
  - 2026-07-13: `Nova.speak()` now enforces a global budget on top of each beat's own cooldown: casual lines (IDLE/NAV) are dropped when she has spoken 3 times in the last 2 minutes or anything in the last 15 seconds. COMBAT/THREAT lines bypass the check (warnings are never starved) but still count as speech, so a noisy fight buys quiet afterwards. Existing per-beat cooldowns, severity enum, and `should_preempt` are unchanged; `reset_for_restart()` wipes the ledger. Deterministic coverage added to `tests/ai/run_nova_tests.gd` via the time-parameterized `_speech_budget_allows()`.
- [x] Retire consumed lines for the campaign. Refill before a bank reaches two remaining lines.
  - 2026-07-13: `FallbackLineBank.consume()` now records the delivered text's fingerprint in a `retired_fingerprints` ledger persisted with the bank payload; `replace_used_with_generated()` refuses retired texts even after their slot was recycled (`run_fallback_line_bank_tests.gd`). `consume_cached_narrative_line_bank` queues a `line_bank_low_refill` job while 3 unused lines remain (deduped by cache key while queued/in flight); the worker refills used slots via `replace_used_cached_fallback_lines`. Content source is the speaker's template bank until the batch-generation checkbox upgrades it to prompted lines. `run_line_bank_refill_tests.gd` proves trigger threshold, dedupe, top-up, and no retired-line return end to end.
- [x] Keep tutorial lines authored. After the tutorial, stock pools become degraded emergency content only.
  - 2026-07-13: Added `Nova._bank_line_or_stock()`: every flat-pool beat (gate transit, welcome back, hull critical, system arrival, combat retreat/battered/clean victory) now draws from the prepared bank first and only falls to its stock pool when no bank line is ready — and every stock draw is logged to GenerationDiagnostics as `nova_line_bank / stock_line_used` so canned usage is visible (fallbacks are failures). `on_combat_tutorial` stays authored and never touches the bank helper (tripwired in `run_nova_tests.gd`). The dock tier ladder keeps its authored escalation pools for now — escalation tiers don't map to a flat bank; revisit when batch generation can produce tiered content.
- [x] Use the campaign-specific gate glitch mechanism as a protected special bank; director-only memory flicker remains large-model-only.
  - 2026-07-13: The existing pipeline already satisfied the generation side (`_ensure_nova_glitch_hints` runs once per campaign on the large model via the `nova_glitch` capability, leak-guards every line against the director-only `nova_memory_flicker` with `glitch_line_leaks_flicker`, and uses absence — not filler — on failure). Added the consumption-side protection: `gate_glitch` is a protected category in `NovaLineBankCategories`, and Nova's `_line_kind_allowed()` refuses protected kinds unless a filter explicitly requests them — including the consumed-line fallback path, where a disallowed line stays burned rather than delivered to the wrong beat. Covered in `run_nova_tests.gd` (behavioral guard checks + pipeline source tripwires).
- [ ] Add relevance scoring: prefer a story/mission-aware line over a generic movement joke when a real beat just occurred.
- [x] Add silence tests: repeated events after escalation cap should often produce no line.
  - 2026-07-13: `run_nova_tests.gd` proves six back-to-back docks produce exactly one spoken line (the tier ladder's quiet zone plus the global speech budget's minimum gap absorb the rest), and movement events with no prepared bank produce zero lines. Movement-side suppression after the rate-limit cap (suppressed events counted, not spoken) is covered in `run_ship_behavior_observer_tests.gd`.

Phase 8 exit gate:

- [ ] A scripted flight with repeated dock, boost, retarget, gate, and arrival events produces no exact line repeats and respects silence/cooldowns.
- [ ] N.O.V.A. references only knowledge available to the player and the ship.
- [ ] N.O.V.A. recognizes meaningful patterns (repeat behavior, mission route, rough outcome) without narrating every control input.
- [ ] Movement reactions remain instant with the model process stopped after banks are prepared.

### Phase 9 — Instant, knowledge-aware lounge conversations

**Goal:** retain the warmth of two-way lounge chat without a model request after every reply.

Primary files:

- `scripts/story/LoungeConversation.gd`
- `scripts/UIManager.gd`
- `scripts/LLMInterface.gd`
- `scripts/story/KnowledgeLedger.gd`
- `scripts/story/NarrativeCacheScheduler.gd`
- `scripts/persistence/CampaignNpcIdentityStore.gd`
- `tests/story/run_lounge_conversation_tests.gd`

Checklist:

- [ ] Replace per-reply generation with a pre-generated flat exchange bundle: opener, 2–3 code-approved player intents/questions, paired NPC answers, and a natural close.
- [ ] Start with one meaningful player reply per bundle. For warm/story-important contacts, expose “keep talking” only when a second bundle is already cached. Do not preserve three turns by reintroducing visible waits.
- [ ] Select player intents from knowledge gaps, NPC relationship, current stake, and delivered rumors. Avoid generic friendly/pushback/odd options when a natural story question exists.
- [ ] Validate that each answer responds to its paired player line and remains in character.
- [ ] Mark rumors/facts heard only when the relevant answer is displayed. Fix the current approach path that can mark a hook heard while merely building the opener prompt.
- [ ] Persist conversation stance and fact IDs learned into the NPC’s structured memory; summarize later.
- [ ] Replace display-name keys with stable NPC IDs for warmth, cold-contact state, and once-per-dock rewards.
- [ ] Keep refusal/disposition mechanics code-owned. The model writes the way refusal sounds, not whether it occurs or how much reputation changes.
- [ ] Cache likely contact bundles during flight-to-station/system arrival. The card should indicate unavailable/pending before selection rather than turn a click into `Listening...`.
- [ ] Let a rare contact conversation activate or clarify a mission beat, but require an actual fact/beat ID—not a free-form string appended directly to `pending_hooks`.
- [ ] Preserve the stranger deal’s code-owned mechanics; make its pitch and any story intel obey the same knowledge/cache contracts.

Phase 9 exit gate:

- [ ] Reply clicks remain instant with Ollama stopped after preparation.
- [ ] NPC answers are relevant to the selected player line in 50/50 automated fixtures and >= 95% of a reviewed real-model batch.
- [ ] No rumor is marked heard until its delivery field is shown.
- [ ] Returning to the same NPC produces a relationship/memory-aware exchange, not a reset opener.

### Phase 10 — Uniqueness, coherence, quality gates, and designer tools

**Goal:** make “feels alive” inspectable and enforceable rather than subjective hope.

Primary files:

- new `scripts/story/NarrativeQualityGate.gd`
- new `scripts/story/NarrativeFingerprintLedger.gd`
- `scripts/diagnostics/GenerationDiagnostics.gd`
- `scripts/ui/DevPanel.gd`
- `scripts/registry/LLMDialogueContentRegistry.gd`
- new `tests/story/run_narrative_quality_gate_tests.gd`
- new `tests/story/run_narrative_fingerprint_ledger_tests.gd`
- new `tests/story/run_dialogue_relevance_tests.gd`
- real-model batch tools under `tests/tools/`

#### Automated quality checks

- [ ] Exact fingerprint rejection across all post-tutorial player-facing lines in one campaign.
- [ ] Near-duplicate check using normalized distinctive-token/bigram overlap; tune thresholds separately for short barks and longer answers.
- [ ] Mission-pattern check across type, cause, stake, giver, location, complication, and disclosure role.
- [ ] Question/answer relevance check using required anchors and forbidden topic drift.
- [ ] Unexplained-reference check against allowed entity/fact aliases.
- [ ] Persona check against address rules, banned tics, sentence length, vocabulary, and role ownership.
- [ ] Causal visibility check: the opening or a readily available answer must communicate why the job matters and what changes.
- [ ] Knowledge leak check against director-only tokens and fact states.
- [ ] Humor-density check as a warning, not a hard quota: flag every-line punchlines and repeated joke mechanisms.
- [ ] Objective/mechanics consistency remains a hard gate.

#### DevPanel additions

- [ ] “Why this offer?” inspector: beat, thread, cause, stake, selected type, scoring breakdown, rejected alternatives, and recent streak state.
- [ ] Knowledge ledger viewer by `unknown/rumored/known/confirmed`, with source and revision.
- [ ] Character card viewer with public vs. director fields and relationship revisions.
- [ ] Conversation bundle viewer: allowed facts, question intents, validation results, source, cache key, and TTS readiness.
- [ ] Cache queue: priorities, in-flight model, age, hits, misses, stale discards, and evictions.
- [ ] N.O.V.A. banks and recent silence/speech budget.
- [ ] Kaelen current safe context beside hidden fields with a prominent leak boundary.
- [ ] One-click safe replay of a generated bundle in the dev panel without applying gameplay consequences.

Phase 10 exit gate:

- [ ] A designer can explain any displayed line’s truth inputs, source, cache history, and validation decisions.
- [ ] A 100-bundle generation batch has zero hard leaks/objective contradictions and meets reviewed quality targets.
- [ ] Known bad fixtures fail for the expected reason rather than a generic “invalid.”

### Phase 11 — Migration, content cleanup, soak testing, and release

**Goal:** retire the disconnected legacy path only after the new system proves it is the game’s strongest feature.

Primary files:

- all files above
- `data/content/llm_dialogue_content.json`
- `docs/llm_dialogue_content_editing.md`
- `docs/whileYouWasSleeping.md`
- `PROJECT_MAP.md` / `PROJECT_MAP.json`

Checklist:

- [ ] Move remaining live speaker persona/rule text from `LLMInterface.gd` and `UIManager.gd` into validated registry data where appropriate. Keep mechanics and privacy rules in code.
- [ ] Remove duplicate hardcoded quest few-shots/dummy substitution only after V2 has a full rollback tag and green soak evidence.
- [ ] Demote stock N.O.V.A./Kaelen/agent post-tutorial pools to explicit degraded paths; keep tutorial-authored content untouched.
- [ ] Migrate active saves: story state, NPC identities, active mission metadata, relationship keys, and cache store. Missing cache is not a save failure; rebuild it in background.
- [ ] Test save/load at every risky point: generated offer not viewed, mid-question, accepted mission, objective complete before dock, mid-turn-in, mid-lounge exchange, chapter transition, and model unavailable.
- [ ] Run at least five fresh campaigns across different creative lanes. For each, play/replay the first 10 agent missions and record mission sequence, causal comprehension, NPC recall, N.O.V.A. repetition, and Kaelen payoff quality.
- [ ] Run a continuous 2-hour campaign soak with system jumps, reloads, multiple stations, at least 12 agent missions, lounge conversations, and model interruption/recovery.
- [ ] Have a human reviewer score anonymized dialogue bundles on 1–5 scales: naturalness, character identity, contextual logic, useful player questions, story connection, humor fit, and desire-to-continue.
- [ ] Require average >= 4.2/5 in each primary category and no individual primary category below 3 for release candidates.
- [ ] Verify latency/fallback/uniqueness SLOs in §11 below.
- [ ] Turn V2 flags on by default only after all release gates pass; retain a one-release rollback switch.
- [ ] Delete obsolete legacy code in a separate change after one stable release, not in the same commit that enables V2.
- [ ] Update `docs/whileYouWasSleeping.md` with landed phases, refresh the project map with `python generate_repo_map.py`, and update the editing guide for designers.

Phase 11 exit gate:

- [ ] The old path is not silently serving normal play.
- [ ] Five campaigns feel causally and characterfully distinct in blind review.
- [ ] No player-visible post-tutorial interaction requires waiting for live text generation.
- [ ] The narrative system meets the full Definition of Done below.

## 9. Conversation Craft Rules

These are validation/editor rules for the writing layer. They do not replace fact validation.

### NPC opening

A strong opening usually contains three things in natural order:

1. **grounding:** what concrete thing is wrong;
2. **stake:** why this person/world cares now; and
3. **ask:** what the player can do.

It need not explain the hidden cause. It must give the player enough footing to ask intelligently.

Bad:

> “The Meridian issue has reached threshold. Handle the usual retrieval.”

Why it fails: “Meridian issue,” “threshold,” and “usual retrieval” assume shared knowledge the player may not have.

Better shape:

> “Our shield line is out of ore. The scheduled convoy never arrived, and I need a replacement load before maintenance starts choosing which decks matter.”

This gives a novice footing and naturally creates informed questions: what happened to the convoy, why the reserve is empty, or how dangerous the replacement route is.

### Player questions

- Echo the NPC’s actual words or mission subject. Avoid abstract buttons such as “Tell me more.”
- Ask one thing at a time.
- Reflect knowledge: novice questions identify entities; informed questions challenge timing, motive, inconsistency, or consequence.
- Never make the player voice assert a fact not in the knowledge ledger.
- “What do you mean?” is valid when the line is genuinely ambiguous; prefer a grounded form: “What do you mean by ‘off-ledger’?”
- If the agent is withholding, let the player notice: “That explains the ore. It doesn’t explain the missing manifest.”
- Do not force the player to ask a clarification to see the base objective, destination, reward, or deadline. Mechanics remain visible in Contract Details.

Suggested ranking for the primary question button:

1. unknown term/entity required to understand the ask;
2. unknown cause behind the urgency;
3. contradiction with a rumored/known fact;
4. concrete risk;
5. connection to a prior job/thread;
6. personal stake for a warm recurring NPC.

### NPC answers

- Answer the question in the first sentence. Personality colors the answer; it must not replace the answer.
- Withholding is allowed only when the speaker acknowledges the boundary and gives enough information to proceed.
- Introduce at most one ungrounded proper noun in a short answer, and immediately identify why it matters.
- Do not repeat the full opening or Contract Details.
- Imperfect characters can lie or be wrong only when the chapter packet marks that fact as rumor/lie and later systems can resolve it. Random hallucination is not characterization.

### Character voice

- Persona should be recognizable with the name removed.
- Do not turn verbal habits into catchphrases. A docking metaphor “at most once per exchange” is a voice constraint; saying it every line is parody.
- Use contractions, fragments, and mild interruptions where they fit. Avoid stage directions and prose narration in spoken fields.
- Keep major agents distinct, but let campaign pressure modify them. Voss under panic becomes more controlling, not suddenly jokey; Ryn under pressure becomes smoother and less trustworthy; Dask becomes terser, not poetic.
- Generated NPCs are not watered-down versions of the major three. Their card, local job, relationship, and stake own their voice.

### Dark/dry PG-13 humor

- Humor is how people cope with systems, danger, money, paperwork, bad food, and mortality.
- Prefer specific understatement over generic zingers.
- Let serious beats stay serious. A reveal, betrayal, death, or vulnerable admission does not need a joke stapled to it.
- Avoid explicit sexual content, slurs, graphic gore, cruelty toward protected groups, and jokes that break the setting.
- The same humor mechanism should not dominate a whole station. One pedant, one fatalist, one optimist, and one tired parent feel like a room; four sarcastic fixers feel like one prompt.

### Kaelen and N.O.V.A. ownership

- Kaelen owns brokerage, client handoffs, strategic route gossip, negotiation memory, mission outcomes, and controlled campaign hints.
- N.O.V.A. owns the ship’s body, immediate sensor/navigation state, piloting patterns, combat survival, and her own damaged memory.
- Kaelen should not magically know a boost was mistimed unless plausible telemetry was shared in the mission outcome. N.O.V.A. should not know a broker’s private motive unless the player/ship learned it.
- “Shiny” remains Kaelen-only. N.O.V.A. uses Captain sparingly. Most characters use no nickname.

## 10. Worked Narrative Example — One Cause, Varied Play

This is an architecture example, not production text.

### Hidden spine

A faction arranged the destruction of its own ore convoy to conceal the transfer of a prototype navigation core. The player must not know this at chapter start.

### Player-safe initial state

- Fact: the station’s ore convoy is missing.
- Fact: shield fabrication is consuming the reserve.
- Rumor: wreckage was found away from the filed route.
- Unknown: why the convoy diverted and what it carried.

### Four connected missions without a four-mining streak

1. **Emergency supply (`DELIVER_ORE`)** — relieve the immediate shield shortage. The player can ask why the reserve is gone and learn that the scheduled shipment disappeared. Completion visibly lowers shortage pressure.
2. **Manifest run (`DELIVERY_COURIER`)** — carry sealed routing records to an investigator before the faction bureaucracy buries them. The giver acknowledges that the ore bought time but did not explain the convoy.
3. **Wreck evidence (`RECOVER_COMBAT_DROP`)** — recover a transponder shard from raiders stripping the off-route wreck. Completion confirms the convoy changed course voluntarily.
4. **Silence order (`TARGET_WITH_COMMS_REVERSAL`)** — intercept the supposed raider leader, who calls before the final kills and claims the convoy arrived already empty. The player’s branch changes whom they trust and which fact becomes confirmed.

The player experiences mining, courier travel, combat recovery, and a choice-bearing fight. Every job advances the same mystery, and each briefing can assume only the knowledge earned so far.

### Relationship callbacks

- The supply giver remembers whether the player demanded hazard pay.
- The investigator’s warmth depends on whether the player pressed for an explanation or treated it as cargo.
- Kaelen’s turn-in after the transponder does not say “credits wired”; she notices that the filed route and wreck location disagree, then deflects if asked how quickly she understood it.
- N.O.V.A. may comment on the route mismatch because the navigation records are now in the ship’s knowledge, but not before.

### Failure/decline does not stall the story

- Declining the ore run raises shortage pressure and activates a purchase-delivery alternative.
- Abandoning the manifest run lets the bureaucracy seize it; the next clue becomes harder and the investigator remembers.
- Destroying the reversal target before listening resolves the combat but loses a fact; the chapter continues on a more suspicious branch.

This is the standard every chapter packet should enable: repeated causal meaning, varied play, real consequences, and knowledge-earned conversation.

## 11. Definition of Done and Release Metrics

### Causality and story progression

- [ ] 100% of post-tutorial agent offers have valid campaign/thread/beat/cause IDs.
- [ ] 100% of those offers expose a comprehensible surface reason in the opening or the primary grounding answer.
- [ ] 100% of completion/decline/abandon paths update beat/thread state or an explicit alternate/failure consequence.
- [ ] In blind playtest, >= 90% of players can answer “why did this NPC need that job?” after the interaction without reading debug data.
- [ ] No mission completion is unable to resolve its stamped beat because metadata was lost.

### Variety and uniqueness

- [ ] Zero exact post-tutorial line repeats within a campaign, excluding deliberate quoted callbacks clearly marked as callbacks.
- [ ] Near-duplicate line rate < 2% in reviewed 100-bundle batches.
- [ ] Zero three-in-a-row identical agent objective types.
- [ ] Zero repeated premise fingerprints inside the eight-offer window.
- [ ] Repeated mechanics satisfy the “three changed dimensions” rule.
- [ ] Across 10 generated campaigns, campaign premise/title/reveal/thread similarity stays below the configured distinctiveness threshold and creative lanes do not repeat back-to-back.

### Conversation logic and characters

- [ ] >= 95% of reviewed player questions are judged relevant to the immediately preceding line and player knowledge.
- [ ] >= 95% of reviewed NPC answers directly answer the selected question.
- [ ] Zero player options assert unavailable knowledge.
- [ ] Zero nickname/speaker ownership violations.
- [ ] Recurring NPC blind identification: reviewers can match at least 80% of anonymized lines to the correct character among four candidates after meeting them in play.

### Latency and reliability

- [ ] 0 post-tutorial option clicks launch live text generation.
- [ ] p95 click-to-text <= 100 ms.
- [ ] p95 click-to-cached-audio start <= 300 ms on the reference machine.
- [ ] Required bundle cache readiness >= 99% at interaction time.
- [ ] Required-field degraded source rate < 1% over the 2-hour soak.
- [ ] No generic stock Kaelen/N.O.V.A./agent line appears on the normal V2 path.
- [ ] Save/reload at every listed interaction boundary retains factual and conversational continuity.

### Privacy and mechanics

- [ ] Zero director-only leak tokens in every small-model prompt/output test.
- [ ] Zero model-authored changes to counts, rewards, targets, deadlines, relationship numbers, or consequences.
- [ ] Plot-armor checks remain green for Kaelen and N.O.V.A.
- [ ] All mission capability, checkpoint, campaign store, story state, and scene parse regressions pass.

## 12. Test Strategy

### Layer 1 — Pure deterministic tests (run on every checkbox)

No Ollama, TTS server, rendered scene, or random global state. Inject clocks, RNG seeds, story packets, character cards, and mission histories.

Required new suites:

- `tests/story/run_knowledge_ledger_tests.gd`
- `tests/persistence/run_narrative_checkpoint_state_tests.gd`
- `tests/ai/run_context_block_leak_tests.gd`
- `tests/persistence/run_chapter_narrative_packet_store_tests.gd`
- `tests/ai/run_chapter_narrative_director_tests.gd`
- `tests/story/run_mission_director_tests.gd`
- `tests/story/run_challenge_budget_tests.gd`
- `tests/story/run_character_director_tests.gd`
- `tests/persistence/run_campaign_npc_state_store_tests.gd`
- `tests/story/run_mission_conversation_plan_tests.gd`
- `tests/story/run_dialogue_bundle_validator_tests.gd`
- `tests/story/run_mission_conversation_controller_tests.gd`
- `tests/persistence/run_narrative_cache_store_tests.gd`
- `tests/story/run_narrative_cache_scheduler_tests.gd`
- `tests/story/run_narrative_cache_invalidation_tests.gd`
- `tests/story/run_kaelen_interaction_bundle_tests.gd`
- `tests/story/run_ship_behavior_observer_tests.gd`
- `tests/story/run_narrative_quality_gate_tests.gd`
- `tests/story/run_narrative_fingerprint_ledger_tests.gd`
- `tests/story/run_dialogue_relevance_tests.gd`

Every suite must fail loudly if its target script cannot compile. Do not repeat the historical pattern where a failed preload resulted in a false PASS with zero assertions.

### Layer 2 — Existing regression suites

Run the relevant subset after every checkbox and the full set at each phase exit:

- `tests/domain/run_mission_contract_tests.gd`
- `tests/domain/run_mission_instance_tests.gd`
- `tests/domain/run_mission_collection_tests.gd`
- `tests/domain/run_mission_capability_tests.gd`
- `tests/domain/run_timed_mission_tests.gd`
- `tests/domain/run_public_board_validation_tests.gd`
- `tests/run_mission_template_tests.gd`
- `tests/persistence/run_story_state_bible_seed_tests.gd`
- `tests/persistence/run_campaign_npc_identity_store_tests.gd`
- `tests/persistence/run_campaign_kaelen_memory_store_tests.gd`
- `tests/story/run_story_manager_hook_tests.gd`
- `tests/story/run_lounge_conversation_tests.gd`
- `tests/story/run_ambient_chat_tests.gd`
- `tests/ai/run_narrative_director_tests.gd`
- `tests/ai/run_local_model_gateway_tests.gd`
- `tests/ai/run_nova_tests.gd`
- `tests/registry/run_llm_dialogue_content_registry_tests.gd`
- `tests/diagnostics/run_generation_diagnostics_tests.gd`
- `tests/speech/run_speech_service_tests.gd`
- `tests/parse_check.gd`
- `tests/parse_check_scene_scripts.gd`

Run Godot tests **sequentially** with a unique workspace-local log per suite. Example:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\knowledge_ledger.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/story/run_knowledge_ledger_tests.gd --log-file $logPath
```

If the old signal-11/log-rotation crash appears before test output, treat it as a log-path startup problem first and verify that a unique `--log-file` was actually supplied.

### Layer 3 — Real-model protocol live fire

Run separately from deterministic tests. Capture the prompt, raw envelope, parsed fields, validation results, latency, and final displayed bundle.

- [ ] 30 mission bundles across all supported agent objective types and at least eight character cards.
- [ ] 20 knowledge-state variants of the same mission to verify question depth changes without leaks.
- [ ] 20 lounge exchange bundles across stranger/neutral/warm/hostile states.
- [ ] 10 N.O.V.A. bank generations across at least three campaigns and systems.
- [ ] 20 Kaelen handoff/turn-in bundles across causes and outcome bands.
- [ ] Inject malformed/slow/timeout responses and verify background retry + instant degraded delivery.
- [ ] Stop Ollama after caches are populated and run the complete interaction script; no click should stall.

Do not accept “JSON parsed” as a quality pass. Apply the human rubric from Phase 11.

### Layer 4 — End-to-end save/reload and playtest

Mandatory scenarios:

- [ ] Fresh campaign through tutorial into first V2 offer.
- [ ] Ask every available clarification, back out, return, then accept.
- [ ] Decline a required story beat and observe alternate/failure progression.
- [ ] Complete two missions with the same mechanic under different causes and verify callbacks.
- [ ] Save/reload with an unseen cached offer.
- [ ] Save/reload mid-offer after one fact was learned.
- [ ] Save/reload after acceptance and before objective completion.
- [ ] Save/reload with objective complete and turn-in cached.
- [ ] Jump systems and verify stale home-system bundles never appear.
- [ ] Raise/lower relationship and verify cache invalidation + tone change.
- [ ] Trigger N.O.V.A. movement streaks and verify escalation then silence.
- [ ] Revisit a lounge NPC after prior help, refusal, and learned rumor.
- [ ] Kill/restart/rollback and verify narrative stores follow the active timeline contract.
- [ ] Temporarily stop/restart Ollama and confirm recovery does not reorder or overwrite current bundles.

## 13. Risks and Required Mitigations

| Risk | Why it matters | Required mitigation |
|---|---|---|
| “Unique” becomes random incoherence | More sampling can weaken continuity | Code-owned causal plan, fact IDs, character card, and mechanical skeleton precede prose. |
| Chapter-packet output is too complex for the large model | Nested schemas have failed elsewhere | Proven labeled blocks, code assembly, fixed limits, semantic validation, correction retry. |
| New-campaign loading becomes too long | Extra large-model work can hurt first impression | Measure packet cost; generate only current packet at start, next packet at 60%; show a truthful loading stage. Do not move the cost back onto interaction clicks. |
| Small jobs contend and time out | Current log already shows sequential quest timeouts and ~40 s selection | One prioritized scheduler, one small request in flight, no best-of-three sequential path. |
| Cache serves convincing but stale lies | Stale narrative is worse than no narrative | Semantic keys, revisions, selective invalidation, accepted-mission truth freeze, stale-discard tests. |
| Over-invalidation destroys hit rate | Keying on every mutable number makes caching useless | Use only relevant revisions and coarse state bands; document dependencies per interaction kind. |
| UIManager becomes even harder to maintain | It already owns too many unrelated flows | Pure plan/compiler/controller classes; UIManager only renders and forwards events. |
| Character cards turn into adjective soup | Long personas do not guarantee a person | Required drive, contradiction, pressure tell, kindness tell, taboo, and current stake. |
| NPCs over-explain the mystery | Causality can become exposition | Tiered facts, opening/clarify/complete disclosure, player-safe allowlists, one new referent at a time. |
| NPCs under-explain and remain confusing | “Subtext only” is the current failure | Surface cause required; primary grounding question; causal visibility quality gate. |
| Humor becomes exhausting | Mandatory jokes flatten drama and voices | Humor mechanisms, station diversity, warnings not quotas, serious-beat exemptions. |
| N.O.V.A. becomes spammy | More movement awareness creates more triggers | Semantic aggregation, global speech budget, severity, cooldown, escalation cap, silence tests. |
| Story stalls after refusal/failure | Linear generated beats can become soft locks | Every required beat declares decline/failure consequences and at least one alternate approach. |
| Save migration strands campaigns | Multiple v2 stores add compatibility risk | Versioned migrations, legacy defaults, fixture saves, transactional writes, cache rebuild on missing data. |
| Fallbacks look successful and hide regressions | Better emergency prose can mask model failure | Required source telemetry and degraded rate release gate; never relabel degraded composition as model output. |
| Cross-campaign text/memory leaks | Global quest history currently exists | Per-campaign structured history/cache; legacy markdown import only; campaign-ID validation. |

## 14. Implementation Handoff Rules for a Lower Coding Agent

- [ ] Read `PROJECT_MAP.md` first, then read the actual files named in the active checkbox before editing.
- [ ] Read `docs/whileYouWasSleeping.md` before resuming someone else’s phase.
- [ ] Work in phase order unless a dependency note explicitly permits otherwise.
- [ ] Complete one checkbox-sized change at a time. Do not combine a schema migration, UI rewrite, and prompt rewrite into one unreviewable change.
- [ ] Add/update tests in the same change as behavior.
- [ ] Never check a box based only on compilation. Run its deterministic tests plus the relevant regression subset.
- [ ] Write the test evidence and any deviation immediately under the checkbox or in the Decision/Progress Log below; do not rely on memory at the end of a long session.
- [ ] Preserve feature-flag rollback until Phase 11.
- [ ] Do not delete the legacy path while V2 is still behind a flag.
- [ ] Do not expand mission mechanics inside a narrative checkbox. Use capabilities already present; create a separate approved gameplay plan for genuinely new mechanics.
- [ ] Do not patch a bad line with another global canned line. Repair the data contract, prompt, validator, or field-level emergency composer and record the failure.
- [ ] Keep all generated fact/character/cache files inside the active campaign directory and validate campaign IDs on open.
- [ ] Refresh `PROJECT_MAP.md` / `PROJECT_MAP.json` after adding the major new systems in Phases 3 and 6 and again at final handoff.

Recommended change grouping:

1. schema/store + migration + tests;
2. pure director/plan logic + tests;
3. model prompt/parser/validator + live-fire evidence;
4. scheduler/cache wiring + tests;
5. UI integration + controller/gamepad tests;
6. diagnostics/dev tooling; and
7. legacy cleanup only after soak.

## 15. Assumed Product Decisions (Owner Review Welcome)

These defaults let implementation proceed without blocking. Change them in this document before their dependent phase begins if they do not match the intended game.

1. **Interaction speed is worth startup/background cost.** Recommended default: spend an extra measured large-model preparation step at new-campaign loading rather than ever making the player wait after a dialogue click.
2. **Agent contracts advance the campaign story.** Public-board work may remain local/world texture, but must still have a real local cause. It does not have to advance the main mystery every time.
3. **Campaigns remain extensible/endless for now.** Chapter packets deliver strong mini-arc setup/escalation/payoff and then extend through horizon generation. A final campaign ending is a separate design decision.
4. **“Every interaction is unique” means no exact post-tutorial line reuse within a campaign, strict near-repeat controls, and campaign-specific context—not a promise that two humans can never express the same idea across all possible campaigns.** Deliberate quoted callbacks are allowed and must be marked as callbacks.
5. **Questions are authored intents, not free text.** This preserves voice, safety, gamepad usability, knowledge gating, and instant cached replies.
6. **N.O.V.A. is observant but selective.** She notices meaningful movement patterns, not every click. Silence protects her personality.
7. **Dark/dry PG-13 is the baseline, not a joke quota.** Some campaigns/beats can be heavier; humor should emerge from character and pressure.
8. **Kaelen’s mystery remains unresolved.** The player can learn what she did and why it mattered without receiving a complete origin/identity answer.

## 16. Decision and Progress Log

Add newest entries at the top. Include date, phase/checkbox, decision or evidence, tests run, and any follow-up.

| Date | Phase | Entry | Evidence / follow-up |
|---|---|---|---|
| 2026-07-12 | Phase 6E | Added the pure fallback-bank foundation for Kaelen/N.O.V.A. quality fallbacks. `FallbackLineBank` creates target-sized fallback banks, tracks fallback consumption, and replaces used fallback slots with generated lines without changing their source label to fallback. | Tests: `run_fallback_line_bank_tests.gd`. Follow-up: persist bank state and wire model-generated refresh into Kaelen/N.O.V.A. runtime banks. |
| 2026-07-12 | Phase 6E | Upgraded the Kaelen/N.O.V.A. line-bank worker from loose template seed lines to real 20-slot fallback-bank payloads. The cache payload now labels the source as `fallback_bank`, includes the full fallback-bank state, and exposes ready line entries for existing Kaelen/N.O.V.A. consumers. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: persistent consumption accounting and generated replacement refresh. |
| 2026-07-12 | Phase 6E | Added runtime fallback-bank consumption for Kaelen and N.O.V.A. Ready speech paths now call `consume_cached_narrative_line_bank`, which marks one fallback slot used and updates the scheduler payload; background TTS warmup still calls the read-only lookup. | Tests: `run_narrative_cache_scheduler_tests.gd`, `run_nova_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: persist consumed bank state and refresh used slots with validated generated lines. |
| 2026-07-12 | Phase 6E | Added generated-line replacement for used Kaelen fallback slots. A successful unique Kaelen handoff callback now calls `replace_used_cached_fallback_lines`, which applies `FallbackLineBank.replace_used_with_generated` to the current-system bank. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: extend the same replacement route to N.O.V.A. and persisted bank state. |
| 2026-07-12 | Phase 6E | Added behavior coverage for scheduler payload updates so fallback-bank consume/replace state remains visible to all requesters on a deduped ready job. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Added a persistence foundation for fallback-bank payload state. `NarrativeCacheStore.update_result_payload()` can now update an existing cache entry's ready payload, with reopen coverage for fallback-bank use/replacement counters. | Tests: `run_narrative_cache_store_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: wire GameRoot scheduler payload updates through the store. |
| 2026-07-12 | Phase 6E | Wired GameRoot's cache worker and fallback-bank mutation paths to `NarrativeCacheStore`. Ready payloads are upserted when jobs complete, and consume/replace mutations update the persisted result payload when the store is available. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: restore ready scheduler jobs from persisted payloads on campaign load. |
| 2026-07-12 | Phase 6E | Added ready-payload restore from `NarrativeCacheStore` into `NarrativeCacheScheduler` on campaign load. Persisted ready payloads now become ready scheduler jobs again with their saved requesters and result payloads. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Added fallback-bank replacement cap coverage so generated lines cannot silently grow a full unused 20-line fallback bank. | Tests: `run_fallback_line_bank_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Extended `NarrativeCacheScheduler.diagnostic_summary()` with ready payload content/source counts and fallback-bank use/replacement totals. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Surfaced narrative cache payload-source diagnostics in the DevPanel story bridge summary so cache/fallback activity is visible during manual testing. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added ready-cache lookup hit/miss counters to `NarrativeCacheScheduler` stats and diagnostic summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added ready-cache hit/miss counts to the DevPanel narrative cache diagnostic summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added `interaction_clicked` stamping for cached contact/station offer consumption and line-bank speech consumption, with `ready_to_click` timing in scheduler diagnostics. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added interaction click count and ready-to-click average to the DevPanel narrative cache diagnostic summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added p50/p95 seconds to scheduler duration summaries, supporting Phase 6 percentile latency checks. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added ready-to-click p95 to the DevPanel narrative cache diagnostic summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added degraded job count/rate to scheduler diagnostics so degraded delivery remains visible as a metric. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added degraded job count/rate to the DevPanel narrative cache diagnostic summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Mirrored cached narrative interaction-click stamps into GenerationDiagnostics so report-only click-to-generate checks include ready-cache consumption paths. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added a guarded batch processor for system-arrival contact-offer jobs, allowing arrival prefetch to build ready deterministic offers for all queued contacts when story context is available. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Added low-priority system-arrival ambient pool jobs plus an `ambient_chatter` fallback-bank worker, so ambient refill work can produce ready scheduler payloads after higher-priority work clears. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6E | Completed system-arrival contact-offer coverage by extending deterministic story-agent offers to every chapter-director objective type, including legacy `KILL_SHIPS`, `DELIVER_ORE`, and `PICKUP_SPECIAL` candidates. | Tests: `run_story_agent_offer_builder_tests.gd`, `run_narrative_cache_scheduler_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Added a reusable GenerationDiagnostics gate assertion for click-to-generate reports, giving automated V2 flow tests a direct pass/fail hook. | Tests: `run_generation_diagnostics_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Surfaced click-to-generate report count in the DevPanel story bridge narrative-cache summary. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Added a cached dialogue-option V2 flow fixture that records contact-offer, station-offer, clarify-question, and accept-choice click/text lifecycle evidence, then asserts no click-to-generate report occurs on ready-cache/bundled-text paths. | Tests: `run_narrative_cache_scheduler_tests.gd`. |
| 2026-07-13 | Phase 6 exit gate | Added a reusable percentile SLO assertion for GenerationDiagnostics so warm-run gates can fail on missing samples or p95 latency over target for click-to-text and click-to-audio metrics. | Tests: `run_generation_diagnostics_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Added a scheduler cache-readiness SLO assertion so required-field readiness can fail on missing lookup samples or a ready-cache hit rate below the target. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Completed stale-bundle invalidation coverage for story beat, allowed-facts, and relationship-tier changes while preserving accepted/frozen truth. | Tests: `run_narrative_cache_invalidation_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6 exit gate | Closed the old sequential quest-timeout contention risk by re-verifying the single constrained quest-bundle path and scheduler one-in-flight contention guard. | Tests: `run_quest_speaker_rule_validation_tests.gd`, `run_narrative_cache_scheduler_tests.gd`. |
| 2026-07-13 | Phase 7 | Added the canonical `KaelenInteractionKinds` registry, including turn-in grouping and completion-safe aftermath reveal gating, and routed existing Kaelen handoff bank usage through the `AGENT_HANDOFF` constant. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Scoped Kaelen handoff pools by story revision, agent, system, and relationship band while keeping legacy unscoped store methods for compatibility. | Tests: `run_kaelen_handoff_store_tests.gd`, `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added the safe Kaelen interaction packet foundation, including mission cause/stake/giver, asked questions, accepted terms, relevant memory, safe Kaelen style, completion-only aftermath context, and salted director-secret leak coverage. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Wired the live Kaelen handoff prompt to consume the safe interaction packet, so broker lines can use allowed mission/story/style context while hidden director context stays behind the wall. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Completed the Kaelen handoff-pool scheduler path: prepared scoped lines are consumed before live generation, cached handoff banks beat canned fallback, and handoff pool refills now enter the central narrative cache scheduler with contention-aware deferral. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `run_narrative_cache_scheduler_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Wired Kaelen turn-in/completion and abandon generation through safe interaction packets, including completion-only earned aftermath instructions. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Closed the live Kaelen protected-field audit with a source guard that rejects direct reads of hidden angle, unknown truths, undelivered hidden hints, or never-reveal fields from Kaelen prompt generation. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Replaced UI-only Kaelen completion/abandon line globals with a mission-keyed `kaelen_reaction_bundle` stored on the active mission so generated reactions survive save/reload with the mission data. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added objective-complete Kaelen reaction refresh: mission progress now emits a one-time ready-to-turn-in snapshot and UIManager regenerates the persisted reaction bundle from that exact final state. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Tightened Kaelen turn-in clarity after live tutorial feedback: prompt rules and a clarity guard now reject unexplained next-task language and unintroduced offscreen story nouns while allowing generic resolved offscreen benefits. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Tuned Kaelen turn-in voice so completion lines can briefly show heart before snapping back to profit, keeping her human without losing her broker mask. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added Kaelen outcome-profile turn-in classification so completion packets distinguish clean/rough/late timing, partial delivery history, accepted terms, and learned story facts before choosing the turn-in interaction kind. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added gated visible-effect projection to Kaelen completion packets, letting turn-ins name safe concrete payoffs such as protected people, restored infrastructure, reopened routes, or advanced evidence before returning to profit. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added completion-only earned-background reveal boundaries so Kaelen can briefly explain safe aftermath or what a job prevented without exposing protected identities, motives, origins, hidden causes, or director-only facts. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added code-owned Kaelen relationship continuity for completed, declined, abandoned, expired, and failed mission outcomes; future handoff pools and safe packet style now use the derived relationship band instead of resetting to neutral. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `run_story_state_migration_tests.gd`, `run_context_block_leak_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Wired first generated-system arrival hails through prepared current-system Kaelen line banks during gate travel, preferring `first_system_arrival` lines before broker-level template fallback. | Tests: `run_fallback_line_bank_tests.gd`, `run_narrative_cache_scheduler_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Recorded delivered Kaelen playback as chronicle events plus Kaelen memory metadata, preserving line fingerprints/event kinds after actual handoff, turn-in, abandon, and first-arrival delivery. | Tests: `run_kaelen_interaction_bundle_tests.gd`, `run_campaign_schema_tests.gd`, `run_campaign_kaelen_memory_store_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Tightened public-board Kaelen turn-ins so generated and fallback lines must name the actual poster, actual job placeholder, and available local story pressure while preserving Kaelen's disgusted board-work voice. | Tests: `run_public_board_validation_tests.gd`, `run_mission_contract_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 7 | Added dialogue-bundle speaker-prefix, secret-token, and exact repeated-line validation with field-level degraded repair, and made deterministic fallback answers intent-shaped so safe generated-agent bundles remain unique. | Tests: `run_dialogue_bundle_validator_tests.gd`, `run_story_agent_offer_builder_tests.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 3A health gate | Added a procedural fallback chapter packet path so repeated chapter-plan validation failures no longer strand loading at 96%; fallback packets are labeled, logged, registered, and queued for first-interaction prefetch. | Tests: `run_chapter_narrative_director_tests.gd`, `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-13 | Phase 6D | Bounded fresh-campaign loading TTS warmup to a small Kaelen/N.O.V.A. starter subset and deferred full line-bank warmup until after loading release. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Added contact-aware system-arrival prefetching: system arrival events now include real registered faction agents and generated station faction contacts, and the scheduler queues one contact-offer bundle per contact. | Commits `6ad647c`, `a3ec983`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: add the worker/validation path that turns these contact jobs into ready offers. |
| 2026-07-12 | Phase 6E | Added the first scheduler worker/ready gate for contact offers. `GameRoot.process_next_narrative_cache_job()` now finds supported queued jobs, builds system-contact offer payloads through the deterministic story-offer builder, validates lifecycle stamps, and marks successful jobs ready for requester lookup. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: expand worker support beyond template-safe contact offers and wire consumers to use ready cached payloads before falling back to live generation. |
| 2026-07-12 | Phase 6E | Wired cached contact offers into the agent board path. `UIManager` now asks `GameRoot` for a requester-specific ready cached contact offer before calling fresh quest generation, and `GameRoot` can process only that contact's supported queued job if it is not ready yet. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: broaden worker support so more queued offer/bank types can satisfy UI requests. |
| 2026-07-12 | Phase 6E | Extended the scheduler worker/consumer path to current-station offer jobs. `GameRoot` can build a template-safe station-contact offer from the station's local faction contact, and the background agent-board path can consume that ready payload before live generation. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: Kaelen/N.O.V.A. startup banks and non-template offer generation still need worker coverage. |
| 2026-07-12 | Phase 6E | Added first-pass Kaelen/N.O.V.A. line-bank worker support. Startup and current-system bank jobs now produce ready `story_line_bank` payloads with speaker identity, voice profile, line IDs, and public-context projection only. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: consume line banks from runtime Kaelen/N.O.V.A. paths and replace template seed banks with validated model-authored banks. |
| 2026-07-12 | Phase 6E | Wired fresh-campaign loading to consume ready Kaelen/N.O.V.A. startup line banks for TTS warmup. The loading gate now queues startup prefetches, asks for requester-specific line-bank payloads, and waits only if TTS has bank audio to cache. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: choose bank lines during live Kaelen/N.O.V.A. runtime events instead of only pre-caching their audio. |
| 2026-07-12 | Phase 6E | Wired N.O.V.A. system-arrival chatter to consume ready current-system line banks before stock fallback lines. Existing chance, cooldown, and gate-transit silence checks remain in front of the bank lookup. | Tests: `run_nova_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: add consumption/memory accounting and model-authored bank generation. |
| 2026-07-12 | Phase 6E | Wired Kaelen's agent-handoff intro to consume ready current-system `agent_handoff` bank lines before canned fallback text. Existing unique LLM handoff remains the highest-priority source when ready. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: relationship/mission-specific Kaelen banks and consumption accounting. |
| 2026-07-12 | Phase 6E | Added background TTS warmup for current-system Kaelen/N.O.V.A. banks on system arrival. `notify_system_arrived()` now asks for ready line-bank payloads and caches their voice lines without blocking gameplay. | Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: persistent bank consumption/fingerprint accounting. |
| 2026-07-12 | Phase 6E | Added a central new-campaign loading prefetch event and queued it from the fresh-campaign loading release path. This captures station offer/mechanic/lounge intent, Kaelen startup bank, N.O.V.A. startup bank, and first chapter-beat bundles in the scheduler before gameplay resumes. | Commits `4cbfd54`, `9da52eb`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Follow-up: add the scheduler worker/ready gate so bank jobs become actual generated-ready content before marking the full checkbox complete. |
| 2026-07-12 | Phase 6E | Completed the chapter-packet prefetch trigger path: the existing 60% consumption threshold requests the next chapter packet, and successful packet commits now queue first interaction bundles for the first beats. | Commits `8278c61`, `ef09053`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Added a scheduler entrypoint for low-priority ambient/pool refill work. Refills now queue only when the pool is below threshold, idle, and no higher-priority jobs are pending/in flight. | Commit `62bd5ca`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Added station target/fly-to prefetching: station selection and accepted fly/dock commands now queue current-station, mechanic greeting, and likely lounge jobs through the scheduler. | Commits `f2e3c9d`, `924cab9`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6E | Wired mission lifecycle prefetch triggers into `GameRoot`: acceptance queues baseline/likely outcome work, progress queues likely turn-in work once the scheduler threshold is met, and completion queues exact P0 turn-in work. | Commits `a1e463c`, `4ac7649`, `9718df3`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. Full multi-mission smoke was attempted; it passed the new acceptance-prefetch assertion and later failed on older combat progress behavior, so the committed guard remains focused and deterministic. |
| 2026-07-12 | Phase 6E | Added the system-arrival prefetch path: the scheduler now accepts non-mission arrival events, plans current-system agent/Kaelen/N.O.V.A. work plus visible-station P0 work, and `GameRoot` queues those jobs from `system_changed`. | Commits `ff99985`, `6bdbfe0`. Tests: `run_narrative_cache_scheduler_tests.gd`, `parse_check.gd`, `parse_check_scene_scripts.gd`. |
| 2026-07-12 | Phase 6D | Added TTS-readiness groundwork: scheduler can queue audio cache jobs after text validation, text work wins over equal-priority audio work, TTS failures are tracked separately from ready text, and Kaelen/N.O.V.A. latency filler clips have a non-semantic safety gate. | Commits `63c066a`, `8994493`, `9531e8a`, `0f90ed7`. Tests: `run_narrative_cache_scheduler_tests.gd`, `run_speech_service_tests.gd`, `parse_check.gd`. Filler clips are gated but playback/assets are not wired yet. |
| 2026-07-10 | Plan | Initial evolution plan written from current map, handoff notes, narrative docs, source, and fallback summary. | No runtime code changed. First implementation action is Phase 0 baseline, not prompt tuning. |

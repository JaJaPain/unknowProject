# Fresh-Eyes Vision & Plan — 2026-09-23

> **DIRECTOR-ONLY DOCUMENT.** Section 5 contains the fixed-cast secret. Nothing
> in this file may be copied into `docs/world_lore.md`, `fixed_cast_souls.json`,
> any prompt template, or any other text that reaches an LLM prompt or the
> player. Small models leak what they are told. The secret lives in authored,
> baked content and in code only.

Written by Claude (Opus 5.5) after a read of `PROJECT_MAP.md`, `design_end_goal.md`,
`design_narrative_system.md`, `todo.md`, the fixed-cast souls, the TTS device
notes and the relevant runtime code. No code was changed in this pass.

**Abe's answers that shaped this doc (2026-09-23):**

| Question | Answer |
|---|---|
| Where can AI generation run? | **Hybrid.** Local by default, optional cloud model the player opts into. |
| Voice acting | **Baked fixed cast + TTS.** N.O.V.A. and Kaelen get a large pre-rendered bank; runtime TTS covers generated lines and the generated cast. |
| The secret | Defined. See Section 5. |
| Campaign length | **Open-ended.** Small arcs resolve, new ones appear, and the universe keeps going as long as the Captain is alive. |

---

## 1. Diagnosis: where the project is today

### What is genuinely strong

- **The north star is clear and testable** (`design_end_goal.md`). Most projects never get this far.
- **The causal backbone exists.** Quest causal contracts, plausibility validation, fact packets that keep private facts out of prompts, asymmetric faction desires, pressure tracks, investigations, a knowledge ledger, novelty history, and a chronicle that branches timelines on checkpoint reloads.
- **The fixed cast has real character tech.** State machines, rapport, attachment ledger, and small tricks like `NovaAnatomySlip`, where the model writes the setup and code guarantees the payoff. That is the right pattern for small models, and this plan relies on it heavily.
- **Kaelen already remembers deaths across rollbacks** (`GameRoot.record_player_death` → `CampaignKaelenMemoryStore`, `_classify_kaelen_rollback`). By accident, that is the first building block of the secret.

### What fresh eyes see as the core problem

**The project is asking a 4B model to be the author, then building ever more validators to catch it failing.** Evidence from the project's own notes:

- The critic had zero discriminative power (passed 28/28 labeled cases).
- Writer eval notes say *"several accepted lines are plainly not good."*
- The 12B bible generation fails JSON parsing and starves the small model of VRAM.
- `GameRoot.gd` (10.8K lines), `LLMInterface.gd` (7.7K) and `UIManager.gd` (10K+) are carrying far too much.

Each validator is reasonable on its own. Together they are a treadmill: more generation leads to more failure modes, which leads to more validators, which leads to more plumbing. None of it makes campaigns feel more different.

**The reframe this whole doc builds on:**

> **Uniqueness comes from STRUCTURE and SIMULATION. The LLM is the VOICE, not the AUTHOR.**

A campaign feels unique when *who wants what, what happened, who remembers you, and what the place is physically like* are different. Those things can be generated deterministically from seeds and authored grammars, with 100% reliability and zero VRAM. The LLM then does what small models are actually good at: turning a fully specified situation into a few natural lines of speech in a specific voice.

The optional cloud tier (Section 8) is where real *authoring* can happen, for players who opt in. Local play must feel unique without it.

### A note on "not restrictive / not repetitive"

I read the brief as both: the game should never feel **repetitive** (the same job again) or **restrictive** (the game railroading you). Sections 3 and 4 add player-originated missions and consequence chains to cover the second.

---

## 2. The foundation: "Breathe In, Breathe Out" (8GB, few loading screens)

This is the most important architectural suggestion in the doc, because it solves three problems at once: VRAM contention, generation latency, and loading screens.

### The rhythm

| Phase | What the player sees | What the machine does |
|---|---|---|
| **Breathe out: flight** | Open space, combat, mining, travel. Full rendering. | **Consumes** only content that is already generated and already voiced. The LLM is **unloaded** (`keep_alive: 0`). TTS only renders small reactive lines, on CPU. |
| **Breathe in: dock / gate jump** | The docking sequence, or the jump tunnel. Cheap to render. | **Produces.** The LLM loads and batch-generates everything the next stretch of flight needs. TTS pre-renders the resulting lines to an audio cache. The next system is built on a worker thread. |

Docking and gate jumps are already the moments you want to use as disguised loads. This makes them the game's **writer's room** as well. By the time the Captain undocks, every mission conversation, radio broadcast, taunt pool and N.O.V.A. reaction for the next stretch is already written *and voiced*. There is no live latency, no waiting on a spinner mid-conversation, and the LLM never fights the renderer for VRAM during combat.

### Why this fits 8GB

A proposed peak budget, to be **measured** in Phase 0 rather than trusted:

| Consumer | Flight | Dock / jump window |
|---|---|---|
| Driver + OS + compositor | ~0.8 GB | ~0.8 GB |
| Godot rendering (1080p, medium) | ≤ 4.5 GB | ~1.5 GB (tunnel / dock interior is cheap) |
| LLM `qwen3:4b` Q4_K_M + 4–8k KV cache | **0 (unloaded)** | ~3.2 GB |
| Kokoro TTS (82M) | CPU, 0 GB | CPU, or GPU if the adaptive selector admits it |
| **Peak** | **~5.3 GB** | **~5.5 GB** |

The key move is that **the LLM and full-scene rendering are never resident at the same time.** That leaves real headroom on an 8GB card instead of a knife-edge.

Rules that follow from it:

1. **No 8B or 12B model in the local shipping path during play.** `qwen3:8b` may run *only* on the landing screen or during the first-load campaign creation, when the renderer is idle. Players who want better authoring use the cloud tier.
2. **Model load cost is paid inside the window.** Loading a 4B model from an SSD takes about 1–3 s. The jump tunnel and docking sequences need a minimum length that covers load + batch + unload, with a diegetic extension if the batch runs long (Section 2.3).
3. **Flight-time generation is an exception, not the rule.** If something truly must be generated mid-flight (for example a player-originated pitch, Section 4.4), it goes to CPU inference or waits for the next window, and the UI says "Kaelen will get back to you".

### 2.1 Lookahead generation

You always know where the Captain *could* go next: the gates in the current system and the stations in it. `NarrativeCacheScheduler` already has triggers like `nearby_system`. Push it further:

- **When the Captain targets a gate**, start a worker-thread build of the destination system (geometry, faction roster, NPC recipes, quirks) using `ResourceLoader.load_threaded_request` and `WorkerThreadPool`. By the time the jump plays, the scene is ready to swap in.
- **At each dock**, pre-generate a content packet for the *current* system (missions, radio, rumors) and a smaller "arrival packet" for each *adjacent* system (the first broadcast, the first hail, the first Kaelen line on arrival).
- **Everything the LLM writes gets voiced in the same window** and saved to a campaign audio cache (`user://campaigns/<id>/voice_cache/`). A line with text but no audio is not "ready".

### 2.2 Loading screens: target exactly one

| Moment | Treatment |
|---|---|
| Game boot | The only real loading screen. Warm the shader pipeline cache here (render every material and particle once off-screen), so there is no first-combat stutter. Godot 4 compiles pipelines lazily, and that stutter reads as "loading" even when nothing is. |
| New campaign | The tutorial is authored, so it can start immediately. Campaign generation (premise, first arcs, first systems) runs **in the background during the tutorial**. The player never waits for it. |
| Gate jump | Tunnel sequence, 6–10 s. Next system swaps in during it. |
| Docking | Tractor beam + docking animation, 4–8 s. The station UI and the content packet are ready when it finishes. |
| In-system travel | No loads, ever. Stations, planets and belts all live in the same scene. |

### 2.3 Diegetic stalling

If the batch is not finished when the minimum tunnel time is up, **extend the tunnel with a reason**: gate turbulence, a longer exit burst, N.O.V.A. calling out "field harmonics are off, holding us in the throat for a moment". Author 20–30 baked N.O.V.A. lines for this. If generation fails outright, the fallback content is used and the player never knows.

This also creates a free hook for the secret (Section 5): occasionally, during a long stall, there is a faint second voice on the channel.

---

## 3. Making each campaign structurally unique

### 3.1 Replace "one campaign bible" with an **Arc Engine**

The current model is one spine written at campaign start: 5–6 chapters that lead to one ending. That clashes with the open-ended answer, and it puts the whole campaign's quality on one fragile 12B generation.

Instead, run **overlapping arcs of different sizes**. Arcs start, escalate, resolve, and their *consequences* seed the next arcs:

| Arc scale | Lifetime | Example |
|---|---|---|
| **Personal** | 1–3 missions | A mechanic owes money to the wrong people and needs a quiet delivery. |
| **Local** | One system, 5–10 missions | Two generated factions fight over a failing reactor station. |
| **Regional** | 3–5 systems | A plague ship is moving through the gate network and every system reacts differently. |
| **Undercurrent** | Whole campaign, never fully resolves | The secret layer (Section 5). |

At any moment, 1 regional, 2–3 local and a handful of personal arcs are live. When one resolves, the **Consequence Router** reads *how* it resolved (who won, who was humiliated, what the Captain did, what was destroyed) and seeds new arcs from it. This is "storylets" / quality-based narrative, the approach behind *Fallen London* and *Sunless Sea*, and it is proven for open-ended play.

**Why this makes campaigns different:** two campaigns can start from similar premises and still diverge completely after two or three resolutions, because the Captain's choices pick which consequences exist. It also maps cleanly onto systems already built: arcs are made of desires (`DesireProgressLedger`), pressure (`LocalPressureDirector`), investigations (`InvestigationRuntime`) and resolutions (`CampaignResolutionCompiler`). The Arc Engine is mostly a scheduler over those.

### 3.2 A **Premise Deck** instead of free generation

Arc seeds come from an authored deck of **premise archetypes**, filled in with generated specifics. Authoring the deck by hand, once, is what makes quality reliable. Start with ~40 and grow it; combined with the other generators below, the space gets very large very fast.

Each premise card is a small data file with roles, pressure tracks, 3–4 escalation beats, 3+ possible resolutions, and the consequences each resolution emits. Examples:

- **Gold rush**: something valuable was found; everyone is arriving at once.
- **Succession crisis**: a leader died; three heirs, and one of them is lying.
- **Quarantine**: a station is sealed; nobody agrees on why.
- **Dying star**: the system has a few in-game weeks left; who evacuates whom?
- **Cold war**: two factions are one incident away from shooting.
- **The heist**: someone plans to rob the richest thing in the system and needs a pilot.
- **Cult of the gate**: a movement believes the gates are alive.
- **Collapse**: the faction that held the system together is failing; vultures circle.
- **Charter vote**: the Captain's actions tip a vote.
- **Ghost fleet**: ships that vanished decades ago are showing up on sensors.
- **Refugee exodus**, **forged history**, **monopoly break**, **debt spiral**, **mutiny**, **sabotaged terraforming**, **defector**, **smuggled AI**…

Cards also declare **which mission verbs they can express** (kill, deliver, mine, investigate, recover, comms reversal…). That is how the "unique REASON, familiar verb" requirement in claim 8 gets met reliably.

**Card usage is remembered per computer, not per campaign** (Abe, 2026-09-23). A `PremiseCardHistoryStore` works like the existing `NoveltyHistoryStore` and `RunOpeningHistoryStore`: a small file in `user://premise_card_history.json`, outside every campaign slot, so **deleting a campaign never resets it**.

How drawing works:

1. **Filter.** Start from the cards that fit the moment: requirements, required system hazards, the seeds the last story left behind, and the main-story beat that's needed next.
2. **Never repeat within a campaign.** A card already used in this campaign is never drawn again in it.
3. **Unused first.** Among the fitting cards, draw only cards not yet used in the current **cycle**.
4. **When the fitting cards run out, take the least recently used.** If every fitting card has been used this cycle, draw the one used longest ago, and never one of the last ~30 cards used on this machine. Exhaustion is judged per situation, not across the whole deck, so a rare card (a black-hole story) can't block everything else.
5. **New cycle.** When ~90% of the whole deck has been used, a new cycle begins. The "used this cycle" marks clear, but the last-used order is kept, so the recency rule in step 4 still applies across the reset.
6. **New cards jump the queue.** Cards added in a game update have never been used, so they're drawn first.

What counts as "used": a card is marked used when the player is first **shown** its opening beat (an offer, a hail, a notice). A card drawn in a campaign that was deleted before the player saw it doesn't count. The store holds only card ids, a cycle number and a use counter: no story content, no names, nothing about the fixed cast.

Scope: `user://` is per Windows user account. If the game ships on Steam with cloud saves, syncing this file makes it follow the *player* across machines, which is arguably better.

### 3.3 **Faction DNA**: new factions per system that are *felt*, not just named

`CampaignGeneratedFactionStore` and generated desires already exist. What is missing is making each generated faction **look, sound and behave** differently, so the player recognises them within seconds without reading a label. Give each faction a DNA record, generated from a seed:

| Gene | Drives | Uses existing tech |
|---|---|---|
| Ideology axes (order/freedom, profit/duty, tradition/progress) | Desires, laws, who they like | Generated desires, relationship spectrum |
| **Ship design language** | Allowed kitbash hulls/parts, silhouette bias (long/spiky/boxy/asymmetric), paint pattern, hull wear | `ShipAssembler.generate_recipe`, kitbash parts, badges |
| Palette + badge | Hull colours, engine exhaust tint, station lighting | Faction materials, badge sheets |
| **Naming language** | Phoneme set + naming patterns for ships, people and places | `CampaignSystemNames` |
| **Voice family** | Kokoro blend weights, speed band, comms filter preset | Kokoro voice blending (already used) |
| Combat doctrine | Swarm vs. heavy, drone-heavy, ambush, honour duels | Combat AI, taunt pools |
| Local laws | Weapons-cold zones, tariffs, mining permits, curfews | Generalise `IllegalMiningEnforcement` |

**Local laws are a secret weapon for uniqueness.** A system that bans scanning, or where mining without a charter is a capital offence, or where docking requires a bribe, changes how the player *plays*. Every law is also a free source of smuggling, bribery and enforcement missions.

### 3.4 Reputation answer: **Deeds that travel**

`design_end_goal.md` left open what reputation means when factions change per system. Recommendation: **three layers.**

1. **Per-faction standing** stays, but only for factions in systems you have visited. The HUD shows the factions *of the current system*.
2. **People** remember you individually (Section 3.6).
3. **Deeds** are portable. Every significant act becomes a Deed record ("destroyed a relief convoy", "spared a Wraith captain", "broke the blockade at Tessin"). Deeds **travel through the gate network as rumours** and arrive in new systems before or after you. Each new faction **interprets your deeds through its own DNA**: pirates admire the convoy kill, merchants fear it, a religious faction thinks the spared captain means you are chosen.

Your reputation in a brand-new system is then already unique to *this* campaign, without any faction having travelled. It also creates great moments: arriving somewhere new and hearing a stranger on the radio tell a garbled version of what you did three systems ago.

### 3.5 **System Quirks**: systems that play differently

Visual variety alone will not make systems memorable. Give each system 1–2 **quirks that change the rules**, drawn from a deck and made cheap with shaders and environment parameters:

- **Pulsar**: a sweep every 90 s knocks shields offline, so fights are about timing.
- **Nebula**: sensor range cut to a third; ambushes and hiding.
- **Ion storm**: drones disabled while the storm front passes.
- **Dense debris**: salvage-rich, collisions dangerous, big ships struggle.
- **Dying star**: the campaign clock matters; stations evacuate over time.
- **Black-hole proximity**: time dilation. Contracts near the well run on a different clock.
- **Dead system**: no stations, only derelicts and one squatter outpost.
- **Gravity tides**: asteroid belts drift over hours, so mining spots move.
- **Relay dark zone**: no comms, so N.O.V.A. is the only voice and Kaelen goes silent. (Also a secret hook.)

Quirks feed the Premise Deck (a dying star wants the *Dying star* or *Refugee exodus* card) and Faction DNA (who would choose to settle in a nebula?). The combination is what makes systems unrepeatable.

### 3.6 **The Recurring Cast** (nemesis and ally memory)

One of the most effective emergent-story systems in modern games is the *Shadow of Mordor* nemesis model: individuals who remember you, change because of you, and come back. It needs very little LLM.

- Named pilots (enemy aces, rival haulers, a stubborn customs officer) are persistent records in `CampaignNpcIdentityStore` / `CampaignNpcStateStore`.
- When the Captain beats, spares, humiliates, rescues or cheats one of them, the record changes: a **scar** (a visible kitbash damage or patch part on their ship), a **grudge or debt**, a **promotion or fall**.
- They **reappear** in later systems with new ships and new allegiances, often inside other arcs. The pilot you left drifting two systems ago now runs the blockade you need to get through, and opens with a taunt about the drift.
- Hails and taunts use the existing taunt pipeline, conditioned on the shared history.

Players tell stories about the recurring cast. That is the "you won't believe what happened in my game" outcome from `design_narrative_system.md`.

### 3.7 The main story: Hidden Hand, Story Ledger and the Showrunner pass

Premise cards make each chapter reliable, but on their own they don't add up to a main story. This section adds one, without writing it in advance. **The main story comes together from what the player has already seen, so that looking back it feels planned.**

**Five pieces:**

1. **The Hidden Hand.** At campaign start, draw a hidden actor's *motive*, *method* and *goal* from decks. It runs as a background agent, executing plan steps on the campaign clock and adapting when the player interferes. Its **identity is left open**: *what* is happening is fixed, *who* is doing it isn't decided yet.
2. **Loose threads.** Every premise card carries 2–4 concrete, unexplained details (`loose_threads`, tagged with the methods they could be evidence of). When a card is drawn, some threads are traces of the Hidden Hand's current plan step and the rest are decoys.
3. **Casting from people already met.** Card roles marked `prefer_existing` reuse people the player already knows. When the story locks (below), the Hidden Hand's identity is **cast from that known pool**: whoever explains the most threads the player has seen.
4. **Beats with a purpose.** The main story follows a dramatic shape (setup → rising pressure → midpoint reveal → crisis → climax → aftermath). The Arc Engine draws cards whose `beat.function` and `hidden_hand_compat` fit the beat it needs next, like a drama manager.
5. **A theme per campaign.** Pick a central question (the premise-card `themes` vocabulary) and a few recurring motifs. Card selection prefers matching themes, and the small LLM gets the motifs as flavour.

**The Story Ledger.** Code writes a compact shorthand entry the moment each event happens. An LLM never summarises it, because LLM summaries drift. For example:

`J3 | card:rigged_assay@Vessa | cast:oren(dockmaster,helpful) | thread:t_after_hours_stamp pinned=yes | player:returned_to_chief`

Forty events fit in about 1.5–2k tokens. The ledger is the input to the Showrunner and to Kaelen's recaps, and it doubles as a debugging trace.

**The Showrunner pass** (the medium model, `qwen3:8b`, or the cloud tier if opted in):

| Pass | When | What it does |
|---|---|---|
| Draft | Around jump 2 (trigger: ≥4 threads, ≥3 known cast) | A private, revisable guess at the direction. Its only effect is to bias which threads get seeded next, so hints start pointing at the likely answer. |
| Lock | Around jumps 4–6 (≥6 threads, ≥3 engaged by the player, ≥4 known cast) | Commits the identity and the hidden truth; schedules the midpoint reveal. From here on the plan **constrains** card draws. |
| Re-plan | After big player choices, or if the chosen identity is killed or removed early | Re-plans the next 3 beats. A player derailing the scheme is a feature. |
| Season end | When the main story resolves | Picks which leftover threads and seeds start the next main story. |

**How each pass works (code proposes, the model chooses and explains, code checks):**

1. Code scores the ledger and proposes the **top 3 candidates** (person + motive + method), each with the threads it could explain.
2. The model **chooses one by ID** and writes, in schema-constrained JSON (Ollama's `format` option): the hidden truth in a few sentences, how each thread connects, and the next 3 beats. It refers to everything by ID and invents no names or facts.
3. Code **checks** that every ID exists, that at least 3 threads the player actually saw are explained, and that nothing contradicts the ledger. On failure it retries once, then falls back to code's top-scored candidate.

**Fitting it in 8GB:** the pass is never urgent. Run `qwen3:8b` on **CPU in the background** during flight (at about 5–10 tokens/s, a ~600-token answer takes a minute or two; it needs ~5–6GB of system RAM, so 16GB is the recommended spec), or on the GPU during a docked session. Opted-in players send the pass to the cloud model instead. This is the single best place in the game to spend cloud quality.

**The player's thread board:** `InvestigationPanel` becomes a board where the player pins details they find suspicious. Pinned threads get extra weight when the story locks, so a plausible player theory can come true.

**Hard rule:** a reveal must point to at least 3 things the player actually saw. If nothing fits well enough, the lock is postponed and more threads are seeded. The fixed-cast secret (Section 5) stays completely separate and never enters the ledger or any Showrunner prompt.

---

## 4. Unique missions per campaign: the **Mission Composer**

You asked for a system that creates unique missions for each campaign. The existing pieces (8 capabilities, causal contracts, investigation shapes) are good raw material. The missing piece is **composition**: missions today are mostly one verb with one cause. A composer builds each mission from independent layers, so the number of distinct missions multiplies instead of adding.

### 4.1 The five layers

```
MISSION = Verb(s)  ×  Reason  ×  Complication  ×  Turn  ×  Fallout
```

| Layer | Source | Example |
|---|---|---|
| **Verb(s)** | The existing capabilities: kill, deliver ore, courier, investigate signal, pickup special, purchase delivery, recover combat drop, comms reversal. Chain 1–3 of them. | Deliver → Investigate |
| **Reason** | The live arc and the requester's desire (causal contract). **Never** authored per mission. | The heir needs proof the will was forged before the charter vote. |
| **Complication** | A deck of ~30 complications, filtered by system quirk, local laws and faction DNA. | The cargo is contraband under local law; the drop point is inside a nebula. |
| **Turn** | A deck of ~20 mid-mission turns, rolled with a probability (not every mission turns). | The target hails you and makes a counter-offer. |
| **Fallout** | What each way of finishing does to the world: deeds, standings, pressure tracks, recurring cast, new arc seeds. | Deliver honestly → heir wins the vote; sell to rival heir → a blockade appears next visit. |

The LLM never invents structure. It receives a fully resolved mission and writes **only** the requester's lines, the hail during the turn, and the fallout reaction. That is exactly the narrow, fact-packet-fed job the existing `DialogueFactPacket` + quality-gate path is built for.

### 4.2 Turns that make missions memorable

Turns are where a returning player is surprised. A starter deck:

- **Counter-offer**: the target hails and offers more to switch sides (built on `CommsReversalCapability`).
- **Wrong cargo**: the sealed container is not what was declared (scan reveals it; choose: deliver, dump, sell, confront).
- **The requester is the problem**: halfway through, evidence shows the job serves the requester's lie.
- **Third party**: a recurring-cast rival is working the same job.
- **Surrender**: the kill target powers down and begs; a spare becomes a Deed.
- **Double booking**: two factions hired you for opposite outcomes, and each assumes you're theirs.
- **Stowaway**: someone is in the hold; they talk.
- **Law change**: the local law shifts mid-mission (curfew, tariff), turning a legal job illegal.
- **Quirk strike**: the system quirk hits at the worst time (pulsar sweep, ion storm front).

Turns always **offer a choice** and always emit fallout, which feeds Deeds, the Recurring Cast and the Arc Engine. That is what makes the world feel non-restrictive: the player's answer to a turn becomes the next part of the story.

### 4.3 Failing forward

A failed or abandoned mission must be **story, not a dead end**. Every mission definition carries a failure fallout just like its success fallout: the convoy you didn't protect gets raided, prices spike, the requester turns up later bitter or ruined, a recurring-cast pilot takes credit. Nothing just disappears from the board.

### 4.4 Player-originated work: **Leverage**

The strongest way to make missions unique is to let the player *create* them. `KnowledgeLedger` already tracks what the Captain knows. Turn knowledge into a tradeable resource:

- Things you learn (a forged manifest, a patrol schedule, where a derelict is, who the stowaway really is) become **Leverage** items.
- At any station, you can **sell, trade or threaten** with Leverage: offer the manifest to the rival heir, tip off customs, blackmail the requester.
- Each use generates a new mission or arc beat on the spot, from the composer, with the Captain as the cause.

No two players will make the same Leverage decisions, so no two campaigns get the same player-originated missions. This is mostly composition over existing systems, and the LLM work fits in the next dock window ("Let me make some calls. Come back after your next run.").

### 4.5 Not everything should be a mission

A world that only offers contracts feels like a job board. Mix in **uncontracted events** in space, generated from the same layers without a requester: distress calls (real or bait), a derelict drifting through, two factions skirmishing near a belt (pick a side or loot the wreckage), a recurring-cast pilot waiting at a gate. These come from the dock-window content packet, so they are pre-voiced.

### 4.6 **System radio**: the world talks while you fly

Every system gets a generated radio station (host personality from Faction DNA + the system's premise). Broadcasts are written and voiced during the dock/jump window, then played during flight:

- News that reflects the Arc Engine (your deeds, garbled; the charter vote; the quarantine).
- Ads for local businesses, propaganda, public notices about local law changes.
- Recurring-cast call-ins and the occasional bounty notice with your name on it.

It is cheap (pre-rendered audio), makes the offscreen simulation visible, makes flight time feel alive, and it is one of the strongest "this place is different" signals you can give. Passing everything through a **comms/radio filter** (band-pass, light distortion, static) is doubly useful: it sells diegetic radio *and* masks TTS artifacts. Apply the same filter to generated NPC hails.

---

## 5. The Undercurrent: N.O.V.A., Kaelen and the secret

### 5.1 Canon (director-only, never in a prompt)

- N.O.V.A. and Kaelen come from **another dimension in which the Captain died**.
- They want to **bring the Captain back** to that dimension. There is a **problem** they must solve first. The problem is **undefined** and stays that way.
- **They do not like each other.** They cooperate only because both want the Captain back.
- **Neither is physically present** in the Captain's universe. *How* they are present is unknown.
- **Kaelen does appear in lounges sometimes** (Abe, 2026-09-23). What stands at the table is not her real body. The technology is undefined; the working model is a **next-level android**, a perfect body that transmits all of its senses back to wherever she really is. N.O.V.A. has no body at all and lives in the ship.
- None of this is known to the player. It may never be answered.

### 5.1a Kaelen's android: flawless by design

The android is **indistinguishable from a human** (Abe, 2026-09-23). Nobody around her, whether NPC, scanner or player, should ever suspect it. That makes it a different kind of secret from the rest of the undercurrent: **the body produces no hints at all.**

- **In the lounge she is simply a woman.** She eats, drinks, laughs, gets irritated and reacts instantly. Her look and clothes change naturally between visits. She has no tells: no latency, no cold skin, no odd voice filter, no glitch.
- **No scans, no damage, no machinery.** Nothing in the game can scan her, hurt her, or show what she is made of. This is not because she dodges it; it simply never comes up. If a lounge turns violent, she has left for ordinary, believable reasons (a call, a deal elsewhere).
- **The voice in person is clean.** No comms filter in the lounge; the comms filter applies only when she is actually on comms.
- **Generated NPCs treat her as an ordinary, well-known broker.** They have met her, drunk with her and owe her money. Nothing they say hints otherwise.

**Where the mystery lives instead:** only in things *about* Kaelen, never in her body, and only at the rare tiers already in 5.4. For example: she knew something before she could have; she remembers a death that didn't happen in this timeline; she and N.O.V.A. argue a little too personally about the Captain. A player might one day wonder *who* Kaelen is. Nothing should ever make them wonder *what* she is.

Hard rule for content and code: **nothing may reference an android, proxy, robot, remote body or transmitted senses**, in any prompt, lore file, generated text or baked line. Add these terms to the Phase 0 secret-leak test.

### 5.2 The quiet structural gift

This secret explains the game's central design rule. **Every campaign is a different universe.** A new campaign is, in canon, another universe the Captain is living in, with the same two voices beside them. "Everything is new except N.O.V.A. and Kaelen" stops being a design constraint and becomes the mystery. A player who plays five campaigns might eventually ask: *why are these two always here?* That question is the payoff, and the game never has to answer it.

Nothing in the UI should say "universe" or "dimension". But the campaign select screen can be designed so that, in hindsight, it looks like threads or frequencies rather than save files.

### 5.3 Ground rules

1. **The secret never enters an LLM prompt.** Not the canon, not hints, not keywords. Every piece of secret-bearing content is **hand-authored and baked** into the fixed-cast voice bank. Add a test that fails if forbidden terms (for example *dimension*, *bring you back*, *other side*, *died*, when attached to the Captain) appear in any prompt template, soul projection, or `world_lore.md`.
2. **Every hint must be deniable.** Each has a mundane explanation available (glitch, broker paranoia, a joke, a comms error).
3. **Scarcity is the whole effect.** Hints are budgeted per campaign *and* per profile. Rare things stay rare. Nothing is ever repeated word-for-word to the same player.
4. **Nothing ever confirms.** No codex entry, no achievement name, no subtitle speaker label that gives it away.
5. **The generated world never knows.** Generated NPCs, factions and arcs cannot reference the fixed cast's nature. They may only notice surface oddities (Section 5.4, tier 0).

### 5.4 Hint tiers

Hints are selected by a new `UndercurrentDirector` (code-owned, like `FixedCastStateMachine`), which reads the **Echo Ledger** (5.5) and a per-campaign budget.

| Tier | Frequency | Examples |
|---|---|---|
| **0: Texture** (always on, deniable) | Constant, low-key | N.O.V.A.'s anatomy slips (already built): she keeps reaching for a body she doesn't have. N.O.V.A. and Kaelen are coldly polite to each other. Kaelen is completely ordinary in person (Section 5.1a); the texture comes only from her knowing a little too much. Her broker fee is never seen being spent. |
| **1: Friction** | A few per campaign | **Two-hander scenes**: baked exchanges where N.O.V.A. and Kaelen snipe at each other in front of the Captain, then stop abruptly, as if remembering an agreement. They argue about the Captain's safety *a little too personally* for a ship AI and a broker. |
| **2: Uncanny** | 1–2 per campaign, not every campaign | **Crossed wire**: N.O.V.A. thinks a channel is closed, and the Captain hears half a sentence of her and Kaelen arguing, then static. **Dark zone**: in a relay dark zone (Section 3.5), Kaelen *still* says one line, when nothing should reach the ship. **Tunnel stall**: during a long jump stall, a faint second voice under N.O.V.A.'s. **Too early**: Kaelen warns about a threat before any sensor could know. |
| **3: Echoes** (profile level) | Only for players with past campaigns; rare | Traces of the Captain's *previous campaigns* (5.5): a derelict carrying the name of the ship from their last campaign; an NPC wearing the face of an old recurring-cast rival; Kaelen: "You always take the long way through a belt." (the player's actual habit across campaigns). N.O.V.A. hesitates before calling the Captain "Captain", as if another word nearly came first. |
| **4: The line** | Extremely rare (5.6) | The death line. |

### 5.5 The Echo Ledger (cross-campaign memory)

A small **profile-level** store, outside any campaign slot, that survives campaign deletion:

- Past campaigns' ship names, a few recurring-cast identities, notable deeds, cause of each death, and measurable habits (preferred gate, preferred combat range, how often the Captain spares enemies).
- Which hints have already been shown to this player, so nothing repeats.
- Total play time and total deaths, for gating tier 3 and 4.

It can reuse the persistence and transaction patterns from `CampaignTransactionStore`. Kaelen's existing death-memory-across-rollback is the in-campaign version of the same idea, and should be **kept**: after a checkpoint reload, Kaelen occasionally references the death that "didn't happen" in this timeline, then covers it ("Forget it. Long shift.").

### 5.6 The death line

> Screen cuts to black. No UI. N.O.V.A.: **"Damn it, Kaelen! I told you this could happen!"** Two seconds of silence. Then the normal death screen appears, as if nothing happened.

Rules proposed to keep it extremely rare and powerful:

- **Never** in the tutorial, and never before the profile has ~5 hours of total play time and several deaths.
- Roughly a **1–2% chance per eligible death**, with a guaranteed cooldown afterward (for example no repeat for 20+ hours of play).
- The canonical line plays the first time. A small pool of 3–4 authored variants (for example Kaelen's cold reply, cut off mid-word) can exist for players who see it again years later, each shown once per profile.
- After a reload, N.O.V.A.'s first line is unusually subdued and Kaelen's is unusually short. Both baked.
- **Decision for Abe:** subtitles. Showing the line as a subtitle helps accessibility; showing it with a speaker name weakens deniability. Recommendation: show the text only if subtitles are on, with **no speaker label**, and never write it to any log, codex or recap.

### 5.7 The undefined problem, given a shape

The problem stays undefined, but each campaign's **Undercurrent arc** (Section 3.1) can pick one **motif** the fixed cast reacts strangely to, without explaining: a gate that N.O.V.A. refuses to use, a repeating signal that carries the Captain's ship ID, a derelict pilot with the Captain's callsign, a region where the Captain's deeds reach the radio *before* they happen. The motif never resolves, and the fixed cast never explains their reaction. Across many campaigns, players get many silhouettes of the problem and no answer.

---

## 6. 100% voice acted: the voice pipeline

### 6.1 Three voice tiers

| Tier | Who | How | When rendered |
|---|---|---|---|
| **Baked bank** | N.O.V.A. and Kaelen: reactions, barks, two-handers, stall lines, every secret-bearing line | Authored text, rendered offline by a build tool, loudness-normalised, shipped as OGG | Build time |
| **Pre-rendered runtime** | Fixed-cast lines that must name generated specifics (a system, a faction, a pilot), all mission dialogue, radio, hails, taunts | Kokoro, during the dock/jump window | Generation window, cached per campaign |
| **Live** | Tiny reactive lines that can't be predicted | Kokoro on CPU, short sentences only | During flight, rare |

**Critical rule: the baked bank and runtime lines must use the same voice model and blend.** If the baked bank were rendered with a better TTS or a voice clone, the switch to runtime Kokoro mid-conversation would be obvious and would break the illusion. Keep Kokoro for both until a better local model can do both. Any upgrade later is then a re-bake plus a provider swap, which `SpeechService` / `voice_provider_kokoro.json` already make possible.

### 6.2 Make the voice limitations diegetic

- **Kaelen speaks over comms** most of the time, and a comms filter hides TTS roughness. In the lounge she speaks **clean**, with ordinary room acoustics and no filter, so nothing about her in-person voice seems odd.
- **N.O.V.A. speaks through the ship's intercom.** A subtle, clean, slightly roomy filter; when the ship is damaged, her filter degrades with it.
- **Generated NPCs** speak through the comms filter of their faction's DNA (Section 3.3), so a faction *sounds* like itself.

### 6.3 Voice DNA for the generated cast

Each generated NPC gets a voice recipe stored in its identity record: Kokoro blend weights (2–3 base voices), speed, a small pitch shift, an EQ and comms preset. Kokoro blending is already in use (`voice_provider_kokoro.json`). Generating the blend from the faction's voice family plus a personal offset gives an effectively endless supply of distinct-sounding people. Keep a perceptual-distance check so two NPCs in the same scene never sound alike.

### 6.4 Baked bank scale

Rough target for launch: **~1,500 lines each** for N.O.V.A. and Kaelen, organised by the situation keys `FixedCastVoiceBank` and `BakedAudioIndex` already use, with 5–10 variants per common key so barks never repeat inside a session. Author them with help (Section 8.2), review them by hand, and render them with a batch tool. The secret-bearing lines are a small, carefully written subset.

---

## 7. Visuals on 8GB: kitbash, Blender, and shaders

You don't need many new bespoke assets. You need **modularity**, so the generators have more to combine, and **cheap variety**, so systems look distinct without costing VRAM.

### 7.1 Where new assets would pay off most

If Blender MCP time is spent, spend it on **modular parts that multiply**, all sharing a small set of **trim-sheet textures** (one atlas per material family) so they cost almost nothing in VRAM:

1. **Kitbash part families** for silhouette language (Section 3.3): 4–6 families (long/needle, blocky/industrial, organic/curved, asymmetric/scrap, spiked/aggressive), each with hull, wing, engine, and greeble parts.
2. **Scar and patch parts**: welded plates, missing panels, jury-rigged engines. These make the Recurring Cast's history visible.
3. **Station modules**: habitat ring, docking arm, refinery, antenna mast, hangar, shipyard frame. Stations assembled per faction DNA stop every station looking alike.
4. **Derelict variants**: broken versions of the same modules for dead systems, echoes and salvage.

### 7.2 Variety that costs almost nothing

- **Procedural skyboxes per system** from a seeded shader (nebula colour, star density, galaxy band), baked once to a cubemap in the jump window. No stored textures per system.
- **Planet shaders with seeds** (continents, gas bands, rings, city lights) rather than per-planet textures.
- **Decals** for faction markings, scars and wear, instead of new textures.
- `MultiMeshInstance3D` for asteroid fields and debris; LODs and impostors for distant ships.
- VRAM-compressed textures (BPTC/S3TC) with mipmaps across the board, and a hard texture budget per system.

### 7.3 Performance guardrails

- Shader pipeline warmup on boot (Section 2.2).
- A per-system budget for active NPC ships, lights and particles, enforced by the system builder.
- An in-game performance overlay in dev builds (VRAM, frame time, active nodes), and the Phase 0 measurement harness.

---

## 8. The optional cloud tier, and using big models at build time

### 8.1 Runtime: opt-in "Story Author" mode

For players who opt in (and supply a key or account), a cloud model takes over the **authoring** jobs that a local 4B model struggles with: filling premise cards with richer specifics, writing arc escalation beats, and writing mission dialogue in the dock window.

- Same contracts, same fact packets, same validators. The cloud model is a different writer behind the same gate, not a different system.
- Runs **only** in generation windows and is batched, so cost per session stays small and predictable.
- Results are cached into the campaign, so a campaign plays the same offline afterwards.
- If the network fails, the window falls back to the local model silently.
- **The secret rule still applies.** Nothing in Section 5 is ever sent.
- Only generated world data is sent. No personal data, and nothing that identifies the player.

### 8.1a Opt-in: "Create new story cards" (Abe, 2026-09-23)

Players with the cloud tier can let the API **write brand-new premise cards** for their own game, on top of the shipped deck. Deck cards are still the backbone; generated cards are an optional extra, held to the same rules.

**Settings** (off by default):

| Setting | Options |
|---|---|
| Create new story cards | Off · Only when I'm running low on fresh cards · Mix new cards in regularly |
| Spending limit | A monthly cap the player sets (for example in dollars or tokens). Generation stops at the cap, with no prompts mid-game. |
| Write a batch now | A button on the landing screen: "Write 5 new cards" |

**Cost warning.** The first time the player turns it on, and on the settings screen after that, the game shows:
- an **estimated cost per card**, calculated from the provider's current price list (shipped as an updatable config file, never hard-coded) and measured token counts: about 10k input tokens for the brief (mostly cacheable) and 3–4k output tokens per card, plus retries;
- a clear note that **cards that fail the checks still cost money**;
- a **running total** for this month against the cap.

**How a card is made:**
1. It's generated only in a generation window (docking, a jump, or the landing screen), never mid-flight.
2. The request carries the same writing brief Gemini uses, plus a short list of the player's existing card loglines and novelty tags so it doesn't duplicate them. The fixed-cast secret and reserved topics are handled exactly as in the brief, and nothing from Section 5 is ever sent.
3. **The in-game validator** (a GDScript port of `tools/premise_cards/validate_premise_cards.py`) checks it. On failure it retries once with the validator's messages; if it fails again, it's thrown away.
4. A card that passes is saved to `user://premise_cards_generated/`, marked as generated, and joins the same card-history system (Section 3.2), so it's drawn first as a never-used card.
5. Generated cards stay on the player's machine and are never uploaded or shared.

**Quality safety valve:** if a player dislikes a generated card while playing it, a "retire this story" option removes it from their local deck for good.

### 8.2 Build time: the biggest lever nobody is using yet

**Use large models when you build the game, not only when the player plays it.** Premise cards, complication and turn decks, law and quirk decks, name phoneme sets, radio show formats, and the fixed-cast baked bank are all authored once and benefit every player at zero runtime cost. That is where Claude (and your Blender MCP for parts) can help most:

- Draft decks in bulk; you curate and approve.
- Write N.O.V.A. and Kaelen bank lines against their soul bibles; you cut hard.
- Generate test campaigns headlessly and critique them for sameness.

Local models then only have to do the narrow, reliable job: voicing a fully specified situation.

---

## 9. What NOT to cram in

"We don't have to cram everything into this game." Agreed. Recommendations for what to **stop, freeze or defer**:

| Item | Recommendation | Why |
|---|---|---|
| Critic calibration on the 4B model | **Freeze.** | Measured at zero discriminative power. Small models are poor judges of their own output. Deterministic checks + authored structure do the job better. |
| Single-spine campaign bible on `gemma4:12b` | **Retire** in favour of Premise Deck + Arc Engine. | Fails to parse, starves VRAM, and conflicts with open-ended play. |
| `qwen3:8b` / 12B during play | **Remove from the runtime path.** | Cannot share 8GB with the renderer. Landing screen / cloud only. |
| New validators for LLM prose | **Stop adding.** Keep the existing ones. | Each new generation surface creates new failure modes; shrink the surfaces instead. |
| Planetary landing, deeper lounge social layer, new combat modes | **Park** until the Arc Engine loop is fun. | Don't serve uniqueness or the fixed cast directly, and each is a large project. |
| Splitting `GameRoot` / `LLMInterface` / `UIManager` | **Only where new work touches them.** New systems go in their own files and talk through signals. | A big-bang refactor is risky; opportunistic extraction is not. |

The guiding test from `design_end_goal.md` still applies: *which claim does this serve?* Add a second: **does this make the loop more different, or just bigger?**

---

## 10. Implementation plan

Ordered so that a **vertical slice** (tutorial → 3 generated systems → a few arcs resolving into new ones, all voiced, on an 8GB machine) exists as early as possible. Breadth (bigger decks, more quirks, more parts) comes after the slice feels right. Sizes: **S** ≈ days, **M** ≈ 1–2 weeks, **L** ≈ 3+ weeks of focused sessions.

### Phase 0: Measure and set the rules (S–M)

- VRAM/RAM measurement harness: Godot in a heavy combat scene, plus `qwen3:4b` loaded, plus Kokoro, on a real 8GB card. Record peak and 1% low frame times. Commit results to `docs/`.
- Confirm the model roster: `qwen3:4b` only during play; 8B/12B landing-screen or cloud only.
- **Secret-leak test**: fails if forbidden undercurrent terms appear in any prompt template, soul projection or `world_lore.md`.
- **Exit criteria:** a measured budget table replacing the estimate in Section 2.

### Phase 1: Breathe in, breathe out (M)

- `GenerationWindow` service: opens on dock start / jump start, loads the model, runs the `NarrativeCacheScheduler` queue as a batch, pre-renders all resulting speech, unloads the model, closes.
- Voice cache per campaign; "ready" means text **and** audio.
- Worker-thread build of the destination system on gate targeting; swap during the tunnel.
- Minimum tunnel/dock durations + diegetic stall with baked N.O.V.A. lines.
- Shader pipeline warmup on boot.
- **Exit criteria:** a full dock → undock → jump → arrive loop with **zero** live LLM calls during flight, no hitches on system swap, VRAM under budget.

### Phase 2: Premise Deck + Arc Engine (L)

- Premise card schema in `data/content/premise_cards/`, with 10 cards for the slice.
- `ArcEngine` scheduler over existing desires, pressure tracks, investigations and resolutions; arc scales (personal/local/regional).
- `ConsequenceRouter`: resolution → deeds, standing changes, new arc seeds.
- `PremiseCardHistoryStore` (per computer, survives campaign deletion): cycle-based "unused first, then least recently used" drawing, as described in Section 3.2.
- **Exit criteria:** in a headless run, 10 generated campaigns show different arc sequences after 3 resolutions each, and no arc dead-ends.
- **Content track (runs in parallel):** Gemini writes premise cards from `docs/gemini_prompts/premise_card_prompt.md`. A validator script checks structure, references and vocabularies automatically. Claude reviews only what passes, for playability and variety.

### Phase 2b: Main story: Hidden Hand, Story Ledger, Showrunner (M–L)

- Hidden Hand agent (motive/method/goal decks) with plan steps on `CampaignClock`.
- Story Ledger written by code at event time.
- Thread seeding from card `loose_threads`; decoy vs. trace selection; thread board in `InvestigationPanel`.
- Showrunner passes (draft, lock, re-plan, season end): code proposes, the model chooses and explains, code checks. Runs on CPU in the background or through the cloud tier.
- The locked plan constrains card draws.
- **Exit criteria:** in 10 headless campaigns, every lock explains ≥3 threads the simulated player saw, fallback rate is measured, and a playtester can explain the reveal back in their own words.

### Phase 3: Mission Composer (L)

- Layered composer: verbs × reason × complication × turn × fallout, on top of `MissionDefinition` and the capability registry.
- Starter decks: 12 complications, 8 turns (counter-offer first; it builds on `CommsReversalCapability`).
- Failure fallout on every mission.
- LLM writes only the requester lines, the turn hail and the fallout reaction, from the fact packet.
- **Exit criteria:** across 10 headless campaigns, the semantic signature of offered missions (verb + reason + complication + turn) repeats less than a set threshold; playtest shows turns producing real choices.

**→ Vertical slice checkpoint.** Play it. Tune. Decide what to cut before breadth.

### Phase 4: Faction DNA + System Quirks (M–L)

- DNA record in `CampaignGeneratedFactionStore`: ideology, ship language, palette, naming, voice family, doctrine, laws.
- `ShipAssembler` reads ship language; stations assembled from modules per DNA.
- Local laws as a generalisation of `IllegalMiningEnforcement`.
- 4 quirks for the slice: pulsar, nebula, ion storm, relay dark zone.
- **Ore types** (used by premise cards): `silicate` (exists today), `ferrite`, `water_ice`, `cuprite`, `thorium`. Asteroid variants by belt and quirk, per-type prices, `deliver_ore` gains an ore-type field, and `thorium` hooks into local law (a licence to carry).
- HUD reputation shows the current system's factions.
- **Exit criteria:** blind test: a playtester can tell two generated factions apart by ship silhouette and voice alone.

### Phase 5: Deeds + Recurring Cast (M)

- Deed records, rumour propagation through the gate graph, DNA-based interpretation.
- Recurring cast: persistent pilots, scars as kitbash parts, grudges, reappearance rules.
- **Exit criteria:** in a 3-hour playtest, at least one recurring pilot comes back, and the tester notices.

### Phase 6: The Undercurrent (M)

- `UndercurrentDirector` (code-owned, no LLM), per-campaign hint budget.
- Profile-level **Echo Ledger**.
- Baked lines: tier 0–2 texture, friction two-handers, crossed wires, dark-zone line, stall voice, post-reload lines.
- The death line with its gating, cooldown and subtitle rule.
- Tier 3 echoes (past ship-name derelicts, old rival faces, habit callbacks).
- **Exit criteria:** secret-leak test green; a scripted 50-death simulation shows the line at the intended rarity; Abe signs off the baked lines personally.

### Phase 7: World texture: Radio, events, Leverage (M–L)

- System radio station per system, generated and voiced in windows, played in flight through a comms filter.
- Uncontracted space events from the composer layers.
- Leverage: `KnowledgeLedger` items become sell/trade/threaten actions that spawn missions.
- **Exit criteria:** a playtester can name something they heard on the radio that related to what they did.

### Phase 8: Cloud Story Author (M)

- Provider behind the existing gateway; opt-in settings; batching in windows; caching; silent local fallback; secret rule enforced by the Phase 0 test.
- Opt-in "Create new story cards" (Section 8.1a): cost estimate from an updatable price config, player-set monthly cap, GDScript port of the card validator, local generated-card deck, "retire this story" option.

### Phase 9: Freshness qualification (M, then ongoing)

- Headless batch runner: generate 50 campaigns (first 3 systems each). Measure premise, mission-signature, faction-DNA and system-quirk overlap. This finishes the planned-but-unbuilt item G in `todo.md`.
- Human test: a player who has finished one campaign plays the first hour of a new one and marks everything that felt familiar. That list becomes the next content priority.

### Then: breadth

Grow the decks (premises toward 40+, complications 30+, turns 20+, quirks 12+), more kitbash families and station modules, more baked fixed-cast lines, informed by what Phase 9 says repeats first.

---

## 11. Decisions for Abe

| # | Decision | Recommendation |
|---|---|---|
| 1 | **Death model.** "As long as the Captain is alive" suggests death matters. Today death offers a checkpoint reload or a new campaign. | Keep checkpoint reloads (they are canonically N.O.V.A. and Kaelen pulling the Captain back, and they power Kaelen's cross-timeline memory). Optionally add a costly "hard mode" where death ends the universe. |
| 2 | ~~**Kaelen in the lounge.**~~ **Resolved (Abe, 2026-09-23).** | She appears in lounges sometimes through an undefined technology, modelled as a next-level android that transmits all of its senses back to her. It is flawless, and nobody ever suspects it. See Section 5.1a. |
| 3 | **Death-line subtitles.** | Text only if subtitles are on, no speaker label, never logged. |
| 4 | **Tutorial factions.** The 8 fixed factions are tutorial-only. | Confirm they never appear after the first system, except as rumours or deeds that reach later systems. |
| 5 | **Cloud provider and billing.** Player's own key, or an account you run? | Player's own key first (no running cost for you); revisit later. |
| 6 | **Premise deck authorship.** | Claude drafts in bulk from this doc; you curate. Start with 10 for the vertical slice. |
| 7 | **Hint visibility across campaigns.** Should tier 3 echoes appear at all for players who delete old campaigns? | Yes. The Echo Ledger survives campaign deletion. That persistence is part of the mystery. |

---

## 12. Summary

1. **Structure and simulation author the story; the LLM voices it.** Premise cards, an Arc Engine, a layered Mission Composer, Faction DNA, System Quirks, Deeds and a Recurring Cast make campaigns different in ways a returning player can feel, without depending on a 4B model's creativity.
2. **Breathe in, breathe out.** All generation and voicing happens during docking and gate jumps, which are also the only loads after boot. The LLM and full rendering never share VRAM, which is how this fits in 8GB.
3. **The secret is the reason every campaign is a new universe.** It is protected by hard rules: authored and baked only, never in a prompt, deniable, budgeted, never confirmed, with the death line kept extremely rare.
4. **Use big models at build time.** Decks, baked lines and part libraries are authored once with help from Claude and Blender MCP, and benefit every player at no runtime cost. The cloud tier is a bonus for players who opt in, not a requirement.
5. **Build a vertical slice first** (Phases 0–3), play it, and cut before adding breadth.

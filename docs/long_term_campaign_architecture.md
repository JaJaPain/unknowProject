# Long-Term Campaign Architecture

## Purpose

This is the living master plan for turning the current SpaceGame prototype into
an ongoing, procedurally authored campaign. It records approved design rules,
technical boundaries, implementation order, and decisions that can wait until
their dependent systems are ready.

The goal is not to generate everything at runtime with one prompt. The goal is
to let a local LLM direct an evolving story while deterministic game systems
protect continuity, performance, balance, saves, and player freedom.

## Hardware And Model Budget

- The target consumer GPU has **8 GB of VRAM**.
- The complete game must remain usable within that target, including gameplay
  rendering and local AI workloads.
- AI services may not assume that the story LLM, text-to-image model, vision
  reviewer, and every supporting model are resident in VRAM simultaneously.
- Background generation must use a model scheduler that loads, unloads, or
  swaps models by job type.
- Interactive gameplay receives priority over background generation.
- Asset jobs may pause between stages when the game needs GPU memory.
- Every model integration requires measured peak VRAM, system RAM, load time,
  generation time, output quality, and license compatibility.
- Open-source supporting models may be added when they provide a needed
  capability and fit the total 8 GB target.
- CPU or system-RAM fallback is acceptable for non-interactive jobs when it
  prevents gameplay stalls, even if generation takes longer.
- Quantization, reduced image resolution, staged upscaling, and cached outputs
  are preferred to raising the minimum hardware requirement.

The initial performance budget should reserve most VRAM for Godot rendering and
load only one major AI model at a time. Exact allocations must be based on
measurements from representative gameplay scenes rather than advertised model
sizes.

### Model-Agnostic Integration

The game must depend on AI capabilities, not model brands or provider-specific
request formats.

Game systems request bounded capabilities such as:

- plan a campaign arc
- produce structured mission dialogue
- summarize campaign history
- classify or review an image
- synthesize speech for a voice profile

A provider adapter translates that request for Ollama, another local runtime,
or a future supported backend. Provider URLs, model names, context limits,
quantization choices, and generation settings belong in external profiles
rather than gameplay code.

Each capability declares:

- a versioned input and output schema
- required modalities
- minimum context and memory requirements
- latency class
- validation rules
- deterministic or curated fallback behavior
- ordered compatible model profiles

Saved campaigns store generated results, provenance, schema versions, and asset
hashes. They must not require the same model to remain installed in order to
load or continue playing. Replacing a model may affect future generated content
but may not rewrite established campaign canon.

Model changes must pass a capability test suite before a profile can be marked
compatible. This tests schema compliance, PG-13 restrictions, protected canon,
speaker rules, timeout behavior, and fallback handling.

No gameplay, campaign, mission, NPC, or asset system may call Ollama or another
provider directly. Those calls belong behind provider adapters and the model
scheduler.

### Unified Speech Service

All spoken dialogue uses one provider-neutral `SpeechService`. Kaelen, faction
agents, minor NPCs, mechanics, station services, mission dialogue, and future
characters must not call a TTS engine or provider endpoint directly.

Game systems submit a speech request containing:

- text to speak
- stable speaker or voice-profile ID
- delivery priority
- optional interaction or dialogue ID
- whether playback should interrupt, queue, or only pre-cache

The speech service owns:

- text cleanup and speaker-rule validation
- voice-profile resolution
- provider selection and request translation
- synthesis, cancellation, queueing, and pre-caching
- audio decoding and playback
- cache keys and cache lifetime
- background-audio ducking
- connection status, timeout handling, and silent fallback

Characters store stable voice-profile IDs such as `voice.kaelen.v1`, not Kokoro
voice names. A replaceable provider profile maps that stable ID to the active
engine's voice, speed, pitch, style, language, and other supported settings.
Changing TTS engines therefore requires updating or generating provider
mappings rather than editing every NPC or dialogue caller.

The initial provider adapter may continue using the current Kokoro service.
Future adapters may use another local engine or platform-specific speech
backend while preserving the same game-facing calls.

Speech caching must include the normalized text, stable voice-profile version,
provider-profile version, synthesis settings, and output format. This prevents
an engine or voice update from accidentally reusing incompatible cached audio.

Tone and canon rules belong before provider synthesis. In particular, Kaelen's
`Shiny` rule and every other speaker's `Indy` rule must behave identically
regardless of which TTS provider is active.

### Initial Senior Model Profile

The initial senior-model profile is **Gemma 4 12B IT Unified**, using a 4-bit
GGUF. This is a replaceable deployment profile, not a permanent game
dependency.

Primary deployment:

- Ollama model: `gemma4:12b`
- Ollama-reported package size: approximately 7.6 GB
- Inputs: text and image
- Advertised context capacity: 256K tokens

Pinned GGUF source:

- Repository: `unsloth/gemma-4-12b-it-GGUF`
- Initial quant candidate: `UD-Q4_K_XL`
- Direct Ollama command:
  `ollama run hf.co/unsloth/gemma-4-12b-it-GGUF:UD-Q4_K_XL`
- License: Apache 2.0

The repository revision and downloaded file hash must be recorded before a
release build.

The reported 7.6 GB package size is not a safe peak-VRAM estimate. Runtime
buffers, KV cache, image tokens, and Godot rendering also consume VRAM.
Therefore:

- Do not use the advertised 256K context during gameplay generation.
- Start with a deliberately small context budget and increase only after
  measurement.
- Use low visual-token budgets for portrait classification.
- Allow partial CPU offload when Godot is active.
- Unload Gemma immediately after each director or portrait-review batch.
- Keep a smaller-model or curated-rule fallback if Gemma cannot run with safe
  rendering headroom on a particular 8 GB GPU.

## Approved Experience Rules

### Handcrafted Boundary

Only the first solar system's physical layout and resident starting factions
are fixed across campaigns.

After the first system, each new campaign creates its own:

- system topology and branch routes
- planets, moons, rings, asteroid fields, hazards, and encounter zones
- stations, outposts, gates, and deep-space locations
- major, minor, pirate, and unknown faction presence
- faction goals, influence, conflicts, alliances, and local reputation context
- ships, NPCs, businesses, missions, ambient encounters, and story arcs
- economy, ore distribution, regional demand, and notable rewards

Generation is campaign-seeded. Content must be different between new
playthroughs but deterministic and permanent inside one campaign. Reloading,
revisiting, dying and restoring a checkpoint, or temporarily leaving a system
must never reroll established people, factions, geography, resources, routes,
or history.

The current handcrafted test system is development scaffolding, not a fixed
second campaign system. It may remain as an automated-test fixture, but the
production campaign must replace it with a generated first destination.

Fixed game-wide elements remain limited to rules and reusable building blocks:

- Kaelen's identity, protection rules, and long-arc mystery
- the player naming rules (`Shiny` from Kaelen and `Indy` from others)
- supported gameplay capabilities and balance constraints
- curated portrait, voice, ship-part, visual, and fallback libraries
- PG-13 content policy and continuity validators

These fixed building blocks constrain generation without predetermining the
campaign's systems, inhabitants, factions, encounters, or story.

### The Player

- The player has no canonical name, gender, body, or spoken voice.
- Kaelen calls the player **Shiny**.
- Everyone else calls the player **Indy**, meaning an independent pilot.
- "Indy" may also be used for other unaffiliated pilots.
- Shiny begins in the handcrafted first system with the existing ship.
- The game does not explain where Shiny came from or how the ship was acquired.

### Campaign Shape

- The first system, its principal locations, and its starting cast are
  handcrafted and consistent between campaigns.
- The central story is newly generated for each campaign.
- The campaign has no required final ending. Story arcs may end, overlap, and
  lead to new arcs for as long as Shiny remains alive and the player continues.
- The player may ignore the main story indefinitely to trade, mine, fight,
  improve the ship, build relationships, or remain in a favored system.
- Story pressure should remind and tempt the player, not force departure.
- The tone may vary between space opera, political drama, adventure, and
  mystery, but all generated content must remain PG-13.

### Kaelen

- Kaelen can never be killed, permanently removed, or made unavailable by the
  generated story.
- Kaelen is the only character guaranteed to appear at every system's main
  station.
- Her appearance and presentation remain consistent for now.
- Her method of travel is never confirmed. She mocks or deflects direct
  questions.
- She knows a great deal, but she cannot see the future and can be surprised.
- She originates from an unknown final system and is observing earlier systems
  for an unrevealed purpose.
- Kaelen's deals are the primary story mechanism for revealing gates and
  encouraging travel.
- Kaelen may retain faint memories of discarded save timelines. These references
  must be rare, funny or unsettling, and never mechanically punish reloading.

### World Permanence

- Generated systems, gate routes, factions, NPC identities, ship designs,
  portraits, and established canon are permanent for that campaign.
- Generated assets are cached and referenced by stable IDs and generation
  seeds.
- Loading an earlier checkpoint rewinds mutable gameplay state but does not
  regenerate an already created place into a different place.
- Information learned after the loaded checkpoint may become hidden from the
  player UI again, while the cached physical content remains available to the
  campaign.
- Major NPCs connected to the player cannot die off-screen. Their deaths require
  a storyline in which the player is involved.

### Systems And Travel

- Systems are places to inhabit, not levels to clear.
- Gate locations should not be revealed immediately after arrival.
- The player should have time to learn local factions, work, trade, form
  relationships, and become involved before Kaelen offers a path onward.
- The map must eventually branch. At least some systems offer two viable onward
  routes so one disastrous relationship or region cannot trap the campaign.
- All offered destinations must be fully generated before the player can choose
  them.
- Temporary gate damage, blockades, missing coordinates, or political access
  requirements may delay travel when justified by existing game rules.
- The current gate implementation remains the default travel model.
- Rare stories may introduce unexplained ships that apparently travel without
  gates. The game does not need to explain how.
- Planets remain spaceborne landmarks and destinations. Surface landing is out
  of scope.

### Factions And Reputation

- Returning factions carry their established opinion of Indy into new systems.
- New factions form their own opinion unless information plausibly reaches them.
- Reputation may spread through shared organizations, allies, enemies, news, or
  direct communication.
- Gaining high reputation with one faction should concern its enemies.
- A player should not be able to become universally loved without difficult,
  exceptional choices and tradeoffs.
- Systems may change control, experience shortages, blockades, coups, or wars
  after long absences.
- Political change must use in-game time and believable rates. A brief return
  trip cannot completely transform a system without a specific active event.

### Missions

- Abandoning a mission removes it and causes a small reputation loss, normally
  2-3 points.
- Accepted untimed missions remain available until completed or abandoned.
- Timed missions use in-game universal time, never wall-clock time.
- A minor NPC becomes narratively major when Kaelen or a significant story arc
  starts routing important work through that character.
- The long-term mission system must support multiple active missions rather than
  the prototype's single active quest.

### Economy And Return Value

- Main stations provide persistent storage.
- Trading should support profitable regional price differences.
- Repeated buying and selling changes local supply and demand so a single route
  cannot produce infinite risk-free profit.
- Old systems remain useful through allies, stored goods, rare stock, local
  opportunities, faction rewards, expensive high-reputation upgrades, and
  Kaelen's callbacks to previous characters.
- Ship power-plant tiers provide a deliberate progression gate. Higher-tier
  power plants require specific materials introduced in later systems, so the
  player cannot unlock every ship upgrade while remaining in the opening
  region.
- Required upgrade materials must come from established system geology,
  regional trade, missions, faction rewards, or other normal campaign sources.
  They are not arbitrary blockers created only when the player opens the
  upgrade screen.
- Returning to an earlier trusted mechanic or faction vendor with later-system
  materials may unlock powerful upgrades, giving the player another practical
  reason to revisit old allies and stations.
- Economy controls should prevent mechanical exploits without punishing
  legitimate planning and merchant play.

### Ore And Asteroid Composition

Mining should support multiple resources rather than one universal ore.

- Each asteroid receives a deterministic, campaign-persistent composition from
  its seed, location, asteroid family, and system geology.
- Most asteroids contain a dominant common ore and may contain one or more trace
  materials.
- A small percentage of asteroids contain a finite rare deposit.
- Mining ticks draw from the asteroid's remaining composition rather than making
  an unlimited independent rarity roll.
- A rare material may appear as an occasional mining-tick discovery, but its
  total available amount was fixed when the asteroid was created.
- Rare deposits remain depleted after saving, leaving, and returning.
- Mining fields maintain a target population range rather than a fixed permanent
  list of rocks.
- Depleting an asteroid permanently retires that asteroid ID and composition.
- After enough universal time passes, the field may create a replacement
  asteroid with a new stable ID, new position, new shape seed, and newly rolled
  hidden composition.
- Replacement positions must respect ring geometry, navigation clearance, and
  minimum spacing from existing asteroids, stations, gates, and the player.
- Replenishment is gradual, capped, and field-specific. A player cannot clear a
  ring, wait briefly, and receive an immediate full reset.
- Rare-deposit probability is applied to each replacement from the field's
  geological profile. Depleting a known rare asteroid does not cause that same
  location or identity to return.
- Replenishment schedules and replacement seeds are campaign-persistent so
  reloading cannot reroll the next asteroid.
- Fields should never fall below a small gameplay-safe floor for long, even if
  heavily mined. Emergency common-ore replenishment may occur before normal
  replenishment, but it does not receive boosted rare-mineral odds.
- Scanners and upgrades may gradually reveal composition quality without always
  identifying exact quantities.
- Different systems, planets, hazards, and faction territories should have
  distinct geological probability profiles.
- Missions, regional industry, upgrades, and faction demand should give each ore
  a purpose beyond simply selling it for a higher price.
- Cargo must eventually support mixed resource stacks rather than the current
  single ore value.

This preserves the excitement of a rare mining tick while preventing reload
farming, infinite rare drops, and arbitrary changes to a previously known
asteroid.

## Core Architecture Principle

The LLM is a **story planner and writer**, not the authoritative game engine.

The LLM may propose:

- Themes, mysteries, conflicts, and story arcs.
- Faction and NPC concepts.
- Connections between established people and events.
- Mission intent selected from supported mission mechanics.
- Dialogue, rumors, descriptions, summaries, and eulogies.
- Candidate future systems and reasons to travel there.

Deterministic code must own:

- Stable IDs, schemas, saves, and migration.
- Whether an action is legal under game rules.
- Reputation arithmetic and faction relationship effects.
- Prices, supply, demand, rewards, and anti-exploit limits.
- Universal time and simulation rates.
- Mission objectives, timers, completion, failure, and abandonment.
- System topology and gate validity.
- Asset generation jobs, file paths, caching, retries, and fallbacks.
- PG-13 filtering and Kaelen's protected status.
- Applying world changes after validation.

The LLM never writes directly into a save file, Godot scene, economy table, or
live faction state.

## Campaign Data Model

The current `GlobalState` and `GameRoot` save are useful prototypes, but the
campaign needs explicit ownership boundaries before procedural generation.

### Campaign Manifest

Permanent identity and canon:

- Campaign ID and campaign seed.
- Creation version and schema version.
- Approved story premise and current long-range threads.
- Generated system registry.
- Stable gate graph.
- Faction registry and cross-system identities.
- NPC registry.
- Ship design registry.
- Portrait and voice registry.
- Canon facts that later generation is not allowed to contradict.
- Content-generation versions and original generation seeds.

### Timeline State

Mutable state at a save checkpoint:

- Universal date and time.
- Player location, ship condition, inventory, credits, and upgrades.
- Active and available missions.
- Reputation and known relationships.
- System political, security, and economic state.
- NPC current status and location.
- Pending simulation events.
- Current story beats and unresolved hooks.
- Player-visible map knowledge.

### Chronicle

Append-only significant events:

- Conversations and important choices.
- Mission offers, acceptance, completion, failure, and abandonment.
- Reputation changes with reasons.
- Favors, debts, betrayals, rescues, discoveries, and major purchases.
- Gate discoveries and first arrivals.
- Political changes witnessed or caused by Indy.
- Important NPC promotions and relationship turning points.
- Death details and the evidence used for Kaelen's eulogy.

Events should use structured records, not prose alone. Prose summaries are
derived and cached for LLM prompts.

### Kaelen Meta-Memory

A small campaign-adjacent record may survive checkpoint loading:

- Previous death category.
- A few timestamped and timeline-tagged prior-timeline phrases or facts.
- Number of timeline reversals.

On rollback, Kaelen observations newer than the loaded checkpoint move into a
bounded discarded-timeline archive. Campaign time and chronicle sequence, not
wall-clock time, determine which observations belong to the discarded branch.

This record must never alter balance, reveal future outcomes, or make ordinary
NPCs remember discarded events.

### Asset Registry

Each generated asset record includes:

- Stable asset ID.
- Owning campaign and entity ID.
- Generator type and version.
- Deterministic seed.
- Input specification.
- Output path and content hash.
- Validation status.
- Fallback status.

This registry allows portraits, ships, and future visual assets to remain stable
even when an older checkpoint is loaded.

### Generated Storage Policy

- TTS audio is synthesized on demand and is not permanently stored per
  character or dialogue line.
- A small temporary session cache may avoid repeating speech synthesis during
  the current play session.
- Temporary TTS files are cleared automatically and do not become campaign
  assets.
- Character identity, voice selection, speaking style, relationships, and
  memories are stored as compact structured records.
- Human-readable Markdown character summaries may be derived from those records,
  but Markdown is not the authoritative data source.
- Persistent campaign growth primarily comes from portraits, generated ship
  models, system specifications, and chronicle records.

### Visual Asset Strategy

Do not ask the text-to-image model to generate every visible texture. Use three
tiers:

**Procedural and reusable**

- Planet surfaces use reusable shaders, masks, noise, gradients, cloud layers,
  atmosphere parameters, rings, and curated material families.
- Moons use the same system with different seeds and parameter ranges.
- Asteroids use a small set of reusable rock materials, normal maps, and mesh
  families with deterministic scale, shape, color, roughness, and damage
  variation.
- Asteroid silhouettes are produced from one shared subdivided base mesh using
  deterministic vertex deformation: large directional stretching, several
  frequencies of 3D noise, and a small number of broad dents.
- Each asteroid stores only a deformation seed and compact shape parameters,
  rather than a unique model file.
- Use per-instance shader parameters or multimesh custom data so shape variety
  does not require duplicating materials.
- Asteroid collision begins with cheap approximate ellipsoids. A small reusable
  pool of convex collision shapes may replace them if visual mismatch affects
  navigation or mining.
- Common station surfaces, metals, windows, lights, and industrial materials are
  shared across systems.

**AI-generated when identity matters**

- NPC portraits.
- Faction emblems, propaganda, station advertisements, and signage.
- Story artifacts, transmissions, photographs, and unusual discoveries.
- Rare landmark textures when a system needs a singular visual identity.
- Optional source images used to derive masks or decals after validation.

**Curated fallback library**

- Tested planet, moon, asteroid, station, portrait, emblem, and story-art
  assets remain available when generation fails or exceeds its time budget.

Raw image-model output should not be treated as a ready-made planet material.
If AI-generated surface art is used, a deterministic post-process must make it
tileable, resize it, compress it, and validate obvious seams. Normal, roughness,
metallic, emission, and atmospheric behavior should come from controlled game
materials rather than trusting the image model to produce a coherent PBR set.

Generated ship storage is controlled by:

- Creating reusable faction and role variants rather than a unique mesh for
  every disposable patrol ship.
- Referencing shared textures instead of embedding duplicate copies where the
  import pipeline permits it.
- Stable seeds and content hashes for deduplication.
- LOD generation and mesh compression.
- Reserving bespoke ships for major NPCs, special factions, bosses, mysteries,
  and important story events.
- Campaign cleanup tools that can safely rebuild deterministic non-unique ships
  from their saved specifications.

## System Content Model

A typical generated system should use ranges rather than a rigid template:

- 1 main inhabited station.
- 1-3 secondary stations, outposts, or industrial locations.
- 2-5 visually important planets.
- 0-4 notable moons.
- Selective asteroid fields and resource regions.
- Several navigation, trade, patrol, and encounter zones.
- 0-2 environmental hazards.
- 2-4 major local factions.
- Several minor organizations.
- 6-12 initially important recurring NPCs.

Sparse and crowded systems should feel different. Not every planet requires an
asteroid field. Visual compositions such as a moon orbiting a huge planet should
be expressible by the system specification.

Hazards such as radiation, gravity anomalies, storms, or black-hole proximity
should influence routes, resources, and politics. They should support the
system's internal power struggle rather than replace it.

## Background Generation Pipeline

Generation runs outside the live gameplay frame and communicates through a
persistent job queue.

1. **Story Director Proposal**
   - Produces a compact plan for likely future branches.
   - Uses only known canon and structured campaign summaries.
   - Proposes two destinations when the upcoming map branch requires choice.

2. **Rule Validation**
   - Rejects non-PG-13 content.
   - Rejects any plan that kills or removes Kaelen.
   - Rejects unsupported mechanics and contradictory canon.
   - Checks system size and content budgets.

3. **System Specification**
   - Deterministic code converts approved intent into a complete schema:
     locations, factions, NPC slots, encounters, economy profile, gates, and
     required mission capabilities.

4. **Specialized Build Jobs**
   - Ship jobs call the procedural Blender generator with stable seeds.
   - Portrait jobs call the future text-to-image service.
   - The selected Gemma model checks portraits for severe defects, identity
     mismatch, PG-13 violations, and obvious visual corruption.
   - Dialogue and biography jobs create constrained text records.
   - Godot content jobs build data resources and placement manifests.

5. **Technical Validation**
   - Verifies required files, schemas, model importability, bounds, collision
     expectations, missing references, and performance budgets.

6. **Narrative Validation**
   - Verifies names, faction ties, gate links, protected characters, tone, and
     contradictions against campaign canon.

7. **Fallback And Retry**
   - Retries only the failed component with a bounded attempt count.
   - A failed portrait review returns structured defect tags to the image job.
   - Uses curated fallback portraits, ships, names, or missions when necessary.
   - Never blocks the main game indefinitely waiting for generation.

8. **Commit**
   - Atomically adds the completed system and assets to the campaign manifest.
   - A destination is not advertised to the player until this commit succeeds.

9. **Activation**
   - Kaelen or another valid source reveals the route after the player has spent
     sufficient time and engaged with the current system.

The first implementation should use a separate local worker process rather than
threads inside Godot for Blender, image generation, or long LLM jobs. Godot
submits jobs, polls status, and imports completed outputs. This isolates crashes
and keeps the render loop responsive. A model scheduler inside the worker must
serialize GPU-heavy stages under the 8 GB VRAM budget.

## AI Authoring Hierarchy

The current local model is capable of focused structured tasks, but the existing
all-purpose prompting approach will not scale to campaign direction.

### Senior Director: Gemma

The 4-bit Gemma model owns infrequent, high-value work:

- Create the campaign's underlying story premise.
- Maintain the long-range story bible.
- Plan major arcs, mysteries, reveals, and future branch possibilities.
- Review major continuity changes.
- Decide which established facts the smaller writer must honor.
- Review generated NPC portraits before assignment.
- Produce or approve the factual outline for Kaelen's eulogy.

Gemma does not remain loaded during normal gameplay. Its work is queued,
generated ahead of need, validated, stored as structured campaign data, and then
unloaded.

### Fast Writer: Small LLM

The smaller model owns frequent bounded work:

- Mission dialogue and short briefings.
- NPC conversational turns.
- Rumors, chatter, and local descriptions.
- Kaelen reactions and transitions.
- Variations written from an approved beat supplied by the story bible.

The small model may embellish presentation, but it may not alter major canon,
invent unsupported mechanics, kill protected characters, or redirect the
campaign away from Gemma's approved arc.

### Structured Handoff

Gemma should produce compact records rather than a long prose novel:

- Current arc and phase.
- Known truth versus player-visible belief.
- Active factions and motivations.
- Required future beats and optional hooks.
- Forbidden outcomes.
- Kaelen's knowledge and limits.
- Relevant NPC goals and secrets.
- Supported mission-mechanic tags.
- Tone weights for the current arc.

The game retrieves only the fields relevant to the current scene. Focused roles
then operate on that approved context:

- **Story Director:** proposes arcs and next-system motives.
- **Continuity Editor:** checks proposals against relevant canon.
- **Mission Writer:** adds flavor to a mechanic selected by game code.
- **Dialogue Writer:** writes one speaker turn using retrieved memories.
- **Summarizer:** compresses events and relationships.
- **Eulogy Writer:** writes from selected verified chronicle facts.

Code should choose the task, retrieve only relevant context, and validate every
response. Important creative plans use propose, critique, revise, validate rather
than one-shot generation.

## NPC Memory Model

Broad NPC memory is practical if it is retrieval-based.

Each NPC stores:

- Identity, role, faction, personality traits, and voice.
- Current opinion of Indy and confidence in that opinion.
- Relationships with other important NPCs.
- A small set of pinned significant memories.
- Unresolved promises, debts, threats, favors, and missions.
- A compressed relationship summary.
- References to chronicle event IDs.

Routine interactions are periodically summarized. Major moments stay as
individual events. Dialogue generation receives only the NPC profile, current
situation, relationship summary, unresolved obligations, and a few relevant
events.

Importance is dynamic. A minor shopkeeper or repair technician can be promoted
when Kaelen or the player's choices make that character central.

## Universal Time And Simulation

Introduce one campaign-wide clock before timed missions or off-screen change.

The exact calendar presentation can be chosen later, but it must expose:

- Date.
- Universal time on a 24-hour clock.
- Time remaining for timed missions.
- Time elapsed since leaving a system.

Time advances through travel, repairs, upgrades, mission actions, waiting,
docking services, and gate transit when the current gate story requires it.

Off-screen simulation runs in coarse steps, not frame by frame:

- Short absence: price drift, patrol changes, mission updates.
- Medium absence: shortages, faction pressure, leadership tension.
- Long absence: control changes, blockades, coups, or wars.

Protected major NPCs may be displaced, injured, imprisoned, or endangered
off-screen, but not killed without player participation.

## Story Pressure And Gate Revelation

Kaelen's deal follows a reusable rhythm:

1. Indy arrives and establishes a foothold.
2. Local work reveals factions, people, and tensions.
3. The player invests through missions, trade, allies, or conflict.
4. A local thread points toward something beyond the system.
5. Kaelen offers a profitable deal tied to a hidden or restricted gate.
6. The deal reveals coordinates, access, equipment, cargo, or a contact.
7. The player may accept, delay, refuse, or choose another generated branch.
8. The opportunity remains present or evolves without forcing departure.

Gate offers should be eligibility-driven, not based on a fixed quest count.
Possible inputs include in-game time in the system, local familiarity, number of
meaningful contacts, completed work, story readiness, and destination build
status.

## Evolving Map

The map unlocks after the first gate jump and represents player knowledge:

- Visited systems.
- Confirmed gates.
- Known but unvisited systems.
- Rumored or uncertain routes.
- Current known faction influence.
- Known hazards, wars, shortages, or blockades.
- Kaelen opportunities.
- Player notes and bookmarks.

Confirmed permanent routes do not randomly vanish. Access may be temporarily
blocked. Rumors may be inaccurate or stale.

## Direct World Targeting

Approved quality-of-life feature; it may be implemented after the current
foundation checkpoint whenever the targeting and UI work can be isolated safely.

- Right-clicking a visible, targetable world object opens a small context menu at
  the cursor.
- The primary action reads `Target <object display name>`.
- Selecting that action must call the same canonical target-selection path used
  by the overview list. It must not maintain a second target state.
- The action selects the object only. It does not start autopilot, orbiting,
  docking, mining, combat, or gate travel.
- Supported objects initially include asteroids, stations, outposts, jump gates,
  ships, wreckage, and celestial bodies that can already be selected through the
  overview.
- Hidden, undiscovered, disabled, destroyed, or otherwise non-targetable objects
  do not expose the action.
- When several objects overlap under the cursor, the menu provides a short list
  of valid candidates rather than silently choosing an arbitrary object.
- Context-menu input must not fire weapons or issue flight commands.
- The menu closes when the player clicks elsewhere, presses Escape, changes
  system, docks, or the referenced object becomes invalid.
- Display names come from the object's registered definition or current runtime
  identity. Node names are not treated as player-facing names.
- The feature must work for handcrafted and procedurally generated objects
  without per-system setup.

Acceptance checks:

- A visible asteroid can be targeted directly without finding it in the overview.
- A visible station, outpost, ship, gate, and celestial body use the same target
  state and HUD behavior as overview selection.
- Selecting a different object replaces the previous target immediately.
- Overlapping selectable objects can each be chosen deliberately.
- Despawned objects and system transitions cannot leave a stale context menu or
  invalid target reference.
- Existing autopilot, obstruction routing, docking, mining, combat, and overview
  selection regressions still pass.

## System Sky And Stellar Lighting

Every solar system should have a visible stellar identity and a lightly animated
deep-space background.

### System Sun

- Each system specification includes one primary sun with a stable visual ID,
  color temperature, apparent size, direction, brightness, and optional visual
  variation tags.
- The sun appears at an unreachable visual distance and provides the system's
  principal directional light.
- It is a sky and lighting element, not a physical travel destination.
- The sun does not appear in the overview, cannot be targeted, and is excluded
  from autopilot, collision, scanning, mining, mission, and persistence-entity
  queries.
- Flying toward it never makes it meaningfully closer. System boundaries or
  background rendering preserve the distant illusion.
- Light color and intensity must preserve readable ships, stations, planets,
  asteroid fields, HUD markers, and faction colors.
- Generated systems may vary sun color and apparent size within curated limits,
  but story generation does not directly control raw lighting values.
- Binary or unusual stellar arrangements are deferred until the single-sun
  lighting and composition rules are proven.

### Distant Starfield

- Each system receives a sparse deterministic starfield generated from its
  system seed.
- Stars remain at background distance and do not move relative to local world
  objects as the player flies.
- A small subset may occasionally shimmer or blink with subtle, asynchronous
  brightness changes.
- Twinkling must be slow and restrained. The sky should feel alive without
  resembling warning lights, weapons fire, target markers, or UI notifications.
- Star animation uses a shared material or similarly batched technique rather
  than one timer, light, or process callback per star.
- Star count, brightness, color range, animation frequency, and overdraw receive
  explicit performance budgets for the target hardware.
- The starfield is decorative and is not stored as thousands of persistent
  entities. Its seed and visual profile are sufficient to reproduce it.

Acceptance checks:

- The handcrafted and generated test systems each show a distinct distant sun
  that consistently lights their contents.
- The sun cannot be selected, reached, collided with, or listed in the overview.
- The same system seed reproduces the same starfield and stellar presentation.
- Occasional star shimmer is visible during a longer observation without
  distracting from navigation or combat.
- Stellar visuals remain inexpensive and do not materially reduce the Phase 0
  performance baseline.

## Procedural Ship Integration

The external ship generator already supports:

- Stable string seeds.
- Hauler and fighter classes.
- Hull textures.
- Normal-map variants.
- Faction emblems.
- Metallic settings.
- `.glb` export.

The first integration contract should be a command-line worker request:

```json
{
  "job_id": "ship_job_001",
  "asset_id": "ship_design_zenith_scout_01",
  "seed": "campaign-system-faction-role-variant",
  "ship_class": "fighter",
  "texture": "NavyBlueMetal.png",
  "emblem": "emblem_1.png",
  "normal": "hull_normal_var_3.png",
  "metallic": 0.85
}
```

The worker returns a manifest containing output path, hash, bounds, mesh count,
and validation errors. Godot should never infer a ship's combat stats from its
generated geometry. The visual design and gameplay archetype share an ID but
remain separate data.

## Implementation Order

### Phase 0: Preserve The Prototype

Purpose: establish a trustworthy baseline before foundational refactoring.

- Finish the current jump-gate branch and hands-on regression pass. Phase 1 is
  complete and approved with 18 of 18 automated checks plus the normal-play
  approval route passing.
- Document current game loops and known defects.
- Add repeatable startup, jump, save, docking, quest, and upgrade checks.
- Record performance baselines and save representative prototype saves.
- Do not begin procedural campaign generation during this phase.

Exit gate:

- Existing mining, combat, docking, upgrades, quests, TTS, LLM fallback,
  two-way gates, and saves are reproducibly testable.

### Phase 1: Typed Domain Data And IDs

Purpose: stop future systems from depending on loose dictionaries and node names.

- Define schemas or Resources for systems, gates, factions, NPCs, ships,
  missions, relationships, events, assets, and generation jobs.
- Introduce stable IDs for all persistent entities.
- Split immutable definitions from mutable runtime state.
- Replace hard-coded system registry assumptions with a data-driven registry.
- Keep adapters so current gameplay continues to work.

Exit gate:

- The handcrafted first and test systems load through the new registry.
- Existing saves migrate or fail with a clear compatibility message.

### Phase 2: Campaign Store And Save Architecture

Purpose: make permanence reliable before creating more content.

Detailed implementation contract:

- `docs/phase_2_campaign_store_plan.md`
- `docs/phase_2_storage_contract.md`

Implementation progress:

- Checkpoints 1-9 are implementation-complete as of 2026-06-15.
- Safe dock, pre-undock, and gate-arrival bundles now use stable world IDs,
  strip tactical state, recover the last-known-good bundle after corruption,
  and retain legacy `savegame.json` compatibility during migration.
- Three named manual entries copy immutable safe bundles. In-flight requests
  never capture live tactical state, while docked requests refresh the safe
  station checkpoint before copying.
- Text-only save notifications, duplicate autosave suppression, a redesigned
  pause screen, and a three-slot campaign/checkpoint manager are implemented.
- Chronicle events now append to immutable schema-versioned segments. Safe
  checkpoints retain their chronicle head, loading an older manual checkpoint
  creates a persisted timeline branch, and ordinary history queries exclude
  the discarded future without deleting it.
- Existing Markdown quest history imports once as legacy structured events,
  while new quest completion and abandonment events append directly.
- Rewindable map knowledge now assigns each handcrafted gate one known,
  rumored, hidden, blocked, or damaged visibility state. Successful travel
  reveals both route endpoints, while loading an older checkpoint restores its
  earlier visibility without changing permanent manifest or asset records.
- Focused persistence checks and the expanded 30-step gameplay baseline pass.
- Hands-on visual approval of the pause and campaign screens is deferred until
  local host-display access is available.
- The pre-Checkpoint-10 autopilot stabilization checkpoint is implementation-
  complete. Navigation now preflights 3D A* routes around strategic exclusion
  spheres, target selection is passive, point-to-move replaces the active route
  immediately, and right-click commands use a temporary highlighted preview.
- Graphical approval of route shape and steering feel remains pending.
- Checkpoint 10 Kaelen meta-memory and death reload is complete. Verified death
  events retain only approved bounded meta-memory outside the rewound timeline,
  and the death screen can load the latest living checkpoint or open a fresh
  campaign flow.
- Checkpoint 11 version-2 save import is complete. A validated prototype save
  receives a byte-identical backup, imports into an empty slot without
  overwriting campaigns, and activates only after bundle verification.
- Checkpoint 12 automated regression, storage measurement, and rendered
  performance capture are complete. Final hands-on slot, save/load, death,
  deletion, and visual approval remains before Phase 2 closes.

- Create separate campaign manifest, timeline checkpoint, chronicle, map
  knowledge, asset registry, and Kaelen meta-memory stores.
- Add atomic writes, backups, schema versions, and migrations.
- Define rewind behavior for older checkpoints.
- Add cache integrity checks and missing-asset recovery.
- Add three campaign slots. Each campaign has one rolling safe autosave and up
  to three named manual checkpoint copies.
- Create safe checkpoints after successful docking, immediately before
  undocking restores flight control, or after successful jump-gate arrival.
  The arrival save protects dock-and-quit play, while the departure save
  captures missions, cargo, storage, purchases, repairs, and upgrades changed
  during the station visit. Both use the safe dock location rather than a live
  flight position. Additional triggers may be added later only when they cannot
  preserve an immediate tactical advantage.
- Create an initial living safe checkpoint once a new campaign reaches playable
  startup, so quitting before the first dock remains recoverable.
- A manual save requested while flying copies the latest safe checkpoint. It
  does not capture the ship's current position, nearby enemies, current hull or
  shield damage, projectiles, aggro state, or other live tactical conditions.
- A manual save requested while docked may first refresh the safe checkpoint
  after docking state is fully established, then create the named copy.
- Manual saving is unavailable while dead, during a jump transition, before the
  first safe checkpoint exists, or while a save transaction is already active.
- Loading after death restores the latest living checkpoint and updates only
  Kaelen's restricted meta-memory outside the rewound timeline.
- Kaelen memories record timeline, checkpoint, and chronicle sequence. Loading
  an older checkpoint archives only observations newer than that checkpoint;
  death category is retained only when the discarded branch ended in death.
- Post `SYSTEM: Campaign checkpoint saved.` to system chat only after a complete
  autosave transaction succeeds.
- Coalesce repeated autosave requests so one gameplay action cannot flood the
  chat with duplicate save messages.
- Failed saves post a distinct non-TTS system warning and preserve the previous
  valid checkpoint.
- Manual save confirmation identifies the named checkpoint. Migration,
  backup-recovery, and corruption-recovery messages clearly identify what was
  restored without exposing filesystem paths to the player.

Exit gate:

- Generated identity data survives checkpoint loading unchanged.
- Mutable state rewinds correctly.
- Corrupted or partial writes recover safely.
- Saving while flying and then loading restores the last dock or gate-arrival
  checkpoint, never the in-flight tactical position.

### Phase 3: Universal Time

Purpose: provide one clock for missions, economy, travel, and simulation.

- Add the universal calendar and HUD/map display.
- Define time costs for existing actions.
- Add pause-safe timers based on campaign time.
- Add timed mission primitives without requiring generated stories yet.

Exit gate:

- Time advances deterministically, saves correctly, and never uses wall-clock
  time for mission outcomes.

### Phase 4: Chronicle, Relationships, And NPC Promotion

Purpose: create the memory substrate before richer dialogue.

- Add structured event recording.
- Add player-to-NPC, player-to-faction, and faction-to-faction relationships.
- Add reputation reasons and propagation rules.
- Add NPC memory retrieval and summary compaction.
- Add dynamic minor-to-major promotion.
- Replace the Markdown-only quest history with chronicle-derived summaries.

Exit gate:

- Existing handcrafted NPCs remember tested interactions after save, travel, and
  return without sending full histories to the LLM.

### Phase 5: Mission Framework

Purpose: give story generation a safe vocabulary of mechanics.

- Replace the single active quest with mission collections.
- Replace hardcoded objective `match` branches with a mission capability
  registry. A new capability registers its validator, runtime handler, event
  subscriptions, progress formatter, save-state schema, and completion rules
  without editing the mission core.
- Define typed trigger, objective, consequence, turn-in, and cleanup components.
- Allow a mission definition to compose several registered components instead
  of requiring one monolithic mission type.
- Add deterministic trigger capabilities for proximity, docking, entering a
  zone, receiving a transmission, scanning, cargo possession, destruction,
  elapsed campaign time, and prior event or relationship state.
- Add explicit offered, discovered, accepted, active, ready-to-turn-in,
  completed, failed, expired, and abandoned mission states.
- Separate world encounters from mission ownership. An encounter may exist
  before the player notices it, may offer a mission only after a trigger, and
  must clean up or persist according to its own policy if ignored.
- Define encounter eligibility data independently from mission execution:
  rarity, cooldown, system tags, valid locations, required capabilities,
  relationship bounds, campaign-time windows, recent-event exclusions, active
  encounter budget, and repeat policy.
- Port current kill, ore delivery, and special pickup missions.
- Add abandonment with 2-3 reputation loss.
- Add untimed persistence and timed expiration.
- Add prerequisite, branching, follow-up, and cross-system mission support.
- Keep deterministic validation and curated fallbacks.
- Add extension tests proving a new authored mission capability can be
  registered and saved without changing the mission manager, UI, or existing
  capability implementations.

Exit gate:

- Multiple authored missions can coexist, expire, branch, and survive travel.
- A test-only mission capability can be added through registration alone, and
  all existing mission regression tests still pass unchanged.

### Phase 6: Faction And Economy Simulation

Purpose: make systems change believably without direct LLM control.

- Create faction influence, resources, goals, relationships, and conflict state.
- Add coarse off-screen simulation using universal time.
- Protect connected major NPCs from off-screen death.
- Define the first 4-6 ore types, their rarity, value, uses, and regional demand.
- Replace single-resource cargo with mixed resource stacks.
- Add seeded asteroid composition and finite trace or rare deposits.
- Add mining-field population ranges and universal-time replenishment.
- Persist retired asteroid IDs, pending replacements, and replacement seeds so
  save loading cannot reroll rare resources.
- Add scanner information and mineral-discovery rules.
- Define power-plant upgrade tiers and their material recipes. Advanced tiers
  must require one or more resources whose normal sources are found in later
  systems, tying ship capability growth to campaign travel.
- Validate upgrade recipes against generated system geology and economy data so
  every required material has at least one legitimate obtainable source in the
  campaign.
- Prove the complete mining lifecycle in one handcrafted test field before
  procedural systems receive geological profiles.
- Add regional supply, demand, stock recovery, taxes, and access controls.
- Add station storage and trade history.
- Add high-reputation stock and enemy-faction suspicion.
- Add a deterministic ambient encounter scheduler. It periodically evaluates
  registered encounter templates against current world state, pacing budgets,
  cooldowns, location availability, campaign seed, and recent history.
- The scheduler chooses whether an encounter occurs and which eligible template
  receives an opportunity. No LLM call may directly spawn an encounter.

Exit gate:

- Leaving and returning after controlled time produces explainable, bounded
  changes.
- Repeating one trade loop cannot generate unlimited risk-free profit.

### Phase 7: Map And Discovery

Purpose: support branching campaigns before procedural branches are activated.

- Build the evolving system map.
- Add direct right-click world targeting if it has not already been completed as
  an isolated quality-of-life improvement.
- Separate physical campaign topology from player knowledge.
- Support confirmed, hidden, rumored, blocked, and damaged routes.
- Add two deterministic generated branch destinations as the production test.
  Authored fixtures may still be used by automated tests, but no handcrafted
  branch becomes permanent campaign content.
- Add Kaelen's delayed gate-reveal eligibility.

Exit gate:

- The player can discover, compare, and choose between two fully authored
  branches without breaking saves or mission state.

### Phase 8: Generation Job Service

Purpose: create a robust background production pipeline.

- Build the persistent job queue and separate worker process.
- Add job states, retries, cancellation, logs, timeouts, and fallbacks.
- Add a GPU budget manager and single-major-model scheduling.
- Pause or defer AI jobs when gameplay VRAM headroom is too low.
- Integrate the procedural ship builder through a stable command contract.
- Add output hashing and asset registry commits.
- Prove background work does not stall gameplay.

Exit gate:

- The game can request, validate, cache, reload, and reuse generated ships while
  the player continues playing.

### Phase 9: Procedural System Builder

Purpose: build playable systems from validated specifications.

- Define the system specification schema.
- Create reusable location, planet, moon, station, outpost, hazard, encounter,
  spawn, and gate components.
- Support temporary and persistent deep-space encounter anchors that are not
  tied to a planet, station, outpost, or asteroid field.
- Allow encounter specifications to spawn ships or signals, broadcast a single
  or repeated transmission, expose proximity or scan triggers, and remain
  dormant until the player discovers them.
- Add a non-traversable system sun, directional stellar lighting, and a seeded,
  low-cost distant starfield with sparse shimmer.
- Build deterministic layout from a system seed.
- Replace the development test system as the player's production first
  destination. The generated destination is committed to the campaign before
  its gate is revealed.
- Add visual composition rules and performance budgets.
- Generate both sides of a branch before advertising either.
- Add automated structural and runtime validation.

Exit gate:

- A generated system can be built, cached, loaded, left, revisited, and restored
  without the LLM being present.

#### Reference Encounter: Stranded Pilot

The first cross-phase proof of mission extensibility should be an authored
stranded-pilot encounter:

1. A seeded ship enters or is placed at a valid deep-space encounter anchor.
2. This happens only when the ambient encounter scheduler selects the
   `encounter.stranded_pilot` template from the currently eligible pool. It is
   not attached to a fixed mission, system entry, date, or story beat.
3. The ship becomes disabled and sends one system-chat distress transmission.
4. Missing the transmission does not automatically add a mission.
5. Approaching within a configured distance reveals the pilot and offers the
   mission.
6. Accepting it composes registered objectives such as repair assistance,
   delivery, escort, towing support, threat removal, or passenger transport.
7. Turn-in may occur at the stranded ship, an outpost, a main station, or
   another registered destination.
8. Ignoring, refusing, completing, abandoning, leaving the system, saving, and
   returning all follow explicit encounter persistence and cleanup policies.

The stranded pilot is a reference composition, not a special case in the
mission manager. Its purpose is to prove that a new game loop can add
registered capabilities and data without refactoring existing mission logic.
It may never appear in a campaign, may appear only once, or may later appear in
a meaningfully different form if its repeat policy and world conditions allow.

### Phase 10: Story Director

Purpose: introduce campaign-level procedural authorship after the game can
enforce it.

- Generate the opening campaign premise around the fixed first system.
- Maintain active arcs, unresolved hooks, and future branch proposals.
- Use constrained schemas and continuity review.
- Translate approved story intent into supported missions and simulation inputs.
- Let the director select only registered mission and encounter capabilities;
  it may compose supported pieces but may never invent an unimplemented
  gameplay verb.
- The story director may influence encounter weights or attach an approved
  narrative hook, but the deterministic encounter scheduler owns runtime
  eligibility and spawning. Story generation cannot guarantee that an ambient
  event occurs.
- Add PG-13 and Kaelen-protection validators.
- Add graceful fallback arcs when the LLM is unavailable.

Exit gate:

- Several campaigns produce meaningfully different ongoing stories while using
  the same first system and without contradicting established canon.

### Phase 11: NPC, Portrait, Voice, And Dialogue Production

Purpose: populate generated systems with persistent people.

- Generate structured NPC identities and relationships.
- Assign stable voices and create voice fallbacks.
- Integrate text-to-image portrait generation.
- Integrate Gemma vision review and defect scoring.
- Benchmark candidate open-source models on the 8 GB target before selection.
- Add bounded retries and curated fallback portraits.
- Retrieve relevant memories for dialogue.
- Maintain the Shiny/Indy speaker rule in both text and TTS.

Exit gate:

- Generated NPCs retain identity, portrait, voice, and memory across the entire
  campaign.

### Phase 12: Kaelen Travel Deals And Long-Arc Mystery

Purpose: connect free play to forward movement.

- Let the director propose deal motives while code controls readiness.
- Support delayed, refused, revised, and alternate deals.
- Seed rare, non-repeating hints about Kaelen's origin and knowledge.
- Ensure Kaelen is present and usable in every generated main station.
- Add rare discarded-timeline references.

Exit gate:

- Players feel invited toward new systems without being forced, and Kaelen's
  repeated presence becomes intriguing rather than mechanically convenient.

### Phase 13: Death, Chronicle Closure, And Eulogy

Purpose: make a campaign's end reflect what actually happened.

- Freeze the final timeline on death.
- Select verified chronicle facts by importance and theme.
- Generate Kaelen's eulogy from those facts.
- Provide a deterministic fallback eulogy.
- Preserve the campaign as a readable legacy record.
- Allow loading an earlier save while updating only Kaelen's meta-memory.

Exit gate:

- The eulogy accurately references the player's real relationships, choices,
  failures, and accomplishments without inventing contradictory events.

### Phase 14: Long-Run Hardening

Purpose: prove the campaign remains healthy over many systems and many hours.

- Soak-test large chronicles, asset caches, map branches, and old systems.
- Measure prompt sizes, generation latency, memory use, disk growth, and import
  times.
- Measure peak VRAM during gameplay, model loading, portrait generation, vision
  review, and transitions between those workloads.
- Add pruning for disposable logs while preserving canon.
- Add migration tests across released schema versions.
- Balance economy, reputation, travel pacing, and generation lead time.

Exit gate:

- A long campaign can span many systems without save corruption, runaway prompt
  growth, severe loading degradation, or continuity collapse.

## Current Project Fit

Useful foundations already present:

- Persistent `GameRoot` with system swapping.
- Two-way gate travel and transition masking.
- Versioned JSON save prototype.
- Persistent entity capture for selected system objects.
- Handcrafted first system and test system.
- Reputation, upgrades, cargo, mining, combat, docking, and storage foundations.
- Local Ollama integration with validation and fallbacks.
- Kokoro TTS integration and per-voice caching.
- Existing tone guard for Kaelen's "Shiny" versus everyone else's "Indy."
- Procedural ship generator with deterministic seeds and `.glb` export.

Areas that must be restructured before procedural campaigns:

- `GlobalState` currently owns too many unrelated domains.
- `GameRoot.SYSTEM_SCENES` is hard-coded.
- Save version 1 mixes checkpoint state and campaign identity.
- Missions support only one loose dictionary at a time.
- Quest history is prose-first rather than structured event data.
- `LLMInterface` combines many responsibilities and large fallback libraries.
- Much of `UIManager` is generated in one very large script.
- NPC and faction definitions are compiled into code rather than campaign data.
- TTS cache is session-only.
- The ship generator needs a worker manifest and validation contract.

## Deferred Decision Gates

These questions do not block the first architectural phases:

- Exact universal calendar names and starting date.
- Whether normal gate transit consumes time or only story-specific gates do.
- Exact maximum number of active missions.
- Exact system size budgets for low-end hardware.
- Portrait model and Gemma vision model choices.
- The precise truth behind Kaelen's travel and final system.
- Whether non-gate travel ever becomes a player ability.
- The shape of a distant optional campaign finale.
- Any future mature-content mode.
- Planet landing, which remains outside the planned scope.

## Immediate Work Boundary

The next implementation work should stop after Phases 0-2 are designed in more
detail and approved. Procedural story or asset generation should not be wired
into live campaign state until typed IDs, campaign persistence, migrations, and
rewind rules are proven.

This order is intentionally conservative: every later system depends on the
campaign remembering what it created and why.

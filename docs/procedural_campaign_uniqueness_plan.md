# Procedural Campaign Uniqueness Plan

## Purpose

The main goal is that no two campaigns should feel even close to the same.
Systems should not feel like new backgrounds for the same jobs. Each campaign
needs its own factions, people, voices, ships, recurring conflicts, jokes,
rumors, and long-form story direction, while preserving Kaelen as the stable
anchor.

This plan promotes procedural identity from polish to core architecture.

## Current Gap

The project already has strong pieces:

- 150 imported portrait slots in `assets/Portraits/portrait_spritesheet_layout_with_gender.json`.
- 50 badge IDs in `tools/ship_generator/textures/badges/badge_sheets_metadata.json`.
- A headless procedural ship generator wired through `ShipGenerator` and
  `ShipPreGenerator`.
- TTS voice blending with Kokoro voice recipes.
- LLM quest, handoff, mechanic, Kaelen, and public-board text paths.
- Generated systems, stations, gates, patrols, faction weights, and chronicle
  records.

The missing layer is a campaign identity model that all of those systems share.
Right now many systems still reach for static fallback lines, static faction
names, a small set of authored NPCs, and repeated joke/example text. That hides
errors and makes procedural campaigns feel samey.

## Design Principle

Every generated thing should come from the same campaign DNA:

- `campaign_seed`
- campaign story bible
- faction identities
- system-local facts
- NPC identity records
- player history and chronicle facts

Fallbacks should be rare, visible in logs/debug UI, and varied by seed when they
must be used.

## Locked Design Decisions

- The first/home system keeps the original major factions. Zenith, Aurelia, and
  Vanguard give the campaign a stable lore baseline and a known place to return
  to.
- New systems use the same procedural identity machinery whether they are the
  second system or the fiftieth system.
- Original factions can still appear beyond the home system when the story calls
  for it: expansion, alliances, proxy conflicts, old grudges, or trade pressure.
- New factions, conflicts, ores, upgrades, and local mysteries should reveal as
  the player moves through gates. The player should not receive advance notice
  of the full frontier roster.
- Kaelen is the only fixed recurring character besides the player. Other people,
  including mechanics and station contacts, should be generated campaign
  identities unless a later design explicitly promotes them.
- Kaelen's uniqueness is part of the long mystery. Her repeated presence should
  feel intentional, not like a reused NPC template.
- The first time the player encounters Kaelen in a new system, she should have
  a funny system-arrival line that makes her presence feel deliberate and gives
  the player a quick read on the local factions. The tone can be possessive,
  dry, and profit-minded, e.g. "When I said that route was yours, Shiny, I meant
  ours."
- Kaelen's personal mystery should never be fully explained. The story can
  reveal what she is doing, what pressure she is under, and how her choices
  affect the player, but it should preserve unanswered questions about what she
  truly is, where she came from, and what she ultimately knows.
- Generated NPCs can die, move, betray the player, or become unavailable, but
  those major consequences should only happen while the player is in-system or
  directly involved in that story. The game should not kill an NPC in a plot
  while the player is two systems away and unaware.
- Kaelen cannot die.
- The broader story keeps moving even when the player ignores it. The world does
  not pause for the player, and later Kaelen's eulogy for the player can recount
  what the player did, missed, changed, or failed to stop.
- Fallback text, messages, quests, and dialogue are last-resort emergency paths.
  They should never be treated as normal generation.
- Move away from fallbacks as quickly as practical. If a fallback is necessary,
  use engineering judgment, but make the fallback visible to development
  diagnostics and report it during review.
- The LLM should have access to a compact persistent idea-memory file so it can
  see prior generated ideas and avoid repeating factions, NPC concepts, jokes,
  mission premises, names, rumors, and story twists.
- Rumors should sometimes lead somewhere. Most can remain local color, but some
  should be seeded as multi-step rumor trails that point to hidden discoveries,
  faction secrets, unusual systems, rare upgrades, or a late/end-game easter egg.
  These trails should be planned by the campaign-level LLM so they fit the larger
  story instead of being random one-off gossip.
- Main stations need at least one persistent NPC for each faction active in the
  system, plus at least one mechanic. Outposts can have two or more generated
  contacts at random, weighted by local factions and story needs.
- A typical generated system needs at least two meaningful factions so conflict
  can exist. The high end is around four larger factions in one system, plus
  minor hostile factions or crews.
- Minor hostile factions can start as "targets" the player is sent to kill, then
  become more complicated when the player eventually reaches their home system
  and they already hate the player.
- Players can create real alliances with generated factions. Alliances should
  have consequences: gaining a friend can make that faction's enemies hostile,
  change available missions, alter prices, and affect travel safety.
- The game should use humor often enough to lighten the killing, betrayal,
  power, and money themes. The preferred baseline is dry, slightly dark PG-13
  humor, with room for occasional oddballs such as a dad-joke NPC. The world can
  be dangerous without every conversation being grim.
- Agents can call the player "Indy" in the first quest request, but should avoid
  repeating the name in immediate follow-up lines after the player agrees. Using
  the name too often sounds unnatural.
- The UI should become controller-friendly as the station, inventory, map, and
  generated-contact screens grow. Menus need predictable focus order, sensible
  default selections, controller prompts, and quick tab/action navigation instead
  of assuming mouse-only play.
- When the player enters a system for the first time, neighboring/next systems
  should be generated in the background: factions, planets, ships, stations,
  asteroids, gates, and scene placement. The next system should be ready before
  the player meets the requirements to open its gate.
- Generated systems should also vary visually. Some systems can have clear star
  fields, while others can include seeded nebula clouds, dust haze, ion fog, or
  storm-like shader backdrops.
- At new campaign launch, system 2 should begin generation while the player is
  still in the handcrafted home system.
- Background generation should be invisible to the player during normal play.
  The game expects roughly 30 minutes of player time to prepare the next system,
  so there is no need for player-facing progress unless a future platform proves
  much slower.
- If a next system is somehow not ready when the player qualifies to leave,
  Kaelen can fictionally delay or block the exit while generation finishes. This
  is an emergency safety valve, not a normal pacing tool.
- Boost can eventually involve heat damage. Keep the first implementation small,
  with future ship upgrades able to add stronger boosters with more heat risk.
- The story engine is expected to run on local models. If the larger model cannot
  run on a low-VRAM machine, the game should make that state explicit instead of
  silently degrading into static fallback content.

## Target Architecture

### 1. Campaign Bible

At new campaign creation, the larger story model writes a compact campaign
bible. This is likely the larger model, for example Gemma 4 if it is available
and fast enough.

The bible should include:

- campaign theme, tone, and danger level
- central mystery or pressure moving through the gate network
- 3-5 story arcs with escalation rules
- forbidden repeats and style guardrails
- Kaelen-specific constraints and mystery hints
- faction generation rules for this campaign
- recurring motifs, slang, jokes, rumors, and taboo topics
- rare rumor trails, including what they hint at, how many clues they need, and
  what discovery or easter egg they can eventually reveal
- story horizon regeneration rules for extending the campaign when the player
  nears the edge of prepared story

The smaller model then uses the bible for local dialogue, quests, and station
texture. It should not invent a totally unrelated story every time.

The initial bible should not spoil the whole frontier. It should define the
campaign's pressure, Kaelen constraints, home-system context, and generation
rules. New faction and system details can be created later as gates reveal new
regions.

The bible should also be expandable. If the player keeps going long enough to
reach the end of prepared story, the larger model should generate the next story
horizon by appending arcs, rumor trails, faction pressures, and frontier rules to
the existing bible. It must preserve known facts, alliances, enemies, deaths,
discovered systems, and Kaelen's unresolved mystery instead of replacing or
retconning them.

### 2. Generated Faction Identity

Each campaign should generate a faction roster beyond the fixed major factions.
Generated factions should have persistent IDs and presentation data:

- display name, short name, and abbreviation
- ideology, business model, taboo, sense of humor, threat style
- color palette
- badge ID from the 50 badge metadata entries
- ship style: texture, badge/emblem, class preferences, metallic range
- voice style recipe using Kokoro blends
- preferred mission types and enemies
- relationship hooks with other factions
- campaign story role

Generated systems should draw from these factions, not only the same five minor
factions.

Generated factions should usually be discovered as the player reaches new
systems. Some may be tied to the original powers through alliances, supply
chains, secret sponsorship, or open conflict, but the player should learn that
through play rather than from an upfront faction list.

System faction density rules:

- Minimum: two meaningful factions in a generated system when conflict is
  expected.
- Typical: two or three larger local factions.
- High end: four larger factions.
- Minor hostile factions/crews can exist on top of that count as raiders,
  cults, militias, criminals, scavengers, or old enemies.

### 3. Generated NPC Identity

Generated station NPCs should be real campaign records, not temporary display
names.

Each generated NPC should have:

- stable NPC ID
- name
- portrait ID from the 150 imported portrait slots
- voice profile recipe
- faction or independent affiliation
- job at the station
- personality tags
- speech style and joke style
- relationship state with the player
- memory summary and chronicle references
- home system and station
- recurring-contact eligibility

When the player returns to a system, those people should still be there unless
the story changed them.

Major NPC state changes should follow player proximity and involvement rules:
death, betrayal, relocation, capture, and disappearance are valid outcomes only
when the player is present in the system or has accepted/triggered the related
story. Remote systems can continue to develop tension, but they should not spend
named NPCs off-screen without player contact.

### 4. Local System Story Pack

When a new system is generated, create a system story pack from the campaign
bible and local faction mix:

- system identity and local nickname
- station economy and problem
- faction presence and active tension
- local rumor pool
- rumor trail clue candidates
- local mission seeds
- gate mystery hints
- local repeated-language ban list
- arrival chatter and dock chatter topics

Missions in that system should mostly pull from the system story pack, so the
system feels like a place with an active situation.

The story pack should advance over campaign time even if ignored. Ignored arcs
can change prices, faction control, rumors, patrol levels, station services, and
future mission opportunities. Irreversible named-NPC consequences still require
player presence or direct involvement.

The story pack should include humor guidance. Humor can come from NPC
personality, faction culture, system circumstances, and campaign tone. Dry,
slightly dark humor is preferred, but one-off lighter personalities are welcome
when they make the world breathe.

Rumors should have tiers:

- local color: atmosphere, jokes, prejudice, small lies
- actionable hint: points toward a faction, station, resource, gate, or mission
- trail clue: one piece of a larger campaign rumor chain
- rare reveal: unlocks or strongly points toward a hidden discovery, secret
  route, unusual upgrade, faction truth, or endgame easter egg

The player should not know which tier a rumor belongs to immediately. The fun is
realizing later that a throwaway line was part of something larger.

### 5. LLM Pipeline: Big Model Then Small Model

Suggested model roles:

- Big model: campaign bible, new faction batch, system story pack, high-level
  arc revision.
- Small model: local dialogue, quest wording, handoff lines, flavor lines,
  short reactions.

The small model prompt should receive:

- current campaign bible summary
- system story pack
- relevant NPC identity
- relevant faction identity
- chronicle facts for this timeline only
- anti-repeat memory
- output schema

The small model should not receive loose example jokes that can leak into the
game verbatim unless those examples are explicitly marked as banned text.

Dialogue style rules should also control address repetition. For example, an
agent may call the player "Indy" when opening a quest, but should usually avoid
using the name again in the acceptance response.

### 6. Fallback Policy

Fallbacks should become diagnostic and procedural.

Rules:

- Log every fallback with reason, content type, model, elapsed time, and retry
  count.
- Store fallback counters in a visible debug report.
- If fallback rate crosses a threshold, show a developer warning.
- Fallback lines should be seed-varied and context-aware.
- Never use the same fallback line twice in one campaign unless explicitly
  allowed.
- Do not silently replace LLM failure with a line that looks like successful
  authored content.
- Avoid using Kaelen's voice as generic neutral fallback.

### 7. Anti-Repetition Memory

Track recent generated text and obvious content fingerprints:

- exact line hash
- normalized joke phrase hash
- NPC line category
- mission title
- mission objective shape
- faction phrase or slogan

Before showing generated dialogue, reject or retry if it is too close to recent
campaign text or known fallback examples.

Add a persistent idea-memory file for generation prompts. This should not be a
full transcript. It should be a compact, structured list of previously used
creative ideas:

- faction names and concepts
- NPC names, jobs, voices, personality hooks, and joke styles
- system names and defining visuals
- mission premises and objective twists
- recurring rumors, slang, and catchphrases
- rejected or banned repeats
- major story beats already used

The big model and small model can receive the relevant slice of this file before
generating new content. New output should add compact fingerprints/summaries back
to the file after validation.

### 8. UI Action Feedback And Boost

Small UI improvements requested:

- The selected target panel should flash or otherwise visibly mark the active
  command button, such as Fly To, Orbit, Mine, or Attack.
- Add a Boost button on the left side of the selected target panel.
- Boost behavior: +25% ship speed for 5 seconds.
- Cooldown: 60 seconds for now.
- Later tuning can adjust boost duration, speed increase, cooldown, energy
  cost, or upgrade scaling.

### 8A. Controller-Friendly UI Pass

The growing UI should support controller play before menus become too tangled.
This is especially important for station services, inventory, the branch map,
dialogue/contact screens, and target actions.

First version:

- Add explicit focus order for dock menus, inventory, map controls, station
  contacts, quest choices, and target-action buttons.
- Set a useful default focused control whenever a panel opens.
- Add controller prompts beside or beneath common actions, with keyboard/mouse
  prompts still available.
- Support shoulder-button or trigger navigation between major panels where it
  feels natural, such as inventory/map/services tabs.
- Make station-contact conversation actions usable without a mouse.
- Keep escape/back/cancel behavior consistent across every panel.
- Add smoke checks for controller input after major UI changes.

### 9. Seeded Nebula Backgrounds

Generated systems should have optional shader-based nebula clouds layered with
the existing starfield. This supports the uniqueness goal by making some systems
feel visually different before the player even docks.

First version:

- Keep the current star shader/background as the base.
- Add a separate nebula layer using shader noise, color ramps, alpha falloff,
  and slow drift.
- Add `SystemConfig` fields such as `nebula_enabled`, `nebula_seed`,
  `nebula_color_a`, `nebula_color_b`, `nebula_density`, and `nebula_motion`.
- Seed values from the system seed so the same system always looks the same.
- Use sparse probability: many systems stay clear, some get faint haze, rare
  systems get dramatic clouds.
- Tie nebula palette loosely to system story/faction identity later.

Estimated scope:

- Simple pretty version: one implementation session.
- Seeded per-system version: one to two sessions.
- Advanced version with parallax layers, storms, animated wisps, or visual
  events: later polish.

## Implementation Notes: 2026-06-19

Completed tonight:

- Generated faction identity is now wired into generated systems and ship
  styling. Generated factions carry persistent IDs, display names, colors,
  badge choices, voice hints, mission preferences, and ship style seeds.
- Generated station contacts now appear in the dock services UI with portrait
  and faction context.
- Main generated stations receive faction contacts derived from the local
  faction mix, plus a generated mechanic record.
- Agent quest generation can use the visible station faction contact instead of
  always routing through the old neutral/major-faction agent setup.
- Generated-system quest validation now prefers current-system factions and
  outposts for kill and pickup missions.
- Quest idea memory writeback now stores richer premise, faction, objective,
  joke, and rumor data so future LLM prompts can avoid repeating the same ideas.
- Repo maps now exist at `PROJECT_MAP.md` and `PROJECT_MAP.json`, with
  `AGENTS.md` updated so agents consult them before broad exploration.
- Campaign-specific seeds now prevent generated system chains from repeating
  across new campaigns, while old saves remain compatible.
- Runtime generated ship models now load from the campaign folder without a
  Godot editor restart, and current-system ships can hot-swap when generation
  completes.
- Dialogue alignment now uses dummy-name substitution, per-mission examples,
  system-aware kill targets and pickup outposts, agent role subtitles, and
  validation tracing.
- Generated mechanics now use local station mechanic identity and deterministic
  local shop names instead of presenting every frontier maintenance bay as
  Jenna's Grease Monkeys.
- Generated systems now have seeded suns, improved starfields, and nebula
  layers, plus stronger density guardrails for planets, stations, and asteroid
  belts.
- Combat, asteroid, and mining visuals now include impact flashes, death
  explosions, unique asteroid models, asteroid tumble/bob, mining dust, and
  drone collection behavior.

Known follow-ups for tomorrow:

- Verify the branch map does not reveal the name/details of a prepared
  destination while its gate is only rumored. A playtest screenshot showed a
  rumored neighboring system label even though the player had not found it yet.
  The current `BranchMapUI` code intends to reveal destination nodes only for
  `known` gates, so this needs a save-state/runtime reproduction before changing
  the map layer.
- Convert temporary generated contact dictionaries into full campaign-persisted
  NPC identity records with relationship and line-memory fields.
- Add a real generated-contact conversation path so clicking a station contact
  can show local flavor, faction status, and contact-specific work instead of
  only feeding the background quest cache.
- Continue reducing static fallback usage now that diagnostics and idea-memory
  plumbing exist.

## Tomorrow Morning Implementation Queue

### 1. Reproduce And Fix Map Knowledge Leakage

Goal: make sure the player cannot see destination system names, factions, or
details before the gate state justifies it.

Why first: this is a trust issue. Background generation is allowed to create the
next system early, but it must not spoil the player's discovery experience.

Checks:

- Start from a fresh campaign and from an existing checkpoint.
- Trigger Kaelen's first gate rumor.
- Open the branch map before scanning/revealing the gate.
- Confirm whether the map shows only the current system plus a vague rumored
  route, or whether it shows the destination system label/details.
- Confirm whether old save `map_knowledge` can mark a generated destination as
  visible even when its outbound gate is only rumored.

Likely files:

- `scripts/ui/BranchMapUI.gd`
- `scripts/navigation/GateDiscoveryManager.gd`
- `scripts/persistence/CampaignCheckpointStore.gd`
- `scripts/GameRoot.gd` smoke checks around branch-map reveal behavior

Preferred behavior:

- `unknown`: no route and no destination node.
- `rumored`: show a dashed route hint from the current system, but do not show
  the destination node name, factions, stations, or exact position.
- `hidden`, `blocked`, `damaged`: show the route state only if the player has
  enough knowledge to act on it, still avoiding destination spoilers until the
  gate is `known`.
- `known`: show the destination system node and allow route planning.

### 2. Central Model Gateway And Profiles

Status: first implementation pass complete. Keep future work focused on
coverage audits, model-quality measurement, and adding new capabilities through
the shared gateway instead of creating direct Ollama calls.

Goal: route every local model request through one game-facing interface so the
active model can be upgraded without hunting through UI, quest, mechanic, or
story scripts.

Why second: the current game already needs to move from `qwen2.5:1.5b` toward a
stronger small model such as `qwen2.5:3b-instruct`. More upgrades will happen
over time, so model selection must become a profile/config change instead of
hard-coded script edits.

Implementation shape:

- Create one model gateway/profile layer that owns Ollama URL, preferred model
  order, context limits, request options, timeouts, and installed-model
  discovery.
- Route direct UIManager Ollama calls through the shared interface.
- Have callers request capabilities such as `quest_dialogue`, `mechanic_line`,
  `station_contact_line`, `gossip`, `public_board`, `campaign_bible`, and
  `story_horizon` instead of naming a model.
- Prefer `qwen2.5:3b-instruct-q4_K_M` / `qwen2.5:3b-instruct` for small,
  frequent dialogue work when installed, then fall back to the existing 1.5B
  model.
- Keep the larger model role separate for campaign bible, faction batches,
  system story packs, and story horizon regeneration.
- Record selected model, capability, elapsed time, retry count, and fallback
  state in generation diagnostics.

Verification:

- Search confirms no gameplay/UI script sends direct Ollama requests outside
  the gateway.
- Quest generation, mechanic greeting, public board, gossip, and contact text
  all use the shared route.
- Swapping the preferred small model is a single profile/config edit.
- A/B test the same prompt set against 1.5B and 3B for valid JSON rate,
  fallback rate, wrong-faction/wrong-count rate, repeated-name rate, and
  response time.

First implementation pass:

- Added a shared local model gateway/profile file for Ollama URLs, model
  preference order, capability profiles, request timeouts, and generation body
  creation.
- `LLMInterface` now chooses installed small-dialogue and large-story models
  through the shared gateway.
- UI-owned public board, mechanic greeting, and pickup handoff requests now ask
  `LLMInterface` for the gateway URL, model body, and timeout instead of naming
  models directly.
- Second pass moved LLMInterface's remaining direct payloads for dialogue retry,
  background chatter, salvager profiles, Kaelen handoff intros, partial delivery
  lines, and campaign system names through the shared gateway helpers. System
  names now use the large-story profile; short dialogue/flavor calls stay on the
  small-dialogue profile.

### 3. Generated Mechanic Identity

Status: current pass complete. Generated station mechanics now resolve from
local contact data, show their own name/portrait/voice where available, and use
deterministic local shop names for maintenance UI and pickup destinations.

Goal: generated systems should not keep pretending Jenna is every mechanic in
the frontier.

Why second: the generated mechanic record already exists, and the UI still has
Jenna-specific prompts, portraits, and fallback lines. Fixing this gives an
immediate "new system, new people" payoff.

Implementation shape:

- Add a helper that resolves the current station mechanic NPC from generated
  station contact data.
- For the handcrafted home system, keep Jenna.
- For generated systems, feed the generated mechanic's name, portrait,
  faction/independent status, voice profile, personality tags, and station ID
  into mechanic greeting generation.
- Rewrite mechanic prompts so they describe a generic/generated mechanic when
  outside the home system.
- Keep pickup-offer mechanics intact, but make the speaker and flavor local.

Likely files:

- `scripts/GlobalState.gd`
- `scripts/UIManager.gd`
- `scripts/LLMInterface.gd` only if mechanic generation moves out of UI later

Verification:

- [x] Dock at home station: Jenna still appears.
- [x] Dock at generated main station: generated mechanic name/portrait appears.
- [x] Mechanic greeting does not say Jenna in generated systems.
- [x] Pickup-offer accept/decline still works.

### 4. Generated Contact Conversation Mode

Status: first pass complete. Station contacts can be selected from the dock
services panel, show role/faction context, answer faction/trouble/rumor topics
with current system and station facts, and faction contacts can broker local
work through the existing quest path.

Priority note: the Lounge is usable for now. Keep its remaining polish on the
backlog, but prioritize the main generated campaign loop: story packs, gates,
system progression, missions, rewards, and meaningful differences between
systems.

Next UI direction: move casual station people into a dedicated Station Lounge
instead of stacking them on top of core station services. The Lounge should
hold generated locals, faction contacts not currently giving formal work,
rumors, optional Kaelen appearances, and future social hooks.

Goal: station contacts should be more than list decorations and hidden quest
seeds.

Why third: we now show contacts and can use one as the quest giver. The next
step is letting the player intentionally talk to them.

First version:

- [x] Clicking a faction contact opens a focused contact panel.
- [x] Show portrait, name, role, faction, and a short generated local greeting.
- [x] Move station contact browsing into a Station Lounge submenu.
- [x] Offer actions:
  - [x] Ask about the faction.
  - [x] Ask about local trouble.
  - [x] Ask about rumors.
  - [x] Request work from this contact.
- [x] Let Kaelen appear in the lounge with system-aware commentary.
- [x] Let lounge rumors sometimes pull campaign-bible clue templates so they can
  point toward real discoveries, secrets, or easter eggs.
- [ ] Persist discovered lounge rumor clues and connect completed trails to
  actual discoveries, secret routes, rare upgrades, faction truths, or endgame
  easter eggs.
- [ ] Later, when the core procedural loop is stable, explore a light social
  sim layer for lounge NPCs: recurring moods, favors, grudges, friendships,
  rivalries, small personal requests, and consequences for who the player
  helps or ignores. This is explicitly a future polish idea, not near-term
  scope.
- The first implementation can use structured local facts and existing LLM
  request paths; it does not need a full relationship system yet.

Guardrails:

- Contact text should draw from current system facts and idea memory.
- Contact should call the player `Indy` at most once in the opening line.
- Contact should not impersonate Kaelen or use Kaelen's `Shiny` voice.
- Fallback lines should be logged and visibly marked in diagnostics.

### 5. Persisted NPC Identity Records

Status: foundation complete. Generated contacts are persisted through
`CampaignNpcIdentityStore` with stable IDs and identity fields. Keep this open
for relationship updates, recurring-contact behavior, line-memory enforcement,
and lifecycle changes.

Goal: move from generated contact dictionaries to proper campaign NPC records.

Why fourth: this is the foundation for relationship memory, recurring contacts,
line repetition prevention, relocation, betrayal, and death rules.

Record fields:

- [x] stable NPC ID
- [x] display name
- [x] portrait ID
- [x] voice profile ID or recipe
- [x] faction ID
- [x] job/role
- [x] home system ID
- [x] home station ID
- [x] personality tags
- [x] humor style
- [x] relationship state
- [x] memory summary
- [x] line memory fingerprints
- [x] lifecycle flags for available, relocated, captured, dead, or protected

Do not overbuild the UI yet. The first win is stable records that every later
system can reference.

### 6. Fallback Reduction Pass

Status: partially complete. Dialogue substitution, per-type examples,
system-aware targets/outposts, subtitle fixes, and validation tracing are in.
Direct `record_fallback()` calls now count as fallback content sources, and a
`--generation-diagnostics-smoke-test` command verifies the summary counters.
Keep this open for measured fallback-rate reductions rather than treating it as
done.

Goal: use diagnostics to find where we are still silently leaning on generic
text.

Targets:

- Kaelen pickup fallback rate.
- Mechanic intro fallback rate.
- Quest validation retries.
- Static fallback lines that repeat across one campaign.
- Prompt examples leaking into final dialogue.

Output:

- [x] A short diagnostics summary after playtest.
- One targeted prompt/schema fix at a time.
- No hiding errors behind better-sounding static text.

## Recommended Build Order

### Phase 0: Make Fallbacks Visible

Goal: stop hiding problems.

- Add a central `GenerationDiagnostics` service.
- Record every fallback by type and reason.
- Add counters for LLM request failures, validation failures, retries, timeout,
  and fallback usage.
- Add a developer console/log summary command.
- Mark generated content with source: `llm`, `retry`, `procedural_fallback`,
  or `static_fallback`.
- Add tests for fallback logging.
- Add a command-line smoke check that proves fallback source rate is counted
  correctly.

Why first: if we do not measure fallbacks, we cannot know whether uniqueness
work is actually being used.

This phase should stay lean. The goal is not to spend a long time polishing
fallbacks; it is to expose them, reduce them, and move quickly toward real
campaign-driven generation.

### Phase 1: Campaign Bible Schema

Goal: create the shared story spine.

- [x] Define `CampaignBible` schema.
- [x] Store it in a new campaign identity file.
- Generate it at new campaign creation.
- [x] Add an explicit local-model-unavailable state instead of silently starting
  a static fallback campaign.
- Add deterministic procedural emergency fallback only for development/testing
  or very low-spec mode, and label it clearly.
- [x] Label deterministic procedural bootstrap bibles clearly.
- [x] Add save/load validation.
- [x] Add prompt snippets that let small models consume the bible.
- [x] Record active campaign bible source/status in generation diagnostics.
- [x] Add a `NarrativeDirector` prompt/parser layer for large-model campaign
  bible generation, with validation that rejects incomplete model output instead
  of silently filling missing fields from the bootstrap bible.
- [x] Add an explicit LLMInterface/GameRoot bridge that can request a large-model
  campaign bible, write successful results to the campaign bible store, and
  persist `llm_unavailable` or `generation_failed` status when the call cannot
  produce valid story output.
- [x] Queue that campaign bible generation once for each newly created campaign,
  after campaign stores are open, without blocking campaign startup.
- Define the campaign idea-memory file and include relevant prior ideas in
  generation prompts.
- [x] Add a Campaign Bible-specific idea-memory context so large-story prompts
  prioritize previously used factions, NPC concepts, jokes, rumors, systems,
  story beats, style rules, and banned repeats instead of receiving only the
  quest-facing memory slice.
- [x] Write accepted Campaign Bible arcs, rumor trails, style rules, and banned
  repeats back into idea memory so future story horizon generation can avoid
  reusing the same campaign ideas.
- [x] Define rare campaign rumor trails and endgame/easter-egg hint rules with
  stable trail IDs, hint themes, clue templates, discovery types, rarity, and
  payoffs so future local rumors can attach to real breadcrumb chains.
- [x] Define story horizon regeneration triggers with explicit metrics,
  thresholds, and actions so the campaign can extend itself before the player
  runs out of prepared arcs, systems, or rumor payoffs.

Why second: faction, NPC, and quest generation need a shared source of truth.

### Phase 2: Generated Faction Registry

Goal: stop relying on the same small fixed faction set.

- [x] Define generated faction records.
- [x] Assign badges from badge metadata.
- [x] Assign colors, ship generator texture/emblem params, voice style, and
  mission preferences.
- Persist generated factions in campaign state.
- Make `SystemConfig` pick from discovered/generated factions appropriate to
  the current branch, while allowing original factions to appear for story drama.
- Make `ShipGenerator` accept faction style records instead of hard-coded
  `FACTION_TEXTURES` and `FACTION_EMBLEMS`.
- [x] Enforce faction density targets: at least two meaningful factions per
  conflict-bearing generated system, usually two to three, with four larger
  factions as the crowded high end.
- Track hostile minor faction homes so repeated player violence can matter when
  the player eventually reaches their territory.

Why third: factions drive ships, NPCs, local stories, and mission variety.

### Phase 3: Generated NPC Registry

Goal: make station contacts unique and persistent.

- Define generated NPC records.
- Allocate portraits from the imported 150 portrait slots.
- Generate names, jobs, personality, speech style, and voice blends.
- Persist NPCs per station/system.
- Ensure each main station has at least one NPC per active system faction plus
  one mechanic.
- Give outposts two or more random local contacts, weighted by faction and story
  pressure.
- Replace temporary generated contact data with registry-backed NPC identities.
- [x] Add per-NPC line memory to block repeats.
- Add player-proximity rules for death, betrayal, relocation, and disappearance.

Why fourth: conversations cannot feel unique until speakers are unique.

### Phase 4: System Story Packs

Goal: make each system feel like a place.

- [x] Generate a lightweight deterministic story pack when a system config is
  created.
- [x] Tie the first pack to local factions, resources, danger, humor guidance,
  local rumors, mission seeds, and gate mystery hints.
- Use it for public board postings, gossip, station chatter, interceptors, and
  Kaelen hints.
  - [x] Let Lounge rumors sometimes use current-system story pack rumors.
  - [x] Feed system story pack mission seeds/context into public board postings.
  - [x] Feed system story pack mission seeds into agent mission generation.
  - [ ] Add delivery/courier mission types that use the existing cargo and
    special-item structure: pick up from one contact or station, carry to the
    destination, validate handoff, and reward on completion.
  - [ ] Add purchase-from-store mission types: send the player to buy a named
    item from a local or nearby station store, validate that item in inventory,
    then deliver or consume it for the contract.
  - [ ] Let story packs choose delivery and purchase mission intents so public
    board and agent offers are not stuck on fetch/combat loops.
  - [ ] Add tests for delivery and purchase mission generation, inventory
    validation, completion, failure messaging, and save/load persistence.
  - [ ] Feed system story pack danger/faction tension into patrol/interceptor
    behavior.
  - [ ] Feed system story pack humor guidance into local NPC and Kaelen prompts.
- Add a first-Kaelen-encounter beat for each new system: generate one brief,
  funny Kaelen arrival line that welcomes or needles the player, explains that
  she has followed the money into this system, and names the local factions in
  natural dialogue.
  - [x] Add the saved gate-arrival hook and deterministic Kaelen line so each
    generated system gets a one-time first-arrival comment naming local factions.
  - [ ] Replace the deterministic line source with the system story pack once
    story packs exist.
- Include rumor clue slots that can attach local gossip to campaign-level rumor
  trails.
- [x] Include first-pass rumor clue slots that can attach local gossip to
  campaign-level rumor trails.
- [ ] Persist story packs with generated system state instead of relying only on
  deterministic config regeneration.
- Advance unresolved local arcs over time, even when the player ignores them.
- Allow remote consequences for faction control, economy, patrols, rumors, and
  service availability.
- Gate named-NPC irreversible consequences behind player presence or direct
  involvement.
- Include humor guidance for the local system, including what kind of jokes or
  gallows humor fit its people and what would feel out of place.

Why fifth: this is what stops new systems from feeling like palette swaps.

### Phase 5: LLM Orchestration

Goal: separate strategic story generation from local text generation.

- Add a `NarrativeDirector` that owns calls to the big model.
- Add prompt builders for campaign bible, faction batch, NPC batch, and system
  story pack.
- Add schema validation and retry paths.
- Add small-model prompt builders that consume the generated facts.
- Add anti-example rules so prompt examples do not leak into output.
- Add address repetition rules so NPCs do not repeat "Indy" in every line of the
  same exchange.
- Add idea-memory retrieval and writeback so models can see prior ideas and
  avoid reusing them.
- Have the campaign-level LLM plan rare rumor trails so repeated gossip can lead
  to discoveries rather than staying as throwaway flavor.

Why sixth: once the schemas exist, the models have well-defined jobs.

### Phase 5.5: Neighbor System Pre-Generation

Goal: make unexplored systems ready before the player opens their gates.

- On campaign launch, begin generating system 2 in the background while the
  player is in the handcrafted home system.
- When the player first enters any system, queue background generation for its
  neighbor/outbound systems.
- Pre-generate system config, faction roster, planets, stations, asteroids,
  gates, story pack, NPC identities, and ship models.
- Support intentional point-of-interest layouts such as a named asteroid field,
  derelict belt, or resource pocket. These should be authored as discoveries
  with resources, danger, rumor hooks, and map identity, not accidental empty
  systems with too little content.
- Keep generation deterministic from seeds so save/load and retries land on the
  same result.
- Surface generation failures in diagnostics instead of silently falling back to
  generic content.
- Keep normal player UI unaware of this work. Diagnostics/logs can expose
  lagging or failed jobs for development.
- If the player reaches an outbound gate before its destination is ready, route
  the delay through Kaelen dialogue or gate-deal friction while diagnostics
  record the real cause.

Why here: it connects the identity systems to the existing generated-scene and
ship pre-generation pipeline.

### Phase 5.6: Seeded Nebula Visual Identity

Goal: make generated systems visually distinct, not just mechanically distinct.

- Add optional nebula parameters to `SystemConfig`.
- Add a shader-driven nebula layer beside the existing starfield.
- Seed nebula color, density, motion, and probability from the system seed.
- Keep clear-space systems possible so nebulae remain special.
- Later, allow the Campaign Bible or system story pack to influence visual
  palette.

Why here: it fits naturally after system identity and pre-generation, but can be
pulled earlier as a visual win if desired.

### Phase 6: Relationship And Memory Use

Goal: make the world remember the player.

- Add NPC relationship records.
- Add faction relationship reason records.
- Add current-timeline memory queries from chronicle events.
- Add compact summaries for prompt context.
- Let generated NPCs become recurring contacts.

Why seventh: this builds on the chronicle work already started.

### Phase 7: UI Command Feedback And Boost

Goal: small player-facing improvement with low risk.

- Add active-command visual state to the selected target panel.
- Add Boost button.
- Implement 25% speed boost for 5 seconds.
- Add 60-second cooldown.
- Add small heat damage or heat buildup as the first cost model.
- Add HUD cooldown feedback.
- Leave room for later upgraded boosters that give stronger speed benefits with
  higher heat damage.

Why here: it is valuable and straightforward, but it does not unblock the
procedural uniqueness architecture.

### Phase 8: Combat, Progression, And Itemization Depth

Goal: turn the generated universe into a richer long-term game loop once
procedural identity and mission reliability are stable.

- Add weapon profile resources or data records for fire rate, range, energy
  use, heat, damage type, projectile scene, and upgrade scaling.
- Add a dedicated damage model that can account for shields, armor, hull,
  mitigation, and damage categories such as kinetic, thermal, and EM.
- Split projectile behavior into reusable definitions for standard bolts,
  beams, missiles, homing shots, area bursts, and future special munitions.
- Add deeper enemy tactical AI: state machines or utility scoring for approach,
  orbit, strafe, flee, regroup, escort, and coordinated wing behavior.
- Add combat collision-avoidance and target-priority logic so generated patrols
  feel different by faction, role, and ship class.
- Add active gameplay VFX systems for weapon impacts, shield ripples, engine
  trails, boost effects, explosion debris, and repair or scanner feedback.
- Begin breaking the monolithic UI into focused scene/controller pieces as
  features stabilize: HUD, inventory rows, station contacts, map widgets,
  contract cards, and comms panels.
- Add pilot progression that persists beyond the current ship: XP, reputation
  milestones, pilot perks, active abilities, or campaign traits.
- Add class-driven active item behavior for consumables and equipment such as
  scanner probes, shield overchargers, electronic warfare tools, emergency
  repairs, and deployable beacons.

Why here: these systems add a lot of depth, but they should build on a stable
campaign identity, inventory, store, mission, and generated-system foundation.

## Open Questions

Answered:

- Original major factions stay in the home system and can reappear for drama.
- New factions and conflicts reveal as the player moves through gates.
- Kaelen is the only fixed recurring character besides the player.
- Local model failure should be explicit; silent static fallback is not an
  acceptable default for the intended experience.
- Generated NPCs can die, move, betray, or become unavailable only when the
  player is in-system or directly involved. Kaelen cannot die.
- The broader story continues even when the player ignores it.
- Fallback text/messages/quests should be last-resort only.
- Main stations need at least one NPC per active system faction plus a mechanic;
  outposts can have two or more random local contacts.
- Generated systems should usually have two to three larger factions, at least
  two where conflict is expected, and up to four larger factions at the crowded
  high end. Minor hostile factions can exist on top of that.
- Humor should be common enough to lighten the game, with dry/slightly dark
  PG-13 humor as the baseline and occasional lighter weirdos allowed.
- Neighbor systems should pre-generate in the background when entering a system,
  and system 2 should start generating at campaign launch.
- Seeded nebula shader backgrounds should be added to the TODO list as a visual
  identity feature for generated systems.
- Controller-friendly UI should be planned as a real pass, not an afterthought,
  so the expanding station/inventory/map/contact screens remain playable without
  a mouse.
- Boost can start with small heat damage or heat buildup, with larger risky
  boosters left for later upgrades.
- New regions can reveal one or several brand-new larger factions depending on
  the story and seed, but the game should avoid making the player deal with the
  same frontier factions for too long.
- Hostile minor faction home systems should be rare boss-like discoveries. They
  can be dangerous, personal, and memorable, especially if the player has been
  killing that faction's ships for contracts.
- Boss-like hostile home systems should often include a second outbound gate or
  alternate route so the player can experience the dangerous area without being
  permanently forced through it.
- Boss-like hostile systems are rare for fun pacing. The player should not
  commonly jump into systems where everyone is hostile all the time, because
  that would make exploration exhausting instead of exciting.
- Background system generation is invisible to the player during normal play;
  diagnostics are for development/failure cases only.
- Kaelen can hold up an exit if a destination somehow is not ready, but that is
  an emergency mask for a generation failure or slowdown.
- Players can form alliances, but alliances create enemies and consequences.
- Kaelen's personal mystery should never be fully solved, though her actions and
  story role can be revealed enough to support a strong arc.
- Fallback diagnostics matter, but the project should move away from fallbacks
  as quickly as practical.
- Add a persistent idea-memory file so LLM generation can avoid repeating prior
  concepts, names, jokes, and story beats.
- Rumors should sometimes become breadcrumbs in campaign-level rumor trails,
  including rare paths to hidden discoveries or an endgame easter egg.
- Add story horizon regeneration so the larger model can append the next
  campaign arc when the prepared frontier is running low.

Still open:

- No major design questions are blocking the first implementation pass. Details
  can be tuned as systems come online.

## Immediate Next Planning Decision

The strongest next implementation step is Phase 0: make fallback usage visible.
It is small, testable, and will show whether the current game is mostly using
LLM content, retries, procedural fallbacks, or static canned lines.

After that, build the Campaign Bible schema before adding more content. Without
the bible, every new generator risks becoming another disconnected source of
randomness.

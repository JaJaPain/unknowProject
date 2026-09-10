# Narrative System Design
_The goal: every campaign is a whole new story with its own life. A player should be able to say to a friend "you won't believe what happened in my game today" — and mean something different every time._

---

## 1. Vision

Most procedural games generate content. This system generates **meaning**.

The difference: a mining mission is not just "collect 50 ore." It exists because a faction war three systems away destroyed a convoy, which stressed a supply chain, which made a nervous logistics agent offer double pay to someone who doesn't ask questions. The player may never learn all of that. But they'll feel it in the way the agent talks, in the rumor they overhear at the bar, in the system chat two docks over where someone is arguing about a delayed shipment.

Every campaign starts from a different story seed. Different factions at war. Different secrets buried at the center. Different Kaelen comments that make you wonder what she already knows. The missions are different because the world is different — not just reshuffled, but causally connected to a specific set of events that this campaign and no other has.

The player earns the story by playing. They don't read it. They live it through the texture of every interaction.

---

## 2. Architecture Overview

Three layers, each feeding the next:

```
┌─────────────────────────────────────────────────────┐
│  CAMPAIGN SPINE  (gemma4, generated once at start)  │
│  The full arc. Factions, war, cause/effect chain,   │
│  secret at the center. Stored as campaign_bible.    │
└──────────────────────┬──────────────────────────────┘
                       │ informs
┌──────────────────────▼──────────────────────────────┐
│  STORY STATE  (StoryManager, updated in real-time)  │
│  Current chapter. Active tensions. What the player  │
│  knows vs. what is still hidden. Short living doc.  │
└──────────────────────┬──────────────────────────────┘
                       │ injected into every prompt
┌──────────────────────▼──────────────────────────────┐
│  CONTENT GENERATION  (qwen2.5, every interaction)   │
│  Missions, rumors, banter, system chat, Kaelen      │
│  lines — all generated with story state as context. │
└─────────────────────────────────────────────────────┘
```

The player never sees the spine or the story state. They experience the content that flows from it.

---

## 3. The Campaign Spine (gemma4)

Generated once when a new campaign starts. Never regenerated mid-campaign — this is the fixed skeleton everything else hangs on.

### What gemma4 writes

A structured document covering:

- **The inciting event** — what happened before the player arrived that set the world in motion. A war. A betrayal. A discovery. Something that created ripples the player will feel for 5+ hours.
- **The faction landscape** — 2-3 factions in active tension. Each has a goal, a grievance, and something they need. Their conflict creates the supply chain problems, the information wars, the desperate agents handing out missions.
- **The cause/effect chain** — a 5-6 link chain of consequences that spans multiple systems. Each link is a "chapter." The player's missions advance them through the chain without the chain ever being explained directly.
- **The secret at the center** — what's really going on underneath the surface tension. The thing the player pieces together across the whole campaign. May reframe everything they did.
- **Kaelen's angle** — what Kaelen knows, how she's connected, what she won't say. Written into the spine so her comments stay consistent and meaningful across the whole campaign.
- **The ending conditions** — what resolves the story. Not scripted cutscenes — a state the world reaches that closes the arc.

### Format

Stored as `user://campaign_bible.json`. Structured so StoryManager can query individual pieces:

```json
{
  "inciting_event": "...",
  "factions": [ { "name": "...", "goal": "...", "grievance": "...", "needs": "..." } ],
  "chain": [
    { "chapter": 1, "surface_tension": "...", "hidden_cause": "...", "resolves_when": "..." },
    ...
  ],
  "secret": "...",
  "kaelen_angle": "...",
  "ending": "..."
}
```

### The prompt

gemma4 gets the world lore, the current faction registry, the system map, and this instruction: *write a campaign story that a player will discover through 15-20 short missions across 4-6 systems. Make the surface reasons for missions feel mundane and urgent. Make the real reason feel inevitable in retrospect.*

---

## 4. Story State (StoryManager)

The spine is fixed. The story state is alive.

StoryManager maintains a short document — under 300 words — that describes the world **right now** from the player's position in the story. This is what gets injected into every LLM prompt.

### What it tracks

```json
{
  "chapter": 2,
  "active_tensions": [
    "Vanguard destroyed a Hollow Syndicate mining convoy 3 days ago",
    "Delphi Station is short on titanium — agents are nervous and paying extra"
  ],
  "player_knows": [
    "There's a war between Vanguard and Hollow Syndicate",
    "The ore shortage is connected to the war"
  ],
  "player_does_not_know_yet": [
    "The convoy was destroyed on purpose — Hollow Syndicate staged it for insurance",
    "Kaelen brokered the tip that led Vanguard to the convoy"
  ],
  "current_foreshadow": "An intel broker in the next system keeps asking about ship manifests from 3 days ago",
  "kaelen_current_mood": "unusually quiet about the Hollow Syndicate situation"
}
```

### How it updates

After each mission completes, StoryManager checks: did this mission resolve a chapter link? If yes, advance chapter, update tensions, move items from `player_does_not_know_yet` to `player_knows` as appropriate, generate a new `current_foreshadow`.

Updates are cheap — the small model writes 2-3 sentences to update the state document, not a full regeneration.

### Injection

Every LLM call that generates player-facing content gets a `[STORY STATE]` prefix block. The small model doesn't get the full spine — just the current state. It knows enough to be consistent, not enough to spoil things it shouldn't mention yet.

---

## 5. Mission Causality — The "Because" Field

The current mission system generates missions that feel independent. A mining mission is a mining mission. An intel fetch is an intel fetch.

The fix: every mission gets a `because` field that roots it in the current story state. The agent doesn't need to explain this to the player — but the brief, the NPC's tone, and the reward structure should all be shaped by it.

### Example

Without causality:
> *"I need 40 units of titanium ore. Standard rate."*

With causality (`because: "Vanguard destroyed our mining convoy, we're 3 weeks behind, and the foreman is about to lose his contract"`):
> *"Look — I'm not going to pretend this is a normal run. We lost a ship last week, the kind of loss you don't put in a report. I need that ore and I need it quiet. Double the standard rate, no questions asked."*

Same mission. Completely different texture.

### How it works

When StoryManager creates a mission slot, it passes the small model:
- The mission type (mining, fetch, combat, escort)
- The agent personality
- The `because` — pulled from current active tensions
- The story state context block

The small model writes the brief knowing why the mission exists. It can hint at the reason, dance around it, or play it completely straight — all of which feel more alive than a generic brief.

### Chain missions

Some missions should explicitly continue a thread. StoryManager tracks a `pending_hooks` list — story threads that have been seeded but not yet paid off. When the player completes a mission that was marked as a hook, the next mission offer from a connected agent should acknowledge the connection, even obliquely.

> *(After the mining run)* Agent Ryn: *"The ore arrived. Don't ask me how I know — just know that the people who needed to know, know. There's something else. The person who cost us that convoy... someone's been asking questions about them in the Meridian system."*

The player is being handed the next thread without being told they're following a story.

---

## 6. Kaelen — The Constant Thread

Kaelen is never fully explained. That's intentional and must be protected at the architecture level.

The spine gives Kaelen an angle — something she knows, something she's done, something she's watching for. StoryManager knows Kaelen's angle. The small model does not. When Kaelen speaks, she gets the story state and her `current_mood` field, but not her angle. She says things that are consistent with what she knows without the model being able to accidentally reveal it.

### Kaelen's layers

- **Surface Kaelen** — cynical broker, calls the player "Shiny," keeps score in credits
- **Middle Kaelen** — has been around long enough to recognize patterns. Occasionally says things that hint she's seen this before.
- **Deep Kaelen** — knows something about the secret at the center. Will never say it directly. The player pieces it together from 15 hours of small moments.

### How this plays out

In chapter 1, Kaelen makes an offhand comment about the Hollow Syndicate that's slightly too knowing. The player might not even notice.

In chapter 3, after the player discovers the staged convoy, Kaelen doesn't react with surprise. She just says: *"Insurance fraud at that scale takes planning. And patience. Someone's been patient."*

In chapter 5, the player realizes Kaelen knew. Kaelen never confirms it. She just says: *"Shiny. You did good work. Whatever happens next — you did good work."*

That moment only lands because of the 15 hours before it. The architecture has to protect it — StoryManager holds the secret, the small model just gets the mood.

---

## 7. Ambient NPC Dialogue — System Chat

System chat currently carries mission chatter and combat taunts. It should also carry the world.

### Two-person NPC conversations

Generated in the background, seeded with story state. Two dock workers, two pilots, a bartender and a regular. They talk about:

- **Story-adjacent** — the convoy that went missing, the faction that's been pushing into new territory, the agent who's been paying double lately
- **Mundane** — laundry, a bad meal at the station cafeteria, whether the new docking fees are fair, a wife who's tired of waiting
- **Overheard intel** — fragments of the story the player might be trying to piece together, spoken casually between people who don't know the player is listening

The ratio matters. Too much story-chat feels like a briefing room. Too much mundane feels like filler. Roughly: 30% story-adjacent, 20% overheard intel, 50% mundane. The mundane is what makes the world feel real. The intel hits harder because it's surrounded by ordinary life.

### Timing

Fires every 3-5 minutes of real play time when the player is in a system (not in combat, not in a menu). StoryManager picks a topic bucket based on current chapter and rolls whether to go story-adjacent or mundane. Small model writes 2-4 lines of dialogue between the two NPCs.

### Persistence

Conversations don't repeat. StoryManager keeps a `used_topics` list per chapter. Once a topic is used it's retired. This means the ambient chat always feels like it's moving forward, not recycling.

---

## 8. Rumors

Rumors are the connective tissue between the ambient world and the player's active story.

A rumor is a single line delivered by an NPC during a station visit or system chat. It should feel like something overheard, not a quest marker. Examples:

- *"Heard the Hollow Syndicate's been rerouting their ore runs. Something spooked them."*
- *"Station master at Delphi's been turning away ships with Vanguard registry. Quietly."*
- *"Someone at the Meridian bar has been buying rounds for anyone who knows the name of a certain cargo manifest. Weird."*

Rumors are seeded from `pending_hooks` in StoryManager. They plant questions without answering them. The player follows the thread or doesn't — but the world feels like it's happening whether they're paying attention or not.

---

## 9. Implementation Phases

### Phase A — Campaign Spine Generator
- New `CampaignBibleGenerator.gd` — calls gemma4 with world lore + faction registry + system map
- Generates and saves `user://campaign_bible.json` on new campaign start
- StoryManager reads it and initializes chapter 1 story state
- No player-facing output yet — just the skeleton in place

### Phase B — Story State Document
- StoryManager gets a `story_state` dict: chapter, active_tensions, player_knows, player_does_not_know_yet, current_foreshadow, kaelen_current_mood
- `get_story_context_block()` — returns a short formatted string for injection into LLM prompts
- `advance_chapter()` — updates state when a chapter-link mission resolves
- Saved to `user://story_state.json` so it survives session restarts

### Phase C — Mission Causality
- Mission generator gets `because` field from StoryManager's active tensions
- `pending_hooks` list: StoryManager tracks open threads; mission completions check and close them
- Connected agent follow-up: after a hook mission, the connected agent's next brief acknowledges the thread
- Existing `LLMInterface.request_quest_candidate()` gets story context block prepended

### Phase D — Kaelen Integration
- Kaelen's lines get `kaelen_current_mood` from story state but NOT Kaelen's angle
- New Kaelen line types: `kaelen_chapter_comment` (fires once per chapter), `kaelen_hint` (fires when player completes a hook mission)
- StoryManager controls when these fire — not on a timer, on story events

### Phase E — Ambient NPC Dialogue
- New `AmbientChatGenerator.gd` — fires every 3-5 minutes during open play
- Picks topic bucket (story-adjacent / mundane / overheard-intel) from StoryManager
- Small model writes 2-4 lines between two named NPC archetypes
- Delivered via existing `GlobalState.emit_chatter()` system
- `used_topics` list prevents repeats within a chapter

### Phase F — Rumors
- Station visit triggers a rumor check against `pending_hooks`
- 40% chance of a rumor per visit (not every visit — rarity makes them land)
- Single line, delivered as system chat from an unnamed NPC
- StoryManager marks the hook as "hinted" once a rumor fires for it

---

## 10. What Already Exists

_Surveyed 2026-06-26. Much more is built than expected._

| Component | Status |
|---|---|
| `CampaignBibleStore.gd` | **Complete.** Full persistence, validation, status tracking, rumor trails with clue templates, regeneration triggers, expansion rules. Loads/saves `campaign_bible.json` per campaign slot. |
| `NarrativeDirector.gd` | **Complete.** Builds the gemma4 prompt for bible generation. Parses and validates the response. Handles procedural bootstrap fallback. |
| `LLMInterface.request_campaign_bible_generation()` | **Complete.** Calls gemma4 with the NarrativeDirector prompt, handles the response, stores via CampaignBibleStore. |
| Bible generation trigger | **Complete.** `GameRoot` calls `_queue_campaign_bible_generation_for_active_slot()` on new campaign start and on automatic new campaign. |
| `campaign_bible_context_text` | **Complete.** Bible's tone/pressure/rules are injected into quest prompts via `campaign_bible_context_text` in LLMInterface. |
| `story_pack` per system | **Complete.** Each system definition carries `active_tension`, `local_nickname`, `humor_guidance`. Injected into mission and arrival prompts. |
| `SystemStoryArcEvent.gd` | **Exists.** Event type for story arc beats, registered in event scheduler. |
| `StoryManager.gd` | **Exists.** Beat scheduling — fires story beats on kill count, dock, delay, system arrival, quest completion. Needs the story state layer (Phase B). |
| `CampaignChronicleStore.gd` | **Complete.** Full event timeline with branching/checkpoint support. Records what happened. |
| `CampaignKaelenMemoryStore.gd` | **Complete.** Kaelen's bounded memory store — appends memories, manages rollback, tracks reversals. |
| `CampaignAgentMemoryStore` | **Exists.** Per-agent memory for mission context continuity. |
| `GlobalState.emit_chatter()` | **Complete.** Ambient NPC chat delivery already wired. |
| Kaelen voice + personality | **Complete.** TTS blend, speed, style all defined. Needs story-state-aware line types (Phase D). |
| Faction registry | **Complete.** Feeds into bible prompt already. |
| World lore (`world_lore.md`) | **Complete.** Injected into every LLM call. |

**What is actually missing (the real gaps):**

| Gap | Phase |
|---|---|
| **Story State Document** — no living `story_state` dict tracking chapter, active tensions, what player knows vs. doesn't know, pending hooks | Phase B |
| **Mission causality** — missions have `active_tension` per system but no `because` field linking them to a causal chain or story hook | Phase C |
| **Kaelen's angle protected** — no mechanism preventing small model from seeing Kaelen's deep angle from the bible | Phase D |
| **Ambient two-person NPC dialogue** — chatter is single-speaker; no two-NPC conversation generator | Phase E |
| **Rumor hook firing** — rumor trails defined in bible but no runtime system firing them at station visits | Phase F |
| **Story screenshots** — no trigger points capturing frames at story moments | Pre-PDF |
| **Campaign closure PDF** — no PDF/document generator at campaign end | Closure |

The foundation is exceptional. Phase B is the unlock — once story state exists, Phases C–F are additive layers on top of infrastructure that's already there.

---

## 11. The Design Principles to Never Break

1. **The player discovers, never is told.** Story information reaches the player through NPC behavior, mission texture, overheard chat, and Kaelen's silences — never through exposition dumps.

2. **Kaelen's angle is sacred.** StoryManager holds it. The small model never sees it. It can only be revealed by the large model in a specific late-campaign moment, never accidentally leaked in ambient dialogue.

3. **Mundane protects the meaningful.** Every chapter needs mundane ambient chat. The laundry argument makes the intel fragment two minutes later hit like a freight train. Do not cut the mundane to "save tokens."

4. **The story happens whether the player is watching or not.** The world state advances on missions completed, not on player attention. A player who ignores rumors still finds that the world has moved on when they come back to a system.

5. **Every campaign is unrepeatable.** The spine is generated fresh. The faction names, the inciting event, the secret — all new. A player's second campaign should feel like a different author wrote it.

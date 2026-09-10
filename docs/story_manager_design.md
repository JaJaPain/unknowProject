# Story Manager — Design Document (v2)
_Date: 2026-06-22 | Branch: segment-3/economy-stores-events_
_Revised after design session — v1 was passive observer, v2 is active narrative director_

---

## 1. The Core Idea

The StoryManager is a **narrative director** that runs silently in the background.
It knows what story beat comes next. It watches what the player is doing.
And when the player isn't moving toward that beat naturally, it reaches into the
gameplay systems and manufactures organic reasons to go there — without the player
ever knowing it's happening.

The player never sees a "go here for story" marker. They see:
- A quest that happens to be in the next system
- Their current station getting uncomfortable (faction ships gathering, patrols increasing)
- A Kaelen message hinting that something interesting is happening further out
- An upgrade quest that lines up exactly with what they'll need for the next challenge

All of this is the director working. None of it feels scripted.

### What this is NOT
- Not a cutscene engine or a linear railroading system
- Not a replacement for the quest system — it is a hidden layer above it
- Not something the player interacts with directly — it has no UI
- Not a forced path — the player can ignore every nudge, the world just gets quieter

---

## 2. Story Generation at Campaign Start

On the very first campaign load (no save file), the game calls Gemma 4 to generate
the full story arc for this run before the player enters the world.

### What Gemma generates

A structured dictionary — not freeform prose — describing the narrative skeleton:

```gdscript
{
  "title": "The Sable Accord",
  "arcs": [
    {
      "id": "arc_1",
      "name": "First Blood",
      "target_system": "frontier_alpha",    # actual system ID from the generated galaxy
      "beats": [
        {
          "id": "arc1.b1.kaelen_contact",
          "trigger_event": "on_system_arrived",
          "description": "Kaelen reaches out with a cryptic warning about Zenith activity",
          "player_need": null,               # nothing required to reach this beat
          "delivery": "kaelen_voice_message",
          "line": "..."
        },
        {
          "id": "arc1.b2.faction_package",
          "trigger_event": "on_quest_completed",
          "description": "A courier package leads to evidence of a Zenith black site",
          "player_need": { "type": "quest_type", "value": "delivery" },
          "delivery": "quest_injection",
          "payload": { "destination_system": "frontier_alpha", "flavor": "corporate_smuggle" }
        }
      ],
      "system_events": [
        { "system_id": "frontier_alpha", "event": "zenith_patrol_surge", "intensity": 0.4 },
        { "system_id": "home_system",    "event": "faction_pressure",     "intensity": 0.2 }
      ]
    },
    {
      "id": "arc_2",
      "name": "The Black Site",
      ...
    }
  ]
}
```

### Key generation constraints given to Gemma

- Use the actual system IDs from the player's generated galaxy (passed in context)
- Use the actual faction names that exist in this run
- Space beats across 3–5 systems minimum — don't cluster everything in one place
- Each arc's `target_system` must be at least 1 gate jump from the previous arc's system
- Each beat must specify what the player needs to reach it (`player_need`) so the
  director knows what to build toward
- Keep `line` fields short (1–2 sentences) — these are voice messages, not essays

### Storage

The generated story is saved to `GlobalState.story_arc` on first generation and
persisted with the save file. Gemma is not called again for arc generation unless
the player starts a new campaign. However, the StoryManager WILL call Gemma again
for dynamic content within the arc (see Section 5: LLM Orchestration).

---

## 3. Player Behavior Observation

The StoryManager tracks a lightweight behavior snapshot updated on key events.
No per-frame tracking — just state changes that matter narratively.

```gdscript
# StoryManager internal state
var _behavior: Dictionary = {
    "current_system":        "",
    "time_in_system_min":    0,     # CampaignClock minutes since last jump
    "missions_run_here":     0,     # quests completed in current system this visit
    "total_jumps":           0,
    "total_quests":          0,
    "total_kills":           0,
    "systems_visited":       [],
    "last_beat_fired_id":    "",
    "beats_since_progress":  0,     # how many check events since arc advanced
}
```

**Stall detection:** `beats_since_progress` increments every time StoryManager
evaluates and the arc does not advance. When it crosses a threshold (e.g. 3 system
arrivals with no arc progress), the director escalates nudge intensity.

---

## 4. The Nudge System — How the Director Steers

When the player is not naturally moving toward the next beat, the director picks
from a menu of nudges in escalating order. It uses the lightest nudge first.
If that doesn't move the player after N events, it escalates.

### Nudge levels (lightest to heaviest)

| Level | Nudge type | What the player sees |
|---|---|---|
| 1 | `hint_chatter` | Passing NPC or comms relay mentions something in the target system |
| 2 | `kaelen_voice_hint` | Kaelen queues a voice message hinting at opportunity in target system |
| 3 | `quest_injection` | A quest is pushed whose destination is the target system |
| 4 | `world_pressure` | Hostile faction activity increases near current station — it gets dangerous to stay |
| 5 | `poi_highlight` | Target system gets a map highlight (KAELEN INTEL color) |

The director never uses level 4 or 5 without at least one lighter nudge having
been ignored first. It tracks which nudges fired and waits for player response
before escalating.

### Quest injection

The most powerful organic tool. StoryManager writes a hint into
`GlobalState.story_quest_hint` before the player opens the agent panel:

```gdscript
GlobalState.story_quest_hint = {
    "preferred_system": "frontier_alpha",
    "preferred_type":   "delivery",
    "flavor_tag":       "corporate_smuggle",
    "expires_after_docks": 3
}
```

LLMInterface reads this hint when building the quest generation prompt and
biases toward that system/type. The quest still looks procedural — it IS
procedural — the director just tilted the table slightly.

### World pressure

StoryManager writes to `GlobalState.story_world_pressure`:

```gdscript
GlobalState.story_world_pressure = {
    "system_id":  "home_system",
    "faction":    "zenith",
    "intensity":  0.6,       # 0.0–1.0 scales spawn rate and aggression
    "event_type": "patrol_surge"
}
```

MainScene's NPC spawn timer reads this and weights faction spawns accordingly.
The player's home station starts feeling occupied. No popup says "leave now" —
the world just gets harder to stay in.

---

## 5. LLM Orchestration — When StoryManager Calls Gemma

The StoryManager is the single authority on when Gemma4 is called for story content.
No other system triggers a story-related LLM call independently.

### When a Gemma pull is needed

| Situation | What StoryManager requests |
|---|---|
| First campaign load, no save | Full arc generation (structured story dict for all arcs) |
| Arc nearly exhausted (< 2 beats remaining in current arc) | Next arc generation, using current player state + galaxy as context |
| Beat requires a dynamic line not pre-written | Single line generation for that beat's delivery |
| Quest injection beat fires | Quest brief generation biased to story context |
| World pressure event fires | Faction flavor lines for NPC comms around that event |

### The generation queue

StoryManager maintains `_llm_queue: Array` of pending generation requests.
It fires them one at a time (never parallel — Gemma4 is local and single-threaded).
Results are cached in `GlobalState.story_arc` under the beat they belong to.

### Arc refresh threshold

When `beats_remaining_in_arc <= 2`, StoryManager triggers arc generation for the
NEXT arc immediately — before the current arc ends — so content is ready before
the player arrives. This is the "generate ahead" pattern, same as quest pre-caching.

### What gets passed to Gemma for arc generation

```gdscript
{
    "request_type":     "story_arc",
    "arc_number":       2,
    "previous_arc":     { ...summary of arc 1 events that fired... },
    "player_state": {
        "systems_visited":  ["home_system", "frontier_alpha"],
        "total_kills":      12,
        "dominant_faction": "zenith",    # faction player has most rep with
        "ship_tier":        "mid",       # estimated from cargo/upgrade state
    },
    "galaxy_context": {
        "available_systems": [...],      # systems not yet used as arc targets
        "faction_map":       {...},
    },
    "constraints": [
        "Target system must be reachable within 2 gate jumps of frontier_alpha",
        "Introduce one new faction complication not yet seen",
        "Arc should require approximately 4-6 player sessions to complete naturally",
        "Return structured dict matching schema: { arcs: [...] }"
    ]
}
```

### Ownership rule

**StoryManager is the only caller of Gemma4 for story content.**
LLMInterface still handles quest generation and NPC flavor — those are gameplay,
not story. The distinction: if content is meant to advance a narrative arc or
deliver a story beat, it routes through StoryManager. If it's ambient or
procedural (quest dialogue, gossip, mechanic greeting), it routes through
LLMInterface as today.

---

## 6. Message Ownership — Everything Story-Based

The StoryManager owns the schedule for every story-adjacent message in the game.
The individual systems (UIManager, AnomalyRegistry, MainScene) no longer decide
when story content fires — they expose delivery methods that StoryManager calls.

### Message types now owned by StoryManager

| Message | Current owner | Move to StoryManager? |
|---|---|---|
| Kaelen intel voice messages | UIManager (timer on system arrival) | **Yes — beat-driven** |
| Kaelen bounty announcements | UIManager (on dock) | No — these are gameplay, not story |
| Anomaly rumors (NPC chatter hints) | AnomalyRegistry (random on arrival) | **Yes — beat or nudge driven** |
| Faction comms hails (mission reversals) | QuestManager signal | No — gameplay |
| Arrival chatter from passing ships | MainScene (random) | Partially — story beats can inject lines |
| Kaelen system arrival line | GameRoot | **Yes — move into StoryManager beat** |

### The rule of thumb

> If a message could appear in a "Previously on..." recap, it belongs to StoryManager.
> If it's ambient texture that would never appear in a recap, it stays where it is.

---

## 7. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    STORY MANAGER                        │
│                   (autoload singleton)                  │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ StoryState  │  │ BehaviorTrack│  │  NudgeEngine  │  │
│  │ fired_beats │  │ stall detect │  │ level 1–5     │  │
│  │ arc_flags   │  │ time in sys  │  │ quest hints   │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              LLM Orchestration Queue             │   │
│  │  arc_gen / beat_line / quest_brief / faction_msg │   │
│  └──────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────┘
                         │ calls into (one direction only)
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    UIManager       GlobalState     LLMInterface
    voice button    story_hint      Gemma4 calls
    comms hail      world_pressure
         │               │
         ▼               ▼
    SpeechService   MainScene NPC spawner
                    QuestManager context
```

**Dependency rule:** StoryManager calls into everything. Nothing calls into StoryManager
except GameRoot's event hooks (on_system_arrived, on_kill, on_docked, on_quest_completed).

---

## 8. Pros and Cons

### Pros

**The world feels alive without scripted moments.** Players don't see "go here for
story." They see opportunities, pressure, and hints that happen to point the same
direction. The craft is invisible.

**One system owns the narrative.** Right now Kaelen's arrival lines are in GameRoot,
intel drops are in UIManager, anomaly rumors are in AnomalyRegistry. All scattered.
StoryManager centralizes the intent while the existing systems keep doing delivery.

**Generates ahead.** Arc content is ready before the player reaches it because
StoryManager triggers generation when arc beats run low — not when the player
arrives and needs the content immediately. Same pattern as quest pre-caching.

**Scales with Gemma4.** The better the local model gets, the richer the generated
arcs. The StoryManager architecture doesn't change — it just gets better content
to work with.

**Replayable.** Each campaign generates a different story arc against the same
galaxy. Faction dominance, arc targets, and beat content all vary by run.

**Testable.** `StoryManager.force_beat(id)` and `StoryManager.set_stall(n)` let
you fast-forward to any story state in a headless test or debug console.

### Cons

**Gemma4 generation quality is the ceiling.** If the arc output is generic or
internally inconsistent, the entire story suffers. The structured prompt constraints
help but don't eliminate this risk. Need fallback arcs for when generation fails.

**Quest injection is probabilistic, not guaranteed.** The story hint biases quest
generation — it doesn't force it. If the LLM generates an off-hint quest anyway,
the player might not get the nudge. The director has to be okay with this and
try again next dock.

**Stall detection is blunt.** Counting "beats since progress" doesn't distinguish
between "player is grinding happily" and "player is lost and frustrated." Both
trigger escalating nudges. Could over-nudge a player who just likes the current
system.

**Arc targets are fixed systems.** The generated story picks specific system IDs.
If those systems have nothing interesting in them (no station, no contacts), the
beat destination might feel hollow. Arc generation needs to prefer systems with
content.

**Two LLM systems running.** LLMInterface handles quest/NPC content; StoryManager
handles arc content. Both call Gemma4 (local). They need to not overlap in a way
that starves one of the other. The LLM queue in StoryManager helps, but quest
generation (which fires on dock) and arc generation (which fires when beats run
low) could collide.

**Content debt is now structural.** A working StoryManager with an empty or
thin StoryRegistry produces a confusing experience — the nudge system fires but
there's nothing interesting at the destination. The system creates a contract
with the player ("follow these hints, something good is there") that has to be
honored by actual story content.

---

## 9. Implementation Roadmap

### Phase 1 — Foundation (no gameplay change yet)
- `scripts/story/StoryManager.gd` autoload: behavior tracking, beat state, empty evaluate loop
- `scripts/story/StoryRegistry.gd`: static beat array (start with 4–5 Kaelen intel beats)
- `GlobalState`: add `story_arc`, `story_state`, `story_quest_hint`, `story_world_pressure`
- Hook `StoryManager.on_system_arrived()` from GameRoot
- Save/load `story_state` with existing checkpoint

### Phase 2 — Message ownership migration
- Move Kaelen system arrival line from GameRoot into a StoryRegistry beat
- Move Kaelen intel voice messages from UIManager timer into StoryManager beats
- Move anomaly rumors from AnomalyRegistry random roll into StoryManager nudge
- All three now fire only when StoryManager says so

### Phase 3 — Nudge system
- Implement `story_quest_hint` in GlobalState; LLMInterface reads it when building quest prompt
- Implement `story_world_pressure` in GlobalState; MainScene NPC spawner reads it
- Stall detection: `beats_since_progress` counter, escalation thresholds

### Phase 4 — LLM orchestration
- StoryManager `_llm_queue` with single-item processing
- Arc generation on first campaign load (call Gemma4 with structured prompt)
- Arc refresh trigger when < 2 beats remain in current arc
- Fallback hardcoded arc for when Gemma4 fails or is offline

### Phase 5 — Story content
- Write actual arc content in StoryRegistry (or let Gemma4 generate it)
- Define 2–3 complete arcs covering the first 6–8 systems
- This is a writing/design task, runs parallel to Phase 3–4 engineering

---

## 10. Open Questions

1. **Fallback arcs.** If Gemma4 is offline or returns malformed JSON, what story does
   the player get? Need at least one hardcoded arc in StoryRegistry as a safety net.

2. **Arc target system quality check.** Before assigning a system as an arc target,
   StoryManager should verify it has a station (for quest delivery) and at least one
   gate (not a dead end). Where does this check live — in StoryManager or in the
   Gemma4 prompt constraints?

3. **Quest injection detection.** How does StoryManager know if the injected quest
   was accepted? QuestManager needs to emit an event with the destination system so
   StoryManager can clear the hint and register that the nudge worked.

4. **Stall threshold tuning.** What's the right number of events before escalating
   nudges? Too low and the player feels pushed; too high and the story stalls. Start
   at 3 system arrivals with no progress, tune from playtesting.

5. **Player agency signal.** If the player explicitly ignores a level-4 world pressure
   nudge (stays in a dangerous system anyway), should the director interpret that as
   "player wants to stay here" and back off, or keep escalating? Probably back off
   for 2–3 events then try again.

6. **Multi-arc overlap.** Can two arcs be "active" at once? For example, a Kaelen
   story arc and a faction civil war arc running in parallel. This adds richness but
   complicates stall detection and nudge priority. Recommend: one primary arc active
   at a time, secondary arcs can inject ambient events but don't drive nudges.




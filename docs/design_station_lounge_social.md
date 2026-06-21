# Station Lounge — Social-Sim Design

Status: Design notes (no code yet)  
Created: 2026-06-21

## Overview

The Station Lounge becomes a bar — a social space where the player meets
NPCs off-duty, picks up system drama through conversation, and builds
relationships over repeated visits. No contracts, no shop UI. Just people
in a bar with things on their minds.

The core loop: dock → enter Lounge → see who's around → pick someone to
talk to → 2-3 exchanges of LLM-generated conversation → leave with flavor,
intel, or a shifted relationship.

## Visual Layout

The Lounge replaces the current button list with a portrait-based bar scene.

```
┌─────────────────────────────────────────┐
│           HAVEN STATION LOUNGE          │
│                                         │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌─────┐ │
│  │ BAR- │  │ NPC  │  │ NPC  │  │empty│ │
│  │TENDER│  │  A   │  │  B   │  │ seat│ │
│  └──┬───┘  └──┬───┘  └──┬───┘  └─────┘ │
│     │         │         │               │
│  "Marta"   "Rix"    "Ouna"             │
│  Bartender  Drunk    Stressed           │
│                                         │
│  ┌─────────────────────────────────────┐│
│  │ [Conversation area — appears when  ││
│  │  talking to an NPC]                ││
│  └─────────────────────────────────────┘│
│                                         │
│  [ Back to Services ]                   │
└─────────────────────────────────────────┘
```

- 4-5 portrait slots in a horizontal row (bartender always slot 1)
- Empty slots show an empty barstool/chair silhouette
- Each portrait shows: name, mood tag (Drunk, Stressed, Relaxed, etc.)
- Clicking a portrait opens the conversation area below
- Mood tag color-coded: green=good mood, amber=neutral, red=bad mood

## The Bartender

Every station has a bartender. They are the Lounge's anchor — always present,
always willing to talk. Generated per-station so each bar feels different.

**Identity**: Name, appearance (portrait), personality trait (gruff, chatty,
philosophical, nosy). Stored in station data alongside the mechanic profile.
Home station gets a hand-crafted bartender; generated systems get a generated
one.

**What they know**:
- Local system drama (faction tensions, recent events, gate rumors)
- Who's been in the bar lately ("That Aurelia pilot's been drinking alone
  all week")
- Soft warnings ("Watch yourself out past the belt — patrols have been thin")

**Conversation style**: The bartender is the easiest NPC to talk to. They
respond to anything, fill silence naturally, and never push the player away.
2-3 exchanges per visit. They're the safe fallback if no other NPCs are
around.

**Memory (v2)**: The bartender remembers the player across visits. Not full
conversation logs — just key beats: "You were here last week asking about
Zenith patrols" or "Back again? How'd that delivery go?" Stored as a short
list of tagged memory strings in the station save data.

## NPC Presence System

### Who's in the bar?

Each station has a pool of minor NPCs (already exists in `GlobalState`).
When the player enters the Lounge, roll which NPCs are present:

- **Pool**: All minor NPCs assigned to this station
- **Capacity**: 2-4 NPCs per visit (plus bartender)
- **Selection**: Random weighted by NPC activity level / faction presence
- **Cooldown**: When an NPC leaves (player undocks or time passes), they
  get a cooldown timer (30-90 game minutes) before they can appear again
- **Empty seats**: Always show at least 1 empty slot so the bar doesn't
  feel artificially full

### Mood States

Each NPC gets a mood rolled on entry. Mood affects their conversation tone,
what topics they gravitate toward, and how many exchanges they'll tolerate.

| Mood | Tone | Topics | Max Exchanges |
|------|------|--------|--------------|
| Relaxed | Friendly, open | Anything, local color | 3 |
| Drinking | Loose, oversharing | Gossip, complaints, confessions | 3 |
| Stressed | Terse, distracted | Work grumbles, faction anxiety | 2 |
| Celebrating | Loud, generous | Bragging, good news, rounds | 3 |
| Brooding | Short, guarded | Personal issues, cryptic hints | 2 |

Mood is metadata on the NPC's Lounge instance — not persisted. Fresh roll
each visit.

## Conversation System

### Flow

1. Player clicks an NPC portrait
2. NPC greeting appears (mood-colored, with portrait) + 3 conversation choices
3. Player picks a choice
4. NPC responds + 3 new choices (informed by what was just said)
5. Repeat for 2-3 exchanges total
6. NPC winds down naturally ("Well, back to my drink" / "I should go")

### LLM-Generated Choices (not scripted buttons)

Each turn, one LLM call generates:
- The NPC's response to the player's last choice
- 3 new player choices for the next turn

**Prompt context includes**:
- NPC name, role, faction, mood, personality
- Station name and system
- Current system drama (from story pack / event scheduler)
- Conversation history so far (this visit only)
- Player reputation with the NPC's faction
- Constraint: "This is a bar, not a workplace. NPCs can grumble about work
  or drop intel naturally, but they don't offer contracts or discuss business
  formally."

**Choice design**: Each choice should feel like a different conversational
angle, not a good/neutral/evil split. Examples:

- After an NPC complains about Zenith patrols:
  - "Sounds like they're looking for something specific."  (probe for intel)
  - "I ran into a patrol near the belt myself."  (share experience)
  - "Another round? You look like you need it."  (change subject, build rapport)

**Fallback**: If LLM is offline, use a canned 2-exchange tree per mood type.
Short but functional — the player still gets the bar experience, just less
dynamic.

### Response format (single LLM call)

```json
{
  "npc_line": "The NPC's spoken response (under 40 words)",
  "choices": [
    {"label": "Short player choice (under 12 words)", "intent": "probe"},
    {"label": "Short player choice (under 12 words)", "intent": "share"},
    {"label": "Short player choice (under 12 words)", "intent": "deflect"}
  ],
  "mood_shift": "none"
}
```

`intent` is for internal tracking — lets us weight future choices and detect
patterns (player who always probes might get NPCs clamming up). `mood_shift`
can be "warmer", "cooler", or "none" — subtle per-conversation drift.

### Conversation Wind-Down

After max exchanges (2-3 based on mood), the LLM is told this is the final
turn. The NPC delivers a closing line and no choices are generated. The
portrait stays in the bar but clicking them again gives a short brush-off
("Already said my piece, pilot" / *raises glass silently*) until next visit.

### Within-Session Memory

The conversation history array is kept in memory while docked. If the player
leaves the Lounge and comes back (without undocking), the NPC remembers what
was said. On undock, the history clears.

## Intel and Drama Integration

The Lounge is the player's soft intel source. NPCs don't hand the player a
mission briefing — they leak information through bar talk.

**What NPCs can reveal through conversation**:
- Faction tensions ("Aurelia's been hiring mercs — that's never good")
- System events ("Someone hit a Zenith convoy near gate 3 last cycle")
- Gate/route hints ("I heard there's a new lane opening past the belt")
- NPC relationships ("The mechanic here? Don't trust her quotes on Thursdays")
- Economy signals ("Ore prices are through the floor — too many miners")

**How it feeds gameplay**: These aren't quest triggers. They're flavor that
makes the world feel inhabited. Over time, a player who visits Lounges
regularly will have a better read on the political landscape than one who
just grinds contracts. Future work could let Lounge intel actually unlock
hidden quest variants or gate discoveries, but that's v3+.

## Build Order

| Phase | What | Depends On |
|-------|------|-----------|
| 1 | Bar visual layout with portrait slots | UI only |
| 2 | Bartender NPC — always present, 2-3 exchange conversations | LLM prompt |
| 3 | Random NPC presence with mood states and cooldown | GlobalState NPC pool |
| 4 | LLM-generated conversation choices (3 per turn, 2-3 turns) | LLM chatter system |
| 5 | Within-session conversation memory | Context array |
| 6 | Cross-session bartender memory | Station save data |
| 7 | NPCs approaching the player (v2) | Timer/event system |
| 8 | Cross-session memory for all NPCs (v2) | NPC save data |

## Decisions (resolved 2026-06-21)

1. **Bartender portraits**: Unique per station. Each bar gets its own
   generated bartender with a distinct portrait, name, and personality.
2. **Portrait slots**: 4 total (bartender + 3 NPC seats).
3. **Mood visibility**: Hidden until the player clicks. Mood is revealed
   through the NPC's greeting and conversation tone, not a UI tag. Makes
   each conversation a small discovery.
4. **TTS**: Full voice for every NPC line, every message. Long lines can
   be segmented. The Lounge is a still screen with no GPU pressure from
   gameplay rendering, so TTS cost is not a concern.
5. **Ambient audio**: Yes. Bar chatter, glass clinks, background music.
   Audio assets produced in Suno — not a blocker.

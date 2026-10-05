# Campaign spine plan — 2026-10-05

Todo item "F -- campaign direction and endings". Talked through with Abe on
2026-10-05.

## 1. Abe's decisions

1. **Uniqueness is the game's reason to exist.** After the tutorial, every
   campaign is a new experience. At about 10 hours, the answer to "what was
   this campaign about?" must differ every time.
   - The local model (8 GB VRAM budget) makes too many mistakes to keep a
     story straight. Uniqueness therefore comes from **structure**: decks,
     casting from people already met, thread weaving and consequences. The
     model only voices what the structure decided.
2. **Everything connects.** The season's big pieces (the Lodestar, the Hidden
   Hand mystery, the arcs) always converge. Loose threads exist so that at the
   climax the player sees that most of what had been happening led to this
   outcome.
3. **Ending by choice.** "Retire the Captain, the campaign closes, you get your
   story as a keepsake" is the right path.
4. **Death is the player's choice.** On death, either:
   - end the campaign and have the story told as a **eulogy**, or
   - revert to the last save and continue.

## 2. Where things stand

Most of the machinery already exists:

| Piece | What it does today | File |
|---|---|---|
| Lodestar | One far destination per campaign (6 cards); bearings narrow a star-map wedge; arrival scene; season rollover | `data/content/lodestars.json`, `scripts/story/LodestarGuide.gd` |
| Hidden Hand | Motive / method / goal drawn at season start; arcs plant loose threads (traces + decoys); locks onto a person the player met; forges a confrontation card | `scripts/story/premise/HiddenHand*.gd`, `Showrunner.gd` |
| Arcs | Premise-card stories (personal / local / regional), outcomes seed new ones | `ArcEngine.gd`, `PremiseDirector.gd` |
| Undercurrent | N.O.V.A. and Kaelen's secret; never resolves | `scripts/story/undercurrent/` |
| Story Ledger | Code-written shorthand of what happened | arc state `ledger` |

**The gaps:**
- **Two season endings that don't know about each other.** The Hidden Hand's
  confrontation "closes the season", and so does reaching the Lodestar. They
  can land hours apart, so neither is THE climax.
- **They're about different things.** Hidden Hand goals are local politics
  (own the trade lanes, bury an old crime); Lodestars are far-off mysteries
  (a silent fleet, a humming gate). Nothing ties them together.
- **The player can't see the story building.** Threads are tracked, but
  there's no "story so far" for the player to look back at.
- **Unmeasured.** No one has played a season through to its reveal; we don't
  know how long it takes or whether the lock fires in real play.
- **No endings.** No retirement, no eulogy, no keepsake.

## 3. Convergence: one story per season

**The Hidden Hand wants what's at the Lodestar.** The two are drawn together
at season start, so the mystery and the destination are one story:

- Each Lodestar card lists the Hidden Hand goals it can host, with an authored
  **bridge**: why that person needs that place. Examples:
  - *Humming gate* + "own the trade lanes": a gate no one else can use is a
    lane no one else can tax.
  - *Silent fleet* + "bury an old crime": the evidence went down with those
    ships.
  - *Cartographer* + "rewrite a verdict": the charts prove where someone
    really was.
- **The Hidden Hand races you there.** Its plan steps are moves toward the
  Lodestar. The bearings you find are threads too: you're following its trail
  without knowing it.
- **One climax.** The confrontation is staged at the Lodestar (or the system
  just before it). Arriving and confronting are the same moment.
- **Connect the dots.** At the climax, a short scene shows 3–6 things the
  player actually saw (threads from the ledger: the cargo they hauled, the
  stamp on a manifest, the person who lied to them) and how each led here.
  Built by code from the ledger, with real names and places; authored
  connecting lines; the model may smooth wording but adds no facts.
- **Hard rule (existing):** the reveal must point at 3+ things the player saw.
  If too few were seen by the time they near the Lodestar, more threads are
  seeded on the approach.

Uniqueness comes from the combination: 6 Lodestars × the goals each can host ×
10 motives × 12 methods × whoever the player happened to meet × which threads
they saw and what they chose. The structure guarantees it all connects; the
specifics are different every time.

## 4. Feeling the story as it builds

- **Story so far** (a tab in the wiki / Lodestar log): the people met, places
  that mattered, the threads seen (the player can pin the suspicious ones; the
  thread board idea from the vision plan, 3.7). Plain facts from the ledger,
  no model text, so it's always correct.
- **Rising pressure** as the season goes on: the Hidden Hand's moves show up
  in the world (radio, board postings, N.O.V.A. noticing), so the climax
  doesn't come from nowhere.
- **Six more Lodestars** over time: six cards will start to repeat; more cards
  (and more bridges) are the cheapest way to add uniqueness.

## 5. Endings

**Retire (any time, from the systems menu):** confirm, then the campaign is
closed for good and the player gets **their story**:
- an in-game reader (chapters: how it started, who they met, what they did,
  the season's climax, how it ended), and
- a file saved to disk (PDF or HTML), titled with the campaign and Captain.

**Death:** the death screen offers two choices:
- **End the story** -> the same keepsake, told as a **eulogy** (who the Captain
  was, what they did, who they left behind, how it ended), then the campaign
  is closed; or
- **Return to the last save** and carry on (today's behaviour).

**How the text is made (8 GB-safe):** the Story Ledger already records every
event as facts. The keepsake is assembled by code, chapter by chapter, from
those facts with authored sentence patterns (so it's always true). The model
is optional: it may rewrite a paragraph for flow, and every rewrite is checked
against the facts (names, places, numbers) and thrown away if anything is
added or wrong. The fixed-cast secret never appears (existing leak test).

## 6. Build order (proposal)

1. **Season sim.** Fast-forward a season in a test run: does the lock fire,
   how many hours does it take, what does the ledger look like? Then run
   several seeds and compare: how different are two campaigns at 10 hours?
   This gives us real numbers before building more.
2. **Lodestar x Hidden Hand bridges** (data + draw at season start), the
   Hidden Hand's plan steps aimed at the Lodestar, bearings as threads.
3. **One climax:** the confrontation staged at the Lodestar arrival; the
   season closes once.
4. **Connect the dots** scene at the climax.
5. **Story so far** tab.
6. **Endings:** retire + keepsake reader/file; death choice + eulogy.
7. **More Lodestar cards** and bridges (writing, in short review batches).

Lines and bridges are authored and go to Abe in short batches.

## 7. Season sim results (2026-10-05)

`tools/story_sim/run_season_sim.gd`: 6 campaigns in a row (one shared card
history, like one player), up to 30 real hours each, story jobs ~45% of what
the player does, a new system every 30-60 minutes.

| | Result |
|---|---|
| First loose thread seen | ~0.2 h, every campaign |
| Real traces seen by 10 h | 8-24 |
| Main story locked | **2 of 6** campaigns (at 10.0 h and 25.4 h) |
| Confrontation reached / season closed | **0 of 6**, even at 30 h |
| Live stories at 10 h | 25-30 started, only 6-15 resolved |
| Stories two campaigns share at 10 h | 17% average, 35% worst pair (good) |

**Why it doesn't lock:** the prime suspect is always "busy". The draft guess
keeps casting them into new stories (they'd appeared in 3-5), and the lock
waits until they're in none; the candidate list also skips busy people, so it
drops below the 3 it needs. A deadlock that gets worse the better the
recurring-suspect idea works.

**Why nothing closes:**
- **Too many live stories.** About two start per system. Ignored stories
  settle after 3/6/12 in-game DAYS, but the clock moves only on events (about
  5 in-game hours per real hour), so in real play they almost never settle.
  The board fills up and the main story drowns in it.
- **The confrontation is just another posting** among ~30, with nothing
  pointing the player at it.

**Fixes (mechanical, proposed):**
1. **Lock without waiting:** lock when the evidence is there; stop casting the
   suspect into NEW stories once the story is ready; the reveal plays when
   their current story ends (or straight away if none).
2. **Stories settle in play time, not calendar days:** a personal story fades
   after you've been through ~2 more systems, a local one when you've left its
   system and moved on, a regional one after ~6 systems.
3. **A cap on live stories:** this system's own plus one regional; stories
   from systems far behind you wind down.
4. **The main story leads:** its postings come first on the board, and N.O.V.A.
   or Kaelen point at it once it's revealed (and, per section 3, it ends at the
   Lodestar).

**For Abe:** target hours. Suggested: reveal around hours 8-12, climax with
the Lodestar around hours 15-25 (the economy sim puts Class VI, needed for a
depth-13 Lodestar, at ~17 h for an efficient automated captain).

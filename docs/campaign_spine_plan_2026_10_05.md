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

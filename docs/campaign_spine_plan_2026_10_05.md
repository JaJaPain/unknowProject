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

## 8. Abe's answers (2026-10-05, after the sim)

- **Pacing:** yes. Reveal around hours 8-12; the climax at the Lodestar
  around hours 15-25.
- **N.O.V.A.'s database of people:** yes, as **its own button on the systems
  menu**. One entry per named person the player dealt with: portrait, name,
  role/faction, where met, and a very brief code-written line of how ("Agent
  Dan · Myrion Watch — sent you on 3 jobs for ore"). Updates with what
  happens to them (dead, jailed, owes you); after the reveal the culprit's
  entry says what they were.
- **Pins:** yes. The player can mark a person as suspicious; pinned people
  weigh more when the main story chooses its culprit.

Build next: the four sim fixes (re-run the sim until seasons land on those
hours), then N.O.V.A.'s database.
- **N.O.V.A. talks about her database (Abe):** now and then she mentions she's
  keeping every clue and every person, to work out why we're out here and who
  we are. Vague, in keeping with her missing memory from the intro; nothing
  that touches the fixed-cast secret. Authored lines, short batch for Abe.

## 9. Fixes landed (2026-10-05) and the sim after them

1-4 from section 7 are in (`HiddenHand.gd`, `HiddenHandForge.gd`,
`PremiseDirector.gd`): the lock waits on a busy suspect for at most 2 systems
(and the suspect isn't cast into anything new once the evidence is ready);
untouched stories fade by systems visited; at most 6 live stories; the main
story leads the board. Also: the confrontation is now regional (as "local" it
stayed behind in the system where the reveal happened), and the lock needs
evidence from 9 systems, 12 threads seen, 5 real traces (was 4 / 6 / 3).

Sim, 8 campaigns, 30 h max:

| | Before | After |
|---|---|---|
| Main story locked | 2 of 6 | **8 of 8** |
| Reveal | 10-25 h | **8.4-11.2 h (median 9.9)** |
| Confrontation reached | 0 | **8 of 8**, ~1 h after the reveal |
| Stories two campaigns share at 10 h | 17% avg | 10% avg (worst pair 52%) |

Still to do: the climax moves to the Lodestar (section 3); the worst pair
sharing half its stories shows the deck (152 cards, ~25 used per campaign by
10 h) will start repeating after ~6 campaigns: more premise cards over time.
Separately: headless test processes print their result and then don't exit
(hit the 400 s timeout); worth a look.

## 10. Landmark: the twin wreck field (Abe, 2026-10-05)

ChatGPT's model (`art_inbox/twin_wreck_field/`, copied to
`assets/landmarks/twin_wreck_field.glb`): two ~1.4 km ships broken in half,
a debris field ~3 km across, a 4-minute drifting-debris loop. No story yet;
Abe: a once-per-campaign event, led to it, explore the wreckage, find clues
to what happened and maybe something the campaign needs.

**Engine check (`--wreck-snapshot`, RTX 3060):** imports cleanly, animation
loops. 60 fps at 6 km and 2.5 km, 54 at 600 m; but ~700 draw calls (our
busiest scene so far: ~150), from 614 separate pieces. Fix before shipping:
hide the small debris beyond ~1.5 km (Godot visibility ranges), merge the
static hull pieces, fewer materials. Lighting: dark under our sun; the
approach could get work lights or a beacon.

**Event shape (proposal):**
- **Lead:** one per campaign, mid-season. A rumour, a bearing, or two dead
  transponders N.O.V.A. picks up; it's in a system off the main lanes.
- **Arrival:** no stations nearby, just the field; N.O.V.A. goes quiet for a
  moment (authored line).
- **Explore:** 4-6 scan points on the hull halves, deck modules and radiators
  (the scan bubble). Each gives a clue: a log fragment, a damage pattern, a
  cargo manifest. Clues are written from the campaign's own facts, so they
  can be **real traces of the Hidden Hand** (and decoys), feeding the main
  story like any loose thread.
- **What happened:** drawn per campaign (battle, sabotage, collision,
  mutiny), matching the Hidden Hand's method when it can.
- **Something the campaign needs:** a Lodestar bearing, a keystone part, or
  evidence that becomes leverage; plus salvage by drone dive into the decks.
- **Risk (optional):** scavengers already working it, or arriving.
- **Fits section 3:** the Silent Fleet Lodestar and the "bury an old crime"
  bridge are natural homes for it.
- **Radiation keeps you out (Abe, 2026-10-05):** a radiation zone around the
  hulls (~1 km) is why you can't fly in close, and why nobody has picked it
  clean. You scan from the edge; drones go inside (the drone dive). N.O.V.A.
  warns at the line, the HUD shows the zone, crossing it ticks damage,
  autopilot routes stay outside. Fits the "radiation belt" keystone: a
  shielded ship can later reach inner scan points and better salvage, a
  reason to come back. Also the performance fix: no close-up view to render,
  so small debris can be hidden at range (most of the ~700 draw calls).
- **Version 3 is the one (2026-10-05):** ChatGPT batched it to 44 meshes,
  one per material per section, with debris in six drifting groups
  (`assets/landmarks/twin_wreck_field_v3_batched.glb`). Draw calls 704 / 709 /
  621 -> **63 / 69 / 113** at 6 km / 2.5 km / 600 m, and it looks the same
  in the game. The lower-poly-only version changed nothing (614 pieces), as
  expected: the cost was the piece count, not the triangles. The other two
  stay in `art_inbox/twin_wreck_field/`.
- **Animation (2026-10-05):** v3's loop plays (checked: `--wreck-snapshot
  --anim-capture`), but six merged groups bob 0.1-2.7 m over minutes, so it
  reads as still. Abe: good enough for a short set piece. Optional polish
  later: a shader that tumbles every debris piece around its own centre
  (centres computed at load or baked by ChatGPT), still 6 draw calls.

# End Goal

**Stated by Abe, 2026-09-10.** This is the project's north star. Everything else
in `docs/` describes HOW; this describes WHAT FOR. When a decision is unclear,
this file breaks the tie.

---

## The goal, in his words

> The end goal for this game is to be a unique game for each campaign as soon as
> you get past the tutorial. You shouldn't ever feel like you played this before.
> All the missions and end goals after the tutorial should be unique to that
> campaign. The outcome of the game should also be unique. And once you leave the
> first system, no system should ever be the same as any other campaign. It
> should have new factions that have unique desires of their own. They should
> like and dislike other factions uniquely as well. The missions you are given,
> even if they have you kill someone or mine something, should be a unique reason
> as well.

Refined the same day, when asked about the existing fixed factions:

> The factions in the first system exist because of the tutorial. Each new system
> should have new factions in it. And the story that leads you to those new
> systems should rely on those new factions and their desires and likes and
> dislikes to move the story along.

---

## What that commits us to

Eight claims, each testable in play:

1. **The tutorial is the only fixed content.** Everything after it is generated
   per campaign. This is a boundary, not a guideline: if a thing is authored
   once and seen in every campaign, it belongs in the tutorial or nowhere.
2. **No repeated missions.** Not merely reshuffled — a returning player must not
   recognise a mission they have done before.
3. **No repeated end goals.** Each campaign has its own destination, not a shared
   one reached by different routes.
4. **No repeated outcome.** How it ends differs too, not just what happened on
   the way.
5. **No repeated systems past the first.** Layout, contents and character of a
   system are campaign-specific.
6. **New factions per SYSTEM** (refined by Abe, 2026-09-10), each with their own
   desires and their own like/dislike relationships with each other. Not one
   generated set per campaign — a new set in each new system the player reaches.
   The existing eight factions (Aurelia, Zenith, Vanguard, Reavers, Dustborn,
   Ironclad, Wraiths, Obsidian) **exist because of the tutorial** and are
   legitimately fixed for that reason. They are tutorial content. They are not
   meant to travel.
7. **Faction desire is the story ENGINE, not scenery.** The story that leads the
   player to a new system must be driven BY those factions' desires and their
   opinions of each other. Factions are not set dressing that a plot happens in
   front of; what they want, and who they cannot stand, is what moves the player
   from one system to the next.

8. **Unique REASONS, not just unique verbs.** This is the sharpest of the eight.
   "Kill this ship" and "mine this ore" will recur, because they are the verbs
   the game has. What must never recur is WHY. A mission is not unique because
   the target's name changed; it is unique because the reason you are being asked
   is one this campaign invented.

---

## What is deliberately NOT unique

The fixed cast. **N.O.V.A. and Kaelen are constant across every campaign**, and
Abe has been explicit that they are the game's heart (2026-09-07, on protecting
their canon). This is not a contradiction of the goal — it is the structure that
makes the goal survivable.

A world where everything is new every time has nothing for the player to hold on
to. Two known characters give a generated world a fixed point of reference: the
player learns N.O.V.A. and Kaelen once and carries them into every campaign,
while everything around them is unfamiliar. Remove them and "unique every time"
becomes "unmemorable every time".

So: **fixed cast, generated world.** Both halves are load-bearing.

---

## What this reprioritises

Read against this goal, several items in flight change rank.

| Work | Why it matters to the goal |
|---|---|
| **Mission dialogue is permanently templated** (`docs/bugs.md`, found 2026-09-10) | **Critical path.** A template cannot supply a unique REASON. Claim 8 is unreachable while every mission conversation comes from a deterministic composer -- the verbs would vary and the why would not. This moves from "a bug" to "the thing standing between the game and its stated purpose". |
| **Campaign bible JSON parse failure** (`docs/bugs.md`) | **Critical path.** The bible is the mechanism that makes a campaign *this* campaign. If it fails at session start, everything downstream is generic by default. |
| **P2 investigation shapes**, **P3 pressure tracks** | Core, not optional. They are how missions get campaign-specific causes rather than reskinned tasks. |
| **P4 narrow dialogue compilation** | Core. Narrower, cheaper, more reliable generation is what makes per-campaign dialogue affordable on a 4B model. |
| **Generated systems: NPC ships / station variety / difficulty scaling** (`docs/todo.md`) | Claim 5 depends on these. Procedural systems that "feel empty" or "all look the same" are the goal failing in the most visible place. |
| **Per-SYSTEM faction generation** | Claims 6 and 7. **No current work covers this, and it is the biggest unbuilt thing in the project.** See the gap below. |

---

## The largest known gap

**Factions are generated per SYSTEM, and nothing does that today.**

`FactionRegistry.KNOWN_PROFILES` (`scripts/economy/FactionRegistry.gd:21`) is a
hand-authored table of eight factions with fixed relationships, shared by every
campaign and every system.

That table is **not wrong** -- claim 6 says those factions exist because of the
tutorial, so being fixed is correct for them. What is missing is everything
after: each new system needs its own factions, with generated desires and
generated opinions of each other, and claim 7 says those desires must be what
routes the player onward.

**This is the biggest unbuilt thing in the project.** It reaches:

| Touchpoint | Why it is affected |
|---|---|
| Ship naming (`ShipAssembler`, NPC names) | "AURELIA Interceptor 388" assumes a known faction vocabulary |
| Voices (`TTSInterface.get_voice_for_faction`) | maps a fixed faction list to fixed voices |
| Reputation HUD (`Rep: ZEN 76 / AUR 0 / VAN -84`) | displays a fixed three-faction set |
| Mission targets (`_is_overview_mission_target`, KILL_SHIPS `target_faction`) | matches on faction id strings |
| Station ownership and lounge contacts | faction-derived |
| Combat profiles (`KNOWN_PROFILES` ship tiers) | faction IS the stat block today |

**An unresolved design consequence, for Abe to decide before this is planned:**
if factions are per-system, what happens to REPUTATION? Today the HUD shows a
persistent standing with three named factions. If Zenith only exists in the
tutorial system, a campaign-long Zenith reputation is meaningless -- but so is a
reputation that resets every jump. Options include per-system standing, a
portable notoriety that all factions read differently, or reputation with
PEOPLE rather than factions. This needs answering first; it shapes the whole
feature.

Recorded rather than solved. It deserves its own plan once the critical-path
items above are clear.

---

## How to use this file

Before starting work, ask: **which of the eight claims does this serve?** If the
answer is "none", it is polish, and polish is not what this project is short of.

Before calling something done, ask: **would a returning player notice they had
seen this before?** If yes, it is not done, whatever the tests say.

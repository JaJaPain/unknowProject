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

---

## What that commits us to

Seven claims, each testable in play:

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
6. **New factions per campaign, with their own desires** — and their own
   like/dislike relationships with each other. Faction politics are generated,
   not a fixed wheel with names swapped.
7. **Unique REASONS, not just unique verbs.** This is the sharpest of the seven.
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
| **Mission dialogue is permanently templated** (`docs/bugs.md`, found 2026-09-10) | **Critical path.** A template cannot supply a unique REASON. Claim 7 is unreachable while every mission conversation comes from a deterministic composer -- the verbs would vary and the why would not. This moves from "a bug" to "the thing standing between the game and its stated purpose". |
| **Campaign bible JSON parse failure** (`docs/bugs.md`) | **Critical path.** The bible is the mechanism that makes a campaign *this* campaign. If it fails at session start, everything downstream is generic by default. |
| **P2 investigation shapes**, **P3 pressure tracks** | Core, not optional. They are how missions get campaign-specific causes rather than reskinned tasks. |
| **P4 narrow dialogue compilation** | Core. Narrower, cheaper, more reliable generation is what makes per-campaign dialogue affordable on a 4B model. |
| **Generated systems: NPC ships / station variety / difficulty scaling** (`docs/todo.md`) | Claim 5 depends on these. Procedural systems that "feel empty" or "all look the same" are the goal failing in the most visible place. |
| **Faction generation with per-campaign desires and relationships** | Claim 6. **No current work covers this.** See the gap below. |

---

## The largest known gap

**Factions are currently a fixed set.** `FactionRegistry.KNOWN_PROFILES`
(`scripts/economy/FactionRegistry.gd:21`) is a hand-authored table -- Aurelia,
Zenith, Vanguard, Reavers, Dustborn, Ironclad, Wraiths, Obsidian -- shared by
every campaign. Their relationships are likewise fixed.

Claim 6 asks for the opposite: factions invented per campaign, with generated
desires and generated opinions of each other. Nothing in the current plans
addresses this, and it is not a small change: faction identity reaches ship
naming, voices, reputation, mission targets, and station ownership.

Recorded here rather than solved, because naming the gap is more useful than
guessing at it. It deserves its own plan when the critical-path items above are
clear.

---

## How to use this file

Before starting work, ask: **which of the seven claims does this serve?** If the
answer is "none", it is polish, and polish is not what this project is short of.

Before calling something done, ask: **would a returning player notice they had
seen this before?** If yes, it is not done, whatever the tests say.

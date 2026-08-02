# Mission Agents — state and handoff

Paused 2026-08-02. Research only; **nothing wired into Godot.**
Method: `skills/skill_llm_character_dialogue.md`. Full log: `ITERATIONS.md`.

## The idea

Agents are the people Kaelen introduces you to. They're generated per system — new name,
portrait, TTS voice — so they can't each have an authored bible. Instead there's a fixed cast of
**five personalities**, one assigned per agent, so a given agent stays consistent every time you
work in their system.

Author decisions, all settled:

| Question | Answer |
| --- | --- |
| How many personalities | five |
| Which beats | **offers only** for now; Kaelen still closes |
| Does personality change the mission | **no** — delivery only, generation untouched |
| Do you meet them again | yes; agents live in their systems, so repeat work meets the same ones |

## The cast

| Personality | Axis — what they want or fear | Status |
| --- | --- | --- |
| `desperate` | can't afford for you to say no; no one else left to ask | **approved** |
| `old_hand` | weary competence; won't waste anyone's time | **approved** |
| `chancer` | the upsell; never quite lying | **approved** |
| `believer` | the cause outranks you and the fee | **approved** |
| `paranoid` | someone is watching; precise about the wrong things | approved with a caveat (below) |

Sample output, all five on the same kill contract:

> **desperate** — "You're the only one left who can do this. I don't like asking, but I don't
> have a choice."
> **old_hand** — "Hostile ships on the lanes. They're not stupid, so don't assume they'll stay put."
> **chancer** — "Not much of a fight, really. Just clear them out and we'll all be happier.
> You've got the edge, so why not use it?"
> **believer** — "There's a ship out there that's cutting off supply lines to the ones who need
> it most."
> **paranoid** — "You need to take the job, but not the one they're expecting. I mean it. For real."

## The weirdo's boundary

Author: *"a bit misleading, but the mission card should clear most of that up."*

**His vagueness is only safe because the mission card carries the real facts.** So:

- he may be **vague** relative to the card, and may dwell on the wrong things — that's the joke
- he must never **contradict** it. Unclear is characterisation; wrong is a bug
- he is the wrong personality for any beat carrying information the player has no other source for

His signature is a code-picked **fixation**: one narrow thing that matters far too much, insisted
on by plain repetition, then straight back to the job. Author's two examples — *"For real, DON'T
show them. I'm serious"* and *"if he says he's sorry, tell him I'm sorry too. Then make him
dead"* — are the same move. Fixations are grouped `cargo` / `target` / `any` and drawn per
objective type, because a crate prohibition on a kill contract reads as a malfunction.

## Files

| File | Role |
| --- | --- |
| `agents.py` | the five personalities (who / axis / aim) + demo pools + `demos_for()` |
| `agent_offer.py` | the offer beat: briefing notes, fact selection, fixations, `compose()` |

## What made it work

1. **Packets must not sound like speech.** Phrased as dialogue, four of five personalities
   recited all three bullets in order with no voice. Flat notes (`job:` / `risk:` / `fee:`) fixed
   it.
2. **Code selects which facts each personality receives** (author's idea, better than my prompt
   rule). The model can't recite a note it never got. The chancer gets the fee and not the risk;
   the believer gets only the objective.
3. **Nearest-demo exclusion** — the paranoid agent reproduced a demo verbatim when both demo and
   request were pickups. Echoes 3/5 → 1/5.
4. **Authored text a character SPEAKS must be written the way they'd say it.** Fixations written
   third-person made her call herself "the agent".

## Next steps

1. **Decide how a personality is assigned to an agent.** Deterministic from the agent's seed
   (stable across saves, no storage) or stored on the agent record (survives generation changes).
   Deterministic-from-seed is probably right, but it's a save-format call.
2. **Wire it.** The quiet-moment plumbing is directly reusable — `QuietMomentChecks` for
   screening, the selector for recency. An agent offer needs `packet_echo` screening especially,
   since recitation is this beat's characteristic failure.
3. **Per-agent recency.** Agents live in their systems and are met repeatedly, so recency should
   key on the agent, not just the personality.
4. **Later beats.** Offers only for now. Accept / progress / failure are the natural additions,
   and failure is where an axis shows most (the desperate one panics, the old hand shrugs).

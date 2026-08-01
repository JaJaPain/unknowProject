# Quiet-Moment Beat Audit

Which existing game events can carry a character beat, and what verified facts each can hand
the generator. **Nothing here is built yet** — this is the menu to choose from.

The design constraint from all the research: a beat needs a **hook**, not just a trigger. A
packet that says "nothing is wrong" gives the model nothing to work with and it falls back on
the one salient fact every time. The `Hook quality` column is the honest estimate of whether
there's material there.

## What already exists (good news)

- **`ShipBehaviorObserver`** (`scripts/story/ShipBehaviorObserver.gd`) already emits *semantic*
  events with context and a 180s cooldown — `clean_long_transit`, `rough_arrival`,
  `returned_to_same_station`, `changed_mind_again`, `boost_again_quickly`,
  `rough_since_departure`. These are behavioural observations, which is exactly the shape a
  quiet moment wants.
- **Risk/pay tags are already derived** at `scripts/LLMInterface.gd:5282-5285`:
  `high_payout` (≥300), `lower_payout` (<150), `low_risk`, `known_tough`. That is Kaelen's whole
  axis, already computed.
- **`FixedCastAttachmentLedger`** already models earned relationship beats such as
  `known_tough_completion` — a natural trigger for N.O.V.A.'s bond material.
- `hull_fraction` is emitted with movement events (`PlayerShip.gd:3316`).

## Candidate beats

### Kaelen — her axis is risk priced against pay

| Beat | Trigger | Facts available | Hook quality | Notes |
| --- | --- | --- | --- | --- |
| **Low-pay completion** ✅ | `quest_completed_details` + `lower_payout` + `low_risk` | payout band, risk band, title, faction, public_board | **strong** | **Already built and at ~80%.** The reference implementation. |
| **High-pay dangerous completion** | `quest_completed_details` + `high_payout` + `known_tough` | same | **strong** | The mirror image, and her canon line already covers it: *"I get paid a whole lot more for you doing it."* Cheapest next beat — same axis, inverted valence. |
| **Public-board turn-in** | `quest_completed_details` + `public_board` | board template id, payout | **strong** | Where `public_board_money_rule` legitimately applies. Her thin broker fee is the hook. Gate the soul rule to exactly this. |
| **Mission declined** | `quest_declined_details` | title, payout that was on offer | medium | Costs nothing, earns nothing — her canon demo already covers this shape. |
| **Mission abandoned / expired** | `quest_abandoned_details`, `quest_expired_details` | title, what was forfeited | **strong** | Real cost, real material. Bible says state the cost without melodrama. |
| **Big credit swing** | `credits_changed` past a threshold | delta, new total | medium | Needs a threshold or it fires constantly. |
| **Reputation shift** | `reputation_changed` | faction, direction | medium | Risk: she must not invent faction politics. |

### N.O.V.A. — ship-as-body, playful, deniable innuendo

| Beat | Trigger | Facts available | Hook quality | Notes |
| --- | --- | --- | --- | --- |
| **Post-combat, damaged** ✅ | `combat_ended(true)` + `hull_fraction` below threshold | hull fraction, won/lost | **strong** | **Built and author-approved.** Damage is the hook. |
| **Post-combat, undamaged** | `combat_ended(true)` + high `hull_fraction` | as above | **weak** | Tested and failed — no hook, collapses into relief. Either skip, or find a different hook (ammo, heat, the enemy's behaviour). |
| **Long clean transit** ✅ | `clean_long_transit` (already emitted, with `transit_seconds`) | duration, system | **strong** | Author's own canon line is exactly this moment (dust my intakes). Tested; playful register appeared immediately. Fix the "silence" attractor first. |
| **Repair completed** | dock/repair completion | what was fixed | **strong** | Maintenance-innuendo register's home ground. Probably her single best beat. |
| **Rough arrival** | `rough_arrival` (already emitted) | roughness, station | **strong** | Ship-as-body complaint with a built-in hook. |
| **Boost again quickly** | `boost_again_quickly` | seconds since last boost | **strong** | *"You held me at redline"* — already a demo. |
| **Returned to same station** | `returned_to_same_station` | station name, count | medium | Gentle teasing; watch that she doesn't imply he's lost. |
| **Gate transit** | `system_changed` / gate events | gate id, system | **strong** | Her gate unease. **Sensitive** — ties to the amnesia arc and the scripted flashback; coordinate with that before generating freely here. |
| **Cold boot / campaign start** | `startup_load_completed` | new campaign or loaded | **strong** | The memory gap. Also **sensitive** — the opening cinematic is scripted with pre-rendered audio. |
| **Known-tough completion** | `FixedCastAttachmentLedger` `known_tough_completion` | earned beat | **strong** | Her caution paid off. Bond material with an earned trigger. |

## Recommended v1 set

Four beats, chosen so each tests something different rather than repeating the same shape:

1. **Kaelen — high-pay dangerous completion.** Same axis as the built one with valence inverted.
   Tests whether a settled voice transfers across valence for near-zero cost.
2. **Kaelen — public-board turn-in.** Tests the gated soul rule and gives the fee complaint a
   legitimate home.
3. **N.O.V.A. — repair completed.** Her strongest register on its most natural trigger.
4. **N.O.V.A. — long clean transit.** Already emitted with context; the author's canon line
   lives here. Needs the "silence" attractor fixed.

Deliberately **excluded from v1**: gate transit and cold boot. Both are strong beats, but both
collide with the scripted amnesia/flashback content in `docs/todo.md`. Generated lines there
risk contradicting authored story, and that is the one failure the player would actually notice.

## Open questions for the author

1. **Does a beat fire on a cooldown, a probability, or every time?** `ShipBehaviorObserver`
   already uses a 180s semantic cooldown — likely the right model, but quiet moments competing
   with lounge chatter and mission dialogue needs a policy.
2. **Who arbitrates when two characters both have something to say?** `PlayerInteractionQueue`
   exists and is probably the right owner.
3. **Should a beat ever fire during combat?** Recommend no — the fixed-cast bible already
   separates `combat` from `quiet_moment`.

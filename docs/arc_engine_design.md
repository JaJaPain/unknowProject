# Arc Engine Design

Implements plan Sections 3.1-3.2 and 4.1 on top of the premise-card deck.
Code lives in `scripts/story/premise/`. Everything here is pure data + static
functions, so it runs headless and is tested without the game.

## Pieces

| File | Job |
|---|---|
| `PremiseCardLibrary.gd` | Loads the approved deck. |
| `PremiseCardHistoryStore.gd` | Per-machine card history (`user://`). |
| `PremiseCardSelector.gd` | Which card fits this moment. |
| `SystemProfile.gd` | Quirks and states per system. |
| `ArcState.gd` | The campaign's story state as one saveable Dictionary. |
| `ArcEngine.gd` | Starts arcs, lists current offers, applies outcomes and choices, resolves. |
| `PremiseCasting.gd` | Fills card roles with world entities (next step). |
| `PremiseMissionComposer.gd` | Turns a card mission into an existing mission offer (next step). |

## ArcState (campaign save)

```
{
  version: 1,
  next_seq: int,                      # arc ids: "arc.0001", ...
  arcs: { arc_id: Arc },
  used_card_ids: [card_id],           # never repeat a card in one campaign
  system_changes: { system_id: {add: [state], remove: [state]} },
  system_laws: { system_id: {law: "enacted"|"repealed"} },
  price_effects: [ {system_id, good, ore, price, arc_id} ],
  standing: { entity_id: int },       # faction standing deltas from arcs
  fates: { entity_id: [fate] },       # person fates (recurring cast later)
  deeds: [ {tag, public_summary, system_id, arc_id} ],
  seeds: [ {tag, system_id, arc_id} ],# left by resolutions, consumed by new draws
  ledger: [ "shorthand line" ]        # Story Ledger (plan 3.7), code-written
}
Arc = {
  id, card_id, system_id, scale,
  status: "active" | "resolved",
  cast: { role_id: {entity_id, display_name, kind, ...} },
  beat: int,                          # current beat number
  stage: "missions" | "finding" | "choice" | "done",
  done: { "m<i>": outcome_tag },      # missions finished in the current beat
  finding_mission: int,               # mission awaiting a finding pick (stage "finding")
  resolution_id: "",
  started_minute: int, resolved_minute: int,
  shown: bool                         # history recorded (player saw the opening)
}
```

## Rules

**Offers.** In stage `missions`, every mission of the current beat that isn't
done is offered. With `missions_mode: one_of`, all are offered as competing
contracts; the first one finished settles the beat.

**Game outcome → card outcome tag.**
- Mission not completed (failed, abandoned, expired, declined): use a tag
  whose name signals failure (`abandon`, `fail`, `ignored`, `lost`, `escape`)
  if the mission has one; otherwise the arc falls to its `default_resolution`.
  Failing forward: nothing just disappears.
- `comms_reversal` completed: `accept_bribe` → the tag that names the offer
  (`offer`, `took`, `accept`, `bribe`, `deal`, `spare`, `stand`); `finish_kill` →
  the other tag.
- Any other mission with one tag: that tag.
- Any other mission with several tags (scans, findings): stage `finding`; the
  player picks one of the mission's tags (shown as a short decision).

**Routes.** A route to `resolution:X` or `beat:N` takes effect at once. A
`next` route waits until every mission of the beat is done (mode `all`), or
applies at once (mode `one_of`). When the beat is settled: a beat with a
`player_choice` moves to stage `choice`; otherwise the next beat starts.
A `next` from the last beat with no choice falls to the default resolution
(the validator forbids it, but the engine must not stall).

**Resolution.** Applies the card's consequences to the cast:
`standing` → faction entity; `cast_fate` → person entity; `deed` → deeds;
`system_state` → `system_changes` (read through `SystemProfile.apply_changes`);
`law_change` → `system_laws`; `economy` → `price_effects`; seeds → `seeds`.
Writes a ledger line. Status becomes `resolved`.

**Ignored arcs.** When an arc's time budget runs out without the player,
`resolve(default_resolution)`. The world moves on.

**History.** The first time any of an arc's offers is actually shown, the
caller records the card in `PremiseCardHistoryStore` and sets `shown`.

## Out of scope for this step

Casting, offer composition, saving into the campaign store, and live wiring
come in the next steps (see `docs/implementation_log.md`).

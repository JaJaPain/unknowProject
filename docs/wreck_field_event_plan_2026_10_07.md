# The wreck field event (plan, 2026-10-07)

Abe's go-ahead (2026-10-07) on the shape in
`docs/campaign_spine_plan_2026_10_05.md` section 10: once per campaign, the
player is led to the twin wreck field (ChatGPT's set piece, v3 batched),
scans it from the edge of a radiation zone, finds clues to what happened,
some of them real traces of the season's Hidden Hand, and something the
campaign needs.

## What already exists (reused)

- `LodestarGuide.gd`: the pattern for a set piece placed in a system, an
  arrival check, N.O.V.A. lines on timers, state in `story_state`.
- `ScanHoldController.gd`: the pure "hold close, slow, out of combat for
  3 s" timer investigations use.
- `HiddenHand.mark_arc_threads_seen`: makes an arc's threads seen (evidence
  for the reveal).
- `LodestarGuide.offer(source)`: hands out the next Destination bearing if
  one is waiting here.
- `DroneMazeActivity.kind_of`: anything in group `derelict_hull` with meta
  `dive_radius` is a drone-diveable wreck.
- `--wreck-snapshot`: pictures of the model in game.

## Version 1 (this build)

1. **The lead.** Once per campaign, on arrival in a new system at depth 2 or
   deeper, after 5 visits, while the main story is still hidden: N.O.V.A.
   picks up two dead transponders. The field is placed far out in that
   system and is on the overview. Skipped in campaigns whose Destination
   is the Quiet War (it uses the same wrecks). State:
   `story_state["wreck_field"]`.
2. **The field.** The model, with a radiation zone of about 1.5 km round
   its centre. Crossing in: N.O.V.A. warns once, hull damage ticks while
   inside. Fly to stops outside the zone. The hulls are a drone-dive wreck
   from the edge.
3. **Four scan points** round the zone's edge (bow, stern, deck modules,
   radiators). Hold close and slow for 3 seconds at each. Each gives a
   clue to what happened (battle, sabotage, collision or mutiny, matched to
   the Hidden Hand's method when it can) and the first two also turn up a
   real trace of the Hidden Hand (threads marked seen).
4. **The reward.** The last scan carries a Destination bearing if one is
   waiting, otherwise salvage credits; the drone dive is there for loot.
5. **Lines.** N.O.V.A.'s lines and the clue texts are drafts until Abe
   approves them, in small batches.

## Later (not in v1)

- Scavengers working the field (risk).
- A shielded ship (radiation belt keystone) reaching inner scan points.
- Debris tumble shader.

## Status

- [x] 1-4 built (2026-10-07): `WreckFieldEvent.gd`, `WreckField.gd`,
  `WreckScanPoint.gd`, `PremiseDirector.wreck_field_clue`; tests
  `run_wreck_field_tests.gd`, director clue test, `--wreck-event-smoke-test`
  (zone 1.55 km, a faint green rim marks it)
- [ ] Lines approved by Abe

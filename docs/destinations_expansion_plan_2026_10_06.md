# Six new Destinations (plan, 2026-10-06)

Abe: double the Destinations, from 6 to 12. The season sim at 225 cards
showed stories barely repeat any more (1% shared at 10 h); the Destination
is now the biggest repeat a returning player meets. A new campaign's first
Destination already avoids the player's recent ones (`Lodestar.draw_for_new_campaign`);
twelve makes that rotation last twice as long, and gives the Hidden Hand
twice as many places to aim at.

## What one Destination is

1. **A card** in `data/content/lodestars.json`: title, the rumour
   (`first_hint`), N.O.V.A.'s first reaction (`nova_first`), a director note,
   **five bearings** (each a clue line plus a N.O.V.A. line), the arrival
   summary, and the **arrival scene** (the place's speaker, approach line,
   three lines, N.O.V.A.'s reaction, a farewell that points at the next
   horizon). About 20 player-facing lines per Destination, all hand-written,
   reviewed by Abe in short batches.
2. **Four bridges** in `data/content/lodestar_bridges.json`: one sentence per
   Hidden Hand goal this place can host, saying why the culprit wants this
   place. The season's goal is drawn from these.
3. **A set piece** from ChatGPT (brief in `docs/set_piece_wishlist.md`, one per
   window, same export rules: batched, under ~50 meshes and ~8 materials,
   emissives separate, no text).
4. **A landmark kind** in `scripts/story/LodestarLandmark.gd` (`MODELS`, plus
   any small life: a turning part, a pulse, a blink), and its target icon
   (the Destination star, already in the set).

Tests then go from six to twelve (`run_lodestar_tests`, `run_lodestar_arrival_tests`),
and the season sim is re-run.

## The six concepts (for Abe's pick)

Each is a different *kind* of place from the existing six (a beacon, a hidden
fleet, an ancient gate, a secret mine, a garden, a war vault), and leans on
the Hidden Hand goals the current six host least: escape a debt, take the
chair and buy a station (1 each today); own the lanes, keep the lights on,
rewrite a verdict, prove them wrong (2 each).

| # | Destination | What it is | Hosts goals | Set piece |
|---|---|---|---|---|
| 1 | **The Archive** | A record-keepers' station drifting in a gas giant's upper clouds. For generations they have copied every registry, deed and court ruling filed in the region, including the ones that were "lost". | rewrite a verdict, bury an old crime, prove them wrong, take the chair | Tiered cylindrical stacks hanging beneath float bladders, lit reading windows; the giant below is our gas-giant shader |
| 2 | **The Hollow Market** | An ungoverned bazaar dug into the core of a comet, outside every jurisdiction. Anything is for sale; nothing is asked. | escape a debt, own the lanes, buy a station, break a rival | A long icy comet hull bored with ship-sized holes, docking rings and hanging lanterns; the tail from our comet shaders |
| 3 | **The Last Shipyard** | A drydock where one family of shipwrights has spent four generations building a single enormous ship from their great-grandmother's plans. It still isn't finished. | take the chair, prove them wrong, keep the lights on, protect a secret child | An open scaffold cradle around a half-plated giant hull, cranes, sparks (emissive), living modules on the scaffold |
| 4 | **The Halo** | A ring of small pilgrim chapels strung on cables around a dying red star. Anyone may claim sanctuary there, and no weapon may be fired. | protect a secret child, escape a debt, rewrite a verdict, keep the lights on | A loose chain of lantern-lit chapel pods on long tethers (not a solid ring, unlike the Humming Gate), around the star |
| 5 | **The Wellhead** | The ice-moon geyser that waters the whole frontier, run by one dynasty. Every water contract in the region is signed there. | own the lanes, buy a station, keep the lights on, start a war | Tall rig towers over a frozen moon's geyser plume, pipes and tanker berths (the moon is our planet shader) |
| 6 | **The Neutral Ground** | The decommissioned treaty station where old enemies signed the peace. Still the only place the factions meet unarmed. | start a war, take the chair, rewrite a verdict, break a rival | A symmetrical station: two different halves (each side built its own) meeting at one central hall |

Alternate if one doesn't land: **The Listening Post**, an astronomers' dish
array that has been recording one unexplained signal for decades (could
share a look with the signal anomaly set piece).

None of these touch the fixed-cast secret: no thinking machines, no
returning dead, nothing about the Captain.

## Reusing set pieces (Abe's idea, same day)

Every model arrived as separate parts, so the game can hide parts, re-tint
materials, rescale and add surroundings (a planet, a comet tail, particle
plumes) to make one model read as another place. A per-Destination
**variant** setting in `LodestarLandmark` (hide these nodes, tint these
materials, scale, extra effects) makes reuse pure data. Reuse works best with
generic pieces or big changes; a returning player may recognise a distinctive
silhouette.

- **The Last Shipyard: reuse the lone derelict hull,** clean and ~3x scale,
  with its torn side reading as unfinished plating, inside a code-built
  scaffold with cranes and welding-spark emissives. Convincing.
- **The Hollow Market: reuse the Cartographer mine's asteroid** with the mine
  structures hidden, an ice tint, the comet tail shader, and lantern lights at
  the pit and bores. Convincing.
- **The Neutral Ground:** the Quiet War vault, re-tinted clean and pale, is
  possible but reads as a bunker. Prefer new art.
- **The Archive:** the Garden station re-lit as reading windows over a gas
  giant is too recognisable. New art.
- **The Halo, The Wellhead:** nothing fits. New art.

So: two reuses, four new set pieces (four ChatGPT windows instead of six).

## Build order

1. **Abe picks** (all six, or swaps in the alternate).
2. **Cards, two at a time:** I write two Destinations' cards and bridges
   (~40 lines plus 8 bridge sentences); Abe reviews; repeat three times.
   They go live with the primitive stand-in landmark, so they're playable
   before the art.
3. **Set pieces, one per ChatGPT window**, in the same order. Each brief
   goes into `docs/set_piece_wishlist.md` when the previous one lands; I
   check each in the engine, then wire it in.
4. **Tests and the season sim** after each pair, so nothing breaks midway.

Cost: about three review rounds of lines for Abe, and six ChatGPT windows
for the art.

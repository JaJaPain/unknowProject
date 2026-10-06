# Set piece wishlist (for ChatGPT, one per 5-hour window)

Abe, 2026-10-05: ChatGPT can make one large set piece per window. Ranked by
how much each moves the game. Rules for every piece (from the twin wreck
field): original design, no text or logos, metres, **batched** (one mesh per
material per section, small debris merged by material; aim under ~50 meshes and
~8 materials), centred pivots on large sections, no lights or cameras in the
export, a short README with size and counts. Glowing parts as separate emissive
materials so the game can light them.

| # | Piece | Why | Used for |
|---|---|---|---|
| 1 | **The Humming Gate** | Lodestar climax; today a torus | A perfect ancient gate ring, still humming, two factions circling |
| 2 | **The Lighthouse** | Lodestar climax; today a cylinder and a ball | An ancient beacon station kept alive by a salvage clan |
| 3 | **The Silent Fleet's settlement** | Lodestar climax | A hidden colony made of old convoy ships lashed together |
| 4 | **The Cartographer's secret mine** | Lodestar climax | A covert mining rig dug into a big asteroid, in an erased system |
| 5 | **The Garden keepers' station** | Lodestar climax (the green world is a planet shader) | A small botanists' habitat in orbit, greenhouses and solar wings |
| 6 | **The Quiet War cache vault** | Lodestar climax (the battlefield is the twin wreck field) | An armoured pre-decline vault the wrecks died guarding |
| 7 | **A lone derelict ship** (mid-size, ~300 m) | Reused many times: rumour-spawned finds, story wrecks | A dead ship with an open hull to scan and send drones into |
| 8 | **A signal anomaly site** | Investigations, data cores | A strange object or structure emitting the signal |

## Brief #1: The Humming Gate

A jump-gate ring from before the network's decline, the only one still working
perfectly. Every other gate in the game is worn and patched; this one is
whole, clean and quietly powerful.

- **Size:** ring about 1.2 km across (larger than ordinary gates), with its
  supports.
- **Shape:** a thick main ring built from many precise segments, with a
  second, thinner inner ring set slightly off its plane; a few long struts or
  pylons reaching outward like a crown. Symmetrical and deliberate: it should
  read as *engineered by people who knew more than anyone alive now*.
- **Surface:** pale, smooth, unweathered alloy; fine panel seams; no rust, no
  patches, no damage (the opposite of the twin wreck field).
- **Light:** a soft glowing band around the inner ring and small points along
  the segments, as separate emissive materials (the game adds the hum and the
  colour).
- **Optional:** a few small maintenance drones docked on the ring (separate
  meshes, so the game can animate them).
- **No:** writing, symbols, faction marks, other ships.
- **Export:** batched as above; the inner ring as its own mesh (the game may
  rotate it slowly).

**#1 status (2026-10-05):** delivered and approved. `assets/landmarks/humming_gate.glb`:
13 meshes, 6 materials, inner halo on its own pivot; 34-66 draw calls in game.

## Brief #2: The Lighthouse

A navigation beacon station older than the current gate charts. For
generations a salvage clan has kept it alive, trading its memory of forgotten
routes for supplies. It still broadcasts course corrections for gates that
aren't on any chart.

- **Size:** about 900 m tall overall; a destination, readable from far away.
- **Shape:** one tall, slender, elegant original tower (the old beacon),
  clearly older and finer-made than anything else in the game, with a large
  lamp/emitter housing at the top. Wrapped around its lower two-thirds: the
  clan's additions, built over generations from salvage: mismatched habitat
  modules, cargo containers welded into rooms, catwalks, patched solar wings,
  a few docked small craft hulls turned into homes. Old elegance below,
  generations of patchwork wrapped around it.
- **Surface:** the original tower in weathered pale stone-like alloy; the
  clan's parts in mixed, faded colours, rust, patch plates, mismatched panels.
- **Light:** the beacon at the top as a separate emissive material (the game
  makes it pulse); warm window lights scattered through the clan's modules
  (separate emissive material); a few small blinking navigation lights.
- **Optional:** a slowly rotating emitter ring at the top (own pivot).
- **No:** writing, symbols, faction marks, ships flying.
- **Export:** batched (tower, clan additions, lights as few meshes per
  material); the emitter ring on its own pivot.

**#2 status (2026-10-05):** delivered and approved. `assets/landmarks/lighthouse.glb`:
18 meshes, 8 materials, emitter ring on its own pivot; 38-68 draw calls in game.

## Brief #3: The Silent Fleet's settlement

A colony convoy that jumped beyond the charts long ago to escape a war, and
switched off every transponder so nobody could follow. Their descendants live
here still, in the ships that brought them, and want to stay hidden.

- **Size:** about 2 km across.
- **Shape:** six to ten old convoy ships of different sizes and designs
  (colony transports, freighters, a tanker), parked together and **lashed
  into one settlement**: connecting tubes and bridges between hulls, cables,
  shared radiator fields, a central hub built later where they meet. Engines
  cold and long unused; it should read as *a town made of ships that will
  never fly again*.
- **Surface:** old, cared-for hulls, repaired rather than rusting; faded
  original paint; patches where hull plates were taken to build the hub. Dark
  and low-key overall: they're hiding.
- **Light:** dim, warm window lights (separate emissive material), much less
  than a normal station; a few small greenhouse modules with soft green light
  (separate emissive material). No beacons, no navigation lights: they don't
  want to be seen.
- **Optional:** a couple of tiny shuttles docked (separate meshes).
- **No:** writing, symbols, faction marks, weapons, damage from battle.
- **Export:** batched (each ship hull, the connectors, the hub, lights as few
  meshes per material).

**#3 status (2026-10-05):** delivered and approved. `assets/landmarks/silent_fleet.glb`:
32 meshes, 7 materials; 51-64 draw calls in game. Note for a possible later
revision: the layout is a neat hub-and-spoke wheel (ships evenly spaced on long
straight bridges), which reads more like a designed station than ships lashed
together over generations; pulling the ships in close, at irregular angles,
hull to hull with short improvised tubes, would land the brief's feel.


## Brief #4: The Cartographer's secret mine

A famous surveyor found a system rich in rare ore, and a powerful consortium
erased it from the registry to mine it in secret. This is their mine: a big,
efficient, hidden industrial operation that officially doesn't exist.

- **Size:** a large asteroid about 1.5 km across, with the operation built
  into and around it.
- **Shape:** an irregular, heavy, cratered asteroid (not a smooth ball) with a
  deep **open-cut pit** carved into one face, terraced in steps. Built into
  and onto it: a refinery block, ore conveyors or rail lines running out of
  the pit, a few loading cranes, storage silos/tanks, a small crew habitat
  sunk half into the rock (out of sight on purpose), and a docking arm with
  two or three moored ore haulers (static). Industrial, functional, corporate;
  everything built for output, nothing for show.
- **Surface:** dark grey-brown rock with lighter freshly cut faces in the pit
  and a faint mineral glint; the structures in clean, uniform corporate
  plating (the opposite of the Lighthouse's patchwork), with dust and wear
  where the work happens.
- **Light:** work floodlights in the pit and along the conveyors (separate
  emissive material, cold white); a few amber windows in the habitat
  (separate emissive material). Kept low: they're hiding too.
- **Optional:** a conveyor belt or ore carts as their own mesh (the game may
  move them).
- **No:** writing, logos, symbols, faction marks, ships flying, weapons.
- **Export:** batched (the asteroid, the pit structures, the refinery, the
  cranes, the haulers, lights as few meshes per material).

**#4 status (2026-10-05):** delivered and approved. `assets/landmarks/cartographer_mine.glb`:
29 meshes, 8 materials, ~39k triangles; conveyor belt on its own mesh with UVs
for a scrolling shader; 48-71 draw calls in game (19 without it).

## Brief #5: The Garden keepers' station

A small habitat in orbit over a green world, kept by a line of botanists who
have tended its seed vaults for generations. They aren't hiding and they
aren't rich: they're careful. The planet itself is the game's planet shader;
this is only the station above it.

- **Size:** small for a destination, about 600 m across. It should feel
  intimate next to the planet, not compete with it.
- **Shape:** a central spine or hub with long **greenhouse modules** branching
  off it: glass-roofed cylinders or ribbed domes, some long, some short,
  added over time but in a consistent, tidy style. A pair of broad **solar
  wings** (or a slowly turning ring of panels) on one end; a seed vault, a
  heavy, closed, armoured block at the core, clearly the most protected part;
  a small docking ring with room for one or two ships; water and nutrient
  tanks; a few hanging cargo nets or pods of supplies.
- **Surface:** soft, light hull colours (off-white, pale sage, warm grey),
  well-kept and clean, small repairs neatly done; glass panes on the
  greenhouses (a slightly tinted glass material). Cared-for, gentle,
  lived-in: the opposite of the mine.
- **Light:** soft green growing light inside the greenhouses (separate
  emissive material, visible through the glass); a few warm window lights in
  the living modules (separate emissive material); small navigation lights
  on the docking ring (they want visitors to find them).
- **Optional:** the solar wings or panel ring on their own pivot (the game
  may turn them to track the sun); a couple of small tending drones
  (separate meshes).
- **No:** writing, logos, symbols, faction marks, weapons, ships flying,
  plants modelled leaf by leaf (a few simple plant-mass shapes inside the
  glass are enough).
- **Export:** batched (the hub and vault, the greenhouses, the glass, the
  wings, the lights as few meshes per material); glass as its own material.

# Set piece wishlist (for ChatGPT, one per 5-hour window)

Abe, 2026-10-05: ChatGPT can make one large set piece per window. Ranked by
how much each moves the game. Rules for every piece (from the twin wreck
field): original design, no text or logos, metres, **batched** (one mesh per
material per section, small debris merged by material; aim under ~50 meshes and
~8 materials), centred pivots on large sections, no lights or cameras in the
export, a short README with size and counts. Glowing parts as separate emissive
materials so the game can light them.

**Index (2026-10-07).** One row per request; the full brief for each is
below, in order. Hand ChatGPT the first row that isn't done.

| # | Piece | Used for | Status |
|---|---|---|---|
| 1 | **The Humming Gate** | Destination | Done |
| 2 | **The Lighthouse** | Destination | Done |
| 3 | **The Silent Fleet's settlement** | Destination | Done |
| 4 | **The Cartographer's secret mine** | Destination; also reused as the Hollow Market | Done |
| 5 | **The Garden keepers' station** | Destination | Done |
| 6 | **The Quiet War cache vault** | Destination | Done |
| 7 | **A lone derelict ship** (+ 7b detail revision) | Distress-beacon finds (drone-diveable), Competing Claims / Unstable Archive investigation sites; also reused as the Last Shipyard | Done, in play |
| 8 | **A signal anomaly site** | Transmitter Lure investigation sites (seams pulse, centre glow swells) | Done, in play |
| 9 | **The Archive** | New Destination | Done: the game uses ChatGPT's textured 9b as `archive_v2_game.glb` (2048 maps, 29 MB, made with `tools/art/shrink_glb_textures.py`); the 100 MB original is in `art/archive_v2/` (Godot-ignored). The surface detail pass is off for it |
| 10 | **The Neutral Ground** | New Destination (`neutral_ground.glb`) | Reviewed and in game (21 draw calls); game-side: gold light lifted above the hall, windows dimmed, hulls matte |
| 11 | **The Halo** | New Destination (`halo.glb`) | Reviewed and in game (47 draw calls); game-side: candle flicker, bell sways on its pivot |
| 12 | **The Wellhead** | New Destination (`wellhead.glb`) | Reviewed and in game (36 draw calls); game-side: plume rises from `VentEmitter`, beacons blink, frosted-ice surface detail, matte metal |

New Destinations 9-12 already run in the game on stand-in shapes; each
model replaces its stand-in automatically when saved under
`assets/landmarks/` with the file name above.

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

**#5 status (2026-10-05):** delivered and approved. `assets/landmarks/garden_keepers.glb`:
17 meshes, 8 materials, ~37k triangles; both solar wings on their own pivots
(`SolarPort_Pivot`, `SolarStarboard_Pivot`); glass as one alpha-blended
material; 37 draw calls in game (19 without it). Check the glass sorting once
it's placed over its planet.

## Brief #6: The Quiet War cache vault

Before the network's decline, two powers fought a war nobody remembers the
reason for. One side sealed something in an armoured vault and fleets died
guarding it; the twin wreck field is what's left of them. The vault is still
there, intact and shut, in the middle of the dead ships.

- **Size:** about 500 m across; dense and heavy, not tall. It should feel
  like the one thing in the battlefield that nothing could break.
- **Shape:** a squat, faceted armoured core (think a sealed bunker or a
  closed seed of metal, not a station), wrapped in thick overlapping armour
  plates and buttress ribs. One great sealed door or hatch on one face,
  clearly the only way in, closed. Around it, a ring of dead defence
  platforms or turret mounts (inert, barrels drooping or broken off), and
  anchor arms reaching out into nothing. Old, military, overbuilt: built
  to outlast everyone.
- **Surface:** dark gunmetal and dull bronze armour, scorched and pitted from
  weapon fire, deep gouges and craters that never got through; the
  platforms around it far more damaged than the core. No rust patches or
  repairs: nobody has touched it since.
- **Light:** almost none. A few faint, slow status lights still alive on the
  core (separate emissive material, dim red or amber), and a thin seam of
  light around the sealed door (separate emissive material; the game may
  pulse it or open it later).
- **Optional:** the door as its own mesh with its pivot at the hinge or
  centre (the game may open it in a later story); a few loose armour plates
  drifting nearby (separate meshes).
- **No:** writing, symbols, faction marks, flags, ships, bodies, working
  weapons.
- **Export:** batched (the core, the armour, the platforms, the debris, the
  lights as few meshes per material); the door separate.

**#6 status (2026-10-05):** delivered and approved. `assets/landmarks/quiet_war_vault.glb`:
13 meshes, 6 materials, ~10k triangles; the door on `VaultDoor_Pivot` (opens
outward along local +Z), three loose plates for drift; 34-40 draw calls in
game (19 without it).

## Brief #7: A lone derelict ship

A mid-size working ship (a hauler or survey vessel) found dead and drifting.
Unlike the set pieces above, this one is **reused many times**: rumour-spawned
finds, story wrecks, drone dives. So it should be a believable ordinary ship,
not a landmark, and it must look right with different tints and in different
places.

- **Size:** about 300 m long.
- **Shape:** a plain, practical ship: a long spine, a cargo or survey
  section in the middle, a cockpit/bridge block at the front, engines at the
  back. One side is **torn open**: a big breach running into the hull, with
  decks, bulkheads and corridors visible inside, deep enough that a small
  drone could fly in and look around (the game sends drones in). The rest is
  dented but whole.
- **Surface:** neutral, faded hull (mid grey with one muted accent colour),
  scorch marks around the breach, frost or dust on the dark side. Nothing
  that dates it to one faction or one story.
- **Light:** dead by default. A few emergency lights still flickering deep
  inside the breach (separate emissive material; the game may turn them off
  or make them blink), and one beacon light on the hull (separate emissive
  material) the game can use as "still transmitting".
- **Optional:** the engine section slightly twisted or cracked loose; a
  couple of cargo containers drifting out of the breach (separate meshes).
- **No:** writing, registration numbers, logos, faction marks, bodies,
  weapons firing.
- **Export:** batched (the hull, the interior seen through the breach, the
  debris, the lights as few meshes per material); keep it light, since
  several may be on screen over a campaign: aim under ~30 meshes and ~20k
  triangles. Hull colour as a material the game can tint (or vertex colours
  plus one tintable accent material).

**#7 status (2026-10-05):** delivered and usable. `assets/landmarks/lone_derelict.glb`:
13 meshes, 7 materials, only ~3.8k triangles; breach facing +Z with a clear
95 m passage; hull and accent tintable; two drifting containers; 34-40 draw
calls in game (19 without it). Note for a possible later revision: it reads
quite plain and boxy up close (a slab hull and a cube bridge). There's lots
of budget left (3.8k of 20k triangles) for hull detail: plating breaks,
antennas, tanks, ribbing, a more shaped bow.

## Brief #8: A signal anomaly site

Investigations and data cores lead to places where something is
broadcasting that shouldn't be. This is the thing at the end: old, strange,
not obviously made by anyone the player knows. Reused across several
stories, so it should be mysterious without telling one specific story.

- **Size:** about 150 m, small enough to fly right up to.
- **Shape:** an object that doesn't match anything else in the game: for
  example a cluster of tall, thin, dark monoliths or shards arranged in a
  rough ring around an empty centre, slightly tilted, as if grown rather
  than built; or a single smooth, faceted shape with deep grooves. Clean
  geometry, very few details, unsettling proportions. Nothing that reads as
  a ship, a station or a machine with obvious parts.
- **Surface:** very dark, almost black, slightly glossy material with faint
  fine lines etched across it (geometry or a pattern in the material, not
  writing or symbols); a little dust settled in the grooves.
- **Light:** a thin, cold light running in the grooves or along the shard
  edges (separate emissive material; the game will pulse it in time with
  the signal); a faint glow in the empty centre (separate emissive
  material, or a small separate mesh the game can scale or fade).
- **Optional:** two or three small shards floating loose around it
  (separate meshes, centred pivots; the game may rotate them slowly).
- **No:** writing, symbols, glyphs, alien faces or creatures, faction marks,
  ships.
- **Export:** batched; light: under ~20 meshes and ~15k triangles.

## Brief #7b: Lone derelict, detail revision

Revise `assets/landmarks/lone_derelict.glb` (rebuild with
`tools/art/build_lone_derelict.py`); keep everything that works and add
detail. Keep: the size (~300 m), the breach on the +Z side and its clear
95 m passage (re-run the clearance check), the two tintable hull materials,
the two drifting containers, the two emissive materials, the pivots and the
file names. Up close it currently reads as a slab hull with a cube bridge.

- **Hull shape:** break up the long flat sides and top: stepped sections,
  chamfers, a raised dorsal spine, plating seams and panel breaks at
  different depths. The bow shaped and tapered, not a wedge on a box.
- **Bridge:** a proper bridge block integrated into the hull (sloped
  front, a window band, a sensor mast or dish on top) instead of a cube.
- **Hull fittings:** radiator fins, a few tanks or pressure spheres along
  the spine, antenna masts, docking clamps, thruster quads, ribbing around
  the cargo section, maintenance hatches and handrails.
- **Engines:** more shaped nozzles with inner rings and a housing; one
  can be cracked or sheared off.
- **Damage:** a few smaller dents, scorch streaks and missing plates
  elsewhere on the hull (not only the breach); torn plates curling out at
  the breach edges; a few cables and pipes hanging loose in the breach.
- **Interior through the breach:** more readable decks: stairs or ladders,
  pipe runs along the ceilings, a few fixed crates or racks, door frames
  between compartments. Keep the passage clear for drones.
- **Budget:** up to ~15k triangles and under ~30 meshes / ~8 materials;
  still batched by material.
- **No:** writing, registration numbers, logos, faction marks, bodies.

**#7b status (2026-10-06):** delivered and approved. Same file, names, pivots,
tint and emissive materials; now ~9.6k triangles with a stepped spine,
sloped bridge with window band and dish, tanks, radiators, antennas, shaped
engine bells, more damage and a readable interior; the 95 m drone passage
still clear. 34-68 draw calls in game (19 without it).

**#8 status (2026-10-06):** delivered and usable. `assets/landmarks/signal_anomaly.glb`:
7 meshes, 4 materials, only ~1.3k triangles; seven dark leaning shards round
an empty centre, `SA Cold seam emission` seams for the game to pulse with the
signal, `CentreGlow` as its own mesh to scale or fade, three loose shards for
drift; 27-47 draw calls in game (19 without it). Very spare: in game it reads
as black silhouettes with thin cyan lines. When it's wired to investigations,
the game should pulse the seams brightly and grow the centre glow so it
reads from a distance.

## Brief #9: The Archive (new Destination)

An order of record-keepers lives on a station that drifts in the upper clouds
of a gas giant. For generations they have copied every deed, registry and
court ruling in the region, including the ones that were destroyed. Quiet,
scholarly, old, cared for. The gas giant itself is the game's planet shader,
below the station; this is only the station.

- **Size:** about 600 m across, taller than wide.
- **Shape:** a cluster of **tall stack cylinders** (the archive towers: many
  storeys, narrow, like shelved libraries turned on end) **hanging beneath a
  few large float bladders** or lift envelopes that hold them up in the
  clouds. A central spine joins the stacks; walkways and enclosed bridges link
  them; a small docking ring at the bottom. It should read as *a library
  hanging from balloons*.
- **Surface:** warm pale stone-like hull on the stacks, darker bronze framing,
  bladders in a soft matt fabric-like material, weathered but cared for.
- **Light:** rows of small warm **reading-window lights** up every stack
  (separate emissive material); a few soft lamps along the walkways (separate
  emissive material); a dim red navigation light or two on the bladders.
- **Optional:** the bladders as their own meshes (the game may sway them very
  slowly).
- **No:** writing, symbols, books or pages drawn on the outside, faction
  marks, weapons, ships flying.
- **Export:** batched (stacks, frames, bladders, walkways, lights as few
  meshes per material); under ~50 meshes and ~8 materials; no lights or
  cameras; README with size and counts.

**#9 status (2026-10-07):** delivered for review. `assets/landmarks/archive.glb`:
23 meshes/surfaces, 7 materials, 87,144 triangles; approximately 601 m wide,
422 m deep and 792 m tall. Seven illuminated library stacks under three fabric
envelopes with independent centred pivots, enclosed bridges and a lower docking
ring. Reading windows, walkway lamps and dim red navigation use separate
emissive materials. GLB and Godot import checks pass; no cameras or lights in
the export. Source, renders, counts and notes in `art/archive/`.

**#9 V2 (2026-10-07):** separate textured edition at
`assets/landmarks/archive_v2.glb`, with source and close-up renders in
`art/archive_v2/`. Seven PBR material sets, 24 embedded texture maps (4K main
surfaces), preserved vertex positions/connectivity and transforms; 105 inward
cloth/belt faces reoriented for correct shading. Same 23 meshes and 87,144
triangles. V1 is preserved and remains the game's current lookup.

## Brief #10: The Neutral Ground (new Destination, after #9)

The decommissioned treaty station where old enemies signed the peace that
ended the last war. Each side built its own half in its own style; the two
halves meet at one central hall. It is still the only place the factions
meet unarmed.

- **Size:** about 800 m across.
- **Shape:** **two clearly different halves** joined in the middle by a
  **round or domed central hall**: one half angular, plated and blocky; the
  other curved, ribbed and smooth. Each half has its own docking arm on the
  far end. Symmetrical in layout, mismatched in style: *two stations built
  from both ends that met in the middle*.
- **Surface:** each half in its own palette (for example cool grey plates
  and warm sand-coloured curves), both old and well kept; the central hall in
  a third neutral material, slightly grander than either half.
- **Light:** a ring of warm windows around the central hall (separate
  emissive material); each half's windows in its own colour temperature
  (separate emissive materials); small docking lights at both arms.
- **No:** writing, flags, symbols, faction marks, weapons of any kind
  (that's the point of the place), ships flying.
- **Export:** batched as above; the central hall as its own mesh group.

**#10 status (2026-10-07):** delivered for review as
`assets/landmarks/neutral_ground.glb`, with Blender source and two preview renders
in `art/neutral_ground/`. 801.2 m across; 10 meshes, 8 materials, 23,412
triangles. Central hall is an independent group; four separate emissive
materials cover hall windows, both wing window palettes, and docking guides.
GLB structure and isolated Godot import checks passed; gameplay review remains.

## Brief #11: The Halo (new Destination, after #10)

A sanctuary of pilgrim chapels in a system whose red star is dying. By an old
covenant, anyone who rings its bell can't be taken away against their will.
Quiet, devotional, candle-lit, humble. The star is the game's; this is only
the chapels.

- **Size:** about 800 m across.
- **Shape:** a **loose circle of 12-20 small chapel pods** (each a different
  little shape: domes, lanterns, tiny spires; modest, hand-built) **on long
  tethers** running to a **central bell-buoy**: a small structure holding one
  large bell. Not a solid ring (the Humming Gate is a ring); a tethered
  constellation, slightly irregular, some pods closer, some further.
- **Surface:** pale weathered metal and warm stone-like plating, patched and
  cared for; the bell in dark bronze.
- **Light:** **candle light** in every pod's windows (warm, flickery-looking,
  separate emissive material); a soft glow at the bell (separate emissive
  material). Gentle, not bright.
- **Optional:** the bell as its own mesh with its pivot at the top (the game
  may swing it slowly); the pods as separate meshes so they can drift a
  little on their tethers.
- **No:** writing, symbols, holy signs or icons, faction marks, weapons,
  ships flying.
- **Export:** batched (pods, tethers, buoy, bell, lights as few meshes per
  material); under ~50 meshes and ~8 materials.

**#11 status (2026-10-07):** delivered for review as `assets/landmarks/halo.glb`,
with Blender source and overview/bell-detail renders in `art/halo/`. Sixteen
chapel pods on paired tethers, approximately 780 m across; 36 meshes/surfaces,
6 materials, 26,376 triangles. Separate candle and bell emission, pod parents,
and a bell pivot at its top. GLB and isolated Godot import checks passed;
gameplay review remains.

## Brief #12: The Wellhead (new Destination, after #11)

A small ice moonlet whose vent geyser waters the whole frontier. One family
runs the rig towers over the vent. Practical, old, industrial but kept with
pride.

- **Size:** the moonlet about 1 km across; rigs on top; ~1-1.5 km overall.
- **Shape:** an **irregular icy moonlet** (lumpy, cracked, pale blue-white,
  not a smooth sphere) with a **vent crater** on one side. Over the vent: a
  cluster of **tall rig towers**, a capping structure, thick pipes running
  across the ice to **tanker berths** with two or three moored water
  tankers (static), and a small family habitat block. The game adds the
  vapour plume rising from the vent (particles), so leave the vent open.
- **Surface:** frosted ice with darker cracks; the rigs in sturdy painted
  metal (one muted colour, faded), frost on the lower parts.
- **Light:** work lights along the towers and pipes (separate emissive
  material, cool white); warm windows in the habitat (separate emissive
  material); red beacon lights on the tower tops.
- **No:** writing, logos, symbols, faction marks, weapons, ships flying.
- **Export:** batched (moonlet, rigs, pipes, tankers, habitat, lights as few
  meshes per material); under ~50 meshes and ~8 materials; the vent position
  noted in the README.

**#12 status (2026-10-07):** delivered for review as
`assets/landmarks/wellhead.glb`, with Blender source and overview/works-detail
renders in `art/wellhead/`. Approximately 1.28 km tall; 24 meshes/surfaces,
8 materials, 27,472 triangles. Three moored tankers, separate work/window/beacon
emission, and an open vent marked by `VentEmitter` at Godot `(0, 447, 0)` m.
GLB structure, isolated Godot import, and sampled plume-clearance checks passed;
gameplay review remains.

## Game-side surface detail (2026-10-08)

`SurfaceDetail.gd` lays generated, seamless detail (tone, bump, uneven shine;
no texture files) over flat materials: presets stone, metal, paint, rock,
fabric and ice. On: the Lighthouse, Silent Fleet, Cartographer's Mine and
Hollow Market (rock), Garden Keepers, Quiet War vault, Neutral Ground, Halo,
Wellhead (ice) and the derelict in ordinary play. Left clean on purpose: the
Humming Gate (pristine by brief), the Last Shipyard (a new hull), the twin
wreck field, the signal anomaly. Mapping in `LodestarLandmark.SURFACE_DETAIL`;
`--no-surface-detail` for before/after shots.


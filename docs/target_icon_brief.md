# Target icons: brief for ChatGPT

The target panel (top centre of the HUD, next to the target's name) shows a
40 px icon for whatever the player has selected. Today it uses an old
8-icon placeholder sheet (`assets/icons.png`), so a **station shows a sun**,
**gates and planets show the same blue planet**, and **wrecks and anomalies
show a ringed planet**. Players can't tell what they've targeted.

We need one clear icon per kind of thing the player can target.

## Style

- **Flat white silhouettes with a little inner line detail**, on a fully
  transparent background. The game tints them (hostile red, friendly green,
  Destination gold, dim grey for unknown), so the art itself is white
  (#FFFFFF) with darker inner lines or cut-outs at most. No colour, no
  gradients, no glow, no drop shadows.
- They must read at **40 x 40 px**: bold simple shapes, one idea per icon,
  thick enough strokes that nothing vanishes when shrunk. Check each one
  scaled down to 40 px before handing it over.
- Consistent family: same stroke weight, same level of detail, same visual
  size (the shape fills about 80% of the square, centred).
- Original designs, nothing from other games. **No text, letters, numbers
  or symbols** anywhere.
- 3/4 or side views where a shape needs it (ships, stations); planets and
  stars face-on.

## Deliverables

> **For future orders (Abe, 2026-10-06):** small graphics like these come as
> ONE image with all of them in a grid (16 icons = one 4 x 4 sheet, even
> cells, same background, nothing crossing cell borders), not one image per
> icon; it costs about 1/16 of the compute. This order was already under way
> as separate files, so it stays as written below.

- 16 PNGs, **256 x 256**, transparent, white art, named exactly as below,
  in `art_inbox/target_icons/`.
- A short `README.md` in the same folder listing each file and anything to
  know.
- I compose them into the game's sheet and wire them in; don't edit game
  files.

## The icons (in this order)

| # | File | What it is | Silhouette idea |
|---|---|---|---|
| 1 | `target_ship_hauler.png` | Civilian ship: haulers, miners, freighters, traffic | A boxy cargo ship, side or 3/4: bulky hold, small cockpit, engines at the back |
| 2 | `target_ship_combat.png` | Combat ship: raiders, patrols, fighters | A sleek, angular fighter, pointed nose, swept wings or fins |
| 3 | `target_asteroid_rock.png` | Ore asteroid (silicate, ferrite, cuprite, thorium) | A lumpy irregular rock with a few craters and one or two crystal/vein facets so it reads as "has ore" |
| 4 | `target_asteroid_ice.png` | Ice asteroid (water ice, fuel ice) | A chunk of ice: smoother, glassy facets and sharp breaks, a few frost lines |
| 5 | `target_station.png` | Main station (big, dockable, where you berth) | A large station: central hub with a ring or several arms and docking piers; clearly big |
| 6 | `target_outpost.png` | Outpost (small dockable station) | A small station: one module or tower with a single docking arm and a little antenna |
| 7 | `target_gate.png` | Jump gate | A ring standing on edge (3/4 view) with struts; the hole in the middle obvious |
| 8 | `target_planet_rocky.png` | Rocky / cratered planet or moon | A sphere with craters, face-on |
| 9 | `target_planet_ocean.png` | Ocean / terrestrial planet | A sphere with continents and a thin atmosphere ring outline, face-on |
| 10 | `target_planet_gas.png` | Gas giant | A large sphere with horizontal bands, optionally a thin ring |
| 11 | `target_star.png` | Star / sun | A disc with a ring of short, even rays or a corona |
| 12 | `target_wreckage.png` | Wreckage / debris you can salvage | A broken hull: a ship split in two, jagged edges, a few small fragments |
| 13 | `target_derelict.png` | A whole derelict ship (story wrecks, drone dives) | A dead ship mostly intact but tilted, with a torn-open side |
| 14 | `target_anomaly.png` | Signal anomaly / investigation site | Tall thin shards in a loose ring around an empty centre (like our anomaly set piece), a few short signal arcs |
| 15 | `target_cargo.png` | Cargo container, combat drop, pickup | A sturdy cargo crate or canister with clamps |
| 16 | `target_destination.png` | The Destination (the campaign's goal) | A four-pointed guiding star inside a thin circle, like a compass rose's star |

## What the game does with them (for reference)

- Ships pick 1 or 2 by role; the tint says hostile, neutral or friendly.
- Asteroids pick 3 or 4 by ore; the ore name stays in the text.
- Gates use 7 and tint by state (dim for unknown, red for locked).
- Planets pick 8-10 by kind.
- The Destination uses 16 tinted gold. (Today it falls back to the ship
  icon, because the panel has no case for it.)

# Phase 1 Procedural Test System

Status: Complete; deterministic prototype and manual flight review passed

## Purpose

The second solar system is now a reproducible prototype for future generated
systems. It tests runtime construction, stable identity, save restoration, and
autopilot behavior without depending on an LLM or background generation agent.

The fixed seed is `4172026`. Reusing the seed produces the same world IDs and
layout, allowing a failed route or save to be reproduced exactly.

## Generated Contents

- three planets with different physical radii
- two asteroid rings containing 64 persistent asteroids
- two orbital outposts
- one deep-space full-service station
- the authored return gate to the starting system

Planet positions receive deterministic seed jitter. Asteroid position, scale,
vertical dispersion, and orbit speed also come from the system RNG.

## Navigation Contract

Each generated planet provides:

- `celestial` group membership
- spherical collision geometry
- `navigation_clearance_radius` metadata

The navigation radius is calculated from the larger of:

- physical planet radius plus safety margin
- outer asteroid-ring edge plus safety margin

Orbital stations may sit inside that broad navigation envelope. Autopilot
calculates their final approach corridor from physical geometry at runtime.
No production navigation rule refers to a generated planet or station name.

Celestial avoidance uses six hard exits around each navigation circle. At each
exit, only the current celestial is tested for obstruction. A clear result
releases the route immediately; a blocked result advances to the next exit.
The test rejects any ordinary route that reaches a seventh exit.

## Identity Contract

Generated stateful entities receive deterministic IDs derived from the system
and creation key, including:

- `station.test.cinder_exchange`
- `station.test.halcyon_watch`
- `station.test.lantern`
- `entity.test.asteroid.<ring>.<index>`

The return gate keeps its registered ID, `gate.test.to_start`.

## Automated Verification

The real two-way gate smoke test now:

- jumps into the generated system
- verifies seed, planet, station, and asteroid counts
- validates all persistent identities
- verifies every planet has a navigation envelope larger than its body
- simulates autopilot from the arrival gate to all three stations
- approaches a named ring asteroid from the opposite side of its parent planet
- advances that asteroid during the route simulation and verifies the bypass
  travels in the same direction as the asteroid ring
- verifies ring entry uses the physical planet corridor without repeated orbits
- selects the live ring asteroid farthest from Halcyon Watch
- verifies Halcyon blocks the outpost from that asteroid
- flies from that asteroid to the occluded outpost without a second orbit
- stages a return-gate route, then rapidly switches between ring asteroids
- verifies no gate, waypoint, hard-exit, or prior-target state survives
- begins transit toward an asteroid in front of the ship
- switches to an asteroid behind the ship before reaching the old waypoint
- verifies the first new steering update favors the rear target immediately
- returns through the gate
- verifies player, upgrade, storage, and save state

The generated-system gate test passes repeatedly and is included in the full
baseline suite.

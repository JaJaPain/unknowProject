# Autopilot Stabilization Checkpoint

Status: implementation-complete as of 2026-06-15.

This checkpoint interrupts Phase 2 before campaign Checkpoint 10 so navigation
behavior is stable before death and reload coverage expands.

## Control Contract

- Selecting or previewing an object never changes the ship's route.
- Every movement command binds its own navigation target.
- Double-click point-to-move immediately cancels the prior command and assigns
  a new point route.
- Repeated route stalls trigger replanning from the ship's current position.
- Repeated failed replans cancel autopilot and return control to the player.

## Route Planning

- A route is tested before the ship begins following it.
- The planner builds a small three-dimensional visibility graph and uses A* to
  select the shortest valid route.
- Every assigned route segment is checked against strategic exclusion spheres.
- Planetary spheres use `navigation_clearance_radius`, which includes the
  planet, its asteroid belt when present, and a safety margin.
- Stations, jumpgates, and isolated asteroids contribute smaller exclusion
  volumes unless they are the commanded destination.
- Asteroids belonging to a planetary belt are covered by the parent planet's
  single exclusion sphere.

## Target Commands

- Right-click previews an object with a heavier cyan highlight.
- A short right-click preserves its original pointer position; mouse capture
  begins only after camera-drag movement crosses a small threshold.
- World picking reaches across the authored system, including relocated
  outposts, and jumpgates provide a non-physical center selection volume so
  their open portal can be right-clicked.
- The context menu provides Select Target, Fly To, Orbit, and the relevant
  Mine, Dock, Jump, or Attack action.
- The preview clears when a command or Cancel is chosen.
- The existing selected target and active route remain unchanged while the
  player considers the menu.

## Placement

- Authored outposts were moved outside their nearby planetary navigation
  envelopes.
- Generated orbital outposts already use radii outside their associated
  asteroid belts.

## Verification

- focused direct, blocked, and multi-hazard 3D route-planner tests
- gameplay planet-crossing route validation
- passive target-selection and immediate point-move override assertions
- context-preview highlight and station-placement assertions
- jump, docking, save, and campaign regression coverage
- full 25-step headless baseline suite

Hands-on result:

- planet-crossing waypoint routes reach their requested destination
- point-to-move immediately replaces the active autopilot route
- route confirmation in system chat is clear and useful

Pending hands-on approval:

- confirm the repaired station and jumpgate right-click selection matches the
  already verified planet, ship, and asteroid behavior

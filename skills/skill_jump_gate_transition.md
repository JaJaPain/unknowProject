# Skill: Jump Gate Transition (3D Hyperspace Tunnel)

The gate jump is a three-act cinematic orchestrated in `GameRoot.gd`
(the gate-travel coroutine, ~lines 240-409). It layers a **2D
screen-space overlay** (`JumpTransitionFX`) on top of a **real 3D
tunnel scene** (`JumpTunnel`) that the player ship is teleported into.

## Cast of files

| File | Role |
|------|------|
| `scripts/GameRoot.gd` | Orchestrator. Drives the three acts, teleports, system load. |
| `scripts/JumpTransitionFX.gd` (CanvasLayer) | 2D overlay: spool tunnel, chromatic/blur, white flash, exit shockwave ripple. |
| `scripts/JumpTunnel.gd` (Node3D) | The real 3D bore. Owns the camera + ship during transit. |
| `scenes/jump_tunnel.tscn` | Cylinder mesh + warp particles + engine light + WorldEnvironment glow. |
| `shaders/hyperspace_tunnel_3d.gdshader` | Bore shader: scrolling FBM plasma + rushing energy rings. |
| `scripts/WarpExitBubble.gd` / `scenes/warp_exit_bubble.tscn` | Arrival shockwave bubble at the destination gate. |

Constants in `GameRoot.gd`: `JUMP_ENTRY_DURATION := 3.2`,
`JUMP_EXIT_DURATION := 2.0`, `GATE_TRAVEL_MINUTES := 45`,
`ARRIVAL_COOLDOWN_SECONDS := 2.5`.

## The key insight: the ship never moves

**During transit the ship is parked dead-still at the tunnel center.**
There is no forward translation. The sense of speed is faked entirely
by:

1. The shader scrolling its plasma + rings down the bore
   (`time_offset = TIME * speed` in the `.gdshader`).
2. The `WarpParticles` (CPUParticles3D) streaking past at
   `initial_velocity_min/max` 280-420.
3. A slow `tunnel_cylinder.rotate_y()` swirl.

`GameRoot` zeroes `current_speed` and `velocity` before transit and
teleports the ship to a remote coordinate `(50000, 50000, 50000)`,
where a fresh `jump_tunnel.tscn` is spawned around it. This is why
"making the ship fly slower/faster" is the wrong lever — there is no
physics motion to tune, only the shader `speed` and particle velocity.

## Act 1 — Entry (~3.2s)

In `GameRoot`: stretch the ship visual on Z (length-contraction),
tween it into the source gate, widen camera FOV to ~94°, call
`source_gate.begin_jump_charge()`, then
`await transition_fx.play_entry()`. `play_entry` spools the 2D shader
tunnel + chromatic aberration + radial blur and ends on a full white
flash.

## Act 2 — Transit (~5.6s + 0.6s exit burst)

After the white flash covers the screen, `GameRoot`:

- Zeroes `collision_layer`/`collision_mask`, hides `ui_mgr` (prevents
  HUD/overview shader leaks), hides the old system.
- Teleports ship + camera pivot to the remote coordinate with
  `Basis.IDENTITY` (ship faces -Z, straight down the bore).
- Spawns `jump_tunnel.tscn`, calls `setup_real_ship(player)`.
- Fades the white flash **out** so the bore is revealed.
- Loads the destination system in the background while the player
  watches the tunnel.
- After `create_timer(5.6)`, calls `jump_tunnel.begin_exit_burst(0.6)`
  and fades the flash back **in** over 0.6s (whiteout).
- While white: teleports the ship to the arrival gate transform.

### What `JumpTunnel` owns during transit

`setup_real_ship` captures the player `Visual`, `Camera3D`, and
`CameraPivot`, then **aims the camera straight down the bore**:

```gdscript
_camera_pivot.rotation = Vector3.ZERO   # was the -15° gameplay pitch
```

`_process` re-asserts this every frame (so the gameplay camera-follow
in `PlayerShip._physics_process` can't fight it), keeps the ship
locked dead-center (`position = Vector3.ZERO`) with only a whisper of
bank (`roll = sin(t * 0.8) * 0.02`), holds the camera offsets at zero
(no random shake), and does one slow FOV breathe.

`cleanup()` restores the original visual transform, camera FOV, and
the gameplay `-15°` pivot pitch.

### Exit burst

`begin_exit_burst(duration)` is the "punch out the end" beat fired
just before the whiteout. It tweens the shader `speed` ×3.5, the
`ring_speed` ×2.5, and adds +18° FOV (`_fov_burst`, applied per-frame
in `_process`). The tunnel material is **duplicated per-instance in
`_ready`** so this speed ramp never bakes into the shared scene
sub-resource and bleed into the next jump.

## Act 3 — Exit (~2.0s)

`GameRoot` calls `cleanup()` + frees the tunnel, restores collision +
UI, reveals the new system, plays the arrival sound, spawns a
`warp_exit_bubble.tscn` shockwave at the gate, tweens the ship a short
distance off the gate, and runs `transition_fx.play_exit()` (2D decel
blur + expanding shockwave ripple). Then it advances the campaign
clock 45 min, sets the arrival cooldown, queues gate discovery, and
ticks events.

## Tuning knobs

| Want to change | Where |
|----------------|-------|
| Time spent in the tunnel | `create_timer(5.6)` in `GameRoot` (Act 2). |
| Particle density | `amount` on `WarpParticles` in `jump_tunnel.tscn` (currently 192). |
| Particle speed | `initial_velocity_min/max` on `WarpParticles`. |
| Exit-burst strength | `begin_exit_burst` args: `speed * 3.5`, `ring_speed * 2.5`, `_fov_burst → 18.0`, and the `0.6` durations. |
| Ship bank/life | `roll = sin(t * 0.8) * 0.02` in `JumpTunnel._process`. |
| Bore colors / ring frequency | shader params in `jump_tunnel.tscn` (`neon_color`, `accent_color`, `ring_frequency`, `ring_speed`). |

## Gotchas

- **Everything is guarded by `DisplayServer.get_name() == "headless"`.**
  Headless skips all visuals and uses tiny (0.05s) durations so tests
  don't stall.
- **The camera-pivot fight.** `PlayerShip._physics_process` normally
  drives the pivot toward a `-15°` chase pitch. During transit
  `JumpTunnel._process` forces `rotation = Vector3.ZERO` every rendered
  frame so the bore stays centered. If you change one, account for the
  other.
- **Material sharing.** Always duplicate the tunnel material per
  instance before mutating shader params at runtime, or the change
  persists into the next jump.
- **The tunnel cylinder is currently hidden** (`tunnel_cylinder.visible
  = false` in `_ready`) as a diagnostic — the off-axis bore geometry
  read as "flung out the side." Re-enable by removing that line if/when
  the cylinder placement is corrected.

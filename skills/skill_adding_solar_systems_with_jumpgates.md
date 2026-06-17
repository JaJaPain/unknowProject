# Skill: Adding Solar Systems with Jumpgates and Persistent Saves

Use this guide when adding another playable solar system to SpaceGame. It
documents the architecture established by the first two-system implementation.
Follow the contracts below so travel, UI, quests, and saved world state continue
to work consistently.

## Architecture Summary

The persistent scene is `res://scenes/main.tscn`. Its root uses
`res://scripts/GameRoot.gd` and owns:

- `SystemContainer`: holds exactly one active solar-system scene.
- `PlayerShip`: survives system changes.
- Persistent UI and jump-transition effects.
- System loading, paired-gate arrival, autosave, and state restoration.

Solar-system scenes live under `res://scenes/systems/`. They contain world
objects, planets, stations, asteroids, NPCs, and gates, but they must not contain
another player, UI manager, or game root.

`GameRoot.SYSTEM_SCENES` is the authoritative registry of loadable systems.
Every system needs a unique string ID and an entry in that dictionary.

The reusable gate scene is `res://scenes/jump_gate.tscn`, controlled by
`res://scripts/JumpGate.gd`. Gates are paired by string IDs, not NodePaths.
Its `PortalSurface` remains a `QuadMesh`, but
`res://scripts/jumpgate_portal.gdshader` applies a circular alpha mask and
animated procedural ripples so the square boundary is not visible.

Save data is written to `user://savegame.json`. It stores:

- Save format version.
- Current system and last arrival gate.
- Player health, shields, position, and rotation.
- Credits, cargo, upgrades, reputation, and faction kills.
- Active quest data.
- Per-system persistent entity state.

## Non-Negotiable Rules

1. Never replace `res://scenes/main.tscn` with a system scene.
2. Keep the player and UI under the persistent `GameRoot`.
3. Add every new system to `GameRoot.SYSTEM_SCENES`.
4. Give every system and gate a unique, stable ID using lowercase snake case.
5. Point each gate at an existing destination system and destination gate.
6. Put the destination arrival marker outside the gate collision and portal.
7. Give every save-relevant entity a stable ID unique within its system.
8. Never generate persistent IDs randomly or from array order.
9. Capture a destroyed entity's state before calling `queue_free()`.
10. Increase `SAVE_VERSION` if an incompatible save-data structure is introduced.
11. Do not commit large 3D models. Models are ignored by `.gitignore` and must
    be installed locally at the paths expected by their Godot scenes.
12. Do not edit imported files under `.godot/`.
13. Keep the transition fully opaque while changing systems, player transform,
    camera transform, and camera FOV.
14. Synchronize any `top_level` player children after teleporting the player.
    The camera pivot is the current example.
15. Treat entity signals as valid during system teardown. Signal callbacks must
    tolerate nodes that have already left the `SceneTree`.

## Step 1: Establish IDs and Gate Pairing

Choose a permanent system ID:

```text
System display name: Helios Reach
System ID: helios_reach
Scene: res://scenes/systems/system_helios_reach.tscn
```

Choose unique directional gate IDs. Encode both endpoints in the name:

```text
start_to_helios
helios_to_start
```

For a connection from `start_system` to `helios_reach`, the metadata must pair
like this:

```text
Gate in start_system:
  gate_id = start_to_helios
  destination_system_id = helios_reach
  destination_gate_id = helios_to_start

Gate in helios_reach:
  gate_id = helios_to_start
  destination_system_id = start_system
  destination_gate_id = start_to_helios
```

The destination gate is also the arrival anchor. A typo in any of these three
IDs prevents travel.

## Step 2: Create the System Scene

Create `res://scenes/systems/system_<system_id>.tscn` with a `Node3D` root.
Use `system_test.tscn` as the minimal reference and `system_start.tscn` as the
full-world reference.

Minimum structure:

```text
HeliosReach (Node3D)
|- WorldEnvironment
|- DirectionalLight3D
|- Planet (StaticBody3D)
|  |- MeshInstance3D
|  `- CollisionShape3D
`- ReturnGate (instance of res://scenes/jump_gate.tscn)
```

Requirements:

- The root must be a `Node3D`.
- Add an environment and lighting so the scene remains visible after loading.
- Static planets need both a mesh and collision.
- Keep the initial gate area clear of planets, stations, asteroids, and NPCs.
- Do not add `PlayerShip`, `UIManager`, `JumpTransitionFX`, or `SystemContainer`.
- Avoid hard-coded references to nodes in another system scene.

Optional system script:

```gdscript
extends Node3D

func _ready() -> void:
    GlobalState.active_system_root = self
    GlobalState.current_system_id = "helios_reach"
    call_deferred("_refresh_overview")

func _refresh_overview() -> void:
    var ui := GlobalState.get_ui_manager()
    if ui and ui.has_method("refresh_overview"):
        ui.refresh_overview()
```

Save it as `res://scripts/HeliosReachSystem.gd` and attach it to the scene root.
Replace `helios_reach` with the permanent system ID. `GameRoot` also sets these
global values during loading; the script keeps direct editor scene testing and
UI refresh behavior consistent with `TestSystem.gd`.

## Step 3: Register the System

Edit `res://scripts/GameRoot.gd` and add the scene to `SYSTEM_SCENES`:

```gdscript
const SYSTEM_SCENES: Dictionary = {
    "start_system": preload("res://scenes/systems/system_start.tscn"),
    "test_system": preload("res://scenes/systems/system_test.tscn"),
    "helios_reach": preload("res://scenes/systems/system_helios_reach.tscn"),
}
```

This registry is used for normal jumps, startup save loading, and save
validation. A scene existing on disk is not enough; it must be registered.

Do not rename an existing system ID after saves have shipped unless migration
logic is added. Old saves refer to the ID string.

## Step 4: Add and Configure the Destination Gate

Instance `res://scenes/jump_gate.tscn` into the new system.

Set:

```gdscript
gate_id = "helios_to_start"
display_name = "HELIOS RETURN GATE"
destination_system_id = "start_system"
destination_gate_id = "start_to_helios"
destination_display_name = "FRONTIER SYSTEM"
activation_range = 130.0
```

Position and rotate the gate so arriving ships face open space. Open the
instanced gate for editable children only if the arrival marker needs tuning.
The `ArrivalMarker` transform controls the player's exact arrival position and
orientation.

Arrival-marker checklist:

- It is outside the gate model and collision shape.
- It does not overlap another object.
- Its forward direction points away from the portal into safe space.
- A ship at the marker cannot instantly trigger another jump.
- The marker provides enough room for the arrival effect and camera.

The gate scene instances `res://assets/hypergate.glb`. This model is deliberately
ignored by Git. Confirm it exists locally before diagnosing a missing gate
visual. Keep its expected path unchanged or update the reusable gate scene for
all systems.

### Portal Surface and Charge Effect

The blue portal is not a water texture asset. It is a procedural shader on a
36-by-36 `QuadMesh`:

```text
res://scripts/jumpgate_portal.gdshader
```

The shader supplies:

- A circular soft-edged alpha mask.
- Layered directional waves.
- Animated radial ripples.
- A brighter circular rim and center glow.
- A `charge` uniform that increases brightness during spool-up.

`JumpGate.gd` duplicates the `ShaderMaterial` per gate instance. This is
important: changing one gate's charge must not brighten every gate that shares
the scene resource.

The charge tween uses a method callback:

```gdscript
charge_tween.tween_method(
    Callable(self, "_set_portal_charge"),
    0.0,
    1.0,
    duration
)
```

Do not tween `"shader_parameter/charge"` directly. In this project and Godot
version, that property path can begin as `Nil` and produce a tween type-mismatch
error. Set the uniform through `ShaderMaterial.set_shader_parameter()`.

If replacing the procedural shader with a water texture later, retain the
circular UV mask. A texture on an unmasked `QuadMesh` will reveal the original
square or diamond outline.

## Step 5: Add the Matching Gate to the Existing System

Open the source system scene and instance another `jump_gate.tscn`.

For the example:

```gdscript
gate_id = "start_to_helios"
display_name = "HELIOS HYPERGATE"
destination_system_id = "helios_reach"
destination_gate_id = "helios_to_start"
destination_display_name = "HELIOS REACH"
```

Do not reuse an existing `gate_id`, even when two gates share a destination.
The loader finds the arrival gate by its exact ID inside the destination scene.

## Step 6: Add Save-Relevant Entities

Objects that should reset whenever a system reloads need no persistence work.
Objects whose changed state must survive travel or restarting the game must:

1. Join the `persistent_entity` group.
2. Return a stable ID from `get_persistent_id()`.
3. Return JSON-compatible data from `capture_state()`.
4. Apply that data in `restore_state(state)`.
5. Record terminal state before removal when destroyed or depleted.

Template:

```gdscript
extends Node3D

@export var persistent_id: String = ""
var destroyed := false
var health := 100.0

func _ready() -> void:
    add_to_group("persistent_entity")
    if persistent_id == "":
        persistent_id = name

func get_persistent_id() -> String:
    return persistent_id

func capture_state() -> Dictionary:
    return {
        "type": "example_entity",
        "destroyed": destroyed,
        "health": health,
        "position": [
            global_position.x,
            global_position.y,
            global_position.z,
        ],
    }

func restore_state(state: Dictionary) -> void:
    destroyed = bool(state.get("destroyed", false))
    health = float(state.get("health", 100.0))
    var position_data: Array = state.get("position", [])
    if position_data.size() == 3:
        global_position = Vector3(
            float(position_data[0]),
            float(position_data[1]),
            float(position_data[2])
        )
    if destroyed:
        queue_free()

func destroy() -> void:
    destroyed = true
    _record_persistent_state()
    queue_free()

func _record_persistent_state() -> void:
    var game_root := get_tree().current_scene
    if game_root and game_root.has_method("record_persistent_entity_state"):
        game_root.record_persistent_entity_state(self)
```

Use only values JSON can represent: dictionaries, arrays, strings, numbers,
booleans, and null. Convert `Vector3`, transforms, colors, and custom resources
to arrays or dictionaries.

Existing references:

- `Asteroid.gd`: resource depletion and destroyed state.
- `NPCShip.gd`: mission target health, faction, transform, and destroyed state.

### Stable ID Rules

Good:

```text
helios_asteroid_iron_01
helios_pirate_patrol_leader
helios_research_station
```

Unsafe:

```text
Asteroid@1842
random_uuid_generated_on_ready
enemy_<current array index>
```

IDs only need to be unique within one system because states are stored beneath
the system ID. Once used in released saves, treat them as permanent.

### Runtime-Spawning Entities

The generic restore pass can only restore nodes present after the system scene
instantiates. A persistent entity that may be absent from the base scene after
loading needs explicit respawn logic in `GameRoot._restore_system_state()`.

Mission ships are the current example. If adding another runtime-spawned type:

1. Store a distinct `"type"` in `capture_state()`.
2. Preload its scene in `GameRoot.gd`.
3. Detect that type in `_restore_system_state()`.
4. Instantiate it only when its saved state says it still exists.
5. Restore its stable ID before calling `restore_state()`.

## Step 7: Decide What Belongs in the Save

Do not automatically save every decorative object. Persist only state whose
reset would confuse the player or break progression.

Usually persist:

- Mined or destroyed resource objects.
- Destroyed quest targets.
- Damaged persistent mission objects.
- Quest progress tied to the system.
- Player progression and cargo.
- Permanent world choices.

Usually reset:

- Particle effects and temporary projectiles.
- Ambient audio.
- Decorative traffic with no gameplay consequence.
- Short-lived combat effects.
- Procedurally spawned flavor objects unless their loss matters.

If adding a new global progression field, update both
`GameRoot._capture_global_state()` and `GameRoot._apply_global_state()`.
If adding player runtime state, update both `_capture_player_state()` and
`_apply_player_state()`.

When the save shape becomes incompatible, increment:

```gdscript
const SAVE_VERSION := 2
```

Prefer adding migration logic before increasing the version if preserving
existing player saves matters. Without migration, an old version is rejected
and the game starts fresh.

## Step 8: Preserve System Ownership Boundaries

Code that searches for world entities must stay within:

```gdscript
GlobalState.get_system_root()
```

or verify:

```gdscript
system_root.is_ancestor_of(entity)
```

Do not search the entire scene tree and assume every matching node belongs to
the active system. The persistent player, UI, and transition layer live outside
the system root.

Before unloading, `GameRoot` clears stale targets and system-entity references.
New gameplay managers that cache system nodes must also clear or reacquire them
when `GameRoot.system_changed` fires.

### Entity Signals During Teardown

Entities can emit removal or refresh signals from `_exit_tree()`. For example,
`Wreckage.gd` emits `GlobalState.entities_changed` when wreckage leaves the
system. This also happens when the entire old system is unloaded for a jump,
not only when the player salvages one wreck.

Any persistent listener, especially UI, must be safe if its callback runs while
nodes are leaving the tree:

```gdscript
func refresh_overview() -> void:
    var system_root := GlobalState.get_system_root()
    var scene_tree := get_tree()
    if not system_root or not scene_tree:
        return

    for node in scene_tree.get_nodes_in_group("station"):
        if is_instance_valid(node) and system_root.is_ancestor_of(node):
            # Add the node to the overview.
            pass
```

Cache `get_tree()` once and validate it before calling
`get_nodes_in_group()`. Do not repeatedly call `get_tree()` inside the same
callback because the node may be in teardown.

Persistent signal listeners should also disconnect when exiting:

```gdscript
func _exit_tree() -> void:
    if GlobalState.entities_changed.is_connected(refresh_overview):
        GlobalState.entities_changed.disconnect(refresh_overview)
```

This prevents stale callbacks from reaching a UI node after it has left the
tree. Apply the same pattern to future global entity, quest, targeting, or
system-change signals when their listeners can be removed or replaced.

## Step 9: UI and Jump Behavior

Jumpgates automatically join the `jumpgate` group and register with the active
system entity list. The existing UI recognizes that group and provides:

- Overview-list entry.
- Target information and destination name.
- `Approach Gate`.
- `Initiate Jump`.
- Distance, alignment, docking, cooldown, and transition refusal messages.

Do not create a second jump UI for a new system. Correct gate metadata is enough.

The player must:

- Be alive and undocked.
- Target the gate.
- Be within `activation_range`.
- Face the gate within the alignment tolerance.
- Not already be jumping.
- Be past the arrival cooldown.

### Transition Timing and Hidden System Swap

The rendered jump uses these constants in `GameRoot.gd`:

```gdscript
const JUMP_ENTRY_DURATION := 3.2
const JUMP_EXIT_DURATION := 0.9
```

The 3.2-second entry is deliberate story pacing. The portal charge, ship pull,
camera FOV widening, hyperspace tunnel, and entry flash build together. Avoid
adding an idle delay; suspense should remain visually active.

The transition order must remain:

1. Disable player physics and input.
2. Animate portal charge, ship pull, and camera FOV.
3. Fade the hyperspace tunnel to full intensity.
4. At full intensity, make the shader completely opaque across the whole screen.
5. Capture and unload the old system.
6. Instantiate and restore the destination system.
7. Place and rotate the player at the destination gate's `ArrivalMarker`.
8. Restore the camera FOV and synchronize the camera pivot while still covered.
9. Hold full coverage for at least two rendered frames.
10. Play the arrival sound and reverse the tunnel from intensity 1.0 to 0.0.
11. Re-enable player physics and input only after the reveal completes.

The full-screen shader in `jump_transition_fx.tscn` uses `full_coverage` near
maximum intensity. Do not remove that opaque stage. The tunnel's original
center was partially transparent, which exposed the system and camera swap.

`JumpTransitionFX.hold_covered()` forces the tunnel and flash to full intensity
while the destination settles. Keep this call after player/camera placement and
before `play_exit()`.

### Top-Level Camera Pivot Rule

`PlayerShip.CameraPivot` has `top_level = true`. It follows the ship manually in
`PlayerShip._physics_process()` rather than inheriting the player's transform.
Because player physics is disabled during travel, changing
`player.global_transform` does not move the camera pivot automatically.

After setting the arrival transform, always call:

```gdscript
player.sync_camera_to_ship()
```

while the transition is fully opaque. Without this call, the first destination
frame is rendered from the old system coordinates and the camera jumps to the
ship one frame after physics resumes.

Apply the same rule to future top-level camera rigs, target markers, audio
listeners, or helper nodes attached to the player: explicitly synchronize them
before the destination is revealed.

## Step 10: Autosave Expectations

`GameRoot` saves automatically after successful arrival. `Station.gd` and
`OutpostStation.gd` request a save after docking.

When adding another important checkpoint, request saving through the persistent
root:

```gdscript
var game_root := get_tree().current_scene
if game_root and game_root.has_method("save_game"):
    game_root.call_deferred("save_game")
```

Do not let an individual system write a separate save file.

## Step 11: Extend Automated Travel Coverage

The existing `--jump-smoke-test` specifically exercises
`start_system <-> test_system`. A new permanent route should receive an
automated route assertion before relying only on manual testing.

Recommended approach:

1. Add a route-test helper that accepts source system ID, source gate ID,
   destination system ID, and return gate ID.
2. Position the player with `_position_player_for_gate_test()`.
3. Verify out-of-range activation is refused.
4. Request the jump and await `system_changed`.
5. Assert the destination system ID.
6. Assert arrival near `get_arrival_transform()`.
7. Assert `CameraPivot.global_position` matches the player's global position.
8. Clear the test-only cooldown.
9. Jump back and assert player health and shield remain unchanged.
10. Quit with a nonzero exit code on any failed assertion.

Keep test-only behavior behind command-line flags so normal play is unchanged.

## Step 12: Validation Checklist

Before considering the new system complete:

- [ ] New system scene has no player, UI, or nested game root.
- [ ] New system ID is unique and registered in `SYSTEM_SCENES`.
- [ ] Both gate IDs are unique.
- [ ] Both gates point to registered systems.
- [ ] Both `destination_gate_id` values exist in the destination scenes.
- [ ] Both arrival markers face safe, open space.
- [ ] Gate model exists locally at the expected ignored asset path.
- [ ] Portal renders as a circular animated surface with no visible quad corners.
- [ ] Portal brightness builds throughout the jump charge.
- [ ] Overview and target UI show both gates and correct destinations.
- [ ] Out-of-range jump is refused.
- [ ] Misaligned jump is refused.
- [ ] Docked jump is refused.
- [ ] Jump entry takes about 3.2 seconds and remains visually active.
- [ ] Jump effects become fully opaque before system unloading and loading.
- [ ] Arrival reverses the tunnel effect instead of abruptly hiding it.
- [ ] Camera pivot is synchronized before the destination reveal.
- [ ] No camera-position or FOV jump occurs after the overlay disappears.
- [ ] Player health, shields, cargo, credits, upgrades, and quest survive travel.
- [ ] Persistent entities keep their changed state after leaving and returning.
- [ ] Docking autosaves.
- [ ] Restart restores the correct system and valid player transform.
- [ ] New Game/restart deletes the old save and starts fresh.
- [ ] Repeated travel does not duplicate systems, entities, gates, or UI.
- [ ] Unloading systems does not produce null `SceneTree` signal errors.
- [ ] Godot imports and parses without script or scene errors.
- [ ] The aggregate Git diff contains no accidental scene rewrites.

## Verification Commands

Run from the project root. Redirecting Godot's runtime folders prevents local
Windows profile or cache failures from producing misleading crash dialogs.

```powershell
$runtime = Join-Path (Get-Location) '.godot\runtime_user'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$env:APPDATA = $runtime
$env:LOCALAPPDATA = $runtime

.\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --editor --path . --quit
```

Normal startup check without loading an existing save:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --path . --quit-after 240 -- --no-save-load
```

Existing two-way jump and save tests:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --path . -- --jump-smoke-test --save-smoke-test
```

Expected success lines:

```text
[SaveSmokeTest] PASS: player, quest, system state, and validation verified.
[JumpSmokeTest] PASS: two-way travel and player runtime state verified.
```

The optional TTS server may report that Python is unavailable during a short
headless run. That is unrelated to system loading unless the current task also
changes TTS. Forced `--quit-after` runs may also report resources in use at
exit; investigate gameplay script errors separately from forced-exit cleanup.

Git audit:

```powershell
git diff --check
git status --short
git diff --stat
git diff
```

Commit each coherent phase only after reviewing its complete diff.

## Common Failures

### "Unknown destination system"

The `destination_system_id` is absent or misspelled in
`GameRoot.SYSTEM_SCENES`.

### "Destination gate was not found"

The destination scene loaded, but no gate in it has the exact
`destination_gate_id`. Check both halves of the gate pair.

### Player appears inside the gate or planet

Move and rotate the destination gate's `ArrivalMarker`. The gate node's own
transform is not the final player transform.

### Portal still looks like a square or diamond

Confirm `jump_gate.tscn` uses the `ShaderMaterial` from
`res://scripts/jumpgate_portal.gdshader`. The procedural circular mask must
control alpha at the quad edges. A plain `StandardMaterial3D` exposes the mesh's
square outline.

### Portal charge reports a Nil-to-float tween error

Do not tween the shader parameter property path directly. Use
`tween_method()` and call `set_shader_parameter("charge", value)` as implemented
by `JumpGate._set_portal_charge()`.

### Gate exists but has no model

Confirm `res://assets/hypergate.glb` exists locally. Large model formats are
ignored by Git. Also check `JumpGate.gd` warnings for missing meshes.

### Mined or destroyed object returns

Confirm it joins `persistent_entity`, has a stable ID, implements all three
state methods, and records terminal state before `queue_free()`.

### Persistent object restores in one session but not after restart

Its state may contain non-JSON-compatible Godot objects, or its system ID/entity
ID changed. Inspect `user://savegame.json` and the save version.

### Runtime-spawned object never returns

Scene restoration only finds objects already instantiated. Add explicit respawn
handling for its `"type"` in `GameRoot._restore_system_state()`.

### Duplicate UI, player, or audio after jumping

The system scene incorrectly contains persistent-root nodes. Remove them and
keep those nodes only in `main.tscn`.

### References point to the old system after travel

The script cached a node from the unloaded scene. Clear it before unloading or
reacquire it after the `system_changed` signal.

### "Cannot call method get_nodes_in_group on a null value"

A global signal reached a node while that listener was leaving the
`SceneTree`. This commonly appears when old-system entities emit
`entities_changed` from `_exit_tree()`.

In the callback, store `var scene_tree := get_tree()`, return early when it is
null, and use the validated local variable for all group queries. Disconnect
the global signal in the listener's `_exit_tree()` as shown above. Do not
silence or ignore a large debugger count; repeated teardown errors can hide a
real transition regression.

### Camera view jumps shortly after arrival

Check whether the camera rig or one of its parents uses `top_level = true`.
Top-level nodes do not inherit the player's teleport. Call
`PlayerShip.sync_camera_to_ship()` after assigning the arrival transform and
before `JumpTransitionFX.play_exit()`. Keep player physics disabled until the
reverse reveal is finished.

### System or camera swap is visible through the tunnel

At maximum tunnel intensity, the shader must be opaque across the entire
screen, including its center. Perform unloading, loading, player placement,
camera FOV restoration, and camera synchronization before lowering intensity.
Use `hold_covered(2)` to allow the destination to render while hidden.

## Definition of Done

A new system is complete only when the player can intentionally jump into it
and back, the transition hides loading and camera synchronization, the circular
portal animates and charges correctly, arrival is safe, relevant world and
player state survive both travel and process restart, automated checks pass,
and a manual rendered playtest confirms the route feels correct without a
post-arrival camera jump.

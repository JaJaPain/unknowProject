extends Node

## When the distant comet (CometSky) crosses the sky (Abe, 2026-10-05):
## - the first pass about FIRST_S into a session, then GAP_S after each one
##   ends;
## - also when the idle station tour starts (trigger_soon), unless one's
##   crossing already or one only just finished;
## - each pass framed where the camera's looking as it begins, then fixed in
##   the sky, so you can look away and it carries on;
## - the clock stops while paused, in the systems menu, during the intro and
##   on the jump; a jump ends a pass under way.
## One director for the whole session (GameRoot), so jumps and reloads never
## stack comets. Purely cosmetic: nothing to target, no state, no saves.

const FIRST_S := 300.0
const GAP_S := 600.0
const TRIGGER_DELAY_S := 6.0
## After a pass, the tour won't call another for this long.
const TRIGGER_MIN_GAP_S := 90.0
## Each pass swings this far either side of where the camera faces (cosmetic).
const YAW_JITTER := 0.35

var sky: Node3D = null
var _until_next := FIRST_S
var _since_end := INF
var _event := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sky = preload("res://scripts/visuals/CometSky.gd").new()
	sky.name = "CometSky"
	add_child(sky)
	var root := get_parent()
	if root != null and root.has_signal("system_changed"):
		root.connect("system_changed", _on_system_changed)


func is_crossing() -> bool:
	return sky != null and bool(sky.get("running"))


## Where the comet's head is, as a direction from the camera (Vector3.ZERO if
## there's none).
func head_direction() -> Vector3:
	return sky.call("head_direction") if is_crossing() else Vector3.ZERO


## Start one shortly (the station tour, for a bit more ooh la la).
func trigger_soon() -> void:
	if is_crossing() or _since_end < TRIGGER_MIN_GAP_S:
		return
	_until_next = minf(_until_next, TRIGGER_DELAY_S)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	sky.set("observer", cam)
	var frozen := _frozen()
	var root := get_parent()
	if is_crossing() and root != null and bool(root.get("transition_in_progress")):
		_on_system_changed()
		return
	if is_crossing():
		if not bool(sky.call("advance", delta, frozen)):
			_since_end = 0.0
			_until_next = GAP_S
		return
	if frozen or cam == null:
		return
	_since_end += delta
	_until_next -= delta
	if _until_next <= 0.0:
		_begin(cam)


func _begin(cam: Camera3D) -> void:
	_event += 1
	var forward := -cam.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	# A cosmetic seed of its own: system generation's RNG is never touched.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|comet|%d" % [str(GlobalState.current_system_id), _event])
	var yaw := rng.randf_range(-YAW_JITTER, YAW_JITTER)
	forward = forward.normalized().rotated(Vector3.UP, yaw)
	sky.call("begin", _event, Basis.looking_at(forward, Vector3.UP))
	print("[Comet] pass %d in %s" % [_event, str(GlobalState.current_system_id)])


func _frozen() -> bool:
	if get_tree().paused or bool(GlobalState.get("paused")) or bool(GlobalState.get("intro_cinematic_active")):
		return true
	var root := get_parent()
	return root != null and (bool(root.get("transition_in_progress")) or bool(root.get("jump_request_pending")))


func _on_system_changed(_system_id: String = "", _gate: String = "") -> void:
	if is_crossing():
		sky.call("end")
		_since_end = 0.0
		_until_next = GAP_S

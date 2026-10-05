extends Node

## The idle station tour (Abe, playtest 2026-10-05 finding 5): docked, on the
## plain dock menu, with no mouse or key for IDLE_S, the HUD and dock screen
## fade away and a camera drifts slowly round the station, a peaceful lap,
## easing over to watch a freighter come down its beam onto a pier when one
## arrives. Any mouse or key brings everything back exactly as it was (that
## input is swallowed, so it can't press a dock button). Touches no game state.

const IDLE_S := 90.0
const FADE_S := 0.8
## One lap of the station, seconds.
const LAP_S := 180.0
## How quickly the camera settles on where it wants to be (higher = snappier).
const EASE := 0.6
const MUSIC_DIP_DB := -5.0
## Watch a freighter for this long after its beam lets go.
const WATCH_AFTER_S := 4.0
## Kaelen, voice only, while you're away (Abe, 2026-10-05): five minutes
## into the tour, then about every five minutes, over comms (no portrait, no
## text). Every line is heard before any repeats. Lines approved by Abe
## 2026-10-05 except the last (she thinks board work is beneath you).
const KAELEN_FIRST_S := 300.0
const KAELEN_EVERY_S := 300.0
const KAELEN_JITTER_S := 60.0
const KAELEN_LINES := [
	"Shiny, you can't make me any credits if you're sleeping.",
	"Aw, just look. Wonder if Shiny is dreaming of the credits they'll make me?",
	"Still parked, Shiny? Docking fees don't pay themselves. Well, they do. To me.",
	"I've had cargo pods with more ambition than you this afternoon, Shiny.",
	"Take your time, Shiny. It's not as if there's a whole galaxy out there with my money in it.",
	"If you're napping, I'm billing it as a consultation.",
	"I've got clients waiting, Shiny. Real ones. Not the riffraff off the public board.",
]
var _kaelen_next := -1.0
var _kaelen_bag: Array = []

## How far the view leans from the station toward a crossing comet (0-1).
const COMET_LEAN := 0.45

var _ui: Control = null
var _idle := 0.0
var _touring := false
var _cam: Camera3D = null
var _prev_cam: Camera3D = null
var _station: Node3D = null
var _radius := 800.0
var _angle := 0.0
var _clock := 0.0
var _look := Vector3.ZERO
var _watch: Node3D = null
var _watch_until := -1.0
var _fade_layer: CanvasLayer = null
var _fade: ColorRect = null
var _music_db := 0.0
var _music_bus := -1
## `--station-tour-snapshot` shortens the wait.
var idle_s := IDLE_S


func setup(ui: Control) -> void:
	_ui = ui
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 95
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)


func is_touring() -> bool:
	return _touring


func _input(event: InputEvent) -> void:
	var real := event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
		or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0)
	if not real:
		return
	_idle = 0.0
	if _touring:
		get_viewport().set_input_as_handled()
		stop()


func _process(delta: float) -> void:
	if _touring:
		_fly(delta)
		return
	if not _may_start():
		_idle = 0.0
		return
	_idle += delta
	if _idle >= idle_s:
		start()


## Only on the plain dock menu: not in the lounge hunt or a conversation, a
## store, the board, the inventory, a modal, mid-docking, or while anyone is
## talking.
func _may_start() -> bool:
	if _ui == null or not is_instance_valid(_ui) or not _ui.visible:
		return false
	if not bool(_ui.call("_dock_visit_open")) or GlobalState.paused:
		return false
	var dock = _ui.get("dock_panel")
	if dock == null or not dock.visible or bool(_ui.get("_docking_procedure_active")):
		return false
	for panel_name in ["agent_panel", "public_board_panel", "store_panel", "inventory_panel", "ship_upgrades_panel", "ore_trade_popup"]:
		var panel = _ui.get(panel_name)
		if panel != null and is_instance_valid(panel) and panel.visible:
			return false
	var line = _ui.get("dock_message_line")
	if line != null and is_instance_valid(line) and not str(line.text).is_empty():
		return false
	if is_instance_valid(SpeechService) and SpeechService.is_busy():
		return false
	return true


func start() -> void:
	if _touring:
		return
	_station = _ui.get("current_station") as Node3D
	if _station == null or not is_instance_valid(_station):
		return
	_touring = true
	_watch = null
	_kaelen_next = -1.0
	_prev_cam = get_viewport().get_camera_3d()
	_radius = _orbit_radius(_station)
	_angle = _start_angle()
	_cam = Camera3D.new()
	_cam.far = 60000.0
	_cam.fov = 55.0
	_station.get_parent().add_child(_cam)
	if _prev_cam != null:
		_cam.global_transform = _prev_cam.global_transform
	_look = _station.global_position
	print("[StationTour] start at %s (orbit %.0f)" % [str(_station.get("display_name")), _radius])
	# A comet across the sky, for a bit more ooh la la (Abe, 2026-10-05).
	var comet := _comet()
	if comet != null:
		comet.call("trigger_soon")
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_fade, "color:a", 1.0, FADE_S)
	tw.tween_callback(func() -> void:
		if not _touring:
			return
		_ui.visible = false
		_place(1.0)
		_cam.make_current()
	)
	tw.tween_property(_fade, "color:a", 0.0, FADE_S * 1.5)
	_music_bus = AudioServer.get_bus_index("Music")
	if _music_bus >= 0:
		_music_db = AudioServer.get_bus_volume_db(_music_bus)
		AudioServer.set_bus_volume_db(_music_bus, _music_db + MUSIC_DIP_DB)


func stop() -> void:
	if not _touring:
		return
	_touring = false
	_idle = 0.0
	print("[StationTour] stop")
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _music_db)
	var tw := create_tween().set_ignore_time_scale(true)
	_fade.color.a = maxf(_fade.color.a, 0.6)
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _ui != null and is_instance_valid(_ui):
		_ui.visible = true
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	tw.tween_property(_fade, "color:a", 0.0, FADE_S * 0.6)


func _fly(delta: float) -> void:
	if _station == null or not is_instance_valid(_station) or _cam == null or not is_instance_valid(_cam):
		stop()
		return
	_clock += delta
	_angle += TAU / LAP_S * delta
	_kaelen_tick()
	_pick_freighter()
	_place(1.0 - exp(-EASE * delta))


## Where the camera wants to be: on the lap, or watching a freighter. `t` is
## how far to move there this frame (1 = jump).
func _place(t: float) -> void:
	var centre := _station.global_position
	var want_pos: Vector3
	var want_look: Vector3
	if _watch != null and is_instance_valid(_watch):
		var ship := _watch.global_position
		var away := ship - centre
		away.y = 0.0
		away = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
		var side := away.cross(Vector3.UP).normalized()
		# A quiet three-quarter view: out past the ship, off to the side, a
		# little above, the station behind it.
		want_pos = ship + away * _radius * 0.35 + side * _radius * 0.3 + Vector3.UP * _radius * 0.12
		want_look = ship.lerp(centre, 0.25)
	else:
		var bob := sin(_clock * TAU / 47.0) * 0.18 + 0.22
		want_pos = centre + Vector3(cos(_angle), bob, sin(_angle)) * _radius
		want_look = centre
		# While the comet crosses, the camera leans toward it, keeping the
		# station in the picture: the lap would otherwise turn its back on it.
		var comet := _comet()
		var head: Vector3 = comet.call("head_direction") if comet != null else Vector3.ZERO
		if head != Vector3.ZERO:
			var dist := want_pos.distance_to(centre)
			want_look = centre.lerp(want_pos + head * dist, COMET_LEAN)
	_cam.global_position = _cam.global_position.lerp(want_pos, t)
	_look = _look.lerp(want_look, t)
	if _cam.global_position.distance_to(_look) > 1.0:
		_cam.look_at(_look, Vector3.UP)


## A freighter on a beam at this station is worth a look.
func _pick_freighter() -> void:
	if _watch != null and is_instance_valid(_watch):
		if _watch_until < 0.0:
			var still_on := false
			for entry in _traffic_entries():
				if entry.get("ship") == _watch and bool(entry.get("on_beam", false)):
					still_on = true
			if not still_on:
				_watch_until = _clock + WATCH_AFTER_S
		elif _clock >= _watch_until:
			_watch = null
		return
	_watch = null
	_watch_until = -1.0
	for entry in _traffic_entries():
		if entry.get("station") == _station and bool(entry.get("on_beam", false)):
			var ship = entry.get("ship")
			if ship is Node3D and is_instance_valid(ship):
				_watch = ship
				print("[StationTour] watching %s" % ship.name)
				return


func _comet() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("CometDirector") if scene != null else null


func _traffic_entries() -> Array:
	var traffic := get_tree().current_scene.find_child("TrafficDirector", true, false) if get_tree().current_scene != null else null
	if traffic == null:
		return []
	var ships = traffic.get("_ships")
	return ships if ships is Array else []


func _orbit_radius(station: Node3D) -> float:
	if station.has_method("approach_sphere_radius"):
		return float(station.call("approach_sphere_radius")) * 1.1
	var box := AABB()
	var first := true
	for m in station.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return maxf(400.0, box.size.length() * 0.8) if not first else 800.0


## Start the lap from about where the player's camera already is.
func _start_angle() -> float:
	if _prev_cam == null:
		return 0.0
	var d := _prev_cam.global_position - _station.global_position
	return atan2(d.z, d.x)


func _kaelen_tick() -> void:
	if _kaelen_next < 0.0:
		_kaelen_next = _clock + kaelen_first_s
		# Her voice is made ahead, so it's ready when it's time.
		for line in KAELEN_LINES:
			SpeechService.cache(line, GlobalState.KAELEN_VOICE_PROFILE_ID)
		return
	if _clock < _kaelen_next or SpeechService.is_busy():
		return
	if _kaelen_bag.is_empty():
		_kaelen_bag = KAELEN_LINES.duplicate()
		_kaelen_bag.shuffle()
	var line: String = _kaelen_bag.pop_back()
	SpeechService.play_ambient(line, GlobalState.KAELEN_VOICE_PROFILE_ID, true, "Broker Kaelen")
	kaelen_lines_said += 1
	print("[StationTour] Kaelen: %s" % line)
	_kaelen_next = _clock + KAELEN_EVERY_S + randf_range(-KAELEN_JITTER_S, KAELEN_JITTER_S)


## Tests: say the first one sooner, and how many she's said.
var kaelen_first_s := KAELEN_FIRST_S
var kaelen_lines_said := 0

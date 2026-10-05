extends Node

## Says the active mission's N.O.V.A. remark (MissionRemarks) halfway to the
## mission's place, not at the station (Abe, playtest 2026-10-05 finding 7).
##
## - In this system: once you're between 35% and 80% of the way from where
##   you undocked to the mission's place (the tracker's target).
## - Another system: a little after arriving in the next one, once the
##   tunnel lines are done.
## - No place to measure (an ore run, say): about a minute out from the dock.
## Never in combat or over another line; if the window passes, it's dropped,
## never said on arrival. Once per mission (`nova_remark_played` on it).

const CHECK_S := 0.5
const WINDOW_LO := 0.35
const WINDOW_HI := 0.8
const NO_TARGET_AFTER_S := 60.0
const NO_TARGET_GIVE_UP_S := 120.0
const ARRIVAL_AFTER_S := 12.0
const ARRIVAL_GIVE_UP_S := 50.0
## Already about there at undock: no "halfway" to speak of.
const MIN_TRIP := 600.0

var _ui: Node = null
var _mission_id := ""
var _start_dist := -1.0
var _undocked_s := -1.0
var _system := ""
var _arrived_s := -1.0
var _clock := 0.0
var _check := 0.0


func arm(ui: Node) -> void:
	_ui = ui
	_mission_id = ""


func _process(delta: float) -> void:
	_clock += delta
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_S
	var q: Dictionary = QuestManager.active_quest if QuestManager.is_quest_active() else {}
	var line := str(q.get("nova_remark", "")).strip_edges()
	if line.is_empty() or bool(q.get("nova_remark_played", false)) or QuestManager.is_quest_completed():
		return
	var id := str(q.get("runtime_id", q.get("title", "")))
	if id != _mission_id:
		_mission_id = id
		_start_dist = -1.0
		_undocked_s = -1.0
		_arrived_s = -1.0
		_system = ""
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("is_docked")) or bool(GlobalState.get("intro_cinematic_active")):
		return
	if _undocked_s < 0.0:
		_undocked_s = _clock
		_system = str(GlobalState.current_system_id)
	var now_system := str(GlobalState.current_system_id)
	if now_system != _system:
		# Another system: a beat after arriving.
		if _arrived_s < 0.0:
			_arrived_s = _clock
		var since := _clock - _arrived_s
		if since > ARRIVAL_GIVE_UP_S:
			_drop(q)
		elif since >= ARRIVAL_AFTER_S:
			_try_say(q, line)
		return
	var target: Node3D = _target(q)
	if target == null:
		var out := _clock - _undocked_s
		if out > NO_TARGET_GIVE_UP_S:
			_drop(q)
		elif out >= NO_TARGET_AFTER_S:
			_try_say(q, line)
		return
	var d: float = (p as Node3D).global_position.distance_to(target.global_position)
	if _start_dist < 0.0:
		_start_dist = d
		if d < MIN_TRIP:
			_drop(q)
			return
	var way := 1.0 - d / maxf(_start_dist, 1.0)
	if way >= WINDOW_HI:
		_drop(q)
	elif way >= WINDOW_LO:
		_try_say(q, line)


func _target(q: Dictionary) -> Node3D:
	if _ui == null or not is_instance_valid(_ui):
		return null
	var t = _ui.call("_quest_tracker_route_target", q)
	if t == null and str(q.get("objective_type", "")) in ["DELIVERY_COURIER", "PURCHASE_DELIVERY", "PICKUP_SPECIAL"]:
		t = _ui.call("_quest_tracker_turn_in_target", q)
	return t as Node3D if t is Node3D and is_instance_valid(t) else null


var _waiting_logged := false


func _try_say(q: Dictionary, line: String) -> void:
	var combat: bool = is_instance_valid(Nova) and bool(Nova.get("_in_combat"))
	var busy: bool = is_instance_valid(SpeechService) and SpeechService.is_busy()
	if not is_instance_valid(Nova) or combat or busy:
		if not _waiting_logged:
			_waiting_logged = true
			print("[MissionRemark] waiting (combat %s, speech busy %s)" % [combat, busy])
		return
	if Nova.speak_mission_remark(line, "smile"):
		q["nova_remark_played"] = true
		q["nova_remark_said"] = true
		print("[MissionRemark] %s" % line)
	elif not _waiting_logged:
		# The gap after her last line: try again.
		_waiting_logged = true
		print("[MissionRemark] waiting (N.O.V.A. spoke a moment ago)")


func _drop(q: Dictionary) -> void:
	q["nova_remark_played"] = true
	print("[MissionRemark] dropped (no good moment): %s" % str(q.get("title", "")))

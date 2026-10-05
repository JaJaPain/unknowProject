extends Node

## Pickup jobs get intercepted on the way back half the time (Abe,
## 2026-10-05). Rolled once when the item's handed over (kept on the job, so
## a reload doesn't re-roll it); fires on the return leg, a little way along;
## N.O.V.A. warns first, then one hijacker comes for you (the claim jumper's
## rules: one ship, depth-scaled, announced; dock first and it loses you).
## Like the rest of the risk game, nothing before the first upgrade
## (MiningRisk.active()).

const NPC_SCENE := preload("res://scenes/npc_ship.tscn")
const Scaling := preload("res://scripts/domain/DepthScaling.gd")
const MiningRisk := preload("res://scripts/world/MiningRisk.gd")

const CHANCE := 0.5
const FACTION := "reavers"
## Along the way back: the warning comes between these shares of the trip.
const WAY_LO := 0.3
const WAY_HI := 0.6
## No hand-in in this system: this long in flight instead.
const NO_TARGET_AFTER_S := 45.0
const WARNING_S := 25.0
const SPAWN_DISTANCE := 1500.0
const CHECK_S := 0.5

## Draft lines for Abe's review (2026-10-05). {item}: the pickup.
const WARN_LINES := [
	"Captain, a ship just lit its engines behind us and turned our way. I think someone wants the {item} more than we do.",
	"We've picked up a tail. One ship, closing. Whoever sold us the {item} sold the news as well.",
]
const HAIL_LINES := [
	"That {item} isn't yours, freighter. Cut your engines and nobody gets holes.",
	"Nice pickup. We'll take it from here. Or from your wreck. Your call.",
]
const AFTER_LINES := [
	"That's one less person who wanted the {item}. Let's not make a habit of it.",
]

## The ship that came for the last one, and how many went down (tests).
var last_hijacker: Node3D = null
var hijackers_downed := 0
var _check := 0.0
var _flight_s := 0.0
var _start_dist := -1.0
var _job_id := ""
var _pending := false
var _system := ""


func _process(delta: float) -> void:
	_check -= delta
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	var player = gs.player
	var flying: bool = player != null and is_instance_valid(player) and not bool(player.get("is_docked")) and not bool(player.get("destroyed"))
	if flying:
		_flight_s += delta
	if _check > 0.0:
		return
	_check = CHECK_S
	var job: Dictionary = QuestManager.get_pickup_special_data()
	if job.is_empty() or not bool(job.get("picked_up", false)) or bool(job.get("is_intro_tutorial", false)):
		return
	var id := str(job.get("runtime_id", job.get("title", "")))
	if id != _job_id:
		_job_id = id
		_start_dist = -1.0
		_flight_s = 0.0
		_system = str(gs.current_system_id)
	if not job.has("intercept_planned"):
		job["intercept_planned"] = force_next or randf() < CHANCE
		force_next = false
		print("[PickupIntercept] %s: %s" % [str(job.get("title", "")), "intercepted on the way back" if job["intercept_planned"] else "clean run"])
	if not bool(job["intercept_planned"]) or bool(job.get("intercept_done", false)) or _pending:
		return
	if not flying or not (MiningRisk.active() or ignore_first_upgrade_rule):
		return
	var nova := get_node_or_null("/root/Nova")
	if nova != null and bool(nova.get("_in_combat")):
		return
	if _due(gs, player as Node3D, job):
		_warn(job)


## True once the return leg is far enough along.
func _due(gs: Node, player: Node3D, job: Dictionary) -> bool:
	if str(gs.current_system_id) != _system:
		return _flight_s >= NO_TARGET_AFTER_S * 0.5
	var ui = gs.get_ui_manager() if gs.has_method("get_ui_manager") else null
	var target = ui.call("_quest_tracker_route_target", job) if ui != null else null
	if not target is Node3D or not is_instance_valid(target):
		return _flight_s >= NO_TARGET_AFTER_S
	var d := player.global_position.distance_to((target as Node3D).global_position)
	if _start_dist < 0.0:
		_start_dist = d
	var way := 1.0 - d / maxf(_start_dist, 1.0)
	if way >= WAY_HI:
		# Nearly home already (a very short hop): no time for it to be fair.
		job["intercept_done"] = true
		return false
	return way >= WAY_LO


func _warn(job: Dictionary) -> void:
	_pending = true
	job["intercept_done"] = true
	_nova(_fill(WARN_LINES.pick_random(), job), "danger")
	get_tree().create_timer(warning_s).timeout.connect(_spawn.bind(job))


func _spawn(job: Dictionary) -> void:
	_pending = false
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	var root: Node3D = gs.get_system_root() if gs != null else null
	if not is_instance_valid(player) or root == null or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return  # docked or gone: they lose the trail
	var ship := NPC_SCENE.instantiate()
	ship.faction = FACTION
	ship.ship_role = "Interceptor"
	ship.difficulty_multiplier = Scaling.threat_factor(Scaling.current_depth())
	ship.persistent_id = "entity.%s.hijacker.%d" % [str(gs.current_system_id), Time.get_ticks_msec()]
	ship.name = "Hijacker_%d" % (randi() % 1000)
	ship.set_meta("display_label", "Hijacker")
	ship.set_meta("hunts_player", true)
	root.add_child(ship)
	ship.display_name = "%s Hijacker" % gs.faction_display_name(FACTION)
	# From ahead and to one side: they've come to cut you off.
	var p := player as Node3D
	var ahead := -p.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var dir := ahead.rotated(Vector3.UP, randf_range(-0.9, 0.9))
	ship.global_position = p.global_position + dir * SPAWN_DISTANCE
	last_hijacker = ship
	ship.tree_exiting.connect(_on_hijacker_leaving.bind(ship, str(job.get("part_name", ""))))
	gs.emit_chatter(str(ship.display_name).to_upper(), _fill(HAIL_LINES.pick_random(), job), Color(1.0, 0.45, 0.35))


## The hijacker shot down (not just gone, e.g. left behind on a jump): a word
## from N.O.V.A. A destroyed ship is freed at once, so this checks on its way
## out.
func _on_hijacker_leaving(ship: Node, item: String) -> void:
	if is_instance_valid(ship) and bool(ship.get("destroyed")):
		hijackers_downed += 1
		_nova(_fill(AFTER_LINES.pick_random(), {"part_name": item}), "smile")


static func _fill(template: String, job: Dictionary) -> String:
	var item := str(job.get("part_name", "")).strip_edges()
	return template.replace("{item}", item if not item.is_empty() else "cargo")


func _nova(text: String, expression: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova == null:
		return
	if expression == "danger" and nova.has_method("ask_captain"):
		nova.ask_captain(text, "danger")
	elif nova.has_method("speak"):
		nova.speak(text, 2, expression)


## Tests: the next roll is a yes, the first-upgrade rule is waived, shorter
## warning.
var force_next := false
var ignore_first_upgrade_rule := false
var warning_s := WARNING_S

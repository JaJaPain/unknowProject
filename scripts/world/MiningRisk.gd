extends Node

## Risk follows reward (docs/core_loop_plan_2026_10_01.md 3.7, core loop step
## 6b; Abe, 2026-10-01): the rarer the ore, the more it costs to take.
##   - Rare ore (thorium) draws ONE ship every time, announced with time to
##     choose; uncommon cuprite only sometimes.
##   - Red rocks sometimes have a guard already parked beside them, visible
##     on the overview, called out by N.O.V.A. when the rock is targeted.
##   - (Claims on common ore live in GlobalState.report_player_mined_asteroid.)
## Fairness: nothing here before the first upgrade is fitted; every attack is
## announced first; one attacker at a time.

const NPC_SCENE := preload("res://scenes/npc_ship.tscn")
const Scaling := preload("res://scripts/domain/DepthScaling.gd")
const GateClass := preload("res://scripts/domain/GateClass.gd")

const JUMPER_WARNING_S := 40.0
const JUMPER_COOLDOWN_S := 240.0
const CUPRITE_JUMPER_CHANCE := 0.15
const JUMPER_SPAWN_DISTANCE := 1500.0
const JUMPER_FACTION := "reavers"
const GUARD_FACTION := "reavers"
## Guards at depth 0-2 about 30% of red rocks, rising to 70% deep.
const GUARD_CHANCE_MIN := 0.30
const GUARD_CHANCE_MAX := 0.70

var _jumper_pending := false
var _last_jumper_s := -1000.0
var _rocks_drawn: Dictionary = {}  # rock id -> true: one roll per rock
var _guards: Dictionary = {}  # rock id -> guard ship
var _guard_told: Dictionary = {}
var _system_id := ""
var _clock := 0.0
## Tests: guard every red rock regardless of the roll.
var force_guard_all := false
## The last claim jumper sent (tests, and to avoid stacking them).
var last_jumper: Node3D = null


## Mining risk only once the first upgrade is fitted (Ship Rating above stock).
static func active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GlobalState") if tree != null else null
	if gs == null:
		return false
	return GateClass.ship_rating(GateClass.tiers_of(gs.current_upgrades)) > 5


## Guard chance for a red rock at this depth (0..1).
static func guard_chance(depth: int) -> float:
	return clampf(GUARD_CHANCE_MIN + 0.04 * float(maxi(depth - 2, 0)), GUARD_CHANCE_MIN, GUARD_CHANCE_MAX)


## Whether this rock (by id) gets a guard at this depth. Fixed per rock.
static func rock_is_guarded(rock_id: String, depth: int) -> bool:
	return float(posmod((rock_id + ":guard").hash(), 1000)) / 1000.0 < guard_chance(depth)


func _process(delta: float) -> void:
	_clock += delta
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	var system_id := str(gs.current_system_id)
	if system_id != _system_id:
		_system_id = system_id
		_guards.clear()
		_guard_told.clear()
		_jumper_pending = false
	if not active():
		return
	_place_guards()
	_call_out_guard()


## Called by GlobalState each time the player's laser takes ore from a rock.
func on_mined(rock: Node3D) -> void:
	if not active() or _jumper_pending or not is_instance_valid(rock):
		return
	var ore := str(rock.get("ore_type"))
	if ore != "thorium" and ore != "cuprite":
		return
	var rock_id := str(rock.get("persistent_id"))
	if _rocks_drawn.has(rock_id):
		return
	_rocks_drawn[rock_id] = true
	if _clock - _last_jumper_s < JUMPER_COOLDOWN_S:
		return
	if ore == "cuprite" and randf() > CUPRITE_JUMPER_CHANCE:
		return
	_jumper_pending = true
	_last_jumper_s = _clock
	var ore_name := "thorium" if ore == "thorium" else "cuprite"
	_nova("Someone's picked up the %s. One ship, inbound, about forty seconds. Keep cutting, leave with what we've got, or get ready for them." % ore_name)
	get_tree().create_timer(JUMPER_WARNING_S).timeout.connect(_spawn_jumper)


func _spawn_jumper() -> void:
	_jumper_pending = false
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	var root: Node3D = gs.get_system_root() if gs != null else null
	if not is_instance_valid(player) or root == null or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return  # docked or gone: they lose the trail
	var ship := _make_ship(JUMPER_FACTION, "Interceptor", "Claim Jumper", "claimjumper")
	# Locks on from range and closes in, at normal (depth-scaled) strength:
	# is_reinforcement would also make it an elite.
	ship.set_meta("hunts_player", true)
	root.add_child(ship)
	ship.display_name = "%s Claim Jumper" % gs.faction_display_name(JUMPER_FACTION)
	last_jumper = ship
	var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	ship.global_position = (player as Node3D).global_position + away * JUMPER_SPAWN_DISTANCE
	gs.emit_chatter("SYSTEM", "Contact inbound: a claim jumper is closing on your position.", Color(1.0, 0.45, 0.35))


## One guard beside each guarded red rock in this system, parked and waiting.
func _place_guards() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	var root: Node3D = gs.get_system_root() if gs != null else null
	if root == null:
		return
	var depth := Scaling.current_depth()
	for rock in get_tree().get_nodes_in_group("tech_seam_asteroid"):
		if not rock is Node3D or not root.is_ancestor_of(rock) or bool(rock.get("destroyed")):
			continue
		var rock_id := str(rock.get("persistent_id"))
		if rock_id.is_empty() or _guards.has(rock_id):
			continue
		if not force_guard_all and not rock_is_guarded(rock_id, depth):
			_guards[rock_id] = null
			continue
		var guard := _make_ship(GUARD_FACTION, "Gunner", "Seam Guard", "seamguard")
		root.add_child(guard)
		guard.display_name = "%s Seam Guard" % gs.faction_display_name(GUARD_FACTION)
		var side := Vector3(1, 0, 0).rotated(Vector3.UP, float(posmod(rock_id.hash(), 628)) / 100.0)
		guard.global_position = (rock as Node3D).global_position + side * 90.0
		guard.patrol_center = guard.global_position
		guard.set_meta("guarding_rock", rock_id)
		_guards[rock_id] = guard


## N.O.V.A. calls out a guarded red rock the first time it's targeted.
func _call_out_guard() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	var t = gs.active_target if gs != null else null
	if not is_instance_valid(t) or not (t as Node).is_in_group("tech_seam_asteroid"):
		return
	var rock_id := str(t.get("persistent_id"))
	var guard = _guards.get(rock_id, null)
	if guard == null or not is_instance_valid(guard) or bool(guard.get("destroyed")) or _guard_told.has(rock_id):
		return
	_guard_told[rock_id] = true
	_nova("There's a ship sitting on that rock. It hasn't moved. It's waiting. Get close and it'll come for us.")


func _make_ship(faction: String, role: String, label: String, tag: String) -> Node3D:
	var gs := get_node_or_null("/root/GlobalState")
	var ship := NPC_SCENE.instantiate()
	ship.faction = faction
	ship.ship_role = role
	ship.difficulty_multiplier = Scaling.threat_factor(Scaling.current_depth())
	ship.persistent_id = "entity.%s.%s.%d" % [str(gs.current_system_id) if gs != null else "sys", tag, Time.get_ticks_msec()]
	ship.name = "%s_%d" % [label.replace(" ", ""), randi() % 1000]
	ship.set_meta("display_label", label)
	return ship


func _nova(text: String) -> void:
	load("res://scripts/ui/Wiki.gd").unlock("mining_risk")
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "danger")

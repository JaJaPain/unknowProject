extends Node

# StoryQuestManager — parallel story quest runtime.
# Runs alongside QuestManager without interfering. One story quest active at a time.
# StoryManager calls begin_quest(); GameRoot/NPCShip/UIManager call the event hooks.

signal quest_started(quest_def: Dictionary)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String, reason: String)
signal quest_ui_updated(title: String, objective_line: String, time_remaining_s: float)
signal quest_ui_hidden()

# ── Active quest state ────────────────────────────────────────────────────────
var _quest: Dictionary = {}           # the full definition
var _obj: Dictionary = {}             # current objective tracking state
var _pending_spawns: Dictionary = {}  # system_id → Array[spawn_def]
var _spawned_ship_ids: Array = []     # persistent_ids we spawned (for cleanup)
var _time_limit_s: float = 0.0
var _time_elapsed_s: float = 0.0
var _survive_elapsed_s: float = 0.0
var _active: bool = false
var _finished: bool = false           # guard against double complete/fail


func _process(delta: float) -> void:
	if not _active or _finished:
		return
	# Time limit countdown
	if _time_limit_s > 0.0:
		_time_elapsed_s += delta
		if _time_elapsed_s >= _time_limit_s:
			_fail_quest("time_expired")
			return
		_emit_ui_update()
	# Survive-duration objective tick
	if _obj.get("type") == "survive_duration_in_system" and _obj.get("in_target_system", false):
		_survive_elapsed_s += delta
		var needed: float = float(_obj.get("duration_s", 60.0))
		if _survive_elapsed_s >= needed:
			_complete_quest()
		else:
			_emit_ui_update()


# ── Public API ────────────────────────────────────────────────────────────────

func reset_for_restart() -> void:
	_quest = {}
	_obj = {}
	_pending_spawns = {}
	_spawned_ship_ids = []
	_time_limit_s = 0.0
	_time_elapsed_s = 0.0
	_survive_elapsed_s = 0.0
	_active = false
	_finished = false
	quest_ui_hidden.emit()


func is_active() -> bool:
	return _active

func get_active_quest() -> Dictionary:
	return _quest.duplicate(true)

func begin_quest(def: Dictionary) -> void:
	if _active:
		push_warning("[StoryQuestManager] Quest already active — ignoring begin_quest.")
		return
	_quest = def.duplicate(true)
	_active = true
	_finished = false
	_time_elapsed_s = 0.0
	_survive_elapsed_s = 0.0
	_pending_spawns = {}
	_spawned_ship_ids = []

	# Build objective state
	var obj_def: Dictionary = _quest.get("objective", {})
	_obj = obj_def.duplicate(true)
	_obj["done"] = false
	if _obj.get("type") == "survive_duration_in_system":
		_obj["in_target_system"] = false

	# Queue spawns by system_id; spawn contacts immediately
	for spawn in _quest.get("spawns", []):
		var sys_id: String = str(spawn.get("system_id", ""))
		if sys_id.is_empty():
			_execute_spawn(spawn)
		else:
			if not _pending_spawns.has(sys_id):
				_pending_spawns[sys_id] = []
			_pending_spawns[sys_id].append(spawn)

	# Time limit
	var limit_min: float = float(_quest.get("time_limit_min", 0.0))
	_time_limit_s = limit_min * 60.0

	# Narrative hook
	_deliver_hook(_quest.get("hook", {}))

	quest_started.emit(_quest)
	_emit_ui_update()
	print("[StoryQuestManager] Quest started: %s" % _quest.get("id", "?"))


# Called by UIManager._on_planted_npc_pressed when advances_quest flag is set
func on_planted_npc_talked(npc_id: String) -> void:
	if not _active or _finished:
		return
	if _obj.get("type") == "talk_to_planted_npc":
		var target: String = str(_obj.get("target_npc_id", ""))
		if target.is_empty() or target == npc_id:
			_complete_quest()


# Called by NPCShip on destroy
func on_ship_destroyed(persistent_id: String, faction: String) -> void:
	if not _active or _finished:
		return
	match _obj.get("type"):
		"kill_tagged_ship":
			if persistent_id == str(_obj.get("target_persistent_id", "")):
				_complete_quest()
		"protect_ship":
			if persistent_id == str(_obj.get("target_persistent_id", "")):
				_fail_quest("protected_ship_destroyed")


# Called by UIManager on dock
func on_docked(station) -> void:
	if not _active or _finished:
		return
	if _obj.get("type") == "dock_with_item":
		var needed: String = str(_obj.get("required_item", ""))
		if not needed.is_empty() and GlobalState.inventory.has_item(needed):
			_complete_quest()


# Called by GameRoot on system arrival
func on_system_arrived(system_id: String) -> void:
	if not _active or _finished:
		return
	# Fire deferred spawns for this system
	if _pending_spawns.has(system_id):
		for spawn in _pending_spawns[system_id]:
			_execute_spawn(spawn)
		_pending_spawns.erase(system_id)
	# Objective checks
	match _obj.get("type"):
		"reach_system":
			if system_id == str(_obj.get("target_system", "")):
				_complete_quest()
		"survive_duration_in_system":
			var target: String = str(_obj.get("target_system", ""))
			_obj["in_target_system"] = (system_id == target)
			if not _obj["in_target_system"]:
				_survive_elapsed_s = 0.0  # reset if they leave
			_emit_ui_update()


# ── Internal ──────────────────────────────────────────────────────────────────

func _deliver_hook(hook: Dictionary) -> void:
	if hook.is_empty():
		return
	var text: String = str(hook.get("text", ""))
	var delay_s: float = float(hook.get("delay_s", 0.0))
	match str(hook.get("type", "")):
		"intercepted_transmission":
			var ui := _find_ui_manager()
			if ui and ui.has_method("show_intercepted_transmission"):
				ui.show_intercepted_transmission(text, delay_s)
		"kaelen_voice":
			var ui := _find_ui_manager()
			if ui and ui.has_method("queue_kaelen_voice_message"):
				if delay_s > 0.0:
					await get_tree().create_timer(delay_s).timeout
					if not is_instance_valid(self) or not _active:
						return
				ui.queue_kaelen_voice_message(text)
		"planted_npc":
			# Merge the npc sub-dict into story_planted_npc, adding advances_quest flag
			var npc_def: Dictionary = hook.get("npc", {}).duplicate(true)
			npc_def["advances_quest"] = true
			GlobalState.story_planted_npc = npc_def


func _execute_spawn(spawn: Dictionary) -> void:
	var spawn_type: String = str(spawn.get("type", ""))
	match spawn_type:
		"ship":
			_spawn_story_ship(spawn)
		"npc_contact":
			var contact: Dictionary = spawn.duplicate(true)
			contact["advances_quest"] = bool(spawn.get("advances_quest", false))
			GlobalState.story_planted_npc = contact


func _spawn_story_ship(spawn: Dictionary) -> void:
	var scene = load("res://scenes/npc_ship.tscn")
	if scene == null:
		push_error("[StoryQuestManager] Could not load npc_ship.tscn")
		return
	var parent: Node3D = get_tree().current_scene
	# Try to find the active system root
	if parent and parent.has_method("get_active_system_root"):
		var sys_root = parent.get_active_system_root()
		if sys_root:
			parent = sys_root

	var npc = scene.instantiate()
	npc.faction = str(spawn.get("faction", "zenith"))
	npc.speed = float(spawn.get("speed", 12.0))
	npc.ship_role = str(spawn.get("ship_role", "Logistics"))
	npc.persistent_id = str(spawn.get("persistent_id", "story.ship.%d" % randi()))
	npc.name = "StoryShip_%s" % npc.persistent_id.replace(".", "_")

	# Story behavior flag — flee_on_sight handled by Codex in NPCShip AI
	var behavior: String = str(spawn.get("behavior", "patrol"))
	if npc.has_method("set_story_behavior"):
		npc.set_story_behavior(behavior)
	elif "story_behavior" in npc:
		npc.story_behavior = behavior

	parent.add_child(npc)

	# Spawn position: random deep-space entry point
	var angle := randf() * TAU
	var dist := 900.0
	npc.global_position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	if "patrol_center" in npc:
		npc.patrol_center = Vector3.ZERO

	_spawned_ship_ids.append(npc.persistent_id)
	print("[StoryQuestManager] Spawned story ship: %s (%s)" % [npc.persistent_id, npc.faction])


func _complete_quest() -> void:
	if _finished:
		return
	_finished = true
	_active = false

	var complete_def: Dictionary = _quest.get("on_complete", {})

	# Credits
	var credits: int = int(complete_def.get("credits", 0))
	if credits > 0:
		GlobalState.player_credits += credits

	# Reputation
	var rep_changes: Dictionary = complete_def.get("reputation", {})
	for faction in rep_changes:
		if faction in GlobalState.reputations:
			GlobalState.reputations[faction] = clampf(
				float(GlobalState.reputations[faction]) + float(rep_changes[faction]),
				-100.0, 100.0
			)

	# Item reward
	var reward_item: String = str(complete_def.get("item", ""))
	if not reward_item.is_empty():
		GlobalState.inventory.add(reward_item, 1, 10)

	# Arc flag
	var arc_flag: String = str(complete_def.get("arc_flag", ""))
	if not arc_flag.is_empty():
		GlobalState.story_state["arc_flags"][arc_flag] = "complete"

	# Chatter delivery
	var sender: String = str(complete_def.get("chatter_sender", ""))
	var line: String = str(complete_def.get("chatter_line", ""))
	if not line.is_empty():
		var color := Color(0.85, 0.5, 1.0) if sender == "Kaelen" else Color(0.8, 0.9, 0.8)
		GlobalState.emit_chatter(sender if not sender.is_empty() else "System", line, color)

	# Kaelen voice button
	if bool(complete_def.get("kaelen_voice", false)) and not line.is_empty():
		var ui := _find_ui_manager()
		if ui and ui.has_method("queue_kaelen_voice_message"):
			ui.queue_kaelen_voice_message(line)

	quest_completed.emit(str(_quest.get("id", "")))
	quest_ui_hidden.emit()
	print("[StoryQuestManager] Quest complete: %s" % _quest.get("id", "?"))
	_quest = {}
	_obj = {}


func _fail_quest(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_active = false

	var fail_def: Dictionary = _quest.get("on_fail", {})

	var arc_flag: String = str(fail_def.get("arc_flag", ""))
	if not arc_flag.is_empty():
		GlobalState.story_state["arc_flags"][arc_flag] = "failed"

	var line: String = str(fail_def.get("chatter_line", ""))
	if not line.is_empty():
		GlobalState.emit_chatter("Kaelen", line, Color(0.85, 0.5, 1.0))

	quest_failed.emit(str(_quest.get("id", "")), reason)
	quest_ui_hidden.emit()
	print("[StoryQuestManager] Quest failed: %s — %s" % [_quest.get("id", "?"), reason])
	_quest = {}
	_obj = {}


func _emit_ui_update() -> void:
	if not _active:
		return
	var title: String = str(_quest.get("title", "Story Quest"))
	var obj_line: String = _objective_display_line()
	var remaining: float = max(0.0, _time_limit_s - _time_elapsed_s)
	quest_ui_updated.emit(title, obj_line, remaining)


func _objective_display_line() -> String:
	match str(_obj.get("type", "")):
		"kill_tagged_ship":
			return "Destroy the target ship"
		"protect_ship":
			return "Keep the ship alive"
		"reach_system":
			var sys: String = str(_obj.get("target_system", "")).replace("_", " ").capitalize()
			return "Jump to %s" % sys
		"dock_with_item":
			var item: String = str(_obj.get("required_item", "the item")).replace("_", " ").capitalize()
			return "Dock with %s in cargo" % item
		"talk_to_planted_npc":
			return "Find the contact at the station"
		"survive_duration_in_system":
			var needed: float = float(_obj.get("duration_s", 60.0))
			var remaining: float = max(0.0, needed - _survive_elapsed_s)
			return "Hold position — %.0fs remaining" % remaining
	return "Objective unknown"


func _find_ui_manager() -> Node:
	var nodes := get_tree().get_nodes_in_group("ui_manager")
	return nodes[0] if not nodes.is_empty() else null

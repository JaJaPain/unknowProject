extends Node

const HISTORY_FILE_PATH = "user://quest_history.md"
const MissionAdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)
const MissionInstanceType := preload(
	"res://scripts/domain/MissionInstance.gd"
)
const MissionCapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)
const MissionCollectionType := preload(
	"res://scripts/domain/MissionCollection.gd"
)

signal quest_accepted()
signal quest_accepted_details(quest_data: Dictionary)
signal quest_progress_updated()
signal quest_completed()
signal quest_completed_details(quest_data: Dictionary)
signal quest_abandoned()
signal quest_abandoned_details(quest_data: Dictionary)
signal quest_expired(title: String)
signal quest_expired_details(quest_data: Dictionary)
signal pickup_handoff_ready(line: String, voice_profile_id: String, is_fallback: bool, npc_name: String)
signal comms_reversal_triggered(mission_data: Dictionary)

var _collection: MissionCollection = MissionCollection.new()
var active_quest: Dictionary:
	get:
		var focused = _collection.get_focused()
		if focused == null:
			return {}
		return focused.data
	set(value):
		if value.is_empty():
			_collection.clear()
		else:
			_collection.clear()
			var inst = MissionInstanceType.from_dict(value)
			_collection.add(inst)
var last_validation_error: String = ""
var _board_cooldowns: Dictionary = {}
const BOARD_COOLDOWN_MINUTES: int = 120

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create history file if it does not exist
	_load_quest_history()
	# Connect to ship destroyed signals to track combat quests
	GlobalState.ship_destroyed.connect(_on_ship_destroyed)
	CampaignClock.time_changed.connect(_on_campaign_time_changed)

func reset_for_restart():
	_collection.clear()
	_board_cooldowns.clear()
	print("[QuestManager] State reset for new game.")


func _load_quest_history() -> String:
	if not FileAccess.file_exists(HISTORY_FILE_PATH):
		var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
		if f:
			f.store_line("# Quest History Log")
			f.close()
		return ""
	
	var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.READ)
	if f:
		var content = f.get_as_text()
		f.close()
		return content
	return ""

func _log_quest_to_file(quest_title: String, quest_type: String, outcome: String):
	var history = _load_quest_history()
	var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(history)
		f.store_line("- **" + quest_title + "** (" + quest_type + "): " + outcome)
		f.close()


# Returns only the history lines relevant to `agent_name` (e.g. "Director Voss").
# Since the on-disk history doesn't store agent_name, we filter by the faction
# the agent speaks for — Zenith=Voss, Aurelia=Ryn, Vanguard=Dask, neutral=Kaelen.
# This keeps the LLM prompt short and focused on the pilot's relationship with
# the upcoming quest giver's faction, instead of dumping the whole log.
# Falls back to a substring search on the quest title if the faction map misses.
func filter_history_for_agent(agent_name: String, faction: String) -> String:
	var full = _load_quest_history()
	if full.strip_edges() == "":
		return ""

	# Map agent → faction keyword to look for in the quest title (lowercased)
	var faction_keyword: String = ""
	match faction.to_lower():
		"zenith":
			faction_keyword = "zenith"
		"aurelia":
			faction_keyword = "aurelia"
		"vanguard":
			faction_keyword = "vanguard"
		_:
			# neutral / unknown — treat as "the rest". Return last 5 lines unfiltered
			# so Kaelen can still reference the pilot's overall track record.
			var all_lines = full.split("\n")
			var tail: Array = []
			for i in range(max(0, all_lines.size() - 5), all_lines.size()):
				if all_lines[i].strip_edges() != "":
					tail.append(all_lines[i])
			return "\n".join(tail)

	# Filter: keep lines that mention the faction keyword OR contain the agent's
	# name directly (covers edge cases where the LLM uses a unique title).
	var kept: Array = []
	for line in full.split("\n"):
		var lower = line.to_lower()
		if line.strip_edges() == "":
			continue
		if lower.find(faction_keyword) != -1 or lower.find(agent_name.to_lower()) != -1:
			kept.append(line)

	if kept.is_empty():
		return ""

	# Cap at the most recent 8 entries to keep the prompt small
	if kept.size() > 8:
		kept = kept.slice(kept.size() - 8, kept.size())

	return "\n".join(kept)

func is_quest_active() -> bool:
	return _collection.has_any_active()


func get_mission_instance():
	return _collection.get_focused()


func get_mission_collection() -> MissionCollection:
	return _collection


func is_lane_occupied(lane_name: String) -> bool:
	var lane_map := {
		"AGENT": MissionInstanceType.SourceLane.AGENT,
		"BOARD": MissionInstanceType.SourceLane.BOARD,
		"STATION": MissionInstanceType.SourceLane.STATION,
	}
	if not lane_map.has(lane_name):
		return false
	return _collection.is_lane_occupied(lane_map[lane_name])

func get_lane_data(lane_name: String) -> Dictionary:
	var lane_map := {
		"AGENT": MissionInstanceType.SourceLane.AGENT,
		"BOARD": MissionInstanceType.SourceLane.BOARD,
		"STATION": MissionInstanceType.SourceLane.STATION,
	}
	if not lane_map.has(lane_name):
		return {}
	var mission = _collection.get_by_lane(lane_map[lane_name])
	if mission == null:
		return {}
	return mission.data


func get_pickup_special_data() -> Dictionary:
	var station = get_lane_data("STATION")
	if not station.is_empty() and station.get("objective_type", "") == "PICKUP_SPECIAL":
		return station
	var agent = get_lane_data("AGENT")
	if not agent.is_empty() and agent.get("objective_type", "") == "PICKUP_SPECIAL":
		return agent
	return {}


func get_completed_count() -> int:
	var history := _load_quest_history()
	if history.strip_edges().is_empty():
		return 0
	var count := 0
	for line in history.split("\n"):
		if line.strip_edges().begins_with("- **"):
			count += 1
	return count


func is_quest_completed() -> bool:
	if not is_quest_active():
		return false
	var cap = MissionCapabilityRegistryType.get_for_type(
		active_quest["objective_type"]
	)
	if cap == null:
		return false
	return cap.is_completed(active_quest)


func request_new_quest(
	agent_faction: String,
	callback: Callable,
	agent_profile: Dictionary = {}
) -> void:
	var history_text = _load_quest_history()
	LLMInterface.request_quest_generation(
		agent_faction,
		history_text,
		GlobalState.player_credits,
		GlobalState.reputations,
		callback,
		agent_profile
	)

func accept_quest(
	quest_data: Dictionary,
	selected_choice: Dictionary
) -> bool:
	var runtime_mission_id := _create_runtime_mission_id(quest_data)
	var adapted := MissionAdapterType.build_active_state(
		quest_data,
		selected_choice,
		runtime_mission_id,
		GlobalState.current_system_id,
		CampaignClock.total_minutes
	)
	var validation: ValidationResult = adapted["validation"]
	if not validation.is_valid():
		last_validation_error = _validation_message(validation)
		push_warning(
			"[QuestManager] Rejected malformed mission offer: %s" %
			last_validation_error
		)
		return false

	var consequence = adapted["consequence"]
	GlobalState.player_credits += consequence.credits_immediate
	for faction in consequence.reputation_change.keys():
		GlobalState.adjust_reputation(
			faction,
			consequence.reputation_change[faction]
		)

	var new_mission = MissionInstanceType.create_active(
		(adapted["state"] as Dictionary).duplicate(true)
	)
	if not _collection.add(new_mission):
		last_validation_error = "Lane %s is already occupied" % new_mission.lane_name()
		push_warning("[QuestManager] %s" % last_validation_error)
		return false
	_collection.focus(new_mission.runtime_id)
	last_validation_error = ""
	if active_quest["objective_type"] in [
		"KILL_SHIPS",
		"RECOVER_COMBAT_DROP",
	]:
		var spawn_faction = active_quest["target_faction"]
		var spawn_count = active_quest["count_required"]
		var accepted_runtime_id := str(active_quest["runtime_id"])
		get_tree().create_timer(3.0).timeout.connect(func():
			if not is_quest_active():
				return
			if str(active_quest.get("runtime_id", "")) != accepted_runtime_id:
				return
			if active_quest.get("objective_type", "") not in [
				"KILL_SHIPS",
				"RECOVER_COMBAT_DROP",
			]:
				return
			GlobalState.spawn_mission_targets(spawn_faction, spawn_count)
		)

	print(
		"[QuestManager] Quest accepted: ",
		active_quest["title"],
		" type:",
		active_quest["objective_type"],
		" (Difficulty multiplier: ",
		active_quest["combat_multiplier"],
		")"
	)
	quest_accepted.emit()
	quest_accepted_details.emit(active_quest.duplicate(true))
	return true


func _create_runtime_mission_id(quest_data: Dictionary) -> String:
	var identity_source := "%s|%s|%s|%s" % [
		Time.get_unix_time_from_system(),
		Time.get_ticks_usec(),
		quest_data.get("title", "mission"),
		quest_data.get("faction", "neutral"),
	]
	return "mission.runtime.%s" % identity_source.sha256_text().substr(0, 16)


func capture_active_quest() -> Dictionary:
	var focused = _collection.get_focused()
	if focused == null:
		last_validation_error = ""
		return {}
	var normalized := MissionAdapterType.normalize_legacy_state(focused.data)
	var validation := MissionAdapterType.validate_active_state(normalized)
	if not validation.is_valid():
		last_validation_error = _validation_message(validation)
		return {}
	focused.data = normalized
	last_validation_error = ""
	return normalized


func capture_all_quests() -> Array:
	var result: Array = []
	for m in _collection.get_all_active():
		var normalized := MissionAdapterType.normalize_legacy_state(m.data)
		var validation := MissionAdapterType.validate_active_state(normalized)
		if validation.is_valid():
			m.data = normalized
			var d: Dictionary = m.to_dict()
			if m.runtime_id == _collection._focused_runtime_id:
				d["_focused"] = true
			result.append(d)
	return result


func is_active_quest_timed() -> bool:
	return is_quest_active() and bool(active_quest.get("is_timed", false))


func get_active_quest_remaining_minutes() -> int:
	if not is_active_quest_timed():
		return 0
	return maxi(
		0,
		int(active_quest.get("deadline_time_minutes", 0))
			- CampaignClock.total_minutes
	)


func is_active_quest_expired() -> bool:
	return (
		is_active_quest_timed()
		and CampaignClock.total_minutes
			>= int(active_quest.get("deadline_time_minutes", 0))
	)


func check_active_quest_expiration() -> bool:
	var any_expired := false
	for m in _collection.get_all_active():
		if not bool(m.data.get("is_timed", false)):
			continue
		if CampaignClock.total_minutes < int(m.data.get("deadline_time_minutes", 0)):
			continue
		var expired_quest: Dictionary = m.data.duplicate(true)
		expired_quest["expired_time_minutes"] = CampaignClock.total_minutes
		var expired_title := str(m.data.get("title", "Contract"))
		var expired_type := str(m.data.get("objective_type", "TIMED"))
		_record_board_cooldown(m.data)
		_cleanup_mission(m)
		_log_quest_to_file(expired_title, expired_type, "Expired.")
		m.transition_to(MissionInstanceType.State.EXPIRED)
		var rid: String = m.runtime_id
		_collection.remove(rid)
		print("[QuestManager] Quest expired: ", expired_title)
		quest_expired.emit(expired_title)
		quest_expired_details.emit(expired_quest)
		any_expired = true
	return any_expired


func active_quest_payout() -> int:
	if not is_quest_active():
		return 0
	var payout := float(active_quest.get("reward_credits", 0))
	payout *= float(active_quest.get("reward_credits_multiplier", 1.0))
	if bool(active_quest.get("is_urgent", false)):
		payout *= float(active_quest.get("urgent_reward_multiplier", 1.0))
	return int(round(payout))


func can_restore_active_quest(source: Dictionary) -> bool:
	var normalized := MissionAdapterType.normalize_legacy_state(source)
	var validation := MissionAdapterType.validate_active_state(normalized)
	last_validation_error = (
		""
		if validation.is_valid()
		else _validation_message(validation)
	)
	return validation.is_valid()


func restore_active_quest(source: Dictionary) -> bool:
	if source.is_empty():
		_collection.clear()
		last_validation_error = ""
		return true
	var normalized := MissionAdapterType.normalize_legacy_state(source)
	var validation := MissionAdapterType.validate_active_state(normalized)
	if not validation.is_valid():
		last_validation_error = _validation_message(validation)
		push_warning(
			"[QuestManager] Refused invalid saved mission: %s" %
			last_validation_error
		)
		return false
	_collection.clear()
	var inst = MissionInstanceType.from_dict(normalized)
	_collection.add(inst)
	last_validation_error = ""
	return true


func restore_all_quests(source_array: Array) -> bool:
	_collection.clear()
	last_validation_error = ""
	for item in source_array:
		if not item is Dictionary:
			continue
		var normalized := MissionAdapterType.normalize_legacy_state(item)
		var validation := MissionAdapterType.validate_active_state(normalized)
		if not validation.is_valid():
			push_warning(
				"[QuestManager] Skipping invalid saved mission: %s" %
				_validation_message(validation)
			)
			continue
		var inst = MissionInstanceType.from_dict(normalized)
		_collection.add(inst)
		if bool(item.get("_focused", false)):
			_collection.focus(inst.runtime_id)
	return true


func _validation_message(validation: ValidationResult) -> String:
	if validation == null or validation.errors.is_empty():
		return "unknown validation error"
	var messages: Array[String] = []
	for issue in validation.errors:
		var path := str(issue.get("path", ""))
		var message := str(issue.get("message", "Invalid mission data."))
		messages.append(
			message if path.is_empty() else "%s: %s" % [path, message]
		)
	return "; ".join(messages)


# Set the LLM-generated (or fallback) handoff line for an active
# PICKUP_SPECIAL quest. Called by UIManager once the Ollama call
# resolves (or when falling back to a canned line). Stores the line +
# voice metadata on the active quest so the dock UI at the outpost can
# play it without re-running the LLM. No-op if there's no active
# PICKUP_SPECIAL quest — the call is best-effort.
#
# `is_fallback=true` means the line is canned, not LLM-generated. Useful
# for trace logging and for any future "showed a fallback" telemetry.
func set_pickup_handoff(line: String, voice_profile_id: String, is_fallback: bool, npc_name: String) -> void:
	if not is_quest_active() or active_quest.get("objective_type", "") != "PICKUP_SPECIAL":
		return
	active_quest["pickup_handoff_line"] = line
	active_quest["pickup_handoff_voice_profile_id"] = voice_profile_id
	active_quest["pickup_handoff_is_fallback"] = is_fallback
	active_quest["pickup_handoff_npc"] = npc_name
	pickup_handoff_ready.emit(line, voice_profile_id, is_fallback, npc_name)


# Bank a partial ore delivery. Returns the amount actually delivered (capped at remaining need).
func deliver_partial(amount: float) -> float:
	if not is_quest_active() or active_quest["objective_type"] != "DELIVER_ORE":
		return 0.0
	if GlobalState.cargo_type != GlobalState.CargoType.ORE:
		return 0.0
	var remaining = active_quest["amount_required"] - active_quest.get("partial_delivered", 0.0)
	var to_deliver = min(amount, remaining, GlobalState.cargo)
	to_deliver = max(0.0, to_deliver)
	if to_deliver <= 0.0:
		return 0.0
	GlobalState.remove_ore(to_deliver)
	active_quest["partial_delivered"] = active_quest.get("partial_delivered", 0.0) + to_deliver
	print("[QuestManager] Partial delivery: %.1f m³ banked. Total so far: %.1f / %.1f" % [
		to_deliver, active_quest["partial_delivered"], active_quest["amount_required"]])
	quest_progress_updated.emit()
	return to_deliver

# Mark a PICKUP_SPECIAL quest as picked up. Called from the outpost dock UI
# when the player "talks to" the target NPC. Loads the part into the cargo
# hold via GlobalState.accept_special. Returns true on success, false if
# the quest isn't a PICKUP_SPECIAL, isn't active, or is already picked up.
func mark_pickup_complete() -> bool:
	if not is_quest_active() or active_quest["objective_type"] != "PICKUP_SPECIAL":
		return false
	if active_quest.get("picked_up", false):
		return false
	var part_name: String = active_quest.get("part_name", "Unknown Part")
	var target_npc: String = active_quest.get("target_npc", "an unknown contact")
	var target_outpost: String = active_quest.get("target_outpost_display", active_quest.get("target_outpost", "an outpost"))
	var destination: String = active_quest.get("destination", "Grease Monkeys")
	var description: String = "Picked up from %s at %s. Deliver to %s at %s." % [
		target_npc, target_outpost, active_quest["agent_name"], destination
	]
	if not GlobalState.accept_special(part_name, description, target_outpost, destination):
		print("[QuestManager] PICKUP_SPECIAL failed to pick up: cargo hold not empty")
		return false
		
	active_quest["picked_up"] = true
	print("[QuestManager] PICKUP_SPECIAL picked up: '%s' from %s" % [part_name, target_npc])
	quest_progress_updated.emit()
	return true

func complete_quest():
	if not is_quest_active() or not is_quest_completed():
		return

	var cap = MissionCapabilityRegistryType.get_for_type(
		active_quest["objective_type"]
	)
	if cap:
		var hints := cap.on_complete(active_quest)
		if hints.has("block"):
			print("[QuestManager] %s: cannot complete, %s" % [
				active_quest["objective_type"], hints["block"]])
			return
		_apply_completion_hints(hints)

	var final_payout = active_quest_payout()
	GlobalState.player_credits += final_payout
	GlobalState.adjust_reputation(active_quest["faction"], 5.0)
	var completed_quest: Dictionary = active_quest.duplicate(true)
	completed_quest["completed_time_minutes"] = CampaignClock.total_minutes
	completed_quest["final_payout"] = final_payout

	var detail = "Completed. Payout: " + str(final_payout) + " SC. Choice selected: '" + active_quest["choice_text_selected"] + "'."
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], detail)

	_record_board_cooldown(active_quest)
	var completed_id := str(active_quest.get("runtime_id", ""))
	print("[QuestManager] Quest completed successfully: ", active_quest["title"])
	var focused = _collection.get_focused()
	if focused:
		focused.transition_to(MissionInstanceType.State.COMPLETED)
	_collection.remove(completed_id)
	quest_completed.emit()
	quest_completed_details.emit(completed_quest)

func abandon_quest():
	if not is_quest_active():
		return

	GlobalState.adjust_reputation(active_quest["faction"], -3.0)
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], "Abandoned.")
	var abandoned_quest: Dictionary = active_quest.duplicate(true)
	abandoned_quest["abandoned_time_minutes"] = CampaignClock.total_minutes

	_record_board_cooldown(active_quest)
	var abandoned_id := str(active_quest.get("runtime_id", ""))
	print("[QuestManager] Quest abandoned: ", active_quest["title"])
	var focused = _collection.get_focused()
	if focused:
		focused.transition_to(MissionInstanceType.State.ABANDONED)
	_collection.remove(abandoned_id)
	quest_abandoned.emit()
	quest_abandoned_details.emit(abandoned_quest)


func _cleanup_expired_quest() -> void:
	var focused = _collection.get_focused()
	if focused == null:
		return
	_cleanup_mission(focused)


func _cleanup_mission(mission) -> void:
	var cap = MissionCapabilityRegistryType.get_for_type(
		mission.data.get("objective_type", "")
	)
	if cap:
		var hints := cap.on_cleanup(mission.data)
		_apply_cleanup_hints(hints)


func _on_campaign_time_changed(_total_minutes: int) -> void:
	check_active_quest_expiration()

func _on_ship_destroyed(faction_name: String):
	for m in _collection.get_all_active():
		var cap = MissionCapabilityRegistryType.get_for_type(
			m.data.get("objective_type", "")
		)
		if cap == null:
			continue

		var hints := cap.handle_event(
			m.data, "ship_destroyed", {"faction": faction_name}
		)
		if hints.is_empty():
			continue

		if hints.get("progress_changed", false):
			print("[QuestManager] Quest progress: ", m.data.get("current_count", 0),
				"/", m.data.get("count_required", 0))
			quest_progress_updated.emit()

		if hints.has("chatter"):
			var c: Dictionary = hints["chatter"]
			GlobalState.emit_chatter(c["source"], c["text"], c["color"])

		if hints.get("trigger_comms", false):
			var comms_faction: String = hints.get("comms_faction", faction_name)
			_set_ceasefire_for_faction(comms_faction, true)
			comms_reversal_triggered.emit(m.data)

		if hints.get("needs_respawn", false):
			var respawn_faction: String = hints.get("respawn_faction", faction_name)
			_schedule_respawn(respawn_faction)


func resolve_comms_branch(branch_id: String) -> void:
	var focused = _collection.get_focused()
	if focused == null or focused.data.get("objective_type", "") != "TARGET_WITH_COMMS_REVERSAL":
		return
	focused.data["branch_chosen"] = true
	focused.data["branch_id"] = branch_id
	var target_faction: String = str(focused.data.get("target_faction", ""))

	match branch_id:
		"finish_kill":
			_set_ceasefire_for_faction(target_faction, false)
			GlobalState.adjust_reputation(target_faction, -2.0)
		"accept_bribe":
			var bribe_quest: Dictionary = focused.data.duplicate(true)
			var bribe: int = int(focused.data.get("bribe_amount", 0))
			GlobalState.player_credits += bribe
			GlobalState.adjust_reputation(focused.data.get("faction", "neutral"), -3.0)
			GlobalState.adjust_reputation(target_faction, 2.0)
			_despawn_ceasefire_targets(target_faction)
			focused.transition_to(MissionInstanceType.State.COMPLETED)
			var rid: String = focused.runtime_id
			_record_board_cooldown(focused.data)
			_log_quest_to_file(str(focused.data.get("title", "")), "TARGET_WITH_COMMS_REVERSAL", "Resolved: accepted bribe (%d SC)." % bribe)
			bribe_quest["completed_time_minutes"] = CampaignClock.total_minutes
			bribe_quest["final_payout"] = bribe
			bribe_quest["outcome_detail"] = "accepted_bribe"
			_collection.remove(rid)
			quest_completed.emit()
			quest_completed_details.emit(bribe_quest)
		"walk_away":
			var walkaway_quest: Dictionary = focused.data.duplicate(true)
			GlobalState.adjust_reputation(focused.data.get("faction", "neutral"), -1.0)
			_despawn_ceasefire_targets(target_faction)
			focused.transition_to(MissionInstanceType.State.ABANDONED)
			var rid: String = focused.runtime_id
			_record_board_cooldown(focused.data)
			_log_quest_to_file(str(focused.data.get("title", "")), "TARGET_WITH_COMMS_REVERSAL", "Resolved: walked away.")
			walkaway_quest["abandoned_time_minutes"] = CampaignClock.total_minutes
			walkaway_quest["outcome_detail"] = "walked_away"
			_collection.remove(rid)
			quest_abandoned.emit()
			quest_abandoned_details.emit(walkaway_quest)

	quest_progress_updated.emit()


func _set_ceasefire_for_faction(faction_name: String, value: bool) -> void:
	for e in GlobalState.active_system_entities:
		if e and is_instance_valid(e) and not e.get("destroyed"):
			if e.is_in_group("ship") and e.get("faction") == faction_name \
					and e.get_meta("is_quest_target", false):
				e.ceasefire = value


func _despawn_ceasefire_targets(faction_name: String) -> void:
	for e in GlobalState.active_system_entities.duplicate():
		if e and is_instance_valid(e) and not e.get("destroyed"):
			if e.is_in_group("ship") and e.get("faction") == faction_name \
					and e.get_meta("is_quest_target", false):
				e.queue_free()


func _apply_completion_hints(hints: Dictionary) -> void:
	if hints.get("remove_ore", 0.0) > 0.0:
		GlobalState.remove_ore(hints["remove_ore"])
	if hints.get("clear_cargo", false):
		GlobalState.clear_cargo()


func _apply_cleanup_hints(hints: Dictionary) -> void:
	if hints.get("clear_cargo", false):
		GlobalState.clear_cargo()
	var cf_faction: String = str(hints.get("clear_ceasefire_faction", ""))
	if cf_faction != "":
		_set_ceasefire_for_faction(cf_faction, false)


func _schedule_respawn(faction: String) -> void:
	get_tree().create_timer(2.0).timeout.connect(func():
		var needs_targets := false
		for m in _collection.get_all_active():
			if m.data.get("target_faction", "") != faction:
				continue
			var cap = MissionCapabilityRegistryType.get_for_type(
				m.data.get("objective_type", "")
			)
			if cap != null and not cap.is_completed(m.data):
				needs_targets = true
				break
		if not needs_targets:
			return
		var alive_targets := 0
		for e in GlobalState.active_system_entities:
			if e and is_instance_valid(e) and not e.get("destroyed"):
				if e.is_in_group("ship") and e.get_meta("is_quest_target", false):
					alive_targets += 1
		if alive_targets == 0:
			GlobalState.spawn_mission_targets(faction, 1)
			print("[QuestManager] Respawned quest target after NPC kill.")
	)


func _record_board_cooldown(quest_data: Dictionary) -> void:
	if not bool(quest_data.get("public_board", false)):
		return
	var tid: String = str(quest_data.get("public_board_template_id", ""))
	if tid.is_empty():
		return
	_board_cooldowns[tid] = CampaignClock.total_minutes
	print("[QuestManager] Board cooldown set for '%s' until +%d min." % [
		tid, BOARD_COOLDOWN_MINUTES])


func is_board_template_on_cooldown(template_id: String) -> bool:
	if not _board_cooldowns.has(template_id):
		return false
	var ended_at: int = int(_board_cooldowns[template_id])
	return CampaignClock.total_minutes < ended_at + BOARD_COOLDOWN_MINUTES


func get_board_cooldown_remaining(template_id: String) -> int:
	if not _board_cooldowns.has(template_id):
		return 0
	var ended_at: int = int(_board_cooldowns[template_id])
	var remaining := (ended_at + BOARD_COOLDOWN_MINUTES) - CampaignClock.total_minutes
	return maxi(0, remaining)


func capture_board_cooldowns() -> Dictionary:
	return _board_cooldowns.duplicate()


func restore_board_cooldowns(source: Dictionary) -> void:
	_board_cooldowns.clear()
	for key in source.keys():
		_board_cooldowns[str(key)] = int(source[key])

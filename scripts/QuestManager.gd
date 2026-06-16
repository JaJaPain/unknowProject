extends Node

const HISTORY_FILE_PATH = "user://quest_history.md"
const MissionAdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)

signal quest_accepted()
signal quest_progress_updated()
signal quest_completed()
signal quest_abandoned()
signal quest_expired(title: String)
# Emitted by set_pickup_handoff when the LLM (or fallback) handoff line
# for a PICKUP_SPECIAL quest is ready. UIManager listens for this to fire
# the TTS pre-cache. We use a dedicated signal (vs. quest_progress_updated)
# because the line arriving is a one-shot event, not a state diff.
signal pickup_handoff_ready(line: String, voice_profile_id: String, is_fallback: bool, npc_name: String)

var active_quest: Dictionary = {}
var last_validation_error: String = ""

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create history file if it does not exist
	_load_quest_history()
	# Connect to ship destroyed signals to track combat quests
	GlobalState.ship_destroyed.connect(_on_ship_destroyed)
	CampaignClock.time_changed.connect(_on_campaign_time_changed)

func reset_for_restart():
	active_quest = {}
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
	return not active_quest.is_empty()

func is_quest_completed() -> bool:
	if not is_quest_active():
		return false
	
	var type = active_quest["objective_type"]
	if type == "KILL_SHIPS":
		return active_quest["current_count"] >= active_quest["count_required"]
	elif type == "RECOVER_COMBAT_DROP":
		return bool(active_quest.get("ship_log_recovered", false))
	elif type == "DELIVER_ORE":
		# Count already-banked ore plus what's currently in the hold.
		# Only count in-hold ore if the hold is actually carrying ore
		# (a special-cargo load doesn't count toward ore progress).
		var banked = active_quest.get("partial_delivered", 0.0)
		var in_hold = GlobalState.cargo if GlobalState.cargo_type == GlobalState.CargoType.ORE else 0.0
		return (banked + in_hold) >= active_quest["amount_required"]
	elif type == "PICKUP_SPECIAL":
		# Completed when the player has picked up the part at the outpost
		# (i.e. the special cargo is loaded in the hold).
		return active_quest.get("picked_up", false)
		
	return false


func request_new_quest(agent_faction: String, callback: Callable):
	var history_text = _load_quest_history()
	LLMInterface.request_quest_generation(agent_faction, history_text, GlobalState.player_credits, GlobalState.reputations, callback)

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

	active_quest = (adapted["state"] as Dictionary).duplicate(true)
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
	if active_quest.is_empty():
		last_validation_error = ""
		return {}
	var normalized := MissionAdapterType.normalize_legacy_state(active_quest)
	var validation := MissionAdapterType.validate_active_state(normalized)
	if not validation.is_valid():
		last_validation_error = _validation_message(validation)
		return {}
	last_validation_error = ""
	return normalized


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
	if not is_active_quest_expired():
		return false
	var expired_title := str(active_quest.get("title", "Contract"))
	var expired_type := str(active_quest.get("objective_type", "TIMED"))
	_cleanup_expired_quest()
	_log_quest_to_file(expired_title, expired_type, "Expired.")
	active_quest = {}
	print("[QuestManager] Quest expired: ", expired_title)
	quest_expired.emit(expired_title)
	return true


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
	var normalized := MissionAdapterType.normalize_legacy_state(source)
	var validation := MissionAdapterType.validate_active_state(normalized)
	if not validation.is_valid():
		last_validation_error = _validation_message(validation)
		push_warning(
			"[QuestManager] Refused invalid saved mission: %s" %
			last_validation_error
		)
		return false
	active_quest = normalized
	last_validation_error = ""
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

	if active_quest["objective_type"] == "PICKUP_SPECIAL":
		var expected_part: String = active_quest.get("part_name", "")
		if GlobalState.cargo_type != GlobalState.CargoType.SPECIAL:
			print("[QuestManager] PICKUP_SPECIAL: cannot complete, hold is empty")
			return
		if GlobalState.cargo_special.get("name", "") != expected_part:
			print("[QuestManager] PICKUP_SPECIAL: cannot complete, hold has '%s', expected '%s'" % [
				GlobalState.cargo_special.get("name", ""), expected_part])
			return
		
	var final_payout = active_quest_payout()
	GlobalState.player_credits += final_payout
	
	# Adjust faction relationship positive gain
	GlobalState.adjust_reputation(active_quest["faction"], 5.0)
	
	# If delivery quest, deduct only whatever remaining cargo is still in the hold
	# (partial deliveries already deducted cargo when they were banked)
	if active_quest["objective_type"] == "DELIVER_ORE":
		var banked = active_quest.get("partial_delivered", 0.0)
		var remaining_needed = max(0.0, active_quest["amount_required"] - banked)
		if remaining_needed > 0.0:
			GlobalState.remove_ore(remaining_needed)
	# PICKUP_SPECIAL quest: deliver the part. The hold must contain the
	# expected part — if not, refuse to complete (player has the wrong item
	# or the hold was cleared manually).
	elif active_quest["objective_type"] == "PICKUP_SPECIAL":
		GlobalState.clear_cargo()
	elif active_quest["objective_type"] == "RECOVER_COMBAT_DROP":
		if not bool(active_quest.get("ship_log_recovered", false)):
			print("[QuestManager] RECOVER_COMBAT_DROP: cannot complete, data is not recovered")
			return

	# Append to history file log
	var detail = "Completed. Payout: " + str(final_payout) + " SC. Choice selected: '" + active_quest["choice_text_selected"] + "'."
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], detail)
	
	print("[QuestManager] Quest completed successfully: ", active_quest["title"])
	quest_completed.emit()
	active_quest = {}

func abandon_quest():
	if not is_quest_active():
		return
		
	# Apply standing penalty
	GlobalState.adjust_reputation(active_quest["faction"], -3.0)
	
	# Append to history file log
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], "Abandoned.")
	
	print("[QuestManager] Quest abandoned: ", active_quest["title"])
	quest_abandoned.emit()
	active_quest = {}


func _cleanup_expired_quest() -> void:
	if not is_quest_active():
		return
	if active_quest.get("objective_type", "") == "PICKUP_SPECIAL":
		var expected_part := str(active_quest.get("part_name", ""))
		if GlobalState.cargo_type == GlobalState.CargoType.SPECIAL \
				and str(GlobalState.cargo_special.get("name", "")) \
					== expected_part:
			GlobalState.clear_cargo()


func _on_campaign_time_changed(_total_minutes: int) -> void:
	check_active_quest_expiration()

func _on_ship_destroyed(faction_name: String):
	if not is_quest_active():
		return

	if active_quest["objective_type"] == "KILL_SHIPS" and active_quest["target_faction"] == faction_name:
		active_quest["current_count"] += 1
		print("[QuestManager] Quest target killed. Progress: ", active_quest["current_count"], "/", active_quest["count_required"])
		quest_progress_updated.emit()

		# If a quest ship died and we haven't met count_required yet, spawn
		# a replacement so the player can still finish the contract. This
		# covers the case where an NPC killed a target before the player
		# got to it — previously the quest would become unfinishable.
		# Debounce 2s so wreckage settles and the spawn point doesn't
		# overlap the wreck. Capped to never exceed contract size.
		if active_quest["current_count"] < int(active_quest.get("count_required", 0)):
			get_tree().create_timer(2.0).timeout.connect(func():
				# Re-check everything after the debounce — quest may have
				# been completed, abandoned, or scene-reloaded in the meantime
				if not is_quest_active():
					return
				if active_quest["objective_type"] != "KILL_SHIPS":
					return
				if active_quest["target_faction"] != faction_name:
					return
				if active_quest["current_count"] >= int(active_quest["count_required"]):
					return
				# Count alive quest targets (meta-flagged in spawn_mission_targets)
				var alive_targets := 0
				for e in GlobalState.active_system_entities:
					if e and is_instance_valid(e) and not e.get("destroyed"):
						if e.is_in_group("ship") and e.get_meta("is_quest_target", false):
							alive_targets += 1
				# We want at least one alive target on the field so the
				# player has something to chase. Spawn if none.
				if alive_targets == 0:
					GlobalState.spawn_mission_targets(active_quest["target_faction"], 1)
					print("[QuestManager] Respawned quest target after NPC kill.")
			)
	elif active_quest["objective_type"] == "RECOVER_COMBAT_DROP" \
			and active_quest["target_faction"] == faction_name \
			and not bool(active_quest.get("ship_log_recovered", false)):
		active_quest["current_count"] += 1
		var drop_chance := clampf(
			float(active_quest.get("drop_chance", 0.33)),
			0.01,
			1.0
		)
		var recovered := randf() <= drop_chance
		print(
			"[QuestManager] Recovery wreck searched. Count: ",
			active_quest["current_count"],
			" recovered=",
			recovered
		)
		if recovered:
			active_quest["ship_log_recovered"] = true
			active_quest["ship_log_entry"] = (
				"Recovered %s from %s wreckage after %d eligible kills." % [
					str(active_quest.get("item_name", "data pack")),
					str(active_quest.get("target_faction", "hostile")),
					int(active_quest.get("current_count", 0)),
				]
			)
			GlobalState.emit_chatter(
				"SYSTEM",
				"Recovered %s into ship log. Return to %s for payout." % [
					str(active_quest.get("item_name", "data pack")),
					str(active_quest.get("turn_in_location", "station")),
				],
				Color(0.65, 1.0, 0.75)
			)
		quest_progress_updated.emit()

		if not bool(active_quest.get("ship_log_recovered", false)):
			get_tree().create_timer(2.0).timeout.connect(func():
				if not is_quest_active():
					return
				if active_quest["objective_type"] != "RECOVER_COMBAT_DROP":
					return
				if active_quest["target_faction"] != faction_name:
					return
				if bool(active_quest.get("ship_log_recovered", false)):
					return
				var alive_targets := 0
				for e in GlobalState.active_system_entities:
					if e and is_instance_valid(e) and not e.get("destroyed"):
						if e.is_in_group("ship") and e.get_meta("is_quest_target", false):
							alive_targets += 1
				if alive_targets == 0:
					GlobalState.spawn_mission_targets(active_quest["target_faction"], 1)
					print("[QuestManager] Respawned recovery target after NPC kill.")
			)

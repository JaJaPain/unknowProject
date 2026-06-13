extends Node

const HISTORY_FILE_PATH = "user://quest_history.md"

signal quest_accepted()
signal quest_progress_updated()
signal quest_completed()
signal quest_abandoned()
# Emitted by set_pickup_handoff when the LLM (or fallback) handoff line
# for a PICKUP_SPECIAL quest is ready. UIManager listens for this to fire
# the TTS pre-cache. We use a dedicated signal (vs. quest_progress_updated)
# because the line arriving is a one-shot event, not a state diff.
signal pickup_handoff_ready(line: String, voice_id: String, voice_speed: float, is_fallback: bool, npc_name: String)

var active_quest: Dictionary = {}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create history file if it does not exist
	_load_quest_history()
	# Connect to ship destroyed signals to track combat quests
	GlobalState.ship_destroyed.connect(_on_ship_destroyed)

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

func accept_quest(quest_data: Dictionary, selected_choice: Dictionary):
	# Defensive access — LLM data may be missing keys on malformed output
	var obj_data = quest_data.get("objective", {})
	var type = obj_data.get("type", "DELIVER_ORE")
	var reward_credits = obj_data.get("reward_credits", 100)
	
	var consequence = selected_choice.get("consequence", {})
	var credits_immediate = consequence.get("credits_immediate", 0)
	var rep_change = consequence.get("reputation_change", {})
	var combat_mult = max(0.5, consequence.get("combat_multiplier", 1.0))  # clamp: never 0
	var reward_mult = max(0.5, consequence.get("reward_credits_multiplier", 1.0))
	
	# Apply immediate credit rewards/penalties
	GlobalState.player_credits += credits_immediate
	
	# Apply reputation changes
	for faction in rep_change.keys():
		GlobalState.adjust_reputation(faction, rep_change[faction])
		
	# Populate active quest dictionary
	active_quest = {
		"title": quest_data.get("title", "Unnamed Contract"),
		"faction": quest_data.get("faction", "zenith"),
		"agent_name": quest_data.get("agent_name", "Broker Kaelen"),
		"dialogue": quest_data.get("dialogue", ""),
		"objective_type": type,
		"combat_multiplier": combat_mult,
		"reward_credits_multiplier": reward_mult,
		"reward_credits": reward_credits,
		"choice_text_selected": selected_choice.get("text", ""),
		"agent_response": consequence.get("dialogue_response", ""),
		"system_id": GlobalState.current_system_id,
	}
	
	if type == "KILL_SHIPS":
		active_quest["target_faction"] = obj_data.get("target_faction", "zenith")
		active_quest["count_required"] = max(1, int(obj_data.get("count_required", 3) * combat_mult))
		active_quest["current_count"] = 0
		# Schedule mission target spawn for shortly after undock (3 seconds gives time to clear the station)
		var spawn_faction = active_quest["target_faction"]
		var spawn_count = active_quest["count_required"]
		get_tree().create_timer(3.0).timeout.connect(func():
			GlobalState.spawn_mission_targets(spawn_faction, spawn_count)
		)
	elif type == "DELIVER_ORE":
		active_quest["amount_required"] = max(1.0, snapped(obj_data.get("amount_required", 20.0), 1.0))
		active_quest["partial_delivered"] = 0.0  # Tracks ore already handed in via partial shipments
	elif type == "PICKUP_SPECIAL":
		# Special-cargo pickup: go to a named outpost, talk to a named NPC,
		# collect a part, bring it back. The cargo is loaded when the player
		# actually picks it up at the outpost (mark_pickup_complete).
		active_quest["target_outpost"] = obj_data.get("target_outpost", "")
		active_quest["target_outpost_display"] = obj_data.get("target_outpost_display", active_quest["target_outpost"])
		active_quest["target_npc"] = obj_data.get("target_npc", "")
		active_quest["part_name"] = obj_data.get("part_name", "Unknown Part")
		active_quest["destination"] = obj_data.get("destination", "Grease Monkeys")
		active_quest["picked_up"] = false

	print("[QuestManager] Quest accepted: ", active_quest["title"], " type:", type, " (Difficulty multiplier: ", combat_mult, ")")
	quest_accepted.emit()


# Set the LLM-generated (or fallback) handoff line for an active
# PICKUP_SPECIAL quest. Called by UIManager once the Ollama call
# resolves (or when falling back to a canned line). Stores the line +
# voice metadata on the active quest so the dock UI at the outpost can
# play it without re-running the LLM. No-op if there's no active
# PICKUP_SPECIAL quest — the call is best-effort.
#
# `is_fallback=true` means the line is canned, not LLM-generated. Useful
# for trace logging and for any future "showed a fallback" telemetry.
func set_pickup_handoff(line: String, voice_id: String, voice_speed: float, is_fallback: bool, npc_name: String) -> void:
	if not is_quest_active() or active_quest.get("objective_type", "") != "PICKUP_SPECIAL":
		return
	active_quest["pickup_handoff_line"] = line
	active_quest["pickup_handoff_voice_id"] = voice_id
	active_quest["pickup_handoff_voice_speed"] = voice_speed
	active_quest["pickup_handoff_is_fallback"] = is_fallback
	active_quest["pickup_handoff_npc"] = npc_name
	pickup_handoff_ready.emit(line, voice_id, voice_speed, is_fallback, npc_name)


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
		
	var final_payout = int(active_quest["reward_credits"] * active_quest["reward_credits_multiplier"])
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

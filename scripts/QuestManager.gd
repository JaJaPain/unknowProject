extends Node

const HISTORY_FILE_PATH = "user://quest_history.md"
const MissionAdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)
const QuestWorldSnapshotType := preload(
	"res://scripts/domain/QuestWorldSnapshot.gd"
)
const QuestPlausibilityValidatorType := preload(
	"res://scripts/domain/QuestPlausibilityValidator.gd"
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
const StoryAgentOfferBuilderType := preload(
	"res://scripts/story/StoryAgentOfferBuilder.gd"
)

signal quest_accepted()
signal quest_accepted_details(quest_data: Dictionary)
signal quest_progress_updated()
signal quest_objective_completed_details(quest_data: Dictionary)
signal quest_completed()
signal quest_completed_details(quest_data: Dictionary)
signal quest_abandoned()
signal quest_abandoned_details(quest_data: Dictionary)
signal quest_expired(title: String)
signal quest_expired_details(quest_data: Dictionary)
signal quest_declined_details(quest_data: Dictionary)
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
const InvestigationRuntimeType := preload("res://scripts/domain/InvestigationRuntime.gd")
const MissionOutcomeType := preload("res://scripts/domain/MissionOutcome.gd")
const PlayerInventoryType := preload("res://scripts/economy/PlayerInventory.gd")
const InvestigationPlacementType := preload("res://scripts/domain/InvestigationWorldPlacement.gd")
var _investigation_runtime := InvestigationRuntimeType.new()
var _investigation_world := preload("res://scripts/domain/InvestigationWorldRuntime.gd").new()
var _investigation_world_elapsed := 0.0
## One guard per runtime mission covers completion, abandonment, expiry and
## failure. `_terminal_depth` additionally blocks synchronous cargo/reputation
## callbacks from reentering settlement while a transaction is open.
var _terminal_in_progress: Dictionary = {}
var _terminal_depth: int = 0
signal investigation_scan_updated(report: Dictionary)

func begin_investigation_scan(mission_id: String, site_id: String) -> Dictionary:
	return _investigation_runtime.begin_scan(self, mission_id, site_id)

func cancel_investigation_scan() -> void:
	_investigation_runtime.reset()

func dispatch_investigation_command(command: Dictionary) -> Dictionary:
	return _investigation_runtime.dispatch(self, command)

func _physics_process(delta: float) -> void:
	var scan_mission_id := str(_investigation_runtime._scan.get("mission_id", ""))
	var report := _investigation_runtime.tick(self, delta)
	if not report.is_empty():
		report["mission_id"] = scan_mission_id
		investigation_scan_updated.emit(report)
	_investigation_world_elapsed += delta
	if _investigation_world_elapsed >= 0.2 and not get_tree().paused:
		_investigation_world_elapsed = 0.0
		reconcile_investigation_sites()

func reconcile_investigation_sites() -> void:
	if _investigation_world.reconcile(self):
		quest_progress_updated.emit()

func investigation_site_target(mission_id: String, site_id: String) -> Node3D:
	return _investigation_world.target(mission_id, site_id)

func investigation_revealed_sites(mission_id: String) -> Array:
	return _investigation_world.public_sites(mission_id)

## Only observed evidence reaches the panel. Hidden site codes/owners never do.
func investigation_panel_view(mission_id: String) -> Dictionary:
	var mission = _collection.get_by_id(mission_id)
	if mission == null or str(mission.data.get("objective_type", "")) != "INVESTIGATE_SIGNAL": return {}
	var data: Dictionary = mission.data
	var state: Dictionary = data["investigation"]
	var result := {"title": str(data["title"]), "recipe": str(data["recipe"]), "phase": str(state["phase"]), "revision": int(state["investigation_revision"]), "sites": [], "evidence": [], "branches": [], "resolve_site_id": ""}
	var cap = MissionCapabilityRegistryType.get_for_type("INVESTIGATE_SIGNAL")
	for public_site: Dictionary in investigation_revealed_sites(mission_id):
		var row := public_site.duplicate(true)
		row["scanned"] = str(row["site_id"]) in state["scanned_site_ids"]
		row["scan_reason"] = "Search the marked area" if row["site_id"] == "search" else ""
		if row["site_id"] != "search":
			var site: Dictionary = cap._site(state, str(row["site_id"]))
			var pose := _investigation_runtime._pose(self, data, site)
			var reason := str(pose.get("reason", ""))
			if bool(pose.get("ok", false)):
				reason = preload("res://scripts/domain/ScanHoldController.gd").new()._blocking_reason(float(pose["distance"]), float(pose["speed"]), bool(pose["combat"]))
			row["scan_reason"] = reason
			if bool(row["scanned"]) and reason.is_empty(): result["resolve_site_id"] = row["site_id"]
		result["sites"].append(row)
	for evidence: Dictionary in state["evidence"]:
		var site: Dictionary = cap._site(state, str(evidence["site_id"]))
		var label := "Primary" if site.get("role", "") == "primary" else "Verification"
		var code := str(evidence.get("observed_code", ""))
		var owner_id := str(evidence.get("observed_owner_id", ""))
		if not code.is_empty(): label += " route code: " + code
		elif not owner_id.is_empty():
			var owner_name: String = preload("res://scripts/domain/PublicBoardOfferBuilder.gd")._local_faction_display(owner_id)
			label += " owner: " + (owner_name if not owner_name.is_empty() else "ownership record recovered")
		else: label += ": recorder located; ownership not yet verified"
		result["evidence"].append(label)
	var labels := {"report": "File an unverified report — 50% reward", "certify_match": "Certify that the codes match", "certify_mismatch": "Certify that the codes differ", "preserve": "Preserve the verified claim records — full reward", "liquidate": "Salvage the hardware — destroy records, spend one salvage drone, 150% reward"}
	if state["phase"] not in ["ready", "closed"]:
		for branch: String in data["branch_ids"]:
			var reason := ""
			for role: String in cap.BRANCH_REQUIREMENTS[branch]:
				if not cap._role_scanned(state, role): reason = "Scan the %s site first" % role
			var item: String = cap.BRANCH_CONSUMABLE.get(branch, "")
			if not item.is_empty() and not GlobalState.inventory.has_item(item): reason = "Requires one salvage drone"
			if reason.is_empty() and str(result["resolve_site_id"]).is_empty(): reason = "Return within 300 m of a scanned site, below 10 m/s and out of combat"
			result["branches"].append({"id": branch, "label": labels.get(branch, branch), "reason": reason})
	return result
const BOARD_COOLDOWN_MINUTES: int = 120
const EMPTY_AGENT_MEMORY_CONTEXT := (
	"No prior contracts with this agent are recorded yet. "
	+ "Treat the relationship as first-contact or strictly professional."
)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create history file if it does not exist
	_load_quest_history()
	# Connect to ship destroyed signals to track combat quests.
	# player_kill = the player landed the killing blow (counts toward the contract).
	# ship_destroyed = a NON-player kill (never counts; schedules a replacement
	# target so an NPC clearing your target can't finish — or stall — the contract).
	GlobalState.player_kill.connect(_on_player_ship_kill)
	GlobalState.ship_destroyed.connect(_on_ship_destroyed)
	CampaignClock.time_changed.connect(_on_campaign_time_changed)

func reset_for_restart():
	_investigation_runtime.reset()
	_investigation_world.reset(self)
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


# Returns campaign-scoped memory for the quest giver instead of scraping the
# legacy global markdown log. The markdown file remains useful as human-readable
# debug output, but model prompts should query structured per-campaign memory.
func filter_history_for_agent(
	agent_name: String,
	faction: String,
	agent_profile: Dictionary = {}
) -> String:
	var agent_id := LLMInterface.agent_memory_id_for_profile(
		agent_name,
		faction,
		agent_profile
	)
	return _agent_memory_context_for_id(agent_id)


func _generation_history_context(
	agent_faction: String,
	agent_profile: Dictionary = {}
) -> String:
	var agent_name := str(agent_profile.get("name", "Broker Kaelen")).strip_edges()
	if agent_name.is_empty():
		agent_name = "Broker Kaelen"
	var faction := str(
		agent_profile.get("faction", agent_faction)
	).strip_edges().to_lower()
	if faction.is_empty():
		faction = "neutral"
	return filter_history_for_agent(agent_name, faction, agent_profile)


func _agent_memory_context_for_id(agent_id: String) -> String:
	var clean_agent_id := agent_id.strip_edges()
	if clean_agent_id.is_empty():
		return EMPTY_AGENT_MEMORY_CONTEXT
	if GlobalState.campaign_agent_memory_store != null \
			and GlobalState.campaign_agent_memory_store.has_method("prompt_context"):
		var context := str(
			GlobalState.campaign_agent_memory_store.prompt_context(clean_agent_id)
		).strip_edges()
		if not context.is_empty():
			return context
	return EMPTY_AGENT_MEMORY_CONTEXT

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
	if StoryAgentOfferBuilderType.can_build(agent_profile):
		var story_offer := StoryAgentOfferBuilderType.build_offer(
			agent_faction,
			agent_profile,
			int(CampaignClock.total_minutes)
		)
		if not story_offer.is_empty():
			GenerationDiagnostics.record_content_source(
				"quest_generation",
				"template_fallback",
				"QuestManager",
				{
					"agent_faction": agent_faction,
					"agent_name": str(agent_profile.get("agent_name", "")),
					"objective_type": str(story_offer.get("objective", {}).get("type", "")),
				}
			)
			callback.call(story_offer, true)
			return
	var history_text := _generation_history_context(agent_faction, agent_profile)
	GenerationDiagnostics.record_lifecycle_timestamp(
		"quest_generation",
		"job_queued",
		"QuestManager",
		{
			"agent_faction": agent_faction,
			"agent_name": str(agent_profile.get("name", "")),
		}
	)
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
	selected_choice: Dictionary,
	defer_acceptance_events: bool = false
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
	var adapted_state: Dictionary = adapted["state"]
	if str(adapted_state.get("objective_type", "")) == "INVESTIGATE_SIGNAL":
		var placement_check := InvestigationPlacementType.check_saved_sites(
			adapted_state, InvestigationPlacementType.capture(self))
		if not bool(placement_check.get("ok", false)):
			last_validation_error = "Investigation unavailable: %s" % placement_check.get("reason", "unsafe_sites")
			return false
	if bool(adapted_state.get("public_board", false)) \
			and str(adapted_state.get("objective_type", "")) in ["DELIVERY_COURIER", "PURCHASE_DELIVERY"]:
		var recipient := GlobalState.get_delivery_recipient(str(adapted_state.get("destination_station_id", "")))
		if recipient.is_empty():
			last_validation_error = "No local recipient is available at the delivery destination"
			return false
		adapted_state["delivery_recipient_name"] = str(recipient.get("name", ""))
	# Revalidate the saved causal contract against the world as it is NOW. A job
	# can be posted honestly and become impossible before the player accepts it.
	# Missions with no contract are legacy-compatible and skip this entirely;
	# their existing delivery guards above still apply.
	var causal_check: Dictionary = QuestWorldSnapshotType.check_mission(
		adapted_state,
		QuestPlausibilityValidatorType.STAGE_ACCEPTANCE,
		str(adapted_state.get("destination_station_id", ""))
	)
	if bool(causal_check.get("checked", false)) and not bool(causal_check.get("ok", false)):
		last_validation_error = "This job is no longer possible: %s" % ", ".join(
			causal_check.get("issue_codes", [])
		)
		push_warning("[QuestManager] %s" % last_validation_error)
		return false
	if str(adapted_state.get("objective_type", "")) == "DELIVERY_COURIER" \
			and not GlobalState.can_accept_special():
		last_validation_error = "Cargo hold must be empty before accepting courier cargo"
		push_warning("[QuestManager] %s" % last_validation_error)
		return false

	var consequence = adapted["consequence"]
	if defer_acceptance_events:
		if str(adapted_state.get("objective_type", "")) != "INVESTIGATE_SIGNAL" or consequence.credits_immediate != 0 or not consequence.reputation_change.is_empty():
			last_validation_error = "Checkpointed investigation acceptance cannot have immediate side effects"
			return false
	else:
		GlobalState.add_credits(consequence.credits_immediate)
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
	elif active_quest["objective_type"] == "DELIVERY_COURIER":
		var item_name := str(active_quest.get("item_name", "Courier Package"))
		var origin_display := str(active_quest.get("origin_display", "the station"))
		var destination_display := str(
			active_quest.get("destination_display", "the destination")
		)
		var description := "Courier cargo accepted at %s. Deliver to %s." % [
			origin_display,
			destination_display,
		]
		if not GlobalState.accept_special(
			item_name,
			description,
			origin_display,
			destination_display
		):
			_collection.remove(new_mission.runtime_id)
			last_validation_error = "Cargo hold rejected courier package"
			push_warning("[QuestManager] %s" % last_validation_error)
			return false
		if bool(active_quest.get("public_board", false)):
			GlobalState.cargo_special["delivery_assignment"] = {
				"runtime_id": new_mission.runtime_id,
				"destination_station_id": str(active_quest.get("destination_station_id", "")),
				"recipient_name": str(active_quest.get("delivery_recipient_name", "")),
			}

	# Discretionary pacing is recorded once, here, in the acceptance transaction
	# that just succeeded. Tutorial and required story jobs map to no family.
	_record_discretionary_family(active_quest)
	print(
		"[QuestManager] Quest accepted: ",
		active_quest["title"],
		" type:",
		active_quest["objective_type"],
		" (Difficulty multiplier: ",
		active_quest["combat_multiplier"],
		")"
	)
	if not defer_acceptance_events:
		announce_accepted_mission(str(active_quest["runtime_id"]))
	return true

## Append this mission's discretionary family to the pacing window. In memory
## only: the acceptance checkpoint (or the next save) is what makes it durable,
## and a rolled-back acceptance restores the story state that preceded it.
func _record_discretionary_family(quest_data: Dictionary) -> void:
	if not is_instance_valid(StoryManager) or not StoryManager.has_method("record_accepted_discretionary_family"):
		return
	StoryManager.record_accepted_discretionary_family(quest_data)


func announce_accepted_mission(runtime_id: String) -> void:
	var mission = _collection.get_by_id(runtime_id)
	if mission == null: return
	_increment_mission_history_revision("accepted", mission.data)
	quest_accepted.emit()
	quest_accepted_details.emit(mission.data.duplicate(true))


func decline_quest(
	quest_data: Dictionary = {},
	reason: String = "declined"
) -> void:
	var declined_quest := quest_data.duplicate(true)
	declined_quest["declined_time_minutes"] = CampaignClock.total_minutes
	declined_quest["decline_reason"] = reason
	_increment_mission_history_revision("declined", declined_quest)
	quest_declined_details.emit(declined_quest)


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


func clear_active_kaelen_reaction_bundle() -> void:
	if not is_quest_active():
		return
	active_quest.erase("kaelen_reaction_bundle")


func store_active_kaelen_reaction_bundle(
	mission_runtime_id: String,
	completion_line: String,
	abandon_line: String,
	source_id: String = "llm_kaelen_reaction"
) -> bool:
	if not is_quest_active():
		return false
	var clean_runtime_id := mission_runtime_id.strip_edges()
	if clean_runtime_id.is_empty() \
			or str(active_quest.get("runtime_id", "")) != clean_runtime_id:
		return false
	var clean_completion := completion_line.strip_edges()
	var clean_abandon := abandon_line.strip_edges()
	if clean_completion.is_empty() and clean_abandon.is_empty():
		return false
	active_quest["kaelen_reaction_bundle"] = {
		"mission_runtime_id": clean_runtime_id,
		"completion_line": clean_completion,
		"abandon_line": clean_abandon,
		"source_id": source_id.strip_edges(),
		"generated_time_minutes": CampaignClock.total_minutes,
	}
	return true


func active_kaelen_reaction_line(line_kind: String) -> String:
	if not is_quest_active():
		return ""
	var bundle: Dictionary = active_quest.get("kaelen_reaction_bundle", {}) \
		if active_quest.get("kaelen_reaction_bundle", {}) is Dictionary else {}
	if bundle.is_empty():
		return ""
	if str(bundle.get("mission_runtime_id", "")) \
			!= str(active_quest.get("runtime_id", "")):
		return ""
	match line_kind.strip_edges():
		"completion":
			return str(bundle.get("completion_line", "")).strip_edges()
		"abandon":
			return str(bundle.get("abandon_line", "")).strip_edges()
		_:
			return ""


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
	if _terminal_depth > 0:
		return false
	for m in _collection.get_all_active():
		if not bool(m.data.get("is_timed", false)):
			continue
		if CampaignClock.total_minutes < int(m.data.get("deadline_time_minutes", 0)):
			continue
		var rid: String = m.runtime_id
		if not _begin_terminal(rid):
			continue
		var expired_quest: Dictionary = m.data.duplicate(true)
		expired_quest["expired_time_minutes"] = CampaignClock.total_minutes
		var expired_title := str(m.data.get("title", "Contract"))
		var expired_type := str(m.data.get("objective_type", "TIMED"))
		# Nonfocused missions expire through this same guarded transaction, and
		# the snapshot's focus is what a failed settlement restores.
		var snapshot := _capture_settlement_snapshot()
		var signals_were_blocked := GlobalState.is_blocking_signals()
		GlobalState.set_block_signals(true)
		var instance_state: int = int(m.state)
		_record_board_cooldown(m.data)
		_cleanup_mission(m)
		m.transition_to(MissionInstanceType.State.EXPIRED)
		_collection.remove(rid)
		var settled := _settle_terminal(expired_quest, "expired", 0)
		if not bool(settled.get("ok", false)):
			_restore_settlement_snapshot(snapshot, m, instance_state)
			_report_failed_settlement(expired_title, str(settled.get("reason", "")))
			GlobalState.set_block_signals(signals_were_blocked)
			_end_terminal(rid)
			continue
		GlobalState.set_block_signals(signals_were_blocked)
		_end_terminal(rid)
		GlobalState.cargo_changed.emit(GlobalState.cargo)
		_log_quest_to_file(expired_title, expired_type, "Expired.")
		print("[QuestManager] Quest expired: ", expired_title)
		_increment_mission_history_revision("expired", expired_quest)
		var expired_outcome: Dictionary = settled.get("outcome", {}) if settled.get("outcome", {}) is Dictionary else {}
		expired_quest["terminal_outcome_id"] = str(expired_outcome.get("id", ""))
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
	if str(active_quest.get("objective_type", "")) == "INVESTIGATE_SIGNAL":
		var investigation: Dictionary = active_quest.get("investigation", {})
		var branch := str(investigation.get("branch_id", ""))
		# Terms frozen at publication win: the player is paid what the card said,
		# and no pressure modifier is reapplied here.
		var frozen: Variant = investigation.get("branch_payouts", {})
		if frozen is Dictionary and (frozen as Dictionary).has(branch):
			return maxi(0, int((frozen as Dictionary)[branch]))
		var capability = MissionCapabilityRegistryType.get_for_type("INVESTIGATE_SIGNAL")
		var fraction: Array = capability._payout_for(investigation, branch, {})
		return int(floor(payout * float(fraction[0]) / float(fraction[1])))
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
	_investigation_runtime.reset()
	if source.is_empty():
		_investigation_world.reset(self)
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
	_investigation_world.reset(self)
	_collection.add(inst)
	last_validation_error = ""
	return true


func restore_all_quests(source_array: Array) -> bool:
	# Do not erase current missions or silently drop an invalid investigation.
	# The caller can surface its recoverable load error with the old state intact.
	for item in source_array:
		if item is Dictionary and str(item.get("objective_type", "")) == "INVESTIGATE_SIGNAL":
			if not can_restore_active_quest(item):
				return false
	_investigation_runtime.reset()
	_collection.clear()
	_investigation_world.reset(self)
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


func _increment_mission_history_revision(
	event_type: String,
	mission_data: Dictionary
) -> void:
	if is_instance_valid(StoryManager) \
			and StoryManager.has_method("increment_mission_history_revision"):
		StoryManager.increment_mission_history_revision(event_type, mission_data)


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
	active_quest["partial_delivery_count"] = int(
		active_quest.get("partial_delivery_count", 0)
	) + 1
	active_quest["last_partial_delivery_amount"] = to_deliver
	print("[QuestManager] Partial delivery: %.1f m³ banked. Total so far: %.1f / %.1f" % [
		to_deliver, active_quest["partial_delivered"], active_quest["amount_required"]])
	var focused = _collection.get_focused()
	if focused != null:
		_mark_objective_ready_if_completed(focused)
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
	var focused = _collection.get_focused()
	if focused != null:
		_mark_objective_ready_if_completed(focused)
	quest_progress_updated.emit()
	return true

## ---------------------------------------------------------------------------
## Guarded terminal transaction (plan P3 deliverable B)
##
## Every terminal path stages its durable effects in memory, checkpoints them at
## a legal safe boundary, and rolls the whole thing back if that checkpoint
## fails, leaving the mission retryable. No completion or reward signal is
## emitted, and no prose is scheduled, until the result is committed.
## ---------------------------------------------------------------------------

func _capture_settlement_snapshot() -> Dictionary:
	var instance = _collection.get_focused()
	var story: Dictionary = {}
	if is_instance_valid(StoryManager) and StoryManager.has_method("capture_story_state_for_checkpoint"):
		story = StoryManager.capture_story_state_for_checkpoint()
	return {
		"credits": int(GlobalState.player_credits),
		"reputations": GlobalState.reputations.duplicate(true),
		"cargo": float(GlobalState.cargo),
		"cargo_type": int(GlobalState.cargo_type),
		"cargo_special": GlobalState.cargo_special.duplicate(true),
		"inventory": GlobalState.inventory.to_dict(),
		"board_cooldowns": _board_cooldowns.duplicate(true),
		"story_state": story,
		"focused_runtime_id": str(instance.runtime_id) if instance != null else "",
	}


func _restore_settlement_snapshot(snapshot: Dictionary, instance = null, instance_state: int = -1) -> void:
	GlobalState.player_credits = int(snapshot.get("credits", GlobalState.player_credits))
	GlobalState.reputations = (snapshot.get("reputations", {}) as Dictionary).duplicate(true)
	GlobalState.cargo = float(snapshot.get("cargo", 0.0))
	GlobalState.cargo_type = int(snapshot.get("cargo_type", GlobalState.CargoType.EMPTY))
	GlobalState.cargo_special = (snapshot.get("cargo_special", {}) as Dictionary).duplicate(true)
	GlobalState.inventory = PlayerInventoryType.from_dict(snapshot.get("inventory", {}))
	GlobalState.cargo_changed.emit(GlobalState.cargo)
	_board_cooldowns = (snapshot.get("board_cooldowns", {}) as Dictionary).duplicate(true)
	if is_instance_valid(StoryManager) and StoryManager.has_method("restore_story_state_snapshot"):
		StoryManager.restore_story_state_snapshot(snapshot.get("story_state", {}))
	if instance != null:
		# The mission goes back exactly as it was, so the player may retry it.
		if instance_state >= 0:
			instance.state = instance_state
		_collection.add(instance)
		var focus := str(snapshot.get("focused_runtime_id", ""))
		if not focus.is_empty():
			_collection.focus(focus)


## The station the player is actually docked at, or null when in flight.
func _settlement_station() -> Node3D:
	if not is_instance_valid(GlobalState.player) or not bool(GlobalState.player.get("is_docked")):
		return null
	var ui = GlobalState.get_ui_manager()
	if ui == null or not is_instance_valid(ui.current_station):
		return null
	return ui.current_station


## Commit the staged result. Returns {ok, durable, reason, outcome}. `ok` false
## means the caller must roll back; `durable` false with `ok` true means the
## change is live but its save is pending a legal safe boundary.
func _settle_terminal(quest_data: Dictionary, terminal_state: String, credits_paid: int) -> Dictionary:
	if not is_instance_valid(StoryManager) or not StoryManager.has_method("stage_mission_outcome"):
		return {"ok": true, "durable": false, "reason": "story_manager_unavailable"}
	var scene = get_tree().current_scene
	var campaign_id := ""
	if scene != null and "active_campaign_slot_id" in scene:
		campaign_id = str(scene.active_campaign_slot_id)
	var built: Dictionary = MissionOutcomeType.build(
		quest_data, terminal_state, credits_paid, int(CampaignClock.total_minutes), campaign_id
	)
	if not bool(built.get("ok", false)):
		var build_reason := str(built.get("reason", "unbuildable_outcome"))
		if _carries_typed_story_binding(quest_data):
			# New-style data that will not validate fails closed. Terminating it
			# anyway would silently drop a bound consequence.
			return {"ok": false, "durable": false, "reason": "invalid_typed_outcome:" + build_reason}
		# A legacy or unbound mission still terminates, but nothing was
		# persisted, so this is compatibility handling and NOT a durable record.
		return {"ok": true, "durable": false, "compatibility": true,
			"reason": "legacy_unbuildable_outcome:" + build_reason}
	var outcome: Dictionary = built["outcome"]
	var staged: Dictionary = StoryManager.stage_mission_outcome(outcome, quest_data)
	if not bool(staged.get("ok", false)):
		# A duplicate or conflicting terminal record refuses the whole settlement
		# rather than paying twice for one mission.
		return {"ok": false, "durable": false, "reason": str(staged.get("reason", "outcome_rejected")), "outcome": outcome}
	if not bool(staged.get("changed", false)):
		return {"ok": true, "durable": true, "reason": str(staged.get("reason", "")), "outcome": outcome}
	var station := _settlement_station()
	if station != null and scene != null and scene.has_method("request_safe_checkpoint"):
		if not bool(scene.request_safe_checkpoint("mission_settled", station)):
			return {"ok": false, "durable": false, "reason": "checkpoint_failed", "outcome": outcome}
		StoryManager.commit_mission_outcome_finish()
		return {"ok": true, "durable": true, "reason": "", "outcome": outcome}
	# In flight: apply once in the running state and keep a pending record. The
	# next legal safe checkpoint carries the whole result; nothing here pretends
	# an in-flight save is docked or persists tactical pose.
	StoryManager.mark_consequence_save_pending()
	return {"ok": true, "durable": false, "reason": "pending_safe_checkpoint", "outcome": outcome}


## Open the terminal transaction for one mission. Refuses a second entry for the
## same mission and any reentry while another settlement is open.
func _begin_terminal(runtime_id: String) -> bool:
	if _terminal_depth > 0 or _terminal_in_progress.has(runtime_id):
		return false
	_terminal_in_progress[runtime_id] = true
	_terminal_depth += 1
	return true


func _end_terminal(runtime_id: String) -> void:
	_terminal_in_progress.erase(runtime_id)
	_terminal_depth = maxi(0, _terminal_depth - 1)


## True while a settlement is staging or committing. Callers that mutate durable
## state from a signal handler must consult this before acting.
func is_terminal_transaction_in_progress() -> bool:
	return _terminal_depth > 0


## True when a mission carries the typed story bindings a new-style outcome is
## built from. Such a mission must never fall through to legacy termination.
func _carries_typed_story_binding(quest_data: Dictionary) -> bool:
	if not str(quest_data.get("pressure_id", "")).is_empty():
		return true
	var investigation: Variant = quest_data.get("investigation", {})
	if investigation is Dictionary and not (investigation as Dictionary).is_empty():
		return true
	var metadata: Variant = quest_data.get("narrative_metadata", {})
	if not metadata is Dictionary:
		return false
	for field in ["desire_id", "cause_id", "cause_faction_id"]:
		if not str((metadata as Dictionary).get(field, "")).is_empty():
			return true
	return false


func _report_failed_settlement(title: String, reason: String) -> void:
	push_warning("[QuestManager] Settlement rolled back for '%s': %s" % [title, reason])


func complete_quest():
	if not is_quest_active() or not is_quest_completed():
		return
	if _terminal_depth > 0:
		# A synchronous cargo/reputation callback cannot reenter settlement.
		return
	if str(active_quest.get("objective_type", "")) == "INVESTIGATE_SIGNAL" and not _can_turn_in_investigation(active_quest):
		return

	var cap = MissionCapabilityRegistryType.get_for_type(
		active_quest["objective_type"]
	)
	var completion_hints: Dictionary = {}
	if cap:
		var hints := cap.on_complete(active_quest)
		if hints.has("block"):
			print("[QuestManager] %s: cannot complete, %s" % [
				active_quest["objective_type"], hints["block"]])
			return
		completion_hints = hints

	var completed_id := str(active_quest.get("runtime_id", ""))
	if not _begin_terminal(completed_id):
		return
	# Stage every durable effect before anything is announced or written. The
	# snapshot is taken BEFORE any capability cleanup or world mutation.
	var snapshot := _capture_settlement_snapshot()
	var signals_were_blocked := GlobalState.is_blocking_signals()
	GlobalState.set_block_signals(true)
	GlobalState.clear_intro_tutorial_player_protection()
	_apply_completion_hints(completion_hints)
	var completed_quest: Dictionary = active_quest.duplicate(true)
	var instance = _collection.get_by_id(completed_id)
	var instance_state: int = int(instance.state) if instance != null else -1
	var final_payout = active_quest_payout()
	GlobalState.add_credits(final_payout)
	GlobalState.adjust_reputation(active_quest["faction"], 5.0)
	completed_quest["completed_time_minutes"] = CampaignClock.total_minutes
	completed_quest["final_payout"] = final_payout
	_record_board_cooldown(active_quest)
	var focused = _collection.get_focused()
	if focused:
		_transition_to_completed(focused)
	_collection.remove(completed_id)
	var settled := _settle_terminal(completed_quest, "completed", int(final_payout))
	if not bool(settled.get("ok", false)):
		# The kit consumed at resolution is restored with everything else, so a
		# retry neither double-consumes it nor pays twice.
		_restore_settlement_snapshot(snapshot, instance, instance_state)
		_report_failed_settlement(str(completed_quest.get("title", "")), str(settled.get("reason", "")))
		GlobalState.set_block_signals(signals_were_blocked)
		_end_terminal(completed_id)
		return
	_investigation_runtime.reset()
	GlobalState.set_block_signals(signals_were_blocked)
	_end_terminal(completed_id)
	# Past this line the transaction is committed: everything below is
	# notification, logging and presentation, never staged state.
	GlobalState.cargo_changed.emit(GlobalState.cargo)
	var settled_faction := str(completed_quest.get("faction", ""))
	GlobalState.reputation_changed.emit(settled_faction, GlobalState.reputations.get(settled_faction, 0.0))
	var detail = "Completed. Payout: " + str(final_payout) + " SC. Choice selected: '" + str(completed_quest.get("choice_text_selected", "")) + "'."
	_log_quest_to_file(str(completed_quest["title"]), str(completed_quest["objective_type"]), detail)
	print("[QuestManager] Quest completed successfully: ", completed_quest["title"])
	if not bool(settled.get("durable", true)):
		push_warning("[QuestManager] Completion consequences are live but their save is pending a safe checkpoint.")
	_increment_mission_history_revision("completed", completed_quest)
	var settled_outcome: Dictionary = settled.get("outcome", {}) if settled.get("outcome", {}) is Dictionary else {}
	completed_quest["terminal_outcome_id"] = str(settled_outcome.get("id", ""))
	quest_completed.emit()
	quest_completed_details.emit(completed_quest)


func _can_turn_in_investigation(data: Dictionary) -> bool:
	if GlobalState.current_system_id != str(data.get("system_id", "")) or not is_instance_valid(GlobalState.player) or not bool(GlobalState.player.get("is_docked")):
		return false
	var ui = GlobalState.get_ui_manager()
	if ui == null or not is_instance_valid(ui.current_station):
		return false
	var station = ui.current_station
	var expected := str(data.get("turn_in_station_id", ""))
	return (station.has_method("get_world_id") and str(station.get_world_id()) == expected) or GlobalState.resolve_outpost_id(station) == expected or str(station.name) == expected

func abandon_quest():
	if not is_quest_active():
		return
	if _terminal_depth > 0:
		return
	var abandoned_id := str(active_quest.get("runtime_id", ""))
	if not _begin_terminal(abandoned_id):
		return

	# Snapshot first: capability cleanup below releases courier cargo, and a
	# failed settlement has to give that cargo back with everything else.
	var snapshot := _capture_settlement_snapshot()
	var signals_were_blocked := GlobalState.is_blocking_signals()
	GlobalState.set_block_signals(true)
	GlobalState.clear_intro_tutorial_player_protection()
	var abandoned_quest: Dictionary = active_quest.duplicate(true)
	var instance = _collection.get_by_id(abandoned_id)
	var instance_state: int = int(instance.state) if instance != null else -1
	GlobalState.adjust_reputation(active_quest["faction"], -3.0)
	abandoned_quest["abandoned_time_minutes"] = CampaignClock.total_minutes
	_record_board_cooldown(active_quest)
	var focused = _collection.get_focused()
	if focused:
		# Abandoning a courier drops its special cargo through the same
		# capability cleanup that expiry uses, rather than stranding it.
		_cleanup_mission(focused)
		focused.transition_to(MissionInstanceType.State.ABANDONED)
	_collection.remove(abandoned_id)
	var settled := _settle_terminal(abandoned_quest, "abandoned", 0)
	if not bool(settled.get("ok", false)):
		_restore_settlement_snapshot(snapshot, instance, instance_state)
		_report_failed_settlement(str(abandoned_quest.get("title", "")), str(settled.get("reason", "")))
		GlobalState.set_block_signals(signals_were_blocked)
		_end_terminal(abandoned_id)
		return
	_investigation_runtime.reset()
	GlobalState.set_block_signals(signals_were_blocked)
	_end_terminal(abandoned_id)
	GlobalState.cargo_changed.emit(GlobalState.cargo)
	var abandoned_faction := str(abandoned_quest.get("faction", ""))
	GlobalState.reputation_changed.emit(abandoned_faction, GlobalState.reputations.get(abandoned_faction, 0.0))
	_log_quest_to_file(str(abandoned_quest["title"]), str(abandoned_quest["objective_type"]), "Abandoned.")
	print("[QuestManager] Quest abandoned: ", abandoned_quest["title"])
	_increment_mission_history_revision("abandoned", abandoned_quest)
	var abandoned_outcome: Dictionary = settled.get("outcome", {}) if settled.get("outcome", {}) is Dictionary else {}
	abandoned_quest["terminal_outcome_id"] = str(abandoned_outcome.get("id", ""))
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

func _on_player_ship_kill(faction_name: String) -> void:
	_dispatch_ship_destroyed(faction_name, true)


func _on_ship_destroyed(faction_name: String) -> void:
	# Reached only for NON-player kills now (see NPCShip: player kills go through
	# player_kill). Passing by_player=false lets KILL_SHIPS refuse the credit and
	# request a replacement target instead.
	_dispatch_ship_destroyed(faction_name, false)


func _dispatch_ship_destroyed(faction_name: String, by_player: bool) -> void:
	for m in _collection.get_all_active():
		var cap = MissionCapabilityRegistryType.get_for_type(
			m.data.get("objective_type", "")
		)
		if cap == null:
			continue

		var hints := cap.handle_event(
			m.data, "ship_destroyed", {"faction": faction_name, "by_player": by_player}
		)
		if hints.is_empty():
			continue

		if hints.get("progress_changed", false):
			print("[QuestManager] Quest progress: ", m.data.get("current_count", 0),
				"/", m.data.get("count_required", 0))
			if _is_intro_tutorial_contract(m.data) \
					and int(m.data.get("current_count", 0)) >= int(m.data.get("count_required", 1)):
				GlobalState.clear_intro_tutorial_player_protection()
			_mark_objective_ready_if_completed(m)
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


# COMPLETED is only reachable through READY_TO_TURN_IN. Instances that get
# here still ACTIVE (saves from before the ready-state fix, or resolutions
# like the comms bribe that skip the progress path) take the hop first.
func _transition_to_completed(instance) -> void:
	if instance == null:
		return
	if instance.state == MissionInstanceType.State.ACTIVE:
		instance.transition_to(MissionInstanceType.State.READY_TO_TURN_IN)
	instance.transition_to(MissionInstanceType.State.COMPLETED)


func _mark_objective_ready_if_completed(mission) -> void:
	if mission == null:
		return
	if bool(mission.data.get("objective_completed_notified", false)):
		return
	var cap = MissionCapabilityRegistryType.get_for_type(
		mission.data.get("objective_type", "")
	)
	if cap == null or not cap.is_completed(mission.data):
		return
	mission.data["objective_completed_notified"] = true
	mission.data["objective_completed_time_minutes"] = CampaignClock.total_minutes
	mission.data["objective_complete_pending_turn_in"] = true
	# READY_TO_TURN_IN persists through save/reload via _instance_state.
	# No current capability can regress a completed objective; if one ever
	# does, READY_TO_TURN_IN -> ACTIVE is a valid transition back.
	mission.transition_to(MissionInstanceType.State.READY_TO_TURN_IN)
	quest_objective_completed_details.emit(mission.data.duplicate(true))


func _is_intro_tutorial_contract(data: Dictionary) -> bool:
	return str(data.get("title", "")) == "Clean and Easy" \
		and str(data.get("objective_type", "")) == "KILL_SHIPS" \
		and str(data.get("target_faction", "")) == "reavers"


# Public wrapper: the starter mission uses authored dialogue instead of the
# small model, so callers outside QuestManager can detect it too.
func is_intro_tutorial_contract(data: Dictionary) -> bool:
	return _is_intro_tutorial_contract(data)


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
			GlobalState.add_credits(bribe)
			GlobalState.adjust_reputation(focused.data.get("faction", "neutral"), -3.0)
			GlobalState.adjust_reputation(target_faction, 2.0)
			_despawn_ceasefire_targets(target_faction)
			_transition_to_completed(focused)
			var rid: String = focused.runtime_id
			_record_board_cooldown(focused.data)
			_log_quest_to_file(str(focused.data.get("title", "")), "TARGET_WITH_COMMS_REVERSAL", "Resolved: accepted bribe (%d SC)." % bribe)
			bribe_quest["completed_time_minutes"] = CampaignClock.total_minutes
			bribe_quest["final_payout"] = bribe
			bribe_quest["outcome_detail"] = "accepted_bribe"
			_collection.remove(rid)
			_increment_mission_history_revision("completed", bribe_quest)
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
			_increment_mission_history_revision("abandoned", walkaway_quest)
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
	var item_id := str(hints.get("remove_inventory_item", ""))
	var item_quantity := int(hints.get("remove_inventory_quantity", 0))
	if not item_id.is_empty() and item_quantity > 0:
		GlobalState.inventory.remove(item_id, item_quantity)
	if hints.get("clear_cargo", false):
		GlobalState.clear_cargo()


func _apply_cleanup_hints(hints: Dictionary) -> void:
	if hints.get("clear_cargo", false):
		GlobalState.clear_cargo()
	var cf_faction: String = str(hints.get("clear_ceasefire_faction", ""))
	if cf_faction != "":
		_set_ceasefire_for_faction(cf_faction, false)


const RESPAWN_DELAY_SECONDS := 20.0        # gap before a replacement target arrives
const RESPAWN_MIN_PLAYER_DISTANCE := 800.0  # spawn far from the player + wreckage


# Persistent mission ships normally restore with the system. Older or
# interrupted saves can have an active KILL_SHIPS contract without those
# entities, though, which would otherwise leave the contract impossible.
func reconcile_missing_kill_ship_targets_after_restore() -> int:
	var plans := plan_missing_kill_ship_target_respawns(
		GlobalState.active_system_entities
	)
	if plans.is_empty():
		return 0
	var focused = _collection.get_focused()
	var previous_runtime_id: String = (
		focused.runtime_id if focused != null else ""
	)
	var restored_count := 0
	for plan in plans:
		var runtime_id := str(plan.get("runtime_id", ""))
		if not runtime_id.is_empty():
			_collection.focus(runtime_id)
		var target_faction := str(plan.get("target_faction", ""))
		var spawn_count := int(plan.get("spawn_count", 0))
		if target_faction.is_empty() or spawn_count <= 0:
			continue
		GlobalState.spawn_mission_targets(
			target_faction,
			spawn_count,
			RESPAWN_MIN_PLAYER_DISTANCE
		)
		restored_count += spawn_count
	if not previous_runtime_id.is_empty():
		_collection.focus(previous_runtime_id)
	if restored_count > 0:
		print(
			"[QuestManager] Restored %d missing mission target(s) after load."
			% restored_count
		)
	return restored_count


# Kept separate from spawning so the recovery decision is deterministic and can
# be checked without loading a game scene.
func plan_missing_kill_ship_target_respawns(entities: Array) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	for mission in _collection.get_all_active():
		var data: Dictionary = mission.data
		if str(data.get("objective_type", "")) != "KILL_SHIPS":
			continue
		var capability = MissionCapabilityRegistryType.get_for_type("KILL_SHIPS")
		if capability == null or capability.is_completed(data):
			continue
		var faction := str(data.get("target_faction", "")).strip_edges()
		if faction.is_empty() or _has_alive_quest_target_for_faction(entities, faction):
			continue
		var remaining := maxi(
			1,
			int(data.get("count_required", 1)) - int(data.get("current_count", 0))
		)
		plans.append({
			"runtime_id": mission.runtime_id,
			"target_faction": faction,
			"spawn_count": remaining,
		})
	return plans


func _has_alive_quest_target_for_faction(entities: Array, faction: String) -> bool:
	for entity in entities:
		if entity is Dictionary:
			var snapshot := entity as Dictionary
			if bool(snapshot.get("is_quest_target", false)) \
					and bool(snapshot.get("is_ship", true)) \
					and not bool(snapshot.get("destroyed", false)) \
					and str(snapshot.get("faction", "")) == faction:
				return true
			continue
		if entity == null or not is_instance_valid(entity):
			continue
		if entity.is_in_group("ship") \
				and bool(entity.get_meta("is_quest_target", false)) \
				and not bool(entity.get("destroyed")) \
				and str(entity.get("faction")) == faction:
			return true
	return false


func _schedule_respawn(faction: String) -> void:
	get_tree().create_timer(RESPAWN_DELAY_SECONDS).timeout.connect(func():
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
		if not _has_alive_quest_target_for_faction(
			GlobalState.active_system_entities,
			faction
		):
			GlobalState.spawn_mission_targets(faction, 1, RESPAWN_MIN_PLAYER_DISTANCE)
			print("[QuestManager] Respawned quest target far from player after NPC kill.")
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

class_name PremiseDirector
extends Node

## Runs premise-card arcs in a live campaign (plan Sections 3.1-3.2, 4.1).
##
## Owned by GameRoot like QuietMomentDirector. All story logic lives in the
## pure classes next to this file; this node only keeps the campaign's arc
## state, talks to the per-machine card history, and turns arcs into board
## postings. It never reads the scene tree itself: callers pass a `world`
## snapshot (PremiseWorldSnapshot.capture() in the game, a plain dict in tests).
##
## Save: to_dict()/load_from_dict() ride in the checkpoint runtime state, so
## arcs roll back with everything else when the player reloads.

signal decision_ready(arc_id: String, decision: Dictionary)
signal arc_resolved(arc_id: String, resolution_id: String)

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const HistoryType := preload("res://scripts/story/premise/PremiseCardHistoryStore.gd")
const SelectorType := preload("res://scripts/story/premise/PremiseCardSelector.gd")
const ProfileType := preload("res://scripts/story/premise/SystemProfile.gd")
const ArcsType := preload("res://scripts/story/premise/ArcEngine.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")
const ComposerType := preload("res://scripts/story/premise/PremiseMissionComposer.gd")

const SAVE_VERSION := 1
## How many live arcs of each scale a system carries at once.
const TARGET_PER_SYSTEM := {"personal": 1, "local": 1}
## Campaign-wide: one regional story at a time.
const TARGET_REGIONAL := 1
## If the player never engages, the world settles an arc after this long
## (campaign minutes) with its default resolution.
const IGNORE_BUDGET_MINUTES := {"personal": 3 * 1440, "local": 6 * 1440, "regional": 12 * 1440}

var enabled := true
var library = null
var history_path := HistoryType.DEFAULT_PATH
var campaign_seed := 0
var state: Dictionary = ArcsType.empty_state()
var _history: Dictionary = HistoryType.empty_history()
var _history_loaded := false
# System display names seen this session, for filling {system} in decision text.
var _system_names: Dictionary = {}


func _init() -> void:
	library = LibraryType.new()
	var result = library.load_from_dir()
	if not result.is_valid():
		push_warning("[PremiseDirector] Premise deck unavailable: %s" % result.summary())
		enabled = false


func reset_for_new_campaign(seed_value: int = 0) -> void:
	campaign_seed = seed_value
	state = ArcsType.empty_state()


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "campaign_seed": campaign_seed, "arcs": state.duplicate(true)}


func load_from_dict(data: Dictionary) -> void:
	if int(data.get("version", 0)) != SAVE_VERSION or not data.get("arcs") is Dictionary:
		state = ArcsType.empty_state()
		return
	campaign_seed = int(data.get("campaign_seed", 0))
	state = (data["arcs"] as Dictionary).duplicate(true)


# --- the world asks -----------------------------------------------------------

## Base profile for a system (deterministic; no save needed).
func profile_for(world: Dictionary) -> Dictionary:
	return ProfileType.generate(str(world.get("system_id", "")), int(world.get("system_seed", 0)),
		str(world.get("star_type", "yellow")), bool(world.get("is_first_system", false)))


## Starts arcs so this system has its share of live stories. Returns new arc ids.
func ensure_arcs(world: Dictionary, now_minute: int) -> Array[String]:
	var started: Array[String] = []
	_system_names[str(world.get("system_id", ""))] = str(world.get("system_display", ""))
	if not enabled or not bool(world.get("post_tutorial", false)) or bool(world.get("is_first_system", false)):
		return started
	var system_id := str(world.get("system_id", ""))
	var profile := profile_for(world)
	var live_here := {"personal": 0, "local": 0}
	var regional := 0
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if str(a["scale"]) == "regional":
			regional += 1
		elif str(a["system_id"]) == system_id:
			live_here[str(a["scale"])] = int(live_here.get(str(a["scale"]), 0)) + 1
	var wanted: Array[String] = []
	for scale in ["local", "personal"]:
		for _i in maxi(0, int(TARGET_PER_SYSTEM[scale]) - int(live_here.get(scale, 0))):
			wanted.append(scale)
	if regional < TARGET_REGIONAL:
		wanted.append("regional")
	for scale in wanted:
		var arc_id := _start_one(world, profile, scale, now_minute)
		if not arc_id.is_empty():
			started.append(arc_id)
	return started


## Board postings for the arcs in this system. Records card history the first
## time an arc's opening is shown.
func board_postings(world: Dictionary, now_minute: int) -> Array[Dictionary]:
	var postings: Array[Dictionary] = []
	if not enabled:
		return postings
	var system_id := str(world.get("system_id", ""))
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if str(a["system_id"]) != system_id and str(a["scale"]) != "regional":
			continue
		var card: Dictionary = library.get_card(str(a["card_id"]))
		for ref in ArcsType.current_offers(state, library, arc_id):
			var offer: Dictionary = ComposerType.compose(ref, card, a["cast"], world, campaign_seed)
			if offer.is_empty() or bool(offer.get("premise_needs_completion", false)):
				continue
			offer["objective_summary"] = str(offer["objective"].get("type", "")).replace("_", " ").capitalize()
			postings.append(_posting(arc_id, ref, offer))
			if not bool(a.get("shown", false)):
				_record_shown(arc_id, str(a["card_id"]))
				a = ArcsType.arc(state, arc_id)
	return postings


## A mission the game finished (or dropped). Returns true if it belonged to an arc.
func on_mission_terminal(quest_data: Dictionary, terminal_state: String, now_minute: int) -> bool:
	var ref := _arc_ref(quest_data)
	if ref.is_empty():
		return false
	var branch := str((quest_data.get("objective", {}) as Dictionary).get("branch_id", quest_data.get("branch_id", "")))
	state = ArcsType.apply_mission_result(state, library, ref["arc_id"], int(ref["beat"]), int(ref["mission_index"]),
		terminal_state, branch, now_minute)
	_after_change(ref["arc_id"])
	return true


func pending_decisions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for arc_id in ArcsType.active_arc_ids(state):
		var d := ArcsType.pending_decision(state, library, arc_id)
		if not d.is_empty():
			d["arc_id"] = arc_id
			var a := ArcsType.arc(state, arc_id)
			var names := {"system_display": str(_system_names.get(str(a["system_id"]), "this system"))}
			d["prompt"] = CastingType.fill_text(str(d.get("prompt", "")), a["cast"], names)
			for option in d.get("options", []):
				option["label"] = CastingType.fill_text(str(option.get("label", "")), a["cast"], names)
			out.append(d)
	return out


func apply_decision(arc_id: String, option_id: String, now_minute: int) -> void:
	var d := ArcsType.pending_decision(state, library, arc_id)
	if d.is_empty():
		return
	if d["kind"] == "finding":
		state = ArcsType.apply_finding(state, library, arc_id, option_id, now_minute)
	else:
		state = ArcsType.apply_choice(state, library, arc_id, option_id, now_minute)
	_after_change(arc_id)


## Arcs the player never engaged with settle on their own.
func tick(now_minute: int) -> void:
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		var engaged := not (a.get("done", {}) as Dictionary).is_empty() or int(a.get("beat", 1)) > 1
		if engaged:
			continue
		var budget := int(IGNORE_BUDGET_MINUTES.get(str(a["scale"]), 4320))
		if now_minute - int(a.get("started_minute", now_minute)) >= budget:
			var card: Dictionary = library.get_card(str(a["card_id"]))
			state = ArcsType.resolve(state, library, arc_id, str(card.get("default_resolution", "")), now_minute)
			_after_change(arc_id)


# --- internals ------------------------------------------------------------------

func _start_one(world: Dictionary, profile: Dictionary, scale: String, now_minute: int) -> String:
	_ensure_history()
	var situation := {
		"quirks": profile.get("quirks", []),
		"states": ArcsType.live_states(state, profile),
		"faction_count": (world.get("factions", []) as Array).size(),
		"seeds": ArcsType.seed_tags(state, str(world.get("system_id", ""))),
		"scale": scale,
		"excluded_ids": state.get("used_card_ids", []),
	}
	var seed_value := hash("%d|%s|%d" % [campaign_seed, world.get("system_id", ""), int(state.get("next_seq", 1))])
	var picks := SelectorType.pick(library, _history, situation, seed_value, 1)
	if picks.is_empty():
		return ""
	var card: Dictionary = library.get_card(picks[0])
	var arc_id_preview := "arc.%04d" % int(state.get("next_seq", 1))
	var cast := CastingType.cast_card(card, world, seed_value, arc_id_preview)
	var started := ArcsType.start_arc(state, card, str(world.get("system_id", "")), cast, now_minute)
	state = started["state"]
	return str(started["arc_id"])


func _posting(arc_id: String, ref: Dictionary, offer: Dictionary) -> Dictionary:
	return {
		"template_id": "board.premise.%s.b%d.m%d" % [str(ref["card_id"]).trim_prefix("premise."), int(ref["beat"]), int(ref["mission_index"])],
		"enabled": true,
		"title": str(offer["title"]),
		"poster": str(offer["agent_name"]),
		"body": str(offer["dialogue"]),
		"objective": str(offer["objective_summary"]),
		"base_reward": int(offer["objective"].get("reward_credits", 0)),
		"duration_minutes": 0,
		"urgent_multiplier": 1.0,
		"premise_posting": true,
		"arc_id": arc_id,
		"quest_data": offer,
		"required_placeholders": [],
		"placeholder_values": {},
	}


static func _arc_ref(quest_data: Dictionary) -> Dictionary:
	var meta: Dictionary = quest_data.get("narrative_metadata", {}) if quest_data.get("narrative_metadata") is Dictionary else {}
	var arc_id := str(meta.get("story_thread_id", quest_data.get("story_thread_id", "")))
	var beat_id := str(meta.get("story_beat_id", quest_data.get("story_beat_id", "")))
	if not arc_id.begins_with("arc.") or not beat_id.begins_with("premise."):
		return {}
	# beat_id = "<card_id>:b<beat>:m<index>"
	var parts := beat_id.split(":")
	if parts.size() != 3 or not parts[1].begins_with("b") or not parts[2].begins_with("m"):
		return {}
	return {"arc_id": arc_id, "card_id": parts[0], "beat": int(parts[1].substr(1)), "mission_index": int(parts[2].substr(1))}


func _after_change(arc_id: String) -> void:
	var a := ArcsType.arc(state, arc_id)
	if a.is_empty():
		return
	if str(a["status"]) == "resolved":
		arc_resolved.emit(arc_id, str(a["resolution_id"]))
		return
	var d := ArcsType.pending_decision(state, library, arc_id)
	if not d.is_empty():
		decision_ready.emit(arc_id, d)


func _ensure_history() -> void:
	if _history_loaded:
		return
	_history = HistoryType.load_history(history_path)["history"]
	_history_loaded = true


func _record_shown(arc_id: String, card_id: String) -> void:
	_ensure_history()
	state = ArcsType.mark_shown(state, arc_id)
	_history = HistoryType.record_shown(_history, card_id)
	_history = HistoryType.advance_cycle_if_due(_history, library.ids())
	HistoryType.save_history(_history, history_path)

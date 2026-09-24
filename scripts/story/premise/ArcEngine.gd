class_name ArcEngine
extends RefCounted

## Runs premise-card arcs (design: docs/arc_engine_design.md).
##
## The whole campaign story state is one Dictionary (see empty_state()), so it
## saves as-is. Every function takes a state and returns a NEW state; nothing
## is modified in place. Cards come from a PremiseCardLibrary.

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const ProfileType := preload("res://scripts/story/premise/SystemProfile.gd")

const STATE_VERSION := 1
const LEDGER_LIMIT := 200

const FAILURE_WORDS := ["abandon", "fail", "ignored", "lost", "escape", "declin", "expire"]
const OFFER_WORDS := ["offer", "took", "accept", "bribe", "deal", "spare", "stand", "paid"]


static func empty_state() -> Dictionary:
	return {
		"version": STATE_VERSION, "next_seq": 1, "arcs": {}, "used_card_ids": [],
		"system_changes": {}, "system_laws": {}, "price_effects": [],
		"standing": {}, "fates": {}, "deeds": [], "seeds": [], "ledger": [],
	}


# --- starting and reading arcs ---------------------------------------------

## Starts an arc for `card` in `system_id` with a cast {role_id: {entity_id, display_name, kind, ...}}.
## Returns {state, arc_id}.
static func start_arc(state: Dictionary, card: Dictionary, system_id: String, cast: Dictionary, now_minute: int) -> Dictionary:
	var next := state.duplicate(true)
	var arc_id := "arc.%04d" % int(next.get("next_seq", 1))
	next["next_seq"] = int(next.get("next_seq", 1)) + 1
	var first_beat := int((card.get("beats", [{}]) as Array)[0].get("n", 1))
	next["arcs"][arc_id] = {
		"id": arc_id, "card_id": str(card.get("id", "")), "system_id": system_id,
		"scale": str(card.get("scale", "")), "status": "active", "cast": cast.duplicate(true),
		"beat": first_beat, "stage": "missions", "done": {}, "finding_mission": -1,
		"resolution_id": "", "started_minute": now_minute, "resolved_minute": -1, "shown": false,
	}
	var used: Array = next["used_card_ids"]
	if not str(card.get("id", "")) in used:
		used.append(str(card.get("id", "")))
	_ledger(next, "%s | start %s @%s" % [arc_id, card.get("id", ""), system_id])
	return {"state": next, "arc_id": arc_id}


static func active_arc_ids(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for arc_id in (state.get("arcs", {}) as Dictionary).keys():
		if str(state["arcs"][arc_id].get("status", "")) == "active":
			out.append(str(arc_id))
	out.sort()
	return out


static func arc(state: Dictionary, arc_id: String) -> Dictionary:
	return (state.get("arcs", {}) as Dictionary).get(arc_id, {})


## Missions the player can take right now for this arc.
## Each: {arc_id, card_id, beat, mission_index, mission, competing}.
static func current_offers(state: Dictionary, library, arc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := arc(state, arc_id)
	if a.is_empty() or a["status"] != "active" or a["stage"] != "missions":
		return out
	var card: Dictionary = library.get_card(a["card_id"])
	var beat := LibraryType.beat(card, int(a["beat"]))
	var missions: Array = beat.get("missions", [])
	var competing: bool = str(beat.get("missions_mode", "all")) == "one_of"
	for i in missions.size():
		if (a["done"] as Dictionary).has("m%d" % i):
			continue
		out.append({"arc_id": arc_id, "card_id": a["card_id"], "beat": int(a["beat"]),
			"mission_index": i, "mission": (missions[i] as Dictionary).duplicate(true), "competing": competing})
	return out


## The decision the player owes this arc, if any:
## {kind: "finding"|"choice", prompt, options: [{id, label}]}; {} when none.
static func pending_decision(state: Dictionary, library, arc_id: String) -> Dictionary:
	var a := arc(state, arc_id)
	if a.is_empty() or a["status"] != "active":
		return {}
	var card: Dictionary = library.get_card(a["card_id"])
	var beat := LibraryType.beat(card, int(a["beat"]))
	if a["stage"] == "choice":
		var pc: Dictionary = beat.get("player_choice", {}) if beat.get("player_choice") is Dictionary else {}
		var options: Array[Dictionary] = []
		for o in pc.get("options", []):
			options.append({"id": str(o.get("id", "")), "label": str(o.get("label", ""))})
		return {"kind": "choice", "prompt": str(pc.get("prompt", "")), "options": options}
	if a["stage"] == "finding":
		var mission: Dictionary = (beat.get("missions", []) as Array)[int(a["finding_mission"])]
		var options: Array[Dictionary] = []
		for tag in mission.get("outcome_tags", []):
			options.append({"id": str(tag), "label": humanize(str(tag))})
		return {"kind": "finding", "prompt": str(mission.get("reason", "")), "options": options}
	return {}


# --- outcomes ----------------------------------------------------------------

## Maps a finished game mission to one of the card mission's outcome tags.
## Returns "" when the arc should fall to its default resolution, and
## "?finding" when the player must pick among several tags.
static func outcome_tag_for(mission: Dictionary, terminal_state: String, branch_id: String = "") -> String:
	var tags: Array = mission.get("outcome_tags", [])
	if terminal_state != "completed":
		for tag in tags:
			if _has_word(str(tag), FAILURE_WORDS):
				return str(tag)
		return ""
	var successes: Array = []
	for tag in tags:
		if not _has_word(str(tag), FAILURE_WORDS):
			successes.append(str(tag))
	if str(mission.get("verb", "")) == "comms_reversal":
		var offer_tag := ""
		var fight_tag := ""
		for tag in successes:
			if _has_word(tag, OFFER_WORDS) and offer_tag.is_empty():
				offer_tag = tag
			elif fight_tag.is_empty():
				fight_tag = tag
		if branch_id == "accept_bribe" and not offer_tag.is_empty():
			return offer_tag
		return fight_tag if not fight_tag.is_empty() else (successes[0] if not successes.is_empty() else "")
	if successes.size() == 1:
		return successes[0]
	if successes.size() > 1:
		return "?finding"
	return ""


## Applies a finished game mission to its arc.
static func apply_mission_result(state: Dictionary, library, arc_id: String, beat_n: int, mission_index: int,
		terminal_state: String, branch_id: String, now_minute: int) -> Dictionary:
	var a := arc(state, arc_id)
	if a.is_empty() or a["status"] != "active" or a["stage"] != "missions" or int(a["beat"]) != beat_n:
		return state
	var card: Dictionary = library.get_card(a["card_id"])
	var missions: Array = LibraryType.beat(card, beat_n).get("missions", [])
	if mission_index < 0 or mission_index >= missions.size():
		return state
	var tag := outcome_tag_for(missions[mission_index], terminal_state, branch_id)
	if tag.is_empty():
		return resolve(state, library, arc_id, str(card.get("default_resolution", "")), now_minute)
	var next := state.duplicate(true)
	if tag == "?finding":
		next["arcs"][arc_id]["stage"] = "finding"
		next["arcs"][arc_id]["finding_mission"] = mission_index
		return next
	return _settle_mission(next, library, arc_id, mission_index, tag, now_minute)


## The player picked a finding (one of the mission's outcome tags).
static func apply_finding(state: Dictionary, library, arc_id: String, tag: String, now_minute: int) -> Dictionary:
	var a := arc(state, arc_id)
	if a.is_empty() or a["stage"] != "finding":
		return state
	var card: Dictionary = library.get_card(a["card_id"])
	var mission: Dictionary = (LibraryType.beat(card, int(a["beat"])).get("missions", []) as Array)[int(a["finding_mission"])]
	if not tag in mission.get("outcome_tags", []):
		return state
	var next := state.duplicate(true)
	next["arcs"][arc_id]["stage"] = "missions"
	var index := int(a["finding_mission"])
	next["arcs"][arc_id]["finding_mission"] = -1
	return _settle_mission(next, library, arc_id, index, tag, now_minute)


## The player answered the beat's player_choice.
static func apply_choice(state: Dictionary, library, arc_id: String, option_id: String, now_minute: int) -> Dictionary:
	var a := arc(state, arc_id)
	if a.is_empty() or a["stage"] != "choice":
		return state
	var card: Dictionary = library.get_card(a["card_id"])
	var pc: Variant = LibraryType.beat(card, int(a["beat"])).get("player_choice")
	if not pc is Dictionary:
		return state
	for option in (pc as Dictionary).get("options", []):
		if str(option.get("id", "")) == option_id:
			var next := state.duplicate(true)
			_ledger(next, "%s | choice %s" % [arc_id, option_id])
			return _follow(next, library, arc_id, str(option.get("leads_to", "")), now_minute, true)
	return state


## Resolves an arc: applies the resolution's consequences and seeds.
static func resolve(state: Dictionary, library, arc_id: String, resolution_id: String, now_minute: int) -> Dictionary:
	var a := arc(state, arc_id)
	if a.is_empty() or a["status"] != "active":
		return state
	var card: Dictionary = library.get_card(a["card_id"])
	var res := LibraryType.resolution(card, resolution_id)
	if res.is_empty():
		res = LibraryType.resolution(card, str(card.get("default_resolution", "")))
	var next := state.duplicate(true)
	var system_id := str(a["system_id"])
	var cast: Dictionary = a["cast"]
	for q in res.get("consequences", []):
		var target := str((cast.get(str(q.get("target", "")), {}) as Dictionary).get("entity_id", q.get("target", "")))
		match str(q.get("type", "")):
			"standing":
				next["standing"][target] = int(next["standing"].get(target, 0)) + int(q.get("delta", 0))
			"cast_fate":
				var fates: Array = next["fates"].get(target, [])
				fates.append(str(q.get("fate", "")))
				next["fates"][target] = fates
			"deed":
				(next["deeds"] as Array).append({"tag": str(q.get("tag", "")), "public_summary": str(q.get("public_summary", "")),
					"system_id": system_id, "arc_id": arc_id, "cast": cast.duplicate(true)})
			"system_state":
				var change: Dictionary = next["system_changes"].get(system_id, {"add": [], "remove": []})
				for s in q.get("add", []):
					(change["remove"] as Array).erase(str(s))
					if not str(s) in change["add"]:
						(change["add"] as Array).append(str(s))
				for s in q.get("remove", []):
					(change["add"] as Array).erase(str(s))
					if not str(s) in change["remove"]:
						(change["remove"] as Array).append(str(s))
				next["system_changes"][system_id] = change
			"law_change":
				var laws: Dictionary = next["system_laws"].get(system_id, {})
				laws[str(q.get("law", ""))] = str(q.get("change", ""))
				next["system_laws"][system_id] = laws
			"economy":
				(next["price_effects"] as Array).append({"system_id": system_id, "good": str(q.get("good", "")),
					"ore": str(q.get("ore", "")), "price": str(q.get("price", "")), "arc_id": arc_id})
	for tag in res.get("seeds", []):
		(next["seeds"] as Array).append({"tag": str(tag), "system_id": system_id, "arc_id": arc_id})
	var record: Dictionary = next["arcs"][arc_id]
	record["status"] = "resolved"
	record["stage"] = "done"
	record["resolution_id"] = str(res.get("id", resolution_id))
	record["resolved_minute"] = now_minute
	_ledger(next, "%s | resolved %s -> %s" % [arc_id, a["card_id"], record["resolution_id"]])
	return next


## The player was shown this arc's opening; the caller also records the card
## in PremiseCardHistoryStore.
static func mark_shown(state: Dictionary, arc_id: String) -> Dictionary:
	if arc(state, arc_id).is_empty():
		return state
	var next := state.duplicate(true)
	next["arcs"][arc_id]["shown"] = true
	return next


## Current states of a system: its base profile plus every arc's changes.
static func live_states(state: Dictionary, base_profile: Dictionary) -> Array:
	var change: Dictionary = (state.get("system_changes", {}) as Dictionary).get(str(base_profile.get("system_id", "")), {})
	return ProfileType.apply_changes(base_profile, change.get("add", []), change.get("remove", []))["states"]


## Seeds left in (or, for regional stories, near) a system, newest first.
static func seed_tags(state: Dictionary, system_id: String = "") -> Array[String]:
	var out: Array[String] = []
	var seeds: Array = state.get("seeds", [])
	for i in range(seeds.size() - 1, -1, -1):
		var s: Dictionary = seeds[i]
		if system_id.is_empty() or str(s.get("system_id", "")) == system_id:
			if not str(s.get("tag", "")) in out:
				out.append(str(s.get("tag", "")))
	return out


static func humanize(tag: String) -> String:
	var words := tag.replace("_", " ").strip_edges()
	return words.substr(0, 1).to_upper() + words.substr(1) if not words.is_empty() else words


# --- internals -----------------------------------------------------------------

static func _settle_mission(next: Dictionary, library, arc_id: String, mission_index: int, tag: String, now_minute: int) -> Dictionary:
	var a: Dictionary = next["arcs"][arc_id]
	var card: Dictionary = library.get_card(a["card_id"])
	var beat := LibraryType.beat(card, int(a["beat"]))
	var mission: Dictionary = (beat.get("missions", []) as Array)[mission_index]
	a["done"]["m%d" % mission_index] = tag
	_ledger(next, "%s | b%d m%d %s" % [arc_id, int(a["beat"]), mission_index, tag])
	var route := str((mission.get("routes", {}) as Dictionary).get(tag, "next"))
	var competing: bool = str(beat.get("missions_mode", "all")) == "one_of"
	if route != "next":
		return _follow(next, library, arc_id, route, now_minute, false)
	if competing or (a["done"] as Dictionary).size() >= (beat.get("missions", []) as Array).size():
		return _after_beat(next, library, arc_id, now_minute)
	return next


## Follows a route target: "next", "beat:N" or "resolution:X".
static func _follow(next: Dictionary, library, arc_id: String, target: String, now_minute: int, from_choice: bool) -> Dictionary:
	if target.begins_with("resolution:"):
		return resolve(next, library, arc_id, target.trim_prefix("resolution:"), now_minute)
	if target.begins_with("beat:"):
		return _enter_beat(next, library, arc_id, int(target.trim_prefix("beat:")), now_minute)
	# "next"
	if from_choice:
		return _enter_beat(next, library, arc_id, int(next["arcs"][arc_id]["beat"]) + 1, now_minute)
	return _after_beat(next, library, arc_id, now_minute)


## The current beat's missions are settled: go to its choice, or the next beat.
static func _after_beat(next: Dictionary, library, arc_id: String, now_minute: int) -> Dictionary:
	var a: Dictionary = next["arcs"][arc_id]
	var card: Dictionary = library.get_card(a["card_id"])
	var beat := LibraryType.beat(card, int(a["beat"]))
	if beat.get("player_choice") is Dictionary and not (beat["player_choice"] as Dictionary).is_empty():
		a["stage"] = "choice"
		return next
	return _enter_beat(next, library, arc_id, int(a["beat"]) + 1, now_minute)


static func _enter_beat(next: Dictionary, library, arc_id: String, beat_n: int, now_minute: int) -> Dictionary:
	var a: Dictionary = next["arcs"][arc_id]
	var card: Dictionary = library.get_card(a["card_id"])
	if LibraryType.beat(card, beat_n).is_empty():
		# Ran off the end without a resolution: the world settles it.
		return resolve(next, library, arc_id, str(card.get("default_resolution", "")), now_minute)
	a["beat"] = beat_n
	a["stage"] = "missions"
	a["done"] = {}
	a["finding_mission"] = -1
	return next


static func _has_word(tag: String, words: Array) -> bool:
	for w in words:
		if tag.to_lower().contains(str(w)):
			return true
	return false


static func _ledger(next: Dictionary, line: String) -> void:
	var ledger: Array = next.get("ledger", [])
	ledger.append(line)
	while ledger.size() > LEDGER_LIMIT:
		ledger.pop_front()
	next["ledger"] = ledger

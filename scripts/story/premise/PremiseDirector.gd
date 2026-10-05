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
## The main story has named its Hidden Hand; the confrontation arc is starting.
signal main_story_locked(display_name: String, arc_id: String)
## A main story (season) has ended; a new one begins with the next arcs.
signal season_closed(season: int, resolution_id: String)

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const HistoryType := preload("res://scripts/story/premise/PremiseCardHistoryStore.gd")
const SelectorType := preload("res://scripts/story/premise/PremiseCardSelector.gd")
const ProfileType := preload("res://scripts/story/premise/SystemProfile.gd")
const ArcsType := preload("res://scripts/story/premise/ArcEngine.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")
const ComposerType := preload("res://scripts/story/premise/PremiseMissionComposer.gd")
const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const ForgeType := preload("res://scripts/story/premise/HiddenHandForge.gd")
const ShowType := preload("res://scripts/story/premise/Showrunner.gd")
const RadioType := preload("res://scripts/story/premise/RadioBroadcaster.gd")
const WriterType := preload("res://scripts/story/premise/LineWriter.gd")
const VoiceType := preload("res://scripts/story/premise/VoiceDNA.gd")
const CastType := preload("res://scripts/story/premise/RecurringCast.gd")
const GatewayType := preload("res://scripts/ai/LocalModelGateway.gd")
const FaintType := preload("res://scripts/story/activities/FaintTransmissions.gd")
const TwistsType := preload("res://scripts/story/premise/MissionTwists.gd")
const FalloutType := preload("res://scripts/story/premise/FailureFallout.gd")
const LeverageType := preload("res://scripts/story/premise/Leverage.gd")
const EncountersType := preload("res://scripts/story/premise/RecurringEncounters.gd")
const FactionDNAType := preload("res://scripts/story/premise/FactionDNA.gd")

const SAVE_VERSION := 1
## How many live arcs of each scale a system carries at once.
const TARGET_PER_SYSTEM := {"personal": 1, "local": 1}
## Campaign-wide: one regional story at a time.
const TARGET_REGIONAL := 1
## If the player never engages, the world settles an arc after this long
## (campaign minutes) with its default resolution.
const IGNORE_BUDGET_MINUTES := {"personal": 3 * 1440, "local": 6 * 1440, "regional": 12 * 1440}
## Stories nobody touched also fade by PLAY: after this many more systems
## visited (personal/local only once you've left their system). The campaign
## clock moves on events only (about 5 in-game hours per real hour), so the
## day budgets above almost never ran out in a session and the board filled
## up (campaign spine plan, section 7).
const IGNORE_BUDGET_VISITS := {"personal": 2, "local": 2, "regional": 6}
## No more than this many live stories at once.
const MAX_LIVE_ARCS := 6
## Once the evidence is ready, the lock waits at most this many systems for
## the prime suspect's other stories to end.
const LOCK_WAIT_VISITS := 2

var enabled := true
var library = null
var history_path := HistoryType.DEFAULT_PATH
var campaign_seed := 0
var state: Dictionary = ArcsType.empty_state()
var _history: Dictionary = HistoryType.empty_history()
var _history_loaded := false
# System display names seen this session, for filling {system} in decision text.
var _system_names: Dictionary = {}
## Ask the local story model to explain the main story's lock (background,
## non-blocking). Off, or outside the scene tree (tests), the code lock is used.
var use_showrunner := true
var _showrunner_busy := false
var _method_coverage: Dictionary = {}
var _last_world: Dictionary = {}
# Radio items already aired, per system, this session.
var _aired: Dictionary = {}
## Ask the small model to turn director notes into spoken lines (background,
## one at a time, while docked). Off, or outside the scene tree, the board
## shows the director note and nothing is voiced.
var use_line_writer := true
## Override for the line model ("" = LocalModelGateway's small model).
var line_model := ""
const LINE_ATTEMPTS := 2
var _line_queue: Array[Dictionary] = []
var _line_busy := false
## Breathe in, breathe out: model work (lines, the Showrunner) runs only while
## this returns true (GameRoot wires GenerationWindow.is_open). Unset = always.
var window_probe: Callable = Callable()


func _window_open() -> bool:
	return not window_probe.is_valid() or bool(window_probe.call())


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
	# Forged cards (the Hidden Hand confrontations) live in the save, not the deck.
	for card_id in (state.get("synthetic_cards", {}) as Dictionary).keys():
		library.cards[card_id] = (state["synthetic_cards"][card_id] as Dictionary).duplicate(true)


# --- the world asks -----------------------------------------------------------

## Base profile for a system (deterministic; no save needed).
func profile_for(world: Dictionary) -> Dictionary:
	return ProfileType.generate(str(world.get("system_id", "")), int(world.get("system_seed", 0)),
		str(world.get("star_type", "yellow")), bool(world.get("is_first_system", false)), int(world.get("system_depth", -1)))


## Starts arcs so this system has its share of live stories. Returns new arc ids.
func ensure_arcs(world: Dictionary, now_minute: int) -> Array[String]:
	var started: Array[String] = []
	_system_names[str(world.get("system_id", ""))] = str(world.get("system_display", ""))
	if not enabled or not bool(world.get("post_tutorial", false)) or bool(world.get("is_first_system", false)):
		return started
	_last_world = world
	if not HandType.is_active(state):
		if _method_coverage.is_empty():
			_method_coverage = HandType.method_coverage(library)
		state = HandType.begin_season(state, campaign_seed, now_minute, _method_coverage)
	var system_id := str(world.get("system_id", ""))
	_count_visit(system_id, now_minute)
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
	var live := ArcsType.active_arc_ids(state).size()
	for scale in wanted:
		if live >= MAX_LIVE_ARCS:
			break
		var arc_id := _start_one(world, profile, scale, now_minute)
		if not arc_id.is_empty():
			started.append(arc_id)
			live += 1
	return started


## A new system: count it, let untouched stories from systems behind fade, and
## time the lock's wait on a busy suspect.
func _count_visit(system_id: String, now_minute: int) -> void:
	if str(state.get("visit_system", "")) == system_id:
		return
	state["visit_system"] = system_id
	state["visits"] = int(state.get("visits", 0)) + 1
	_fade_by_play(now_minute)
	var story := HandType.main_story(state)
	if HandType.evidence_ready(state):
		if not story.has("evidence_ready_visit"):
			state["main_story"]["evidence_ready_visit"] = int(state["visits"])
		elif int(state["visits"]) - int(story["evidence_ready_visit"]) >= LOCK_WAIT_VISITS:
			state["main_story"]["lock_wait_over"] = true


func _engaged(a: Dictionary) -> bool:
	return not (a.get("done", {}) as Dictionary).is_empty() or int(a.get("beat", 1)) > 1


func _fade_by_play(now_minute: int) -> void:
	var here := str(state.get("visit_system", ""))
	var visits := int(state.get("visits", 0))
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if _engaged(a) or arc_id == str(HandType.main_story(state).get("confrontation_arc_id", "")):
			continue
		var scale := str(a["scale"])
		if scale != "regional" and str(a["system_id"]) == here:
			continue
		if visits - int(a.get("started_visit", visits)) >= int(IGNORE_BUDGET_VISITS.get(scale, 2)):
			var card: Dictionary = library.get_card(str(a["card_id"]))
			state = ArcsType.resolve(state, library, arc_id, str(card.get("default_resolution", "")), now_minute)
			_after_change(arc_id)


## Board postings for the arcs in this system. Records card history the first
## time an arc's opening is shown.
func board_postings(world: Dictionary, now_minute: int) -> Array[Dictionary]:
	var postings: Array[Dictionary] = []
	if not enabled:
		return postings
	for item in _live_offers(world):
		var arc_id := str(item["arc_id"])
		var offer: Dictionary = item["offer"]
		offer["objective_summary"] = str(offer["objective"].get("type", "")).replace("_", " ").capitalize()
		var written := written_line(arc_id, offer)
		if not written.is_empty():
			offer["premise_director_note"] = str(offer["dialogue"])
			offer["dialogue"] = written
			offer["voice_profile"] = VoiceType.register(VoiceType.for_person(str(offer.get("agent_id", "")), str(offer.get("faction", ""))))
		var posting := _posting(arc_id, item["ref"], offer)
		if not written.is_empty():
			posting["voice_line"] = written
			posting["voice_profile"] = offer["voice_profile"]
		var odd := _odd_details(arc_id, ArcsType.arc(state, arc_id), world)
		if not odd.is_empty():
			posting["body"] = str(posting["body"]) + "\n\n" + odd
		# The main story leads the board (campaign spine plan, fix 4).
		if arc_id == str(HandType.main_story(state).get("confrontation_arc_id", "")):
			postings.push_front(posting)
		else:
			postings.append(posting)
		if not bool(ArcsType.arc(state, arc_id).get("shown", false)):
			_record_shown(arc_id, str(item["card"]["id"]))
			state = HandType.mark_arc_threads_seen(state, arc_id, now_minute, 1)
			state = HandType.update_draft(state)
	_maybe_lock(world, now_minute)
	prepare_lines(world)
	return postings


## Composed offers for the arcs live in this system (no side effects):
## [{arc_id, ref, card, offer}].
func _live_offers(world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var system_id := str(world.get("system_id", ""))
	# Complications read the system's quirks (a storm window only where storms are).
	var world_with_quirks := world.duplicate()
	if not world_with_quirks.has("quirks"):
		world_with_quirks["quirks"] = profile_for(world).get("quirks", [])
	# Rivals for the rival twist: the recurring cast (alive, free, not busy).
	world_with_quirks["rival_candidates"] = CastType.candidates(state)
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if str(a["system_id"]) != system_id and str(a["scale"]) != "regional":
			continue
		var card: Dictionary = library.get_card(str(a["card_id"]))
		for ref in ArcsType.current_offers(state, library, arc_id):
			var offer: Dictionary = ComposerType.compose(ref, card, a["cast"], world_with_quirks, campaign_seed)
			if offer.is_empty() or bool(offer.get("premise_needs_completion", false)):
				continue
			out.append({"arc_id": arc_id, "ref": ref, "card": card, "offer": offer})
	return out


# --- spoken lines ---------------------------------------------------------------

static func line_key(arc_id: String, offer: Dictionary) -> String:
	return "%s|%s" % [arc_id, str(offer.get("story_beat_id", ""))]


## The written line for an offer, or "" (not written yet, or it failed and the
## board falls back to the director note).
func written_line(arc_id: String, offer: Dictionary) -> String:
	var entry: Dictionary = (state.get("written_lines", {}) as Dictionary).get(line_key(arc_id, offer), {})
	return str(entry.get("line", "")) if str(entry.get("status", "")) == "ok" else ""


## Queues line writing for this system's offers. Called on arrival (and from
## the board); runs in the background, one request at a time.
func prepare_lines(world: Dictionary) -> void:
	if not enabled or not use_line_writer or not is_inside_tree():
		return
	var lines: Dictionary = state.get("written_lines", {})
	for item in _live_offers(world):
		var offer: Dictionary = item["offer"]
		var key := line_key(str(item["arc_id"]), offer)
		var entry: Dictionary = lines.get(key, {})
		if str(entry.get("status", "")) in ["ok", "failed"] or _line_queue.any(func(j): return j["key"] == key):
			continue
		var job := line_job(key, offer, item["card"], ArcsType.arc(state, str(item["arc_id"]))["cast"], world)
		job["brief"]["history"] = CastType.history_note(state, str(offer.get("agent_id", "")), _system_names, str(item["arc_id"]))
		_line_queue.append(job)
	_pump_lines()


static func line_job(key: String, offer: Dictionary, card: Dictionary, cast: Dictionary, world: Dictionary) -> Dictionary:
	return {"key": key, "private": str(offer.get("premise_private_fact", "")),
		"brief": WriterType.brief_for_offer(offer, card, cast, world),
		"agent_id": str(offer.get("agent_id", "")), "faction": str(offer.get("faction", ""))}


func _pump_lines() -> void:
	if _line_busy or _showrunner_busy or not is_inside_tree() or _line_queue.is_empty() or not _window_open():
		return
	var job: Dictionary = _line_queue.pop_front()
	_line_busy = true
	var http := HTTPRequest.new()
	http.timeout = 60.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		http.queue_free()
		_line_busy = false
		var checked := {"ok": false, "reason": "http", "line": ""}
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			checked = WriterType.check_line(WriterType.response_text(reply.get_string_from_utf8()), job["brief"], job["private"])
		store_line(job, checked)
		_pump_lines())
	GatewayType.note_request("premise_line_writer")
	if http.request(LocalModelGatewayURL(), ["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(WriterType.build_briefing_request(job["brief"], line_model))) != OK:
		http.queue_free()
		_line_busy = false


## Records a checked line (public for tests). A failed check gets one retry,
## then the offer keeps its director note for good.
func store_line(job: Dictionary, checked: Dictionary) -> void:
	var lines: Dictionary = (state.get("written_lines", {}) as Dictionary).duplicate(true)
	var entry: Dictionary = lines.get(job["key"], {"attempts": 0})
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	if bool(checked["ok"]):
		entry["status"] = "ok"
		entry["line"] = str(checked["line"])
		_precache_voice(str(checked["line"]), job)
	elif int(entry["attempts"]) >= LINE_ATTEMPTS:
		entry["status"] = "failed"
		entry["reason"] = str(checked["reason"])
	else:
		_line_queue.append(job)
	lines[job["key"]] = entry
	state["written_lines"] = lines


## Renders the line's audio now, so the board plays it without waiting.
func _precache_voice(line: String, job: Dictionary) -> void:
	if not is_inside_tree():
		return
	var speech := get_node_or_null("/root/SpeechService")
	if speech == null:
		return
	speech.call("cache", line, VoiceType.register(VoiceType.for_person(str(job["agent_id"]), str(job["faction"]))))


## The main story's loose threads for this arc, as a line the pilot notices.
func _odd_details(arc_id: String, arc_record: Dictionary, world: Dictionary) -> String:
	var lines: PackedStringArray = []
	for t in HandType.threads_for_arc(state, arc_id):
		if bool(t.get("seen", false)):
			lines.append(CastingType.fill_text(str(t["detail"]), arc_record.get("cast", {}), world))
	return "" if lines.is_empty() else "Something doesn't sit right: " + " ".join(lines)


## A job failed, was abandoned or ran out of time: record what it does to
## the system it was in (FailureFallout). Returns the record, or {}.
func record_failure(quest_data: Dictionary, terminal_state: String, now_minute: int, names: Dictionary) -> Dictionary:
	var f := FalloutType.for_mission(quest_data, terminal_state, now_minute, names)
	if f.is_empty():
		return {}
	var records: Array = FalloutType.prune(state.get("fallout", []) as Array, now_minute)
	for r in records:
		if str(r.get("id", "")) == str(f["id"]):
			return {}
	records.append(f)
	state["fallout"] = records
	return f


## The captain arrived in a system: maybe someone from an earlier story comes
## to find them (RecurringEncounters). Returns the encounter, or {}.
func on_arrival_encounter(system_id: String) -> Dictionary:
	if not enabled:
		return {}
	var result := EncountersType.on_arrival(state, state.get("encounters", {}), _system_names,
		hash("%d|%s" % [campaign_seed, system_id]))
	state["encounters"] = result["log"]
	return result["encounter"]


## A bitter old contact came after the captain and was destroyed: the feud is
## over for good.
func end_feud(person_id: String, display_name: String, system_id: String) -> void:
	state = EncountersType.feud_ended(state, person_id, display_name, system_id)


## A reveal twist showed the captain a client's secret: keep it as leverage.
## Returns the new entry, or {} (none, or already kept).
func record_leverage(mission_data: Dictionary, now_minute: int) -> Dictionary:
	var entry := LeverageType.from_twist(mission_data, now_minute)
	if entry.is_empty():
		return {}
	var before: Array = state.get("leverage", [])
	var after := LeverageType.add(before, entry)
	if after.size() == before.size():
		return {}
	state["leverage"] = after
	return entry


## Keeps a leverage entry from any source (Leverage.make). Returns it, or {}
## when empty or already kept.
func record_leverage_entry(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var before: Array = state.get("leverage", [])
	var after := LeverageType.add(before, entry)
	if after.size() == before.size():
		return {}
	state["leverage"] = after
	return entry


func leverage_items() -> Array:
	return LeverageType.unused(state.get("leverage", []) as Array)


## Uses a leverage entry ("sell", "expose" or "blackmail") in `world` (the
## current system). Returns the effect for GameRoot to apply; the entry is
## spent and any deed recorded here. A blackmail job that cannot be placed
## spends nothing.
func use_leverage(entry_id: String, how: String, world: Dictionary, now_minute: int) -> Dictionary:
	var entries: Array = state.get("leverage", [])
	var entry: Dictionary = {}
	for e in entries:
		if str(e.get("id", "")) == entry_id:
			entry = e
	var effect := LeverageType.use(entry, how, world, lawful_faction(world))
	if not bool(effect.get("ok", false)):
		return effect
	state["leverage"] = LeverageType.mark_used(entries, entry_id, how)
	var deed: Dictionary = effect.get("deed", {})
	if not deed.is_empty():
		deed = deed.duplicate()
		deed["system_id"] = str(world.get("system_id", ""))
		if not state.get("deeds") is Array:
			state["deeds"] = []
		(state["deeds"] as Array).append(deed)
	return effect


## The faction here that cares most about order (Faction DNA): who an
## exposure goes to. {} when the system has no factions.
func lawful_faction(world: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_order := -INF
	for f in world.get("factions", []):
		var order := float((FactionDNAType.for_faction(str(f.get("id", ""))).get("axes", {}) as Dictionary).get("order", 0.0))
		if order > best_order:
			best_order = order
			best = f
	return best


## Fallout still in effect in a system.
func active_fallout(system_id: String, now_minute: int) -> Array:
	return FalloutType.active(state.get("fallout", []) as Array, system_id, now_minute)


## The next radio item this system hasn't aired yet this visit, or {}.
## Airing a main-story thread counts as the pilot hearing it.
func next_radio_item(world: Dictionary, now_minute: int) -> Dictionary:
	if not enabled:
		return {}
	var system_id := str(world.get("system_id", ""))
	# What a failed job did here comes first: it is the freshest news.
	var fallout_aired: Dictionary = _aired.get(system_id, {})
	for f in active_fallout(system_id, now_minute):
		var fid := str(f.get("id", ""))
		if fallout_aired.has(fid) or str(f.get("radio", "")).is_empty():
			continue
		fallout_aired[fid] = true
		_aired[system_id] = fallout_aired
		return {"id": fid, "kind": "news", "text": str(f["radio"])}
	var radio_world := world.duplicate()
	radio_world["system_names"] = _system_names
	var aired: Dictionary = _aired.get(system_id, {})
	for item in RadioType.broadcast(state, library, radio_world, now_minute):
		if aired.has(str(item["id"])):
			continue
		aired[str(item["id"])] = true
		_aired[system_id] = aired
		if str(item.get("kind", "")) == "thread":
			state = HandType.set_seen(state, str(item["thread_id"]), now_minute)
			state = HandType.update_draft(state)
		return item
	return {}


## Signal tuning: the faint transmission to tune into here, or {} when the
## director is off. See FaintTransmissions.
func faint_transmission(world: Dictionary, seed_value: int) -> Dictionary:
	if not enabled:
		return {}
	var system_id := str(world.get("system_id", ""))
	var display := str(_system_names.get(system_id, world.get("system_display", "this system")))
	return FaintType.pick(state, system_id, display, state.get("heard_intercepts", []), seed_value)


## The drone maze: a story thread a wreck here can hold (its recorder), as
## {kind: "thread", thread_id, text}, or {}.
func recorder_thread(world: Dictionary) -> Dictionary:
	if not enabled:
		return {}
	var system_id := str(world.get("system_id", ""))
	var found := FaintType.thread_candidates(state, system_id, ["wreck"])
	if found.is_empty():
		return {}
	var c: Dictionary = found[0]
	var display := str(_system_names.get(system_id, world.get("system_display", "this system")))
	# Whose recorder it is: the first person in that story, for leverage.
	var subject := ""
	var people: Array = []
	for role_id in (c["cast"] as Dictionary).keys():
		if str(c["cast"][role_id].get("kind", "")) == "person":
			people.append(str(c["cast"][role_id].get("display_name", "")))
	people.sort()
	if not people.is_empty():
		subject = str(people[0])
	return {"id": "thread:%s" % c["thread_id"], "kind": "thread", "thread_id": c["thread_id"],
		"text": CastingType.fill_text(str(c["detail"]), c["cast"], {"system_display": display}), "subject_name": subject}


## The captain pulled it in. A story thread is noticed (it joins the Loose
## ends board, however garbled it came through: N.O.V.A. keeps the
## recording); ambient chatter is marked heard so it does not come round again.
func overhear(item: Dictionary, now_minute: int) -> void:
	if str(item.get("kind", "")) == "thread":
		state = HandType.set_seen(state, str(item["thread_id"]), now_minute)
		state = HandType.update_draft(state)
		return
	var heard: Array = (state.get("heard_intercepts", []) as Array).duplicate()
	if not heard.has(str(item.get("id", ""))):
		heard.append(str(item.get("id", "")))
	state["heard_intercepts"] = heard


## Seen threads for a pin board: [{id, text, pinned}].
func main_story_threads() -> Array:
	var out: Array = []
	var story := HandType.main_story(state)
	# Only once the hand is revealed does the board say what connected; until
	# then it never hints which threads are real traces.
	var revealed := str(story.get("stage", "")) in ["revealed", "closed"]
	var links: Dictionary = (story.get("lock", {}) as Dictionary).get("links", {})
	for t in HandType.seen_threads(state):
		var a := ArcsType.arc(state, str(t["arc_id"]))
		var system_name := str(_system_names.get(str(a.get("system_id", "")), "this system"))
		var entry := {"id": str(t["id"]), "text": CastingType.fill_text(str(t["detail"]), a.get("cast", {}), {"system_display": system_name}),
			"pinned": bool(t["pinned"]), "system": system_name, "seen_minute": int(t.get("seen_minute", -1))}
		if revealed:
			if links.has(str(t["id"])):
				entry["explanation"] = str(links[str(t["id"])])
			else:
				entry["dead_end"] = true
		out.append(entry)
	return out


## Where the main story stands, for the pin board: {stage, season, hand?}.
## The hand's name appears only once they are revealed.
func main_story_summary() -> Dictionary:
	var story := HandType.main_story(state)
	var out := {"stage": str(story.get("stage", "")), "season": int(story.get("season", 1))}
	if out["stage"] in ["revealed", "closed"]:
		out["hand"] = str((story.get("lock", {}) as Dictionary).get("display_name", ""))
	return out


func pin_thread(thread_id: String, pinned: bool) -> void:
	state = HandType.set_pinned(state, thread_id, pinned)


# --- main story lock -------------------------------------------------------------

func _maybe_lock(world: Dictionary, now_minute: int) -> void:
	if not HandType.ready_to_lock(state) or _showrunner_busy:
		return
	if use_showrunner and is_inside_tree():
		if not _window_open():
			return  # the story model waits for a dock or jump; the board asks again
		_request_showrunner(world, now_minute)
	else:
		_apply_lock(HandType.lock_by_code(state, now_minute), world, now_minute)


func _request_showrunner(world: Dictionary, now_minute: int) -> void:
	_showrunner_busy = true
	# 8GB budget: the small model and the story model never fit together, so
	# free the small one first (it reloads on its next use).
	var unload := HTTPRequest.new()
	unload.timeout = 20.0
	add_child(unload)
	unload.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		unload.queue_free()
		_send_showrunner(world, now_minute))
	if unload.request(LocalModelGatewayURL(), ["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(unload_request(line_model))) != OK:
		unload.queue_free()
		_send_showrunner(world, now_minute)


## Ollama unloads a model when asked to generate nothing with keep_alive 0.
static func unload_request(model: String = "") -> Dictionary:
	return {"model": model if not model.is_empty() else preload("res://scripts/ai/LocalModelGateway.gd").DEFAULT_SMALL_MODEL, "keep_alive": 0}


func _send_showrunner(world: Dictionary, now_minute: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = 300.0
	add_child(http)
	var body := JSON.stringify(ShowType.build_request(state, library, _system_names))
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		http.queue_free()
		_showrunner_busy = false
		_pump_lines.call_deferred()
		if not HandType.ready_to_lock(state):
			return  # the world moved on (reload, or already locked)
		var locked := {}
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var parsed := ShowType.parse_response(ShowType.response_text(reply.get_string_from_utf8()), state)
			if bool(parsed["ok"]):
				locked = HandType.lock(state, parsed["choice"], now_minute)
		if locked.is_empty() or not bool(locked["ok"]):
			locked = HandType.lock_by_code(state, now_minute)
		_apply_lock(locked, _last_world if not _last_world.is_empty() else world, now_minute))
	GatewayType.note_request("premise_showrunner")
	if http.request(LocalModelGatewayURL(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
		_showrunner_busy = false
		_apply_lock(HandType.lock_by_code(state, now_minute), world, now_minute)


static func LocalModelGatewayURL() -> String:
	return preload("res://scripts/ai/LocalModelGateway.gd").OLLAMA_GENERATE_URL


func _apply_lock(locked: Dictionary, world: Dictionary, now_minute: int) -> void:
	if not bool(locked.get("ok", false)):
		return
	state = locked["state"]
	# The culprit's untouched side stories end quietly: they don't star in one
	# story while being confronted in another.
	var culprit := str(state["main_story"]["lock"].get("entity_id", ""))
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if _engaged(a):
			continue
		for entry in (a.get("cast", {}) as Dictionary).values():
			if str(entry.get("entity_id", "")) == culprit:
				var card: Dictionary = library.get_card(str(a["card_id"]))
				state = ArcsType.resolve(state, library, arc_id, str(card.get("default_resolution", "")), now_minute)
				_after_change(arc_id)
				break
	var forged := ForgeType.forge(state, world)
	if forged.is_empty():
		return
	var card: Dictionary = forged["card"]
	library.cards[card["id"]] = card.duplicate(true)
	var synthetic: Dictionary = state.get("synthetic_cards", {})
	synthetic[card["id"]] = card.duplicate(true)
	state["synthetic_cards"] = synthetic
	var started := ArcsType.start_arc(state, card, str(world.get("system_id", "")), forged["cast"], now_minute)
	state = started["state"]
	state["main_story"]["stage"] = "revealed"
	state["main_story"]["confrontation_arc_id"] = str(started["arc_id"])
	main_story_locked.emit(str(state["main_story"]["lock"]["display_name"]), str(started["arc_id"]))


## A mission the game finished (or dropped). Returns true if it belonged to an arc.
func on_mission_terminal(quest_data: Dictionary, terminal_state: String, now_minute: int) -> bool:
	var ref := _arc_ref(quest_data)
	if ref.is_empty():
		return false
	var branch := str((quest_data.get("objective", {}) as Dictionary).get("branch_id", quest_data.get("branch_id", "")))
	# A twist's answer travels: taking the money or sparing a surrendered
	# pilot is a deed the factions hear about.
	var twist_id := str(quest_data.get("twist_id", (quest_data.get("objective", {}) as Dictionary).get("twist_id", "")))
	# A reveal twist's answer is its own "branch" for the deed (the arc still
	# reads the hail branch, if any).
	var deed_branch := branch
	var reveal_answer := {"delivering": "deliver", "finishing": "finish_lie", "racing": "race_won",
		"sheltering": "shelter", "turned_in": "turn_in", "running": "run_law"}
	var twist_state := str(quest_data.get("twist_state", ""))
	if terminal_state == "completed" and reveal_answer.has(twist_state):
		deed_branch = str(reveal_answer[twist_state])
	elif twist_state == "exposed":
		deed_branch = "expose"
	elif twist_state == "switched":
		deed_branch = "switch"
	if not twist_id.is_empty():
		var deed := TwistsType.deed_for(deed_branch, str(quest_data.get("twist_target_name", "")))
		if not deed.is_empty():
			var a := ArcsType.arc(state, str(ref["arc_id"]))
			deed["system_id"] = str(a.get("system_id", ""))
			deed["arc_id"] = str(ref["arc_id"])
			deed["cast"] = (a.get("cast", {}) as Dictionary).duplicate(true)
			if not state.get("deeds") is Array:
				state["deeds"] = []
			(state["deeds"] as Array).append(deed)
	state = ArcsType.apply_mission_result(state, library, ref["arc_id"], int(ref["beat"]), int(ref["mission_index"]),
		terminal_state, branch, now_minute)
	# Working a story turns up more of its odd details.
	if terminal_state == "completed":
		state = HandType.mark_arc_threads_seen(state, ref["arc_id"], now_minute, 1)
		state = HandType.update_draft(state)
		_record_culprit_leverage(ref, quest_data, now_minute)
	_after_change(ref["arc_id"])
	return true


## An investigation whose card names a culprit (the role its evidence
## exposes) gives the captain leverage on them once it is done.
func _record_culprit_leverage(ref: Dictionary, quest_data: Dictionary, now_minute: int) -> void:
	if library == null:
		return
	var card: Dictionary = library.get_card(str(ref.get("card_id", "")))
	var missions: Array = LibraryType.beat(card, int(ref.get("beat", 1))).get("missions", [])
	var index := int(ref.get("mission_index", 0))
	if index < 0 or index >= missions.size():
		return
	var mission: Dictionary = missions[index]
	var culprit := str(mission.get("culprit", ""))
	if str(mission.get("verb", "")) != "investigate_signal" or culprit.is_empty():
		return
	var a := ArcsType.arc(state, str(ref["arc_id"]))
	var who: Dictionary = (a.get("cast", {}) as Dictionary).get(culprit, {})
	var name := str(who.get("display_name", ""))
	var site := str(quest_data.get("title", "the investigation")).trim_prefix("Survey at ")
	var entry := LeverageType.make("finding", "finding:%s:%s" % [str(ref["arc_id"]), str(quest_data.get("story_beat_id", index))], name,
		"The evidence from %s points at %s." % [site, name], str(a.get("system_id", "")), now_minute, str(who.get("entity_id", "")) if str(who.get("kind", "")) == "faction" else "")
	record_leverage_entry(entry)


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
		var engaged := _engaged(a)
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
		"hidden_hand_method": str(HandType.main_story(state).get("method", "")),
		"ores": (profile.get("ores", {"silicate": 1.0}) as Dictionary).keys(),
	}
	var seed_value := hash("%d|%s|%d" % [campaign_seed, world.get("system_id", ""), int(state.get("next_seq", 1))])
	var picks := SelectorType.pick(library, _history, situation, seed_value, 1)
	if picks.is_empty():
		return ""
	var card: Dictionary = library.get_card(picks[0])
	var arc_id_preview := "arc.%04d" % int(state.get("next_seq", 1))
	var cast := CastingType.cast_card(card, _with_known_people(world), seed_value, arc_id_preview)
	var started := ArcsType.start_arc(state, card, str(world.get("system_id", "")), cast, now_minute)
	state = started["state"]
	state["arcs"][str(started["arc_id"])]["started_visit"] = int(state.get("visits", 0))
	state = HandType.seed_threads(state, card, str(started["arc_id"]), seed_value)
	return str(started["arc_id"])


## People from earlier arcs become "known" for roles that prefer someone the
## player has met; the main story's draft identity is offered first.
func _with_known_people(world: Dictionary) -> Dictionary:
	var out := world.duplicate(true)
	var known: Array = out.get("known_npcs", [])
	var seen_ids := {}
	for k in known:
		seen_ids[str(k.get("id", ""))] = true
	# The recurring cast: alive, free, not busy in another live story; people
	# with a grudge or a debt come back more often.
	for person in CastType.candidates(state):
		if not seen_ids.has(str(person["id"])):
			known.append(person)
			seen_ids[str(person["id"])] = true
	out["known_npcs"] = known
	var draft := str(HandType.main_story(state).get("draft_entity_id", ""))
	if HandType.evidence_ready(state) and not draft.is_empty():
		# The case is made: the suspect isn't cast into anything new, so their
		# stories can end and the reveal can come.
		out["known_npcs"] = (out["known_npcs"] as Array).filter(func(k): return str(k.get("id", "")) != draft)
		out["priority_npc_ids"] = []
		return out
	out["priority_npc_ids"] = [draft] if not draft.is_empty() else []
	return out


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
		var lines: Dictionary = state.get("written_lines", {})
		for key in lines.keys():
			if str(key).begins_with(arc_id + "|"):
				lines.erase(key)
		arc_resolved.emit(arc_id, str(a["resolution_id"]))
		if ForgeType.is_forged(str(a["card_id"])) and not HandType.main_story(state).is_empty():
			state["main_story"]["stage"] = "closed"
			state["main_story"]["closed_resolution"] = str(a["resolution_id"])
			season_closed.emit(int(state["main_story"].get("season", 1)), str(a["resolution_id"]))
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

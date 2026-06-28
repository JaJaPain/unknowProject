extends Node

# StoryManager — narrative director stub.
# Beat evaluation, arc generation, and nudge logic are implemented in Phase 1–4
# per story_manager_impl.md. This file owns the deferred beat scheduler (Tool 10)
# and the event hooks GameRoot calls into.

# ── DEV: StoryQuestManager smoke-test ────────────────────────────────────────
# Set _SQ_DEBUG = true to fire a hardcoded "kill 3 Reavers" story quest on the
# player's FIRST kill. Lets you verify the full quest pipeline (HUD, objective
# tracking, reward delivery) without needing a real beat source.
#
# HOW TO DISABLE: flip _SQ_DEBUG back to false and save. No other changes needed.
# HOW TO FIND:    grep _SQ_DEBUG in scripts/story/StoryManager.gd
# DO NOT SHIP with _SQ_DEBUG = true.
const _SQ_DEBUG := false
var _sq_debug_fired := false   # guard: only fires once per session

const StoryStateStoreType := preload(
	"res://scripts/persistence/StoryStateStore.gd"
)
const KaelenHandoffStoreType := preload(
	"res://scripts/persistence/KaelenHandoffStore.gd"
)

# ── Phase B: Living story state ───────────────────────────────────────────────
# story_state is the in-memory working copy. StoryStateStore handles persistence.
# player_does_not_know_yet is NEVER included in get_story_context_block().
var story_state: Dictionary = {
	"chapter": 1,
	"active_tensions": [],
	"player_knows": [],
	"player_does_not_know_yet": [],
	"pending_hooks": [],
	"current_foreshadow": "",
	"kaelen_current_mood": "guarded",
	"intro_conversation_had": false,
	"intro_agent_visited": false,
	"intro_quest_delivered": false,
	"hinted_lounge_rumors": [],
	"agent_cooldown_until_minute": 0,
	"agent_cooldown_message_index": 0,
}
var _story_state_store = null   # StoryStateStore, opened by init_story_state()
var _handoff_store = null       # KaelenHandoffStore, opened by init_story_state()

# ── Deferred beat schedule ────────────────────────────────────────────────────
# Each entry: {type, beat_id, threshold, current}
# type: "kills" | "dock" | "delay_min"
var _scheduled_beats: Array = []

# ── Event counters (reset per session, not persisted) ────────────────────────
var _kill_count_session: int = 0
var _dock_count_session: int = 0


func _ready() -> void:
	GlobalState.player_kill.connect(_on_ship_destroyed)
	# Fire starting-system handoff gen once Ollama is actually ready.
	# init_story_state() fires before Ollama is up, so the batch would fail.
	LLMInterface.llm_connection_established.connect(_on_llm_ready, CONNECT_ONE_SHOT)


func reset_for_restart() -> void:
	_scheduled_beats.clear()
	_kill_count_session = 0
	_dock_count_session = 0
	_sq_debug_fired = false


func _on_llm_ready(_model_name: String) -> void:
	# Ollama is up and models are confirmed. Safe to fire the starting-system pool now.
	_trigger_handoff_pool_for_system("system.start")


# ── Phase B: Story state API ──────────────────────────────────────────────────

func init_story_state(campaign_path: String) -> void:
	_story_state_store = StoryStateStoreType.open(campaign_path)
	if _story_state_store.is_valid():
		story_state = _story_state_store.data.duplicate(true)
	else:
		push_warning("[StoryManager] Story state store failed to open; using defaults.")
		story_state = StoryStateStoreType._default_state()
	_handoff_store = KaelenHandoffStoreType.open(campaign_path)
	_push_context_to_llm()
	# Handoff pool gen deferred to _on_llm_ready — Ollama isn't up yet here.

func clear_story_state() -> void:
	_story_state_store = null
	_handoff_store = null
	story_state = {
		"chapter": 1,
		"active_tensions": [],
		"player_knows": [],
		"player_does_not_know_yet": [],
		"pending_hooks": [],
		"current_foreshadow": "",
		"kaelen_current_mood": "guarded",
		"intro_conversation_had": false,
		"intro_agent_visited": false,
		"intro_quest_delivered": false,
		"hinted_lounge_rumors": [],
		"agent_cooldown_until_minute": 0,
		"agent_cooldown_message_index": 0,
	}

# Returns a formatted string safe to inject into LLM prompts.
# Never includes player_does_not_know_yet.
func get_story_context_block() -> String:
	var lines: Array[String] = []
	lines.append("Story State:")
	lines.append("- Chapter: %d" % int(story_state.get("chapter", 1)))
	var tensions: Array = story_state.get("active_tensions", [])
	if not tensions.is_empty():
		lines.append("- Active tensions: %s" % ", ".join(tensions))
	var known: Array = story_state.get("player_knows", [])
	if not known.is_empty():
		lines.append("- Player knows: %s" % ", ".join(known))
	var foreshadow := str(story_state.get("current_foreshadow", "")).strip_edges()
	if not foreshadow.is_empty():
		lines.append("- Foreshadow hint: %s" % foreshadow)
	var mood := str(story_state.get("kaelen_current_mood", "")).strip_edges()
	if not mood.is_empty():
		lines.append("- Kaelen mood: %s" % mood)
	var hooks: Array = story_state.get("pending_hooks", [])
	if not hooks.is_empty():
		lines.append("- Open story threads: %s" % ", ".join(hooks))
	return "\n".join(lines)

# Increments chapter, promotes earned secrets to player_knows, clears resolved
# tensions, then generates a new current_foreshadow via the small model.
# Pass how many items from player_does_not_know_yet to promote this chapter.
func advance_chapter(truths_to_reveal: int = 1) -> void:
	story_state["chapter"] = int(story_state.get("chapter", 1)) + 1
	var hidden: Array = story_state.get("player_does_not_know_yet", [])
	var known: Array = story_state.get("player_knows", [])
	var revealed := mini(truths_to_reveal, hidden.size())
	for i in range(revealed):
		known.append(hidden[i])
	story_state["player_knows"] = known
	story_state["player_does_not_know_yet"] = hidden.slice(revealed)
	story_state["active_tensions"] = []
	_save_story_state()
	_generate_foreshadow()
	# Story context changed — replace all known agent pools so tone stays current.
	_replace_all_handoff_pools()

func _save_story_state() -> void:
	if _story_state_store == null or not _story_state_store.is_valid():
		return
	var result: Dictionary = _story_state_store.save_state(story_state)
	if not bool(result.get("ok", false)):
		push_warning("[StoryManager] Story state save failed: %s" % str(result.get("error", "")))
	_push_context_to_llm()

func _push_context_to_llm() -> void:
	if is_instance_valid(LLMInterface):
		LLMInterface.story_state_context_text = get_story_context_block()

# Async: asks the small model for a one-sentence foreshadow, then saves.
func _generate_foreshadow() -> void:
	var chapter := int(story_state.get("chapter", 1))
	var tensions: Array = story_state.get("active_tensions", [])
	var hooks: Array = story_state.get("pending_hooks", [])
	var tension_text := ", ".join(tensions) if not tensions.is_empty() else "the unknown frontier"
	var hook_text: String = hooks[0] if not hooks.is_empty() else ""
	var prompt := (
		"You are a narrator for a space opera. "
		+ "Chapter %d has just begun. Current tensions: %s. " % [chapter, tension_text]
		+ ("Open thread: %s. " % hook_text if not hook_text.is_empty() else "")
		+ "Write ONE sentence (under 20 words) that a background NPC might hint at — "
		+ "something ominous, incomplete, or suggestive. No names. No explanation."
	)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if parsed == null or not parsed is Dictionary:
				return
			var text: String = str((parsed as Dictionary).get("response", "")).strip_edges()
			if text.is_empty():
				return
			story_state["current_foreshadow"] = text
			_save_story_state()
	)
	var payload := JSON.stringify({
		"model": LocalModelGateway.DEFAULT_SMALL_MODEL,
		"prompt": prompt,
		"stream": false,
		"options": {"num_predict": 40, "temperature": 0.8},
	})
	http.request(
		LocalModelGateway.OLLAMA_GENERATE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		payload
	)


# ── Public tool: deferred beat scheduling ────────────────────────────────────

# Fire beat_id after the player gets N more kills in this session.
func schedule_beat_after_kills(beat_id: String, n: int) -> void:
	_scheduled_beats.append({
		"type":      "kills",
		"beat_id":   beat_id,
		"threshold": _kill_count_session + n,
	})


# Fire beat_id on the very next dock (any station).
func schedule_beat_on_next_dock(beat_id: String) -> void:
	_scheduled_beats.append({
		"type":    "dock",
		"beat_id": beat_id,
	})


# Fire beat_id after delay_min in-game minutes have passed (uses real time at 1:1).
func schedule_beat_after_delay_min(beat_id: String, delay_min: float) -> void:
	_scheduled_beats.append({
		"type":      "delay_min",
		"beat_id":   beat_id,
		"fire_at":   Time.get_ticks_msec() + int(delay_min * 60.0 * 1000.0),
	})


# ── GameRoot event hooks ──────────────────────────────────────────────────────

func on_system_arrived(system_id: String) -> void:
	_check_delay_beats()
	# Top-up any agent pools that have fallen below 4 lines.
	_trigger_handoff_pool_for_system(system_id)


func on_kill(faction: String) -> void:
	_kill_count_session += 1
	# Register a STORY intent — the queue delivers it only after any active combat
	# AND the 3-second post-combat buffer have both cleared.
	PlayerInteractionQueue.enqueue(
		PlayerInteractionQueue.Priority.STORY,
		func(done: Callable) -> void:
			_resolve_kill(faction)
			done.call(),   # story beats are sync; release the slot immediately
		"StoryManager:kill:%s" % faction
	)

func _resolve_kill(faction: String) -> void:
	_check_kill_beats()
	if _SQ_DEBUG and not _sq_debug_fired:
		_sq_debug_fired = true
		_fire_debug_story_quest()


func _on_ship_destroyed(faction: String) -> void:
	print("[StoryManager] ship_destroyed signal: %s (session kills: %d)" % [faction, _kill_count_session + 1])
	on_kill(faction)


func on_docked(_station) -> void:
	_dock_count_session += 1
	_check_dock_beats()
	_check_delay_beats()


func on_quest_completed(_quest: Dictionary) -> void:
	_check_delay_beats()


func get_lounge_rumor(context: Dictionary = {}) -> Dictionary:
	var station_name := str(context.get("station_name", "the lounge")).strip_edges()
	if station_name.is_empty():
		station_name = "the lounge"
	var npc_name := str(context.get("npc_name", "this contact")).strip_edges()
	if npc_name.is_empty():
		npc_name = "this contact"
	var faction_display := str(context.get("faction_display", "")).strip_edges()
	var source_hint := "dock crews"
	if not faction_display.is_empty() and faction_display != "independent crews":
		source_hint = "%s crews" % faction_display
	var hinted: Array = story_state.get("hinted_lounge_rumors", [])
	var candidates: Array[Dictionary] = []
	var hooks: Array = story_state.get("pending_hooks", [])
	for hook in hooks:
		var text := str(hook).strip_edges()
		if text.is_empty():
			continue
		candidates.append({
			"id": "hook:%s" % text.sha256_text().substr(0, 12),
			"title": "Open Thread",
			"source": "Story",
			"weight": 4,
			"line": "%s lowers their voice. Something tied to %s is moving through %s, and the %s keep pretending it is routine." % [
				npc_name,
				text,
				station_name,
				source_hint,
			],
		})
	var foreshadow := str(story_state.get("current_foreshadow", "")).strip_edges()
	if not foreshadow.is_empty():
		candidates.append({
			"id": "foreshadow:%s" % foreshadow.sha256_text().substr(0, 12),
			"title": "Soft Warning",
			"source": "Story",
			"weight": 3,
			"line": "%s has been hearing the same warning from different crews: \"%s\"" % [
				npc_name,
				foreshadow.trim_suffix("."),
			],
		})
	var tensions: Array = story_state.get("active_tensions", [])
	for tension in tensions:
		var text := str(tension).strip_edges()
		if text.is_empty():
			continue
		candidates.append({
			"id": "tension:%s" % text.sha256_text().substr(0, 12),
			"title": "Local Pressure",
			"source": "Story",
			"weight": 2,
			"line": "The public boards blame %s, but the dock crews in %s keep pointing at timing, not motive." % [
				text,
				station_name,
			],
		})
	var known: Array = story_state.get("player_knows", [])
	for truth in known:
		var text := str(truth).strip_edges()
		if text.is_empty():
			continue
		candidates.append({
			"id": "known:%s" % text.sha256_text().substr(0, 12),
			"title": "Echo",
			"source": "Story",
			"weight": 1,
			"line": "That thing you heard about %s? It is starting to show up in ordinary dock talk now." % text,
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("weight", 0)) > int(b.get("weight", 0))
	)
	for candidate in candidates:
		if str(candidate.get("id", "")) not in hinted:
			return candidate
	return candidates[0]


func record_lounge_rumor_heard(rumor_id: String) -> void:
	var clean_id := rumor_id.strip_edges()
	if clean_id.is_empty():
		return
	var hinted: Array = story_state.get("hinted_lounge_rumors", []).duplicate()
	if clean_id in hinted:
		return
	hinted.append(clean_id)
	while hinted.size() > 24:
		hinted.pop_front()
	story_state["hinted_lounge_rumors"] = hinted
	_save_story_state()


func get_agent_contract_availability(_context: Dictionary = {}) -> Dictionary:
	var now_minute := int(CampaignClock.total_minutes)
	var until_minute := int(story_state.get("agent_cooldown_until_minute", 0))
	if until_minute <= now_minute:
		if until_minute > 0:
			story_state["agent_cooldown_until_minute"] = 0
			_save_story_state()
		return {"available": true, "remaining_minutes": 0, "message": ""}
	var message_index := int(story_state.get("agent_cooldown_message_index", 0))
	var messages := [
		"No one is asking right now. I will send you a message when I need you to make us some more money.",
		"Boards are quiet for once. Enjoy the silence. It never lasts.",
		"Nothing worth your fuel on my desk right now. Give it a little time.",
	]
	message_index = clampi(message_index, 0, messages.size() - 1)
	return {
		"available": false,
		"remaining_minutes": until_minute - now_minute,
		"message": messages[message_index],
	}


func start_agent_contract_cooldown(reason: String = "contract_resolved") -> Dictionary:
	var now_minute := int(CampaignClock.total_minutes)
	var cooldown_min := 25 + (randi() % 56)
	if reason == "contract_abandoned":
		cooldown_min = 35 + (randi() % 76)
	story_state["agent_cooldown_until_minute"] = now_minute + cooldown_min
	story_state["agent_cooldown_message_index"] = randi() % 3
	_save_story_state()
	return get_agent_contract_availability()


func clear_agent_contract_cooldown() -> void:
	if int(story_state.get("agent_cooldown_until_minute", 0)) == 0:
		return
	story_state["agent_cooldown_until_minute"] = 0
	_save_story_state()


# ── Internal beat evaluation stubs ───────────────────────────────────────────

func _check_kill_beats() -> void:
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "kills":
			continue
		if _kill_count_session >= int(entry.get("threshold", 0)):
			_fire_beat(str(entry.get("beat_id", "")))
			fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _check_dock_beats() -> void:
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "dock":
			continue
		_fire_beat(str(entry.get("beat_id", "")))
		fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _check_delay_beats() -> void:
	var now: int = Time.get_ticks_msec()
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "delay_min":
			continue
		if now >= int(entry.get("fire_at", 0)):
			_fire_beat(str(entry.get("beat_id", "")))
			fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _fire_beat(beat_id: String) -> void:
	# Phase 1 stub — just logs. Phase 2+ will look up the beat in StoryRegistry
	# and execute its delivery (kaelen_voice_message, quest_injection, etc.).
	if beat_id.is_empty():
		return
	print("[StoryManager] Beat fired: %s (stub — no delivery yet)" % beat_id)


# ── Scripted intro quest ──────────────────────────────────────────────────────

# Called by UIManager when the player dismisses the Kaelen intro popup.
# This marks the first conversation with Kaelen and unlocks the intro quest gate.
func on_kaelen_intro_dismissed() -> void:
	if bool(story_state.get("intro_conversation_had", false)):
		return
	story_state["intro_conversation_had"] = true
	_save_story_state()

# Intro quest delivery is owned by UIManager._show_kaelen_intro_quest_offer().
# StoryManager only persists the flags (intro_quest_delivered, etc.).


# ── Kaelen Handoff Pool ───────────────────────────────────────────────────────

# Returns a pre-generated line from the pool, or "" if the pool is empty.
func draw_kaelen_handoff(agent_name: String) -> String:
	if _handoff_store == null or not _handoff_store.is_valid():
		return ""
	return _handoff_store.draw(agent_name)

# Map faction IDs to the agent rosters used by LLMInterface.
const _FACTION_AGENT_MAP := {
	"faction.zenith":   {"agent_name": "Director Voss",  "agent_role": "Zenith Corporate Acquisitions Director",  "faction": "Zenith"},
	"faction.aurelia":  {"agent_name": "Liaison Ryn",    "agent_role": "Aurelia Syndicate Trade Liaison",          "faction": "Aurelia"},
	"faction.vanguard": {"agent_name": "Captain Dask",   "agent_role": "Vanguard Military Contract Officer",       "faction": "Vanguard"},
}

# Called at game start, on "Fly to" gate, and on system arrival.
# Resolves the agent list from system_id, then generates for any pool below threshold.
func _trigger_handoff_pool_for_system(system_id: String, force_replace: bool = false) -> void:
	if _handoff_store == null or not _handoff_store.is_valid():
		return
	if not is_instance_valid(LLMInterface):
		return
	var faction_ids := _faction_ids_for_system(system_id)
	for faction_id in faction_ids:
		var entry: Dictionary = _FACTION_AGENT_MAP.get(faction_id, {})
		if entry.is_empty():
			continue
		var agent_name: String = entry["agent_name"]
		if not force_replace and _handoff_store.pool_size(agent_name) >= 4:
			continue
		generate_handoff_pool(agent_name, entry["faction"], entry["agent_role"])

# Full replace for all known agents — called on chapter advance.
func _replace_all_handoff_pools() -> void:
	if _handoff_store == null or not _handoff_store.is_valid():
		return
	for entry in _FACTION_AGENT_MAP.values():
		generate_handoff_pool(entry["agent_name"], entry["faction"], entry["agent_role"])

# Async: asks Gemma4 for 16 handoff lines, saves to pool on success.
func generate_handoff_pool(agent_name: String, faction: String, agent_role: String) -> void:
	if not is_instance_valid(LLMInterface):
		return
	var story_context := get_story_context_block()
	LLMInterface.request_kaelen_handoff_batch(
		agent_name, agent_role, faction, story_context, 16,
		func(lines: Array) -> void:
			if lines.is_empty():
				push_warning("[StoryManager] Handoff batch returned empty for %s" % agent_name)
				return
			if _handoff_store != null and _handoff_store.is_valid():
				_handoff_store.refill(agent_name, lines)
				print("[StoryManager] Handoff pool refilled for %s (%d lines)" % [agent_name, lines.size()])
	)

# Look up faction_ids for a system from the system registry.
func _faction_ids_for_system(system_id: String) -> Array:
	var registry_path := "res://data/systems/system_registry.json"
	if not FileAccess.file_exists(registry_path):
		return []
	var file := FileAccess.open(registry_path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		return []
	var systems: Array = (parsed as Dictionary).get("systems", [])
	for sys in systems:
		if str(sys.get("id", "")) == system_id:
			return sys.get("faction_ids", [])
	return []


# ── DEV only — remove guard or flip _SQ_DEBUG when done ──────────────────────
func _fire_debug_story_quest() -> void:
	if not is_instance_valid(StoryQuestManager):
		return
	var quest_def := {
		"id":             "debug_sq_reavers_001",
		"title":          "Clear the Reavers",
		"time_limit_min": 10.0,
		"objective": {
			"type":                 "kill_tagged_ship",
			"target_persistent_id": "debug.reaver.target",
			"display":              "Destroy the Reaver leader",
		},
		"spawns": [
			{
				"type":          "ship",
				"faction":       "reavers",
				"ship_role":     "Combat",
				"persistent_id": "debug.reaver.target",
				"speed":         14.0,
				"behavior":      "patrol",
			}
		],
		"hook": {
			"type":    "kaelen_voice",
			"text":    "New contract just came in. Reavers have been hitting supply lanes nearby — there's a bounty on their leader. Go take care of it.",
			"delay_s": 1.5,
		},
		"on_complete": {
			"credits":       500,
			"chatter_sender": "Kaelen",
			"chatter_line":   "Good work. Credits are in your account.",
			"kaelen_voice":   true,
		},
		"on_fail": {
			"chatter_line": "You ran out of time. The Reaver leader slipped away.",
		},
	}
	StoryQuestManager.begin_quest(quest_def)
	print("[StoryManager] DEBUG: fired story quest debug_sq_reavers_001")

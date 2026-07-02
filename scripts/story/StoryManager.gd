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
	"kaelen_hidden_angle": "",
	"intro_conversation_had": false,
	"intro_agent_visited": false,
	"intro_quest_delivered": false,
	"hinted_lounge_rumors": [],
	"agent_cooldown_until_minute": 0,
	"agent_cooldown_message_index": 0,
	"agent_contracts_since_cooldown": 0,
	"faction_pressure": {},
	"player_choices": [],
	"kaelen_hidden_hints": [],
	"kaelen_hints_delivered": [],
	"kaelen_hint_style": "",
	"bible_seeded": false,
	"act_1_outline_consumed_index": 0,
	"story_arcs_consumed_index": 0,
	"rumor_trails_consumed_index": 0,
	"regeneration_fallback_count": 0,
}
var _story_state_store = null   # StoryStateStore, opened by init_story_state()
var _handoff_store = null       # KaelenHandoffStore, opened by init_story_state()
var _campaign_bible_store = null   # CampaignBibleStore reference, set by init_story_state()

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

func init_story_state(
	campaign_path: String,
	bible_data: Dictionary = {},
	campaign_bible_store = null
) -> void:
	_story_state_store = StoryStateStoreType.open(campaign_path)
	if _story_state_store.is_valid():
		story_state = _story_state_store.data.duplicate(true)
	else:
		push_warning("[StoryManager] Story state store failed to open; using defaults.")
		story_state = StoryStateStoreType._default_state()
	_handoff_store = KaelenHandoffStoreType.open(campaign_path)
	_campaign_bible_store = campaign_bible_store
	if not bible_data.is_empty() and not bool(story_state.get("bible_seeded", false)):
		seed_story_state_from_bible(bible_data)
	_push_context_to_llm()
	# Handoff pool gen deferred to _on_llm_ready — Ollama isn't up yet here.


# ── Phase B: Seed the living story state from the generated campaign bible ────
# Runs once per campaign, guarded by bible_seeded. The bible is the fixed spine;
# this copies its opening beats into the state StoryManager actually mutates and
# injects into prompts. kaelen_hidden_angle is director-only knowledge and must
# never appear in get_story_context_block() — same protection as
# player_does_not_know_yet.
func seed_story_state_from_bible(bible_data: Dictionary) -> void:
	if bool(story_state.get("bible_seeded", false)):
		return
	var active_tensions: Array = story_state.get("active_tensions", [])
	var hidden: Array = story_state.get("player_does_not_know_yet", [])
	var hooks: Array = story_state.get("pending_hooks", [])

	var story_arcs: Array = bible_data.get("story_arcs", [])
	if not story_arcs.is_empty() and story_arcs[0] is Dictionary:
		var arc_summary := str((story_arcs[0] as Dictionary).get("summary", "")).strip_edges()
		if not arc_summary.is_empty():
			active_tensions.append(arc_summary)
	story_state["story_arcs_consumed_index"] = 1 if not story_arcs.is_empty() else 0

	var outline: Array = bible_data.get("act_1_outline", [])
	for i in range(1, outline.size()):
		var beat := str(outline[i]).strip_edges()
		if not beat.is_empty():
			hidden.append(beat)
	story_state["act_1_outline_consumed_index"] = mini(1, outline.size())

	var main_mystery := str(bible_data.get("main_mystery", "")).strip_edges()
	if not main_mystery.is_empty():
		hidden.append(main_mystery)

	var rumor_trails: Array = bible_data.get("rumor_trails", [])
	if not rumor_trails.is_empty() and rumor_trails[0] is Dictionary:
		var clue_templates: Array = (rumor_trails[0] as Dictionary).get("clue_templates", [])
		for clue in clue_templates:
			var clue_text := str(clue).strip_edges()
			if not clue_text.is_empty():
				hooks.append(clue_text)
	story_state["rumor_trails_consumed_index"] = 1 if not rumor_trails.is_empty() else 0

	var opening_situation := str(bible_data.get("opening_situation", "")).strip_edges()
	if not opening_situation.is_empty() \
			and str(story_state.get("current_foreshadow", "")).strip_edges().is_empty():
		story_state["current_foreshadow"] = opening_situation

	var kaelen_angle := str(bible_data.get("kaelen_angle", "")).strip_edges()
	if not kaelen_angle.is_empty():
		story_state["kaelen_hidden_angle"] = kaelen_angle

	# Seed Kaelen's hint plan. Undelivered hints are director-only (never in
	# get_story_context_block, same as player_does_not_know_yet); they move to the
	# player-safe delivered list only when deliver_next_kaelen_hint() pops them.
	var hint_plan: Array = bible_data.get("kaelen_hint_plan", []) if bible_data.get("kaelen_hint_plan", []) is Array else []
	var undelivered: Array = []
	for h in hint_plan:
		var ht := str(h).strip_edges()
		if not ht.is_empty():
			undelivered.append(ht)
	story_state["kaelen_hidden_hints"] = undelivered
	story_state["kaelen_hints_delivered"] = []
	var hint_style := str(bible_data.get("kaelen_hint_style", "")).strip_edges()
	if not hint_style.is_empty():
		story_state["kaelen_hint_style"] = hint_style

	# Seed faction pressure from the bible's anchor faction problems: each anchor
	# starts at neutral pressure (0) with its problem as the posture line. Gameplay
	# (kills, contracts, cargo seizures) shifts pressure later via
	# adjust_faction_pressure(). Player-safe world texture, so it rides in the
	# normal story-state context block.
	var factions: Dictionary = bible_data.get("factions", {}) if bible_data.get("factions", {}) is Dictionary else {}
	var pressure := {}
	for anchor in ["zenith", "aurelia", "vanguard"]:
		var problem := str(factions.get(anchor, "")).strip_edges()
		pressure[anchor] = {"pressure": 0, "posture": problem if not problem.is_empty() else "stable"}
	story_state["faction_pressure"] = pressure

	story_state["active_tensions"] = active_tensions
	story_state["player_does_not_know_yet"] = hidden
	story_state["pending_hooks"] = hooks
	story_state["bible_seeded"] = true
	_save_story_state()
	_update_kaelen_mood()

func clear_story_state() -> void:
	_story_state_store = null
	_handoff_store = null
	_campaign_bible_store = null
	story_state = {
		"chapter": 1,
		"active_tensions": [],
		"player_knows": [],
		"player_does_not_know_yet": [],
		"pending_hooks": [],
		"current_foreshadow": "",
		"kaelen_current_mood": "guarded",
		"kaelen_hidden_angle": "",
		"intro_conversation_had": false,
		"intro_agent_visited": false,
		"intro_quest_delivered": false,
		"hinted_lounge_rumors": [],
		"agent_cooldown_until_minute": 0,
		"agent_cooldown_message_index": 0,
		"agent_contracts_since_cooldown": 0,
		"faction_pressure": {},
		"player_choices": [],
		"kaelen_hidden_hints": [],
		"kaelen_hints_delivered": [],
		"kaelen_hint_style": "",
		"bible_seeded": false,
		"act_1_outline_consumed_index": 0,
		"story_arcs_consumed_index": 0,
		"rumor_trails_consumed_index": 0,
		"regeneration_fallback_count": 0,
	}

# ── Phase C: Mission causality ─────────────────────────────────────────────────
# The single reason a mission generated right now exists. Safe for prompts —
# active_tensions is player-facing world state, not a hidden truth.
func get_current_because() -> String:
	var tensions: Array = story_state.get("active_tensions", [])
	if tensions.is_empty():
		return ""
	return str(tensions[0]).strip_edges()


# Same hash scheme as get_lounge_rumor()'s "hook:" ids so a hook stamped onto a
# quest here matches the same hook if it's also surfaced as a lounge rumor.
func current_hook_ref() -> String:
	var hooks: Array = story_state.get("pending_hooks", [])
	if hooks.is_empty():
		return ""
	var text := str(hooks[0]).strip_edges()
	if text.is_empty():
		return ""
	return "hook:%s" % text.sha256_text().substr(0, 12)


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
	_append_faction_pressure_lines(lines)
	return "\n".join(lines)


# Player-safe faction pressure line for LLM prompts: each anchor's posture plus a
# neutral/rising/easing sign from its pressure scalar. No secrets.
func _append_faction_pressure_lines(lines: Array) -> void:
	var pressure: Dictionary = story_state.get("faction_pressure", {})
	if pressure.is_empty():
		return
	var parts: Array[String] = []
	for anchor in ["zenith", "aurelia", "vanguard"]:
		var fp = pressure.get(anchor, null)
		if not fp is Dictionary:
			continue
		var posture := str(fp.get("posture", "")).strip_edges()
		var scalar := int(fp.get("pressure", 0))
		var sign_word := "neutral"
		if scalar > 0:
			sign_word = "rising(+%d)" % scalar
		elif scalar < 0:
			sign_word = "easing(%d)" % scalar
		if not posture.is_empty():
			parts.append("%s [%s]: %s" % [anchor.capitalize(), sign_word, posture])
	if not parts.is_empty():
		lines.append("- Faction pressure: %s" % " | ".join(parts))


# Records a durable player choice (contract sided-with/refused/betrayed, cargo
# fenced, faction favored). Applies any faction_deltas through the pressure write
# path so a choice both remembers itself AND shifts the world. faction_deltas:
# {faction_key: int delta}. Player-safe world facts, not hidden truths.
func record_player_choice(choice_id: String, description: String, faction_deltas: Dictionary = {}) -> void:
	var clean_id := choice_id.strip_edges()
	var clean_desc := description.strip_edges()
	if clean_id.is_empty() and clean_desc.is_empty():
		return
	var choices: Array = story_state.get("player_choices", [])
	choices.append({
		"choice_id": clean_id,
		"description": clean_desc,
		"faction_deltas": faction_deltas.duplicate(true),
		"at_minute": int(CampaignClock.total_minutes),
	})
	while choices.size() > 64:
		choices.pop_front()
	story_state["player_choices"] = choices
	for faction in faction_deltas.keys():
		adjust_faction_pressure(str(faction), int(faction_deltas[faction]))
	_save_story_state()


# Pops the next undelivered Kaelen hint (director-only until this call) and moves
# it to the delivered list (player-safe). Returns "" if none remain. The caller
# hands the returned line to the small model as text to deliver in Kaelen's voice.
# Delivery is code-paced (chapter advance, trail progress) so hints escalate.
func deliver_next_kaelen_hint() -> String:
	var undelivered: Array = story_state.get("kaelen_hidden_hints", [])
	if undelivered.is_empty():
		return ""
	var hint := str(undelivered[0]).strip_edges()
	story_state["kaelen_hidden_hints"] = undelivered.slice(1)
	if not hint.is_empty():
		var delivered: Array = story_state.get("kaelen_hints_delivered", [])
		delivered.append(hint)
		story_state["kaelen_hints_delivered"] = delivered
	_save_story_state()
	return hint


# Compact, player-safe digest of the most recent choices for horizon-expansion
# prompts, so appended story reacts to who the player has been. "" if none.
func player_choice_digest(limit: int = 6) -> String:
	var choices: Array = story_state.get("player_choices", [])
	if choices.is_empty():
		return ""
	var start := maxi(0, choices.size() - limit)
	var lines: Array[String] = []
	for i in range(start, choices.size()):
		var c = choices[i]
		if c is Dictionary:
			var desc := str(c.get("description", "")).strip_edges()
			if not desc.is_empty():
				lines.append("- %s" % desc)
	if lines.is_empty():
		return ""
	return "Recent player choices:\n%s" % "\n".join(lines)


# Write path for gameplay to shift a faction's pressure (kills, contracts, cargo
# seizures). Clamps to -3..3 and persists. Unknown factions are ignored.
func adjust_faction_pressure(faction: String, delta: int) -> void:
	var key := faction.strip_edges().to_lower()
	var pressure: Dictionary = story_state.get("faction_pressure", {})
	if not pressure.get(key, null) is Dictionary:
		return
	var fp: Dictionary = pressure[key]
	fp["pressure"] = clampi(int(fp.get("pressure", 0)) + delta, -3, 3)
	pressure[key] = fp
	story_state["faction_pressure"] = pressure
	_save_story_state()

# Increments chapter, promotes earned secrets to player_knows, then replaces
# the cleared tensions/hooks with refill content atomically (no chapter should
# ever land with an empty slate — new_tensions/new_hooks come from the bible's
# reserve or a regeneration_trigger call; see _check_chapter_advance_after_hook_resolution).
# Pass how many items from player_does_not_know_yet to promote this chapter.
func advance_chapter(
	truths_to_reveal: int = 1,
	new_tensions: Array = [],
	new_hooks: Array = []
) -> void:
	story_state["chapter"] = int(story_state.get("chapter", 1)) + 1
	var hidden: Array = story_state.get("player_does_not_know_yet", [])
	var known: Array = story_state.get("player_knows", [])
	var revealed := mini(truths_to_reveal, hidden.size())
	for i in range(revealed):
		known.append(hidden[i])
	story_state["player_knows"] = known
	story_state["player_does_not_know_yet"] = hidden.slice(revealed)
	story_state["active_tensions"] = new_tensions
	story_state["pending_hooks"] = new_hooks
	_save_story_state()
	_generate_foreshadow()
	_update_kaelen_mood()
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


# Belt-and-suspenders leak guard for kaelen_current_mood. As of item #12 the mood
# prompt no longer sends the hidden angle at all (mood is derived from delivery
# stage + style), so this should effectively never trigger — but it stays as a
# net: reject any candidate mood that shares a distinctive (long, non-stopword)
# token with the angle, or that is too long to be a real 2-4 word mood.
const _MOOD_STOPWORDS := {
	"the": true, "and": true, "with": true, "that": true, "this": true,
	"from": true, "into": true, "over": true, "your": true, "their": true,
	"them": true, "they": true, "have": true, "will": true, "been": true,
	"about": true, "very": true, "just": true, "than": true, "then": true,
	"kaelen": true, "situation": true, "private": true, "director": true,
	"comes": true, "across": true, "right": true, "makes": true,
}


static func mood_leaks_secret(candidate: String, secret: String) -> bool:
	var mood_words := _distinctive_words(candidate)
	# A real mood is 2-4 words; more distinctive tokens means it's explaining,
	# not describing — treat that as a leak regardless of overlap.
	if mood_words.size() > 6:
		return true
	var secret_words := _distinctive_words(secret)
	for word in mood_words:
		if secret_words.has(word):
			return true
	return false


static func _distinctive_words(text: String) -> Dictionary:
	var out := {}
	var lower := text.to_lower()
	var token := ""
	for i in range(lower.length()):
		var c := lower[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			token += c
			continue
		if token.length() >= 4 and not _MOOD_STOPWORDS.has(token):
			out[token] = true
		token = ""
	if token.length() >= 4 and not _MOOD_STOPWORDS.has(token):
		out[token] = true
	return out


# Async: derives a short mood descriptor from Kaelen's hint-delivery STAGE and
# deflection style — NOT her hidden angle (plan §5.3 fuller fix, item #12). The
# angle is deliberately never placed in the prompt, so the small model can't
# echo it. mood_leaks_secret() stays as a belt-and-suspenders check.
func _update_kaelen_mood() -> void:
	var chapter := int(story_state.get("chapter", 1))
	var style := str(story_state.get("kaelen_hint_style", "")).strip_edges()
	if style.is_empty():
		style = "dry and evasive"
	var delivered := (story_state.get("kaelen_hints_delivered", []) as Array).size()
	var held_back := (story_state.get("kaelen_hidden_hints", []) as Array).size()
	# Only used by the post-response leak guard below; NOT put in the prompt.
	var angle := str(story_state.get("kaelen_hidden_angle", "")).strip_edges()
	var prompt := (
		"Kaelen is a guarded broker with a private past she never explains. "
		+ "Her deflection style: %s. " % style
		+ "It is chapter %d; she has let slip %d small hints so far, with %d still held back. " % [chapter, delivered, held_back]
		+ "Output ONLY a 2-4 word mood descriptor for how she comes across right now "
		+ "(e.g. \"guarded and terse\", \"unusually candid\"). No punctuation besides commas."
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
			if mood_leaks_secret(text, angle):
				# The completion echoed the hidden angle. Drop it, keep the
				# prior mood, and record the near-leak so drift is visible.
				GenerationDiagnostics.record_event(
					"kaelen_mood",
					"leak_blocked",
					"story_manager",
					{"chapter": chapter, "rejected_mood": text}
				)
				push_warning(
					"[StoryManager] Blocked a Kaelen mood that echoed the hidden angle: %s" % text
				)
				return
			story_state["kaelen_current_mood"] = text
			_save_story_state()
	)
	var payload := JSON.stringify({
		"model": LocalModelGateway.DEFAULT_SMALL_MODEL,
		"prompt": prompt,
		"stream": false,
		"options": {"num_predict": 20, "temperature": 0.8},
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


func on_docked(station) -> void:
	_dock_count_session += 1
	_check_dock_beats()
	_check_delay_beats()
	_maybe_fire_dock_rumor(station)


# Ambient rumor firing on dock, parallel to the NPC-conversation-triggered
# path in UIManager._station_contact_story_rumor — both share
# record_lounge_rumor_heard() for dedup, so a rumor heard via one path
# correctly suppresses it on the other. force=true lets a debug button bypass
# the roll for manual testing.
func _maybe_fire_dock_rumor(station, force: bool = false) -> void:
	if not force and randf() >= 0.40:
		return
	var context := _dock_rumor_context(station)
	var rumor: Dictionary = get_lounge_rumor(context)
	if rumor.is_empty():
		return
	var rumor_id := str(rumor.get("id", ""))
	if not rumor_id.is_empty():
		record_lounge_rumor_heard(rumor_id)
	var line := str(rumor.get("line", "")).strip_edges()
	if not line.is_empty():
		GlobalState.emit_chatter("SYSTEM", line, Color(0.6, 0.85, 1.0))


func _dock_rumor_context(_station) -> Dictionary:
	# The station node's display-name resolution is private to UIManager
	# (_current_station_display_name) and not safely reachable from here.
	# get_lounge_rumor() already has solid defaults ("the lounge", "this
	# contact", "dock crews") for a missing context, so an empty context is
	# the safe choice rather than guessing at station property names.
	return {}


func on_quest_completed(quest: Dictionary) -> void:
	_check_delay_beats()
	_resolve_hooks_for_quest(quest)


# If this quest was stamped with the hook that was open when it was generated,
# close that hook out. Only ever resolves the one hook it was stamped with —
# never mass-clears pending_hooks, so unrelated open threads survive.
func _resolve_hooks_for_quest(quest: Dictionary) -> void:
	var ref := str(quest.get("story_hook_ref", "")).strip_edges()
	if ref.is_empty():
		return
	var hooks: Array = story_state.get("pending_hooks", [])
	var remaining: Array = []
	var resolved := false
	for hook in hooks:
		var text := str(hook).strip_edges()
		if not resolved and "hook:%s" % text.sha256_text().substr(0, 12) == ref:
			resolved = true
			continue
		remaining.append(hook)
	if not resolved:
		return
	story_state["pending_hooks"] = remaining
	_save_story_state()
	_check_chapter_advance_after_hook_resolution()


# Fires when the player has closed out every hook seeded for the current
# chapter. This game has no ending state — advancing always refills rather
# than finishing. Reserve order: unused act_1_outline beat, then an unused
# story_arc/rumor_trail, then (only if the bible's reserve is exhausted) a
# regeneration_trigger LLM call that appends fresh content. Chapter count
# climbs forever; nothing here can produce a "the story is over" state.
func _check_chapter_advance_after_hook_resolution() -> void:
	if not story_state.get("pending_hooks", []).is_empty():
		return
	if not _campaign_bible_store_ready():
		return
	var bible: Dictionary = _campaign_bible_store.data

	var outline_idx := int(story_state.get("act_1_outline_consumed_index", 0))
	var outline: Array = bible.get("act_1_outline", [])
	if outline_idx < outline.size():
		var beat := str(outline[outline_idx]).strip_edges()
		story_state["act_1_outline_consumed_index"] = outline_idx + 1
		if not beat.is_empty():
			advance_chapter(1, [beat], [beat])
			return

	var arc_idx := int(story_state.get("story_arcs_consumed_index", 0))
	var arcs: Array = bible.get("story_arcs", [])
	var rumor_idx := int(story_state.get("rumor_trails_consumed_index", 0))
	var rumor_trails: Array = bible.get("rumor_trails", [])
	if arc_idx < arcs.size() or rumor_idx < rumor_trails.size():
		var next_tensions: Array = []
		var next_hooks: Array = []
		if arc_idx < arcs.size() and arcs[arc_idx] is Dictionary:
			var summary := str((arcs[arc_idx] as Dictionary).get("summary", "")).strip_edges()
			if not summary.is_empty():
				next_tensions.append(summary)
			story_state["story_arcs_consumed_index"] = arc_idx + 1
		if rumor_idx < rumor_trails.size() and rumor_trails[rumor_idx] is Dictionary:
			var clue_templates: Array = (rumor_trails[rumor_idx] as Dictionary).get("clue_templates", [])
			for clue in clue_templates:
				var clue_text := str(clue).strip_edges()
				if not clue_text.is_empty():
					next_hooks.append(clue_text)
			story_state["rumor_trails_consumed_index"] = rumor_idx + 1
		if not next_tensions.is_empty() or not next_hooks.is_empty():
			advance_chapter(1, next_tensions, next_hooks)
			return

	# Bible's prepared reserve is exhausted — extend the campaign rather than
	# stalling. See C6 fallback policy: retry-once, loud+counted fallback only
	# as a last resort, never a permanent give-up.
	_request_story_horizon_expansion(0)


# Defensive against: _campaign_bible_store being null, or (rare live-reload
# edge case) holding an object whose script didn't resolve is_valid(). Never
# let a stale/bad reference crash the chapter-advance flow.
func _campaign_bible_store_ready() -> bool:
	if _campaign_bible_store == null:
		return false
	if not is_instance_valid(_campaign_bible_store):
		return false
	if not _campaign_bible_store.has_method("is_valid"):
		push_warning(
			"[StoryManager] _campaign_bible_store has no is_valid() method — " +
			"likely a stale reference from a live script reload. Ignoring until next campaign init."
		)
		return false
	return _campaign_bible_store.is_valid()


# Picks the first regeneration_trigger whose metric value is at/under its
# threshold (metrics computed from the live reserve counts). Falls back to the
# first valid trigger if none match, and {} if there are none. Honors all
# triggers and their thresholds instead of always using triggers[0] (plan #14).
func _select_regeneration_trigger(bible: Dictionary) -> Dictionary:
	var triggers: Array = bible.get("regeneration_triggers", [])
	for t in triggers:
		if not t is Dictionary:
			continue
		if _regeneration_metric_value(str(t.get("metric", "")), bible) <= int(t.get("threshold", 0)):
			return t
	for t in triggers:
		if t is Dictionary:
			return t
	return {}


# Live value of a regeneration-trigger metric from the bible reserve minus the
# consumed index tracked in story_state. major_arc_state has no numeric model
# yet, so it reports 0 (always eligible once its trigger is reached).
func _regeneration_metric_value(metric: String, bible: Dictionary) -> int:
	match metric:
		"active_story_arcs_remaining":
			return maxi(0, (bible.get("story_arcs", []) as Array).size() - int(story_state.get("story_arcs_consumed_index", 0)))
		"rumor_trails_remaining":
			return maxi(0, (bible.get("rumor_trails", []) as Array).size() - int(story_state.get("rumor_trails_consumed_index", 0)))
		"prepared_systems_remaining":
			return maxi(0, (bible.get("act_1_outline", []) as Array).size() - int(story_state.get("act_1_outline_consumed_index", 0)))
		_:
			return 0


func _request_story_horizon_expansion(attempt: int) -> void:
	if not _campaign_bible_store_ready():
		return
	var bible: Dictionary = _campaign_bible_store.data
	# Select the trigger whose metric is at/under its threshold (honor all triggers
	# and the bible's ordering, not just triggers[0]) so we append the kind of
	# content that actually ran out. See plan item #14.
	var trigger: Dictionary = _select_regeneration_trigger(bible)
	# Fold recent player choices into the summary so appended story reacts to who
	# the player has been, not just what reserve remains (plan §2.6).
	var summary := get_story_context_block()
	var choice_digest := player_choice_digest()
	if not choice_digest.is_empty():
		summary += "\n" + choice_digest
	LLMInterface.request_story_horizon_expansion(
		bible,
		trigger,
		summary,
		func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				_apply_story_horizon_expansion(result)
				return
			if attempt < 1:
				_request_story_horizon_expansion(attempt + 1)
				return
			_use_story_horizon_expansion_fallback(str(result.get("reason", "unknown")))
	)


func _apply_story_horizon_expansion(result: Dictionary) -> void:
	# The campaign may have reset/reloaded while this async request was in
	# flight — re-check rather than trusting the caller's earlier check.
	if not _campaign_bible_store_ready():
		return
	var bible: Dictionary = _campaign_bible_store.data.duplicate(true)
	var action := str(result.get("action", ""))
	var next_tensions: Array = []
	var next_hooks: Array = []
	if action == "append_story_arc":
		var arc: Dictionary = result.get("story_arc", {})
		var arcs: Array = bible.get("story_arcs", [])
		arcs.append(arc)
		bible["story_arcs"] = arcs
		var summary := str(arc.get("summary", "")).strip_edges()
		if not summary.is_empty():
			next_tensions.append(summary)
	elif action == "append_rumor_trail":
		var trail: Dictionary = result.get("rumor_trail", {})
		var trails: Array = bible.get("rumor_trails", [])
		trails.append(trail)
		bible["rumor_trails"] = trails
		for clue in trail.get("clue_templates", []):
			var clue_text := str(clue).strip_edges()
			if not clue_text.is_empty():
				next_hooks.append(clue_text)
	else:
		var addition: Array = result.get("act_1_outline_addition", [])
		var outline: Array = bible.get("act_1_outline", [])
		var start_idx := outline.size()
		outline.append_array(addition)
		bible["act_1_outline"] = outline
		story_state["act_1_outline_consumed_index"] = start_idx
		# The freshly-appended beats become this chapter's refill; consuming
		# the first one now keeps the same reserve-then-consume flow as the
		# normal path above.
		if not addition.is_empty():
			next_tensions.append(str(addition[0]).strip_edges())
			next_hooks.append(str(addition[0]).strip_edges())
			story_state["act_1_outline_consumed_index"] = start_idx + 1
	_campaign_bible_store.replace_bible(bible)
	GenerationDiagnostics.record_content_source(
		"story_horizon_expansion", "llm", "story_manager", {"action": action}
	)
	if next_tensions.is_empty() and next_hooks.is_empty():
		# Nothing usable came back despite a structurally valid response —
		# treat as a fallback so the chapter still advances.
		_use_story_horizon_expansion_fallback("empty_expansion_content")
		return
	advance_chapter(1, next_tensions, next_hooks)


# Last resort only, per user requirement this must never become the norm:
# retried once already before this is ever called, and every use here is
# logged, counted, and never silently repeated forever — the real LLM path is
# always retried again on the next hook exhaustion regardless of past failures.
func _use_story_horizon_expansion_fallback(reason: String) -> void:
	var count := int(story_state.get("regeneration_fallback_count", 0)) + 1
	story_state["regeneration_fallback_count"] = count
	GenerationDiagnostics.record_event(
		"story_horizon_expansion",
		"fallback_used",
		"story_manager",
		{"reason": reason, "count": count}
	)
	push_warning(
		"[STORY FALLBACK RISK] regeneration_trigger failed twice (%s) — using procedural filler. Count this campaign: %d" %
			[reason, count]
	)
	var bible: Dictionary = _campaign_bible_store.data if _campaign_bible_store != null else {}
	var factions: Array[String] = ["Zenith", "Aurelia", "Vanguard"]
	var faction: String = factions[randi() % factions.size()]
	var filler := "Tensions with %s are quietly escalating." % faction
	if not str(bible.get("core_pressure", "")).strip_edges().is_empty():
		filler = str(bible.get("core_pressure", "")).strip_edges()
	advance_chapter(1, [filler], [filler])


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


# The player may take up to this many contracts back-to-back before a "no work"
# cooldown can hit, so early play isn't gated on the clock every single time.
const AGENT_CONTRACTS_BEFORE_COOLDOWN := 3


func start_agent_contract_cooldown(reason: String = "contract_resolved") -> Dictionary:
	# A completed contract counts toward the streak; only once the streak reaches
	# the threshold does the cooldown actually apply. Abandoning a contract breaks
	# the streak and applies the cooldown immediately, as before.
	if reason != "contract_abandoned":
		var streak := int(story_state.get("agent_contracts_since_cooldown", 0)) + 1
		if streak < AGENT_CONTRACTS_BEFORE_COOLDOWN:
			story_state["agent_contracts_since_cooldown"] = streak
			_save_story_state()
			return get_agent_contract_availability()
	# Threshold reached (or contract abandoned): apply cooldown, reset the streak.
	story_state["agent_contracts_since_cooldown"] = 0
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

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
const StoryScreenshotsType := preload(
	"res://scripts/story/StoryScreenshots.gd"
)
const KaelenHandoffStoreType := preload(
	"res://scripts/persistence/KaelenHandoffStore.gd"
)
const ContextBlockBuilderType := preload(
	"res://scripts/ai/ContextBlockBuilder.gd"
)
const KnowledgeLedgerType := preload(
	"res://scripts/story/KnowledgeLedger.gd"
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
	"kaelen_relationship": {
		"respect": 0,
		"band": "neutral",
		"revision": 0,
		"last_outcome": "",
		"last_mission_title": "",
		"recent_reason": "",
		"last_changed_minute": 0,
	},
	"kaelen_hidden_angle": "",
	"intro_conversation_had": false,
	"intro_agent_visited": false,
	"intro_quest_delivered": false,
	"intro_repair_target_tip_delivered": false,
	"hinted_lounge_rumors": [],
	"agent_cooldown_until_minute": 0,
	"agent_cooldown_message_index": 0,
	"agent_contracts_since_cooldown": 0,
	"faction_pressure": {},
	"player_choices": [],
	"kaelen_hidden_hints": [],
	"kaelen_hints_delivered": [],
	"kaelen_hint_style": "",
	"nova_quirk": "",
	"nova_memory_flicker": "",
	"nova_glitch_hints": [],
	"ambient_used_topics": [],
	"lounge_warmth": {},
	"screenshot_systems_seen": [],
	"screenshot_stations_seen": [],
	"bible_seeded": false,
	"act_1_outline_consumed_index": 0,
	"story_arcs_consumed_index": 0,
	"rumor_trails_consumed_index": 0,
	"regeneration_fallback_count": 0,
	"story_revision": 0,
	"knowledge_revision": 0,
	"mission_history_revision": 0,
	"knowledge_states": {},
	"beat_states": {},
	"chapter_packet_generation_queued": {},
	"declined_offer_cooldowns": {},
	"story_consequences": [],
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
	# Kill-cinematic / boss-kill screenshots ride the same lethal-impact signal
	# N.O.V.A. uses — the execute camera framing is on screen at that moment.
	if is_instance_valid(CombatManager) and CombatManager.has_signal("action_impact"):
		CombatManager.action_impact.connect(_on_screenshot_action_impact)


func reset_for_restart() -> void:
	_scheduled_beats.clear()
	_kill_count_session = 0
	_dock_count_session = 0
	_sq_debug_fired = false


func _on_llm_ready(_model_name: String) -> void:
	# Ollama is up and models are confirmed. Safe to fire the starting-system pool now.
	_trigger_handoff_pool_for_system("system.start")
	_ensure_nova_glitch_hints()


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
	else:
		# Reloaded campaign: state already carries the quirk — re-arm Nova with it.
		_push_nova_campaign_flavor()
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

	# N.O.V.A.'s campaign color. The quirk is player-safe and rides into ambient
	# prompts + her line pools; the memory flicker is director-only (same
	# protection as kaelen_hidden_angle — never in get_story_context_block()).
	var nova_quirk := str(bible_data.get("nova_quirk", "")).strip_edges()
	if not nova_quirk.is_empty():
		story_state["nova_quirk"] = nova_quirk
	var nova_flicker := str(bible_data.get("nova_memory_flicker", "")).strip_edges()
	if not nova_flicker.is_empty():
		story_state["nova_memory_flicker"] = nova_flicker
	_push_nova_campaign_flavor()

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
	# Silent narrative-moment screenshot: the campaign's opening frame.
	StoryScreenshotsType.capture_deferred(_campaign_path(), "campaign_start")

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
		"kaelen_relationship": {
			"respect": 0,
			"band": "neutral",
			"revision": 0,
			"last_outcome": "",
			"last_mission_title": "",
			"recent_reason": "",
			"last_changed_minute": 0,
		},
		"kaelen_hidden_angle": "",
		"intro_conversation_had": false,
		"intro_agent_visited": false,
		"intro_quest_delivered": false,
		"intro_repair_target_tip_delivered": false,
		"hinted_lounge_rumors": [],
		"agent_cooldown_until_minute": 0,
		"agent_cooldown_message_index": 0,
		"agent_contracts_since_cooldown": 0,
		"faction_pressure": {},
		"player_choices": [],
		"kaelen_hidden_hints": [],
		"kaelen_hints_delivered": [],
		"kaelen_hint_style": "",
		"nova_quirk": "",
		"nova_memory_flicker": "",
		"nova_glitch_hints": [],
		"ambient_used_topics": [],
		"lounge_warmth": {},
		"screenshot_systems_seen": [],
		"screenshot_stations_seen": [],
		"bible_seeded": false,
		"act_1_outline_consumed_index": 0,
		"story_arcs_consumed_index": 0,
		"rumor_trails_consumed_index": 0,
		"regeneration_fallback_count": 0,
		"story_revision": 0,
		"knowledge_revision": 0,
		"mission_history_revision": 0,
		"knowledge_states": {},
		"beat_states": {},
		"chapter_packet_generation_queued": {},
		"declined_offer_cooldowns": {},
		"asked_question_intents": [],
	}
	# Part of the wipe contract: a new campaign must not inherit the old
	# campaign's N.O.V.A. quirk (pushes the now-empty quirk, disarming her).
	_push_nova_campaign_flavor()

# ── Phase C: Mission causality ─────────────────────────────────────────────────
# The single reason a mission generated right now exists. Safe for prompts —
# active_tensions is player-facing world state, not a hidden truth.
func capture_story_state_for_checkpoint() -> Dictionary:
	return StoryStateStoreType._migrate_legacy_state(
		story_state.duplicate(true)
	).duplicate(true)


func restore_story_state_from_checkpoint(checkpoint_story_state: Dictionary) -> bool:
	if checkpoint_story_state.is_empty():
		return false
	var restored := StoryStateStoreType._migrate_legacy_state(
		checkpoint_story_state.duplicate(true)
	)
	var validation := StoryStateStoreType._validate_data(restored)
	if not validation.is_valid():
		push_warning(
			"[StoryManager] Checkpoint story_state restore rejected: %s" %
				validation.summary()
		)
		return false
	story_state = restored.duplicate(true)
	_save_story_state()
	_push_context_to_llm()
	_push_nova_campaign_flavor()
	return true


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


func register_chapter_packet(packet: Dictionary) -> void:
	var packet_id := str(packet.get("packet_id", "")).strip_edges()
	if packet_id.is_empty():
		return
	var beat_states: Dictionary = story_state.get("beat_states", {}) \
		if story_state.get("beat_states", {}) is Dictionary else {}
	var changed := false
	var chapter := int(packet.get("chapter", story_state.get("chapter", 1)))
	var beats: Array = packet.get("beats", []) if packet.get("beats", []) is Array else []
	for beat in beats:
		if not beat is Dictionary:
			continue
		var beat_id := str((beat as Dictionary).get("beat_id", "")).strip_edges()
		if beat_id.is_empty() or beat_states.has(beat_id):
			continue
		beat_states[beat_id] = {
			"packet_id": packet_id,
			"chapter": chapter,
			"state": "available",
			"accepted_at_minute": 0,
			"completed_at_minute": 0,
			"outcome": "",
		}
		changed = true
	if changed:
		story_state["beat_states"] = beat_states
		_save_story_state()


func npc_stakes_from_chapter_packet(packet: Dictionary) -> Dictionary:
	var stakes := {}
	var beats: Array = packet.get("beats", []) if packet.get("beats", []) is Array else []
	for beat in beats:
		if not beat is Dictionary:
			continue
		var beat_data: Dictionary = beat
		var stake_text := str(beat_data.get("stake", "")).strip_edges()
		if stake_text.is_empty():
			continue
		var thread_id := str(beat_data.get("thread_id", "")).strip_edges()
		var urgency := int(beat_data.get(
			"urgency",
			4 if bool(beat_data.get("required", false)) else 3
		))
		var entity_ids: Array = beat_data.get("eligible_entity_ids", []) \
			if beat_data.get("eligible_entity_ids", []) is Array else []
		for entity_id_value in entity_ids:
			var entity_id := str(entity_id_value).strip_edges()
			if not entity_id.begins_with("npc.") or stakes.has(entity_id):
				continue
			stakes[entity_id] = {
				"thread_id": thread_id,
				"why_it_matters_to_them": stake_text,
				"urgency": clampi(urgency, 0, 5),
			}
	return stakes


func mark_chapter_beat_state(
	beat_id: String,
	state: String,
	outcome: String = ""
) -> Dictionary:
	var clean_beat_id := beat_id.strip_edges()
	var clean_state := state.strip_edges()
	if clean_beat_id.is_empty():
		return {"ok": false, "error": "Beat ID is required."}
	if not ["available", "offered", "accepted", "completed", "declined", "failed"].has(clean_state):
		return {"ok": false, "error": "Unsupported beat state: %s" % clean_state}
	var beat_states: Dictionary = story_state.get("beat_states", {}) \
		if story_state.get("beat_states", {}) is Dictionary else {}
	var beat_state: Dictionary = beat_states.get(clean_beat_id, {}) \
		if beat_states.get(clean_beat_id, {}) is Dictionary else {}
	beat_state["state"] = clean_state
	if clean_state == "accepted" and int(beat_state.get("accepted_at_minute", 0)) <= 0:
		beat_state["accepted_at_minute"] = int(CampaignClock.total_minutes)
	if ["completed", "declined", "failed"].has(clean_state):
		beat_state["completed_at_minute"] = int(CampaignClock.total_minutes)
		beat_state["outcome"] = outcome.strip_edges()
	beat_states[clean_beat_id] = beat_state
	story_state["beat_states"] = beat_states
	_save_story_state()
	_notify_chapter_packet_consumption_changed()
	return {"ok": true, "beat_state": beat_state.duplicate(true)}


func record_chapter_offer_declined(
	candidate: Dictionary,
	reason: String = "declined",
	cooldown_minutes: int = 180
) -> Dictionary:
	var beat_id := str(candidate.get("beat_id", "")).strip_edges()
	if beat_id.is_empty():
		return {"ok": false, "error": "Declined candidate requires beat_id."}
	var cooldowns: Dictionary = story_state.get("declined_offer_cooldowns", {}) \
		if story_state.get("declined_offer_cooldowns", {}) is Dictionary else {}
	var key := declined_offer_cooldown_key(candidate)
	if not key.is_empty():
		cooldowns[key] = int(CampaignClock.total_minutes) + maxi(1, cooldown_minutes)
	story_state["declined_offer_cooldowns"] = cooldowns
	var result := mark_chapter_beat_state(beat_id, "declined", reason)
	if bool(candidate.get("required", false)):
		var alternate_beat_id := str(candidate.get("alternate_beat_id", "")).strip_edges()
		if not alternate_beat_id.is_empty():
			_activate_alternate_chapter_beat(alternate_beat_id, beat_id)
		else:
			mark_chapter_beat_state(
				beat_id,
				"failed",
				str(candidate.get("decline_consequence", reason))
			)
	return result


func declined_offer_cooldown_key(candidate: Dictionary) -> String:
	var explicit := str(candidate.get("decline_cooldown_key", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var beat_id := str(candidate.get("beat_id", "")).strip_edges()
	var objective := str(candidate.get("objective_type", "")).strip_edges()
	var giver := str(candidate.get("giver_id", "")).strip_edges()
	if beat_id.is_empty() and objective.is_empty() and giver.is_empty():
		return ""
	return "%s|%s|%s" % [beat_id, objective, giver]


func declined_offer_cooldowns() -> Dictionary:
	return (
		story_state.get("declined_offer_cooldowns", {}) as Dictionary
	).duplicate(true) if story_state.get("declined_offer_cooldowns", {}) is Dictionary else {}


func _activate_alternate_chapter_beat(
	alternate_beat_id: String,
	declined_beat_id: String
) -> void:
	var beat_states: Dictionary = story_state.get("beat_states", {}) \
		if story_state.get("beat_states", {}) is Dictionary else {}
	var alternate: Dictionary = beat_states.get(alternate_beat_id, {}) \
		if beat_states.get(alternate_beat_id, {}) is Dictionary else {}
	alternate["state"] = "available"
	alternate["activated_by_decline_of"] = declined_beat_id
	alternate["activated_at_minute"] = int(CampaignClock.total_minutes)
	beat_states[alternate_beat_id] = alternate
	story_state["beat_states"] = beat_states
	_save_story_state()


func chapter_packet_consumed_ratio(packet: Dictionary) -> float:
	var beats: Array = packet.get("beats", []) if packet.get("beats", []) is Array else []
	if beats.is_empty():
		return 0.0
	var beat_states: Dictionary = story_state.get("beat_states", {}) \
		if story_state.get("beat_states", {}) is Dictionary else {}
	var consumed := 0
	var total := 0
	for beat in beats:
		if not beat is Dictionary:
			continue
		var beat_id := str((beat as Dictionary).get("beat_id", "")).strip_edges()
		if beat_id.is_empty():
			continue
		total += 1
		var beat_state: Dictionary = beat_states.get(beat_id, {}) \
			if beat_states.get(beat_id, {}) is Dictionary else {}
		if ["completed", "declined", "failed"].has(str(beat_state.get("state", ""))):
			consumed += 1
	if total <= 0:
		return 0.0
	return float(consumed) / float(total)


func should_queue_next_chapter_packet(packet: Dictionary) -> bool:
	if packet.is_empty():
		return false
	var trigger: Dictionary = packet.get("next_packet_trigger", {}) \
		if packet.get("next_packet_trigger", {}) is Dictionary else {}
	var threshold := float(trigger.get("start_when_consumed_ratio_at_least", 0.6))
	threshold = clampf(threshold, 0.0, 1.0)
	return chapter_packet_consumed_ratio(packet) >= threshold


func mark_next_chapter_packet_queued(chapter: int) -> bool:
	var queued: Dictionary = story_state.get("chapter_packet_generation_queued", {}) \
		if story_state.get("chapter_packet_generation_queued", {}) is Dictionary else {}
	var key := str(maxi(1, chapter))
	if bool(queued.get(key, false)):
		return false
	queued[key] = true
	story_state["chapter_packet_generation_queued"] = queued
	_save_story_state()
	return true


func is_next_chapter_packet_queued(chapter: int) -> bool:
	var queued: Dictionary = story_state.get("chapter_packet_generation_queued", {}) \
		if story_state.get("chapter_packet_generation_queued", {}) is Dictionary else {}
	return bool(queued.get(str(maxi(1, chapter)), false))


func _notify_chapter_packet_consumption_changed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	if tree.current_scene.has_method("maybe_queue_next_chapter_plan_generation"):
		tree.current_scene.call_deferred("maybe_queue_next_chapter_plan_generation")


# Returns a formatted string safe to inject into LLM prompts.
# Never includes player_does_not_know_yet.
func get_story_context_block() -> String:
	return ContextBlockBuilderType.story_state_public_block(story_state)


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


func increment_mission_history_revision(
	event_type: String,
	mission_data: Dictionary = {}
) -> int:
	_record_kaelen_contract_relationship_event(event_type, mission_data)
	return _increment_revision(
		"mission_history_revision",
		event_type,
		mission_data
	)


func increment_story_revision(
	event_type: String,
	event_data: Dictionary = {}
) -> int:
	return _increment_revision("story_revision", event_type, event_data)


func increment_knowledge_revision(
	event_type: String,
	event_data: Dictionary = {}
) -> int:
	return _increment_revision("knowledge_revision", event_type, event_data)


func kaelen_relationship_state() -> Dictionary:
	var relationship: Dictionary = story_state.get("kaelen_relationship", {}) \
		if story_state.get("kaelen_relationship", {}) is Dictionary else {}
	if relationship.is_empty():
		relationship = {
			"respect": 0,
			"band": "neutral",
			"revision": 0,
			"last_outcome": "",
			"last_mission_title": "",
			"recent_reason": "",
			"last_changed_minute": 0,
		}
	var respect := clampi(int(relationship.get("respect", 0)), -6, 6)
	relationship["respect"] = respect
	relationship["band"] = _kaelen_relationship_band_for_respect(respect)
	return relationship.duplicate(true)


func kaelen_relationship_band() -> String:
	return str(kaelen_relationship_state().get("band", "neutral"))


func _record_kaelen_contract_relationship_event(
	event_type: String,
	mission_data: Dictionary
) -> void:
	var clean_event := event_type.strip_edges()
	var delta := _kaelen_relationship_delta_for_event(clean_event)
	if delta == 0:
		return
	var relationship := kaelen_relationship_state()
	var next_respect := clampi(
		int(relationship.get("respect", 0)) + delta,
		-6,
		6
	)
	relationship["respect"] = next_respect
	relationship["band"] = _kaelen_relationship_band_for_respect(next_respect)
	relationship["revision"] = int(relationship.get("revision", 0)) + 1
	relationship["last_outcome"] = clean_event
	relationship["last_mission_title"] = str(
		mission_data.get("title", "the contract")
	)
	relationship["recent_reason"] = str(mission_data.get(
		"decline_reason",
		mission_data.get("outcome_detail", "")
	))
	relationship["last_changed_minute"] = int(CampaignClock.total_minutes)
	story_state["kaelen_relationship"] = relationship


func _kaelen_relationship_delta_for_event(event_type: String) -> int:
	match event_type:
		"completed":
			return 1
		"declined":
			return -1
		"abandoned":
			return -2
		"expired", "failed":
			return -1
		_:
			return 0


func _kaelen_relationship_band_for_respect(respect: int) -> String:
	if respect <= -4:
		return "strained"
	if respect <= -1:
		return "wary"
	if respect >= 5:
		return "favored"
	if respect >= 2:
		return "reliable"
	return "neutral"


func promote_fact_after_delivery(
	fact_id: String,
	next_state: String,
	source: String,
	confidence: String = "direct"
) -> Dictionary:
	var ledger := KnowledgeLedgerType.new(story_state)
	var result: Dictionary = ledger.promote(
		fact_id,
		next_state,
		source,
		int(CampaignClock.total_minutes),
		confidence
	)
	if bool(result.get("ok", false)) and bool(result.get("changed", false)):
		_save_story_state()
	return result


func promote_question_facts_after_delivery(
	question_payload: Dictionary,
	source: String = "mission_question_answer"
) -> Dictionary:
	var declared_fact_ids: Array = (
		question_payload.get("declared_fact_ids", [])
		if question_payload.get("declared_fact_ids", []) is Array
		else []
	)
	var next_state := str(
		question_payload.get("next_state", "known")
	).strip_edges()
	var confidence := str(
		question_payload.get("confidence", "direct")
	).strip_edges()
	var asked_intent_id := str(
		question_payload.get("intent_id", "")
	).strip_edges()
	var promoted: Array[String] = []
	var skipped: Array[String] = []
	var errors: Array[String] = []
	for raw_fact_id in declared_fact_ids:
		var fact_id := str(raw_fact_id).strip_edges()
		if fact_id.is_empty():
			continue
		var result: Dictionary = promote_fact_after_delivery(
			fact_id,
			next_state,
			source,
			confidence
		)
		if not bool(result.get("ok", false)):
			errors.append(str(result.get("error", "unknown_error")))
		elif bool(result.get("changed", false)):
			promoted.append(fact_id)
		else:
			skipped.append(fact_id)
	if not asked_intent_id.is_empty():
		_record_asked_question_intent(asked_intent_id)
	return {
		"ok": errors.is_empty(),
		"promoted_fact_ids": promoted,
		"skipped_fact_ids": skipped,
		"errors": errors,
		"asked_intent_id": asked_intent_id,
	}


func _record_asked_question_intent(intent_id: String) -> void:
	var asked: Array = (
		story_state.get("asked_question_intents", []).duplicate()
		if story_state.get("asked_question_intents", []) is Array
		else []
	)
	if not asked.has(intent_id):
		asked.append(intent_id)
		story_state["asked_question_intents"] = asked
		_save_story_state()


func _increment_revision(
	revision_field: String,
	event_type: String,
	event_data: Dictionary = {}
) -> int:
	var next_revision := maxi(
		0,
		int(story_state.get(revision_field, 0))
	) + 1
	story_state[revision_field] = next_revision
	_save_story_state()
	GlobalState.trace(
		"[TRACE] [StoryManager] %s=%d after %s (%s)" % [
			revision_field,
			next_revision,
			event_type,
			str(event_data.get("runtime_id", event_data.get("title", ""))),
		]
	)
	return next_revision


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
	# Ambient topics retire per chapter (design doc §7): a new chapter means the
	# dock talk moves on, and last chapter's subjects are fair game again.
	story_state["ambient_used_topics"] = []
	_save_story_state()
	StoryScreenshotsType.capture_deferred(
		_campaign_path(), "chapter_%d" % int(story_state.get("chapter", 1))
	)
	_generate_foreshadow()
	_update_kaelen_mood()
	# Story context changed — replace all known agent pools so tone stays current.
	_replace_all_handoff_pools()

# Hands N.O.V.A. her campaign-specific quirk and gate-glitch lines. The quirk
# and the glitch lines are player-safe; the raw memory flicker is director-only
# and never leaves here — the glitch lines are its oblique, leak-guarded shadow.
func _push_nova_campaign_flavor() -> void:
	if not is_instance_valid(Nova):
		return
	if Nova.has_method("set_campaign_quirk"):
		Nova.set_campaign_quirk(str(story_state.get("nova_quirk", "")).strip_edges())
	if Nova.has_method("set_memory_glitch_lines"):
		var hints: Array = story_state.get("nova_glitch_hints", []) if story_state.get("nova_glitch_hints", []) is Array else []
		Nova.set_memory_glitch_lines(hints)


# Belt-and-suspenders guard for N.O.V.A.'s glitch lines: a line that shares a
# long distinctive word with the hidden flicker is explaining, not evoking —
# reject it. Short/common gate-adjacent words are allowlisted because every
# glitch line legitimately talks about gates, memory, and systems.
const _GLITCH_ALLOWED_WORDS := {
	"memory": true, "memories": true, "systems": true, "captain": true,
	"remember": true, "archives": true, "something": true, "nothing": true,
	"through": true, "transit": true, "feeling": true, "somewhere": true,
}


static func glitch_line_leaks_flicker(line: String, flicker: String) -> bool:
	var line_words := _distinctive_words(line)
	var flicker_words := _distinctive_words(flicker)
	for word in line_words:
		if str(word).length() < 6:
			continue
		if _GLITCH_ALLOWED_WORDS.has(word):
			continue
		if flicker_words.has(word):
			return true
	return false


# Generates N.O.V.A.'s campaign gate-glitch lines from the director-only memory
# flicker — once per campaign, on the LARGE model, leak-guarded line by line.
# No canned fallback: if generation fails twice, she simply keeps her stock gate
# lines this session (absence, not filler) and we log it; the next _on_llm_ready
# (next session) retries naturally because the stored list is still empty.
func _ensure_nova_glitch_hints(attempt: int = 0) -> void:
	if not bool(story_state.get("bible_seeded", false)):
		return
	var existing: Array = story_state.get("nova_glitch_hints", []) if story_state.get("nova_glitch_hints", []) is Array else []
	if not existing.is_empty():
		_push_nova_campaign_flavor()
		return
	var flicker := str(story_state.get("nova_memory_flicker", "")).strip_edges()
	if flicker.is_empty():
		return
	if not is_instance_valid(LLMInterface) or not LLMInterface.has_method("request_nova_glitch_hints"):
		return
	var tone := ""
	if _campaign_bible_store_ready():
		tone = str(_campaign_bible_store.data.get("tone", "")).strip_edges()
	LLMInterface.request_nova_glitch_hints(
		flicker,
		tone,
		func(result: Dictionary) -> void:
			if not bool(result.get("ok", false)):
				if attempt < 1:
					_ensure_nova_glitch_hints(attempt + 1)
					return
				GenerationDiagnostics.record_event(
					"nova_glitch_hints", "generation_failed_twice", "story_manager",
					{"reason": str(result.get("reason", "unknown"))}
				)
				return
			var kept: Array = []
			for line in result.get("lines", []):
				var clean := str(line).strip_edges()
				if clean.is_empty():
					continue
				if glitch_line_leaks_flicker(clean, flicker):
					GenerationDiagnostics.record_event(
						"nova_glitch_hints", "leak_blocked", "story_manager",
						{"rejected_line": clean}
					)
					continue
				kept.append(clean)
			if kept.size() < 2:
				if attempt < 1:
					_ensure_nova_glitch_hints(attempt + 1)
					return
				GenerationDiagnostics.record_event(
					"nova_glitch_hints", "too_few_clean_lines", "story_manager",
					{"kept": kept.size()}
				)
				return
			story_state["nova_glitch_hints"] = kept
			_save_story_state()
			_push_nova_campaign_flavor()
			GenerationDiagnostics.record_content_source(
				"nova_glitch_hints", "llm", "story_manager", {"count": kept.size()}
			)
	)


# Compact, player-safe campaign flavor for AMBIENT prompts (background chatter,
# lounge lines, minor NPC topics). Smaller than get_story_context_block() on
# purpose: ambient generation runs on the small model with tight budgets, so
# this carries only what shifts tone — tone/pressure from the bible, the current
# chapter's lead tension, the foreshadow whisper, and N.O.V.A.'s quirk when the
# speaker is her. Never includes any director-only field.
func get_ambient_flavor_block() -> String:
	var lines: Array[String] = []
	if _campaign_bible_store_ready():
		var bible: Dictionary = _campaign_bible_store.data
		var tone := str(bible.get("tone", "")).strip_edges()
		if not tone.is_empty():
			lines.append("Campaign tone: %s" % tone)
		var pressure := str(bible.get("core_pressure", "")).strip_edges()
		if not pressure.is_empty():
			lines.append("What everyone is worried about: %s" % pressure)
		var humor := str(bible.get("humor_rule", "")).strip_edges()
		if not humor.is_empty():
			lines.append("Humor register: %s" % humor)
	var tensions: Array = story_state.get("active_tensions", [])
	if not tensions.is_empty():
		lines.append("Current local tension: %s" % str(tensions[0]).strip_edges())
	var foreshadow := str(story_state.get("current_foreshadow", "")).strip_edges()
	if not foreshadow.is_empty():
		lines.append("Whisper going around: %s" % foreshadow)
	var known: Array = story_state.get("player_knows", [])
	if not known.is_empty():
		lines.append("Common knowledge by now: %s" % str(known[known.size() - 1]).strip_edges())
	if lines.is_empty():
		return ""
	return "\n".join(lines)


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
		"options": {"num_predict": 40, "temperature": 0.8, "num_ctx": LocalModelGateway.SMALL_NUM_CTX},
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
		"options": {"num_predict": 20, "temperature": 0.8, "num_ctx": LocalModelGateway.SMALL_NUM_CTX},
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
	# First arrival in a NEW system is a narrative moment. An empty seen-list
	# means this is the campaign-load arrival — campaign_start covers that.
	var seen_before := not (story_state.get("screenshot_systems_seen", []) as Array).is_empty()
	if _first_visit_and_record("screenshot_systems_seen", system_id) and seen_before:
		StoryScreenshotsType.capture_deferred(
			_campaign_path(), "system_first_visit_%s" % system_id.replace(".", "_")
		)


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
	# First dock at a NEW station — station node name is stable per system.
	if station != null and is_instance_valid(station):
		if _first_visit_and_record("screenshot_stations_seen", str(station.name)):
			StoryScreenshotsType.capture_deferred(_campaign_path(), "station_first_dock")


# True exactly once per id: appends unseen ids to the story_state list (capped
# 64, oldest dropped) and saves. Pure enough to unit-test without a viewport —
# the capture itself is a separate headless-safe call.
func _first_visit_and_record(list_key: String, id: String) -> bool:
	var clean_id := id.strip_edges()
	if clean_id.is_empty():
		return false
	var seen: Array = story_state.get(list_key, []).duplicate() \
		if story_state.get(list_key, []) is Array else []
	if clean_id in seen:
		return false
	seen.append(clean_id)
	while seen.size() > 64:
		seen.pop_front()
	story_state[list_key] = seen
	_save_story_state()
	return true


# Kill-cinematic / boss-kill screenshot triggers. Boss kills always capture
# (rare, earned); ordinary kills are rate-limited so a busy campaign doesn't
# burn the 200-shot cap on routine Reavers.
const _KILL_SHOT_COOLDOWN_MS := 600000  # 10 real minutes
var _last_kill_shot_ms: int = -100000000


func _on_screenshot_action_impact(
	target: Node, _pos: Vector3, _damage: float, lethal: bool, _blocked: bool, _crit: bool
) -> void:
	if not lethal or target == null or not is_instance_valid(target):
		return
	if target == GlobalState.player:
		return  # the player dying is not a keepsake
	if bool(target.get("is_boss")):
		StoryScreenshotsType.capture_deferred(_campaign_path(), "boss_kill")
		return
	var now := Time.get_ticks_msec()
	if now - _last_kill_shot_ms < _KILL_SHOT_COOLDOWN_MS:
		return
	_last_kill_shot_ms = now
	StoryScreenshotsType.capture_deferred(_campaign_path(), "kill_cinematic")


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
	record_mission_outcome_consequence(quest, "completed")
	_resolve_hooks_for_quest(quest)


func record_mission_outcome_consequence(
	quest: Dictionary,
	outcome: String
) -> Dictionary:
	var metadata := _mission_narrative_metadata(quest)
	var consequence_text := _mission_consequence_text(quest, metadata, outcome)
	if consequence_text.is_empty():
		return {"ok": false, "changed": false, "reason": "no_visible_consequence"}
	var consequences: Array = story_state.get("story_consequences", []) \
		if story_state.get("story_consequences", []) is Array else []
	var entry := {
		"outcome": outcome.strip_edges(),
		"text": consequence_text,
		"thread_id": str(metadata.get("story_thread_id", "")),
		"beat_id": str(metadata.get("story_beat_id", "")),
		"cause_id": str(metadata.get("cause_id", "")),
		"at_minute": int(CampaignClock.total_minutes),
	}
	consequences.append(entry)
	while consequences.size() > 12:
		consequences.pop_front()
	story_state["story_consequences"] = consequences
	_promote_completion_facts_from_metadata(metadata, outcome)
	story_state["story_revision"] = maxi(0, int(story_state.get("story_revision", 0))) + 1
	_save_story_state()
	return {"ok": true, "changed": true, "consequence": entry}


func _mission_narrative_metadata(quest: Dictionary) -> Dictionary:
	var metadata: Dictionary = {}
	var nested: Variant = quest.get("narrative_metadata", {})
	if nested is Dictionary:
		metadata = (nested as Dictionary).duplicate(true)
	for field in [
		"story_thread_id",
		"story_beat_id",
		"story_hook_ref",
		"cause_id",
		"public_because",
		"stake",
	]:
		if quest.has(field):
			metadata[field] = str(quest.get(field, ""))
	for field in ["completion_fact_ids", "question_fact_ids"]:
		if quest.get(field, null) is Array:
			metadata[field] = (quest[field] as Array).duplicate(true)
	return metadata


func _mission_consequence_text(
	quest: Dictionary,
	metadata: Dictionary,
	outcome: String
) -> String:
	var snapshot: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var candidate: Dictionary = snapshot.get("story_candidate", {}) \
		if snapshot.get("story_candidate", {}) is Dictionary else {}
	var world_consequence := str(candidate.get("world_consequence", "")).strip_edges()
	if world_consequence.is_empty():
		world_consequence = str(metadata.get("public_because", "")).strip_edges()
	var decline_consequence := str(candidate.get("decline_consequence", "")).strip_edges()
	var stake := str(metadata.get("stake", candidate.get("stake", ""))).strip_edges()
	match outcome.strip_edges():
		"completed":
			if not world_consequence.is_empty():
				return world_consequence
			if not stake.is_empty():
				return "Resolved pressure: %s" % stake
		"declined":
			if not decline_consequence.is_empty():
				return decline_consequence
			if not world_consequence.is_empty():
				return "Opportunity declined: %s" % world_consequence
			if not stake.is_empty():
				return "Opportunity declined: %s" % stake
		"abandoned", "expired", "failed":
			if not world_consequence.is_empty():
				return "Unresolved pressure: %s" % world_consequence
			if not stake.is_empty():
				return "Unresolved pressure: %s" % stake
	var title := str(quest.get("title", "")).strip_edges()
	if not title.is_empty() and not outcome.strip_edges().is_empty():
		return "%s: %s" % [outcome.strip_edges().capitalize(), title]
	return ""


func _promote_completion_facts_from_metadata(
	metadata: Dictionary,
	outcome: String
) -> void:
	if outcome.strip_edges() != "completed":
		return
	var fact_ids: Array = metadata.get("completion_fact_ids", []) \
		if metadata.get("completion_fact_ids", []) is Array else []
	if fact_ids.is_empty():
		return
	var ledger := KnowledgeLedgerType.new(story_state)
	for fact_id in fact_ids:
		ledger.promote(
			str(fact_id),
			KnowledgeLedgerType.STATE_KNOWN,
			"mission_completed",
			int(CampaignClock.total_minutes),
			"direct"
		)


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
	# Screenshot the moment a story thread closes — but only when this was NOT
	# the chapter's last hook, since advance_chapter captures its own frame and
	# two near-identical shots in the same second help nobody.
	if not remaining.is_empty():
		StoryScreenshotsType.capture_deferred(_campaign_path(), "hook_resolved")
	_check_chapter_advance_after_hook_resolution()


# Campaign directory for narrative artifacts (screenshots, future PDF). ""
# when no campaign is open — StoryScreenshots treats that as a no-op.
func _campaign_path() -> String:
	if _story_state_store == null or not _story_state_store.is_valid():
		return ""
	return str(_story_state_store.campaign_path)


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
	# Chapter-paced Kaelen observation (closes the loop on the bible's
	# kaelen_hint_plan, which was generated but never delivered anywhere).
	# Hints are player-safe SURFACE observations about her, so they surface as
	# something the contact noticed — never as Kaelen explaining herself. Pacing
	# rule: the player can have heard at most one hint per chapter; the pop from
	# hidden to delivered happens in record_lounge_rumor_heard() only when the
	# line was actually heard.
	var next_kaelen_hint := _next_kaelen_hint_if_due()
	if not next_kaelen_hint.is_empty():
		candidates.append({
			"id": "kaelen_hint:%s" % next_kaelen_hint.sha256_text().substr(0, 12),
			"title": "Something About Kaelen",
			"source": "Story",
			"weight": 5,
			"line": "%s glances toward the broker's corner and drops their voice. %s Nobody else seems to clock it." % [
				npc_name,
				next_kaelen_hint.trim_suffix(".") + ".",
			],
		})
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
	# Echo weight climbs with chapter: early on, dock talk chases open threads;
	# by late campaign the things the player has already uncovered dominate the
	# room — the world audibly catches up to the mystery as it unravels.
	var echo_weight := clampi(int(story_state.get("chapter", 1)) - 1, 1, 5)
	var known: Array = story_state.get("player_knows", [])
	for truth in known:
		var text := str(truth).strip_edges()
		if text.is_empty():
			continue
		candidates.append({
			"id": "known:%s" % text.sha256_text().substr(0, 12),
			"title": "Echo",
			"source": "Story",
			"weight": echo_weight,
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


# The next undelivered Kaelen hint, or "" when none is due. Due = hints remain
# AND the player has heard fewer hints than the current chapter number, so hints
# escalate at most one per chapter no matter how much lounge-hopping happens.
func _next_kaelen_hint_if_due() -> String:
	var undelivered: Array = story_state.get("kaelen_hidden_hints", [])
	if undelivered.is_empty():
		return ""
	var delivered_count := (story_state.get("kaelen_hints_delivered", []) as Array).size()
	if delivered_count >= int(story_state.get("chapter", 1)):
		return ""
	return str(undelivered[0]).strip_edges()


# ── Lounge Social Layer L2: contact warmth ────────────────────────────────────
# Warmth 0..3 per lounge contact, earned by buying drinks (and later, good
# conversations). Player-safe world texture: colors conversation openers and
# raises L3 approach odds. New generated contacts should use stable NPC IDs;
# legacy display-name slugs are still read and migrated on first contact.

# Phase 9: contact conversations grant knowledge through real fact IDs,
# never free-form strings appended to pending_hooks. The stranger's paid
# tip lands in the knowledge ledger as a RUMORED fact with player-safe
# public text — which also makes it an askable lounge question (the
# intent selector reads rumored facts).
func record_stranger_intel_fact(station_display: String) -> Dictionary:
	var minute := int(CampaignClock.total_minutes) \
		if is_instance_valid(CampaignClock) else 0
	var salt := "%s|%d" % [station_display.strip_edges(), minute]
	var fact_id := "fact.stranger_intel.m%d_%s" % [
		maxi(0, minute),
		salt.sha256_text().substr(0, 8),
	]
	var ledger := KnowledgeLedger.new(story_state)
	var promoted := ledger.promote(
		fact_id,
		KnowledgeLedger.STATE_RUMORED,
		"lounge_stranger",
		minute
	)
	if not bool(promoted.get("ok", false)):
		return {"ok": false, "error": str(promoted.get("error", "promote_failed"))}
	var states: Dictionary = story_state.get("knowledge_states", {})
	var record: Dictionary = states.get(fact_id, {}) \
		if states.get(fact_id, {}) is Dictionary else {}
	record["public_text"] = (
		"A paid tip from a stranger at %s — coordinates and a name."
		% station_display.strip_edges()
	)
	record["alias"] = "the stranger's tip"
	states[fact_id] = record
	story_state["knowledge_states"] = states
	_save_story_state()
	return {"ok": true, "fact_id": fact_id}


static func lounge_warmth_key(npc_name: String) -> String:
	var out := ""
	for ch in npc_name.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.is_empty() and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


static func lounge_warmth_key_for_contact(
	contact_key: String,
	legacy_name: String = ""
) -> String:
	var clean_key := contact_key.strip_edges()
	if not clean_key.is_empty():
		return clean_key
	return lounge_warmth_key(legacy_name)


func lounge_warmth_for(npc_name: String) -> int:
	return lounge_warmth_for_contact("", npc_name)


func lounge_warmth_for_contact(contact_key: String, legacy_name: String = "") -> int:
	var key := lounge_warmth_key_for_contact(contact_key, legacy_name)
	if key.is_empty():
		return 0
	var warmth: Dictionary = story_state.get("lounge_warmth", {}) \
		if story_state.get("lounge_warmth", {}) is Dictionary else {}
	var migrated := _migrate_lounge_warmth_key(warmth, key, legacy_name)
	if migrated:
		story_state["lounge_warmth"] = warmth
		_save_story_state()
	return clampi(int(warmth.get(key, 0)), 0, 3)


func adjust_lounge_warmth(npc_name: String, delta: int) -> void:
	adjust_lounge_warmth_for_contact("", npc_name, delta)


func adjust_lounge_warmth_for_contact(
	contact_key: String,
	legacy_name: String,
	delta: int
) -> void:
	var key := lounge_warmth_key_for_contact(contact_key, legacy_name)
	if key.is_empty():
		return
	var warmth: Dictionary = story_state.get("lounge_warmth", {}).duplicate() \
		if story_state.get("lounge_warmth", {}) is Dictionary else {}
	_migrate_lounge_warmth_key(warmth, key, legacy_name)
	warmth[key] = clampi(int(warmth.get(key, 0)) + delta, 0, 3)
	# Cap the dict so a long campaign of one-off contacts can't grow unbounded.
	while warmth.size() > 64:
		warmth.erase(warmth.keys()[0])
	story_state["lounge_warmth"] = warmth
	_save_story_state()


func _migrate_lounge_warmth_key(
	warmth: Dictionary,
	contact_key: String,
	legacy_name: String
) -> bool:
	var legacy_key := lounge_warmth_key(legacy_name)
	if contact_key.is_empty() \
			or legacy_key.is_empty() \
			or contact_key == legacy_key \
			or warmth.has(contact_key) \
			or not warmth.has(legacy_key):
		return false
	warmth[contact_key] = warmth[legacy_key]
	warmth.erase(legacy_key)
	return true


# Ambient-chat topic dedup (Phase E). Capped like hinted_lounge_rumors so the
# state file can't grow unbounded on a very long chapter.
func record_ambient_topic_used(topic_id: String) -> void:
	var clean_id := topic_id.strip_edges()
	if clean_id.is_empty():
		return
	var used: Array = story_state.get("ambient_used_topics", []).duplicate() \
		if story_state.get("ambient_used_topics", []) is Array else []
	if clean_id in used:
		return
	used.append(clean_id)
	while used.size() > 48:
		used.pop_front()
	story_state["ambient_used_topics"] = used
	_save_story_state()


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
	# Hearing a Kaelen-hint rumor is the delivery moment: pop it from the
	# director-only hidden list to the player-safe delivered list, and let her
	# mood drift now that she's let one more thing slip.
	if clean_id.begins_with("kaelen_hint:"):
		var current := _next_kaelen_hint_if_due()
		if not current.is_empty() \
				and clean_id == "kaelen_hint:%s" % current.sha256_text().substr(0, 12):
			deliver_next_kaelen_hint()
			_update_kaelen_mood()
			return  # deliver_next_kaelen_hint already saved state
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
	if _handoff_store.has_method("draw_scoped"):
		return _handoff_store.draw_scoped(
			agent_name,
			_kaelen_handoff_story_revision(),
			_kaelen_handoff_system_id(),
			_kaelen_handoff_relationship_band(agent_name)
		)
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
		var current_count := _kaelen_handoff_pool_size(agent_name, system_id)
		if not force_replace and current_count >= 4:
			continue
		var queued := _queue_handoff_pool_refill(
			agent_name,
			entry["faction"],
			entry["agent_role"],
			system_id,
			current_count,
			16,
			force_replace
		)
		if bool(queued.get("ok", false)) or bool(queued.get("deferred", false)):
			continue
		generate_handoff_pool(agent_name, entry["faction"], entry["agent_role"], system_id)

# Full replace for all known agents — called on chapter advance.
func _replace_all_handoff_pools() -> void:
	if _handoff_store == null or not _handoff_store.is_valid():
		return
	for entry in _FACTION_AGENT_MAP.values():
		generate_handoff_pool(
			entry["agent_name"],
			entry["faction"],
			entry["agent_role"],
			_kaelen_handoff_system_id()
		)

# Async: asks Gemma4 for 16 handoff lines, saves to pool on success.
func generate_handoff_pool(
	agent_name: String,
	faction: String,
	agent_role: String,
	system_id: String = ""
) -> void:
	if not is_instance_valid(LLMInterface):
		return
	var story_context := get_story_context_block()
	var scope_system_id := system_id.strip_edges()
	if scope_system_id.is_empty():
		scope_system_id = _kaelen_handoff_system_id()
	var story_revision := _kaelen_handoff_story_revision()
	var relationship_band := _kaelen_handoff_relationship_band(agent_name)
	LLMInterface.request_kaelen_handoff_batch(
		agent_name, agent_role, faction, story_context, 16,
		func(lines: Array) -> void:
			if lines.is_empty():
				push_warning("[StoryManager] Handoff batch returned empty for %s" % agent_name)
				return
			var refill_result := refill_kaelen_handoff_pool_from_lines(
				agent_name,
				lines,
				scope_system_id,
				story_revision,
				relationship_band
			)
			if not bool(refill_result.get("ok", false)):
				push_warning(
					"[StoryManager] Handoff pool refill failed for %s: %s" % [
						agent_name,
						str(refill_result.get("status", "unknown")),
					]
				)
	)


func refill_kaelen_handoff_pool_from_lines(
	agent_name: String,
	lines: Array,
	system_id: String = "",
	story_revision: int = -1,
	relationship_band: String = ""
) -> Dictionary:
	if _handoff_store == null or not _handoff_store.is_valid():
		return {"ok": false, "status": "handoff_store_unavailable"}
	var clean_lines: Array = []
	for raw_line in lines:
		var line := str(raw_line).strip_edges()
		if not line.is_empty():
			clean_lines.append(line)
	if clean_lines.is_empty():
		return {"ok": false, "status": "empty_lines"}
	var scope_system_id := system_id.strip_edges()
	if scope_system_id.is_empty():
		scope_system_id = _kaelen_handoff_system_id()
	var scoped_revision := story_revision
	if scoped_revision < 0:
		scoped_revision = _kaelen_handoff_story_revision()
	var scoped_relationship := relationship_band.strip_edges()
	if scoped_relationship.is_empty():
		scoped_relationship = _kaelen_handoff_relationship_band(agent_name)
	if _handoff_store.has_method("refill_scoped"):
		_handoff_store.refill_scoped(
			agent_name,
			scoped_revision,
			scope_system_id,
			scoped_relationship,
			clean_lines
		)
	else:
		_handoff_store.refill(agent_name, clean_lines)
	print("[StoryManager] Handoff pool refilled for %s (%d lines)" % [agent_name, clean_lines.size()])
	return {
		"ok": true,
		"count": clean_lines.size(),
		"system_id": scope_system_id,
		"story_revision": scoped_revision,
		"relationship_band": scoped_relationship,
	}


func _queue_handoff_pool_refill(
	agent_name: String,
	faction: String,
	agent_role: String,
	system_id: String,
	current_count: int,
	target_count: int,
	force_replace: bool = false
) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"ok": false, "status": "tree_unavailable"}
	var game_root := tree.current_scene
	if game_root == null or not game_root.has_method("queue_kaelen_handoff_pool_refill"):
		return {"ok": false, "status": "scheduler_bridge_unavailable"}
	return game_root.call(
		"queue_kaelen_handoff_pool_refill",
		agent_name,
		faction,
		agent_role,
		system_id,
		current_count,
		target_count,
		_kaelen_handoff_story_revision(),
		_kaelen_handoff_relationship_band(agent_name),
		force_replace
	)


func _kaelen_handoff_pool_size(agent_name: String, system_id: String) -> int:
	if _handoff_store == null or not _handoff_store.is_valid():
		return 0
	if _handoff_store.has_method("pool_size_scoped"):
		return _handoff_store.pool_size_scoped(
			agent_name,
			_kaelen_handoff_story_revision(),
			system_id,
			_kaelen_handoff_relationship_band(agent_name)
		)
	return _handoff_store.pool_size(agent_name)


func _kaelen_handoff_story_revision() -> int:
	return int(story_state.get("story_revision", story_state.get("chapter", 0)))


func _kaelen_handoff_system_id() -> String:
	if is_instance_valid(GlobalState):
		var global_system := str(GlobalState.current_system_id).strip_edges()
		if not global_system.is_empty():
			return global_system
	return str(story_state.get("current_system_id", "system.start"))


func _kaelen_handoff_relationship_band(_agent_name: String) -> String:
	return kaelen_relationship_band()

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

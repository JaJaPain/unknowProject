extends Node

## Signal tuning in the running game. A while into flight in a system,
## N.O.V.A. notices a faint transmission (always when a story thread can be
## overheard here, about half the time otherwise) and the captain can press T
## to tune in. What comes through is played on comms as heard, garbled where
## the lock was weak; a story thread joins the Loose ends board, and ambient
## chatter is sold to a broker.
##
## A failed attempt hears nothing, and the transmission may be offered again
## on a later visit.

const PanelType := preload("res://scripts/ui/SignalTuningPanel.gd")
const Model := preload("res://scripts/story/activities/SignalTuningModel.gd")
const FaintType := preload("res://scripts/story/activities/FaintTransmissions.gd")
const VoiceType := preload("res://scripts/story/premise/VoiceDNA.gd")
const LeverageType := preload("res://scripts/story/premise/Leverage.gd")

## Seconds of calm flight in a system before she mentions it.
const OFFER_AFTER_MIN_S := 40.0
const OFFER_AFTER_MAX_S := 110.0
const AMBIENT_OFFER_CHANCE := 0.5
const TUNE_KEY := KEY_T

const OFFER_LINES: Array[String] = [
	# Statements that point at the receiver prompt, never an open question the
	# player can't see how to answer (Abe, 2026-09-30).
	"Something faint under the static, close by. I've routed it to your receiver. Tune it and we might get words.",
	"There's a voice down in the noise floor. Someone isn't meant to be heard. It's on your receiver now.",
	"Faint transmission, very quiet. I've patched it through to your receiver. It's yours to tune.",
]
const RESULT_LINES := {
	"thread_clean": ["Got all of it. I've put it on the loose ends board.", "Clean copy. That one's going on the board."],
	"thread_partial": ["Most of it. I kept the recording for the board.", "Patchy, but enough. It's on the board."],
	"ambient_clean": ["Clean copy. A broker will pay for that.", "Every word. I've already found a buyer."],
	"ambient_partial": ["Bits and pieces. A broker took it anyway, cheap.", "Half a conversation still sells. Not for much."],
	"failed": ["Lost it. Whoever it was has gone quiet.", "Gone. Maybe they'll talk again another time."],
}

var director: Node = null
## Returns the premise world snapshot for the current system.
var world_provider: Callable = Callable()

var _system_id := ""
var _flight_s := 0.0
var _offer_at := 0.0
var _decided := false
var _offered: Dictionary = {}
var _panel: Node = null
## On-screen prompt while an offer is open: the only other hint was one comms
## line that scrolled away, so players never knew the receiver existed.
var _prompt_layer: CanvasLayer = null
var _prompt: PanelContainer = null
var _prompt_t := 0.0
## The first offer ever gets her full explanation (saved in story_state).
const TAUGHT_FLAG := "signal_tuning_taught"
const FIRST_OFFER_AFTER_S := 30.0


func _taught() -> bool:
	var story := get_node_or_null("/root/StoryManager")
	return story != null and bool(story.story_state.get(TAUGHT_FLAG, false))

const TEACH_LINE := "First time on the receiver, so here's how it works. Press T and I'll hand you the dials. Frequency finds the voice, phase cleans it up, and if you hold it clear it locks. Recordings sell, and now and then one leads somewhere."


func _process(delta: float) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	var system_id := str(gs.current_system_id)
	if system_id != _system_id:
		_system_id = system_id
		_flight_s = 0.0
		# Until she has taught it once, the offer is certain and comes early,
		# so a new player meets the receiver instead of maybe never.
		_offer_at = FIRST_OFFER_AFTER_S if not _taught() else randf_range(OFFER_AFTER_MIN_S, OFFER_AFTER_MAX_S)
		_decided = false
		_offered = {}
	_update_prompt(delta)
	if _panel != null:
		if not _can_listen():
			_panel.abort()
		return
	if not _can_listen():
		return
	_flight_s += delta
	# Never offered beside a station: its traffic and dock chatter drown out
	# anything faint (Abe, 2026-09-30). The clock waits until we're clear.
	if not _decided and _flight_s >= _offer_at and not _near_station():
		_decided = true
		_try_offer()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == TUNE_KEY:
		if not _offered.is_empty() and _panel == null and _can_listen() and not _near_station():
			open_tuning()
			get_viewport().set_input_as_handled()


## No receiver work within this range of any station.
const STATION_QUIET_RANGE := 1000.0


func _near_station() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not is_instance_valid(player):
		return false
	for station in get_tree().get_nodes_in_group("station"):
		if station is Node3D and is_instance_valid(station) 				and (station as Node3D).global_position.distance_to((player as Node3D).global_position) < STATION_QUIET_RANGE:
			return true
	return false


func has_offer() -> bool:
	return not _offered.is_empty()


func _can_listen() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or bool(gs.get("intro_cinematic_active")):
		return false
	# Not behind the title, loading screen or cinematic: the ship exists (and is
	# undocked) during a new campaign's load, so the offer and its prompt fired
	# over the loading screen (Abe, 2026-09-30).
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("_world_hidden") and bool(nova.call("_world_hidden")):
		return false
	var player = gs.player
	if not is_instance_valid(player) or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return false
	var combat := get_node_or_null("/root/CombatManager")
	return combat == null or int(combat.get("state")) == 0


func _try_offer() -> void:
	if director == null or not is_instance_valid(director) or not world_provider.is_valid():
		return
	var world: Dictionary = world_provider.call()
	if world.is_empty():
		return
	var item: Dictionary = director.faint_transmission(world, randi())
	if item.is_empty():
		return
	if _taught() and str(item.get("kind", "")) == "ambient" and randf() > AMBIENT_OFFER_CHANCE:
		return
	offer(item)


## Make `item` available to tune into, and have her mention it.
func offer(item: Dictionary) -> void:
	_offered = item
	var story := get_node_or_null("/root/StoryManager")
	var taught := story != null and bool(story.story_state.get(TAUGHT_FLAG, false))
	_nova(OFFER_LINES[randi() % OFFER_LINES.size()] + ("" if taught else " " + TEACH_LINE))
	if story != null and not taught:
		story.story_state[TAUGHT_FLAG] = true
	load("res://scripts/ui/Wiki.gd").unlock("receiver")
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("RECEIVER", "Faint transmission. Press T to tune in.", Color(0.5, 0.95, 0.85))


## "[T] TUNE RECEIVER" at the bottom of the screen, gently pulsing, for as long
## as the offer is open and the player is free to take it.
func _update_prompt(delta: float) -> void:
	var show := not _offered.is_empty() and _panel == null and _can_listen() and not _near_station()
	if show and _prompt == null:
		_build_prompt()
	if _prompt == null:
		return
	_prompt.visible = show
	if show:
		_prompt_t += delta
		_prompt.modulate.a = 0.75 + 0.25 * sin(_prompt_t * 3.0)


func _build_prompt() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 5
	add_child(_prompt_layer)
	_prompt = PanelContainer.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -150.0
	_prompt.offset_bottom = -110.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.1, 0.85)
	style.border_color = Color(0.5, 0.95, 0.85, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_prompt.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "[T]  TUNE RECEIVER   ·   faint transmission nearby"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	_prompt.add_child(label)
	_prompt_layer.add_child(_prompt)


func open_tuning() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	_panel = PanelType.new()
	add_child(_panel)
	_panel.finished.connect(_on_finished)
	var interference := float(gs.environment_value("signal_interference", 1.0)) if gs != null else 1.0
	_panel.begin(randi(), interference)


func _on_finished(outcome_id: String, clarity: float) -> void:
	_panel = null
	var item := _offered
	_offered = {}
	if item.is_empty():
		return
	if outcome_id == "failed":
		_nova(_line("failed"))
		return
	var now := int(get_node("/root/CampaignClock").total_minutes) if has_node("/root/CampaignClock") else 0
	if director != null and is_instance_valid(director):
		director.overhear(item, now)
		# Leverage: a story conversation overheard is something on its speaker.
		if str(item.get("kind", "")) == "thread" and director.has_method("record_leverage_entry"):
			var system_id := str(get_node("/root/GlobalState").current_system_id) if has_node("/root/GlobalState") else ""
			var kept: Dictionary = director.record_leverage_entry(LeverageType.make("intercept", str(item.get("id", "")),
				str(item.get("speaker_name", "")), "Overheard: " + str(item.get("text", "")).trim_prefix("…"), system_id, now))
			if not kept.is_empty():
				get_tree().create_timer(9.0).timeout.connect(func() -> void:
					_nova("I kept the recording. That's leverage on %s, if we want it." % str(kept["subject"])))
	var heard := Model.garble(str(item["text"]), clarity, hash(str(item["id"])))
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("INTERCEPT", heard, Color(0.6, 0.85, 0.8))
	var speech := get_node_or_null("/root/SpeechService")
	if speech != null:
		# Lost words become pauses in the voice.
		var spoken := heard.replace("…", ", ").strip_edges().trim_prefix(",").strip_edges()
		speech.play_on_comms(spoken, VoiceType.register(VoiceType.for_person(str(item.get("speaker_id", "")))), "Intercept")
	var kind := "thread" if str(item.get("kind", "")) == "thread" else "ambient"
	var grade := "clean" if outcome_id == "clean" else "partial"
	if kind == "ambient" and gs != null:
		var pay := int(FaintType.AMBIENT_PAY.get(outcome_id, 0))
		gs.add_credits(pay)
		gs.emit_chatter("RECEIVER", "Intercept sold to a data broker: %d credits." % pay, Color(0.5, 0.95, 0.85))
	# She comments once the intercept has played.
	var line := _line("%s_%s" % [kind, grade])
	var wait := 2.0 + heard.split(" ").size() * 0.35
	get_tree().create_timer(wait).timeout.connect(func() -> void: _nova(line))


func _line(key: String) -> String:
	var pool: Array = RESULT_LINES.get(key, RESULT_LINES["failed"])
	return str(pool[randi() % pool.size()])


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "mystery")

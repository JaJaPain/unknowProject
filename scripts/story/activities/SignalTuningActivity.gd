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

## Difficulty (Abe, 2026-10-01): seconds to get the lock, and what an ambient
## intercept pays relative to FaintTransmissions.AMBIENT_PAY. The start system
## is always easy.
const DIFFICULTY_SECONDS := {"easy": 40.0, "medium": 25.0, "hard": 15.0}
const DIFFICULTY_PAY := {"easy": 1.0, "medium": 1.6, "hard": 2.5}
## Each difficulty has its own offer lines, so a player learns to hear how hard
## one will be. She never names the difficulty. Statements that point at the
## receiver, never an open question (Abe, 2026-09-30).
const OFFER_LINES := {
	"easy": [
		"Something under the static, close by and fairly steady. I've routed it to your receiver.",
		"A voice in the noise floor, not far off. It's holding still for now. It's on your receiver.",
		"Transmission nearby, faint but patient. I've patched it through to your receiver.",
	],
	"medium": [
		"Something faint under the static, and it's drifting. I've routed it to your receiver. Don't dawdle.",
		"There's a voice down in the noise floor. Someone isn't meant to be heard. It's on your receiver now.",
		"Faint transmission, very quiet, coming and going. I've patched it through to your receiver.",
	],
	"hard": [
		"Barely anything there, and it's slipping already. It's on your receiver. Quickly.",
		"A whisper under a lot of static, fading as I listen. Your receiver has it, for now.",
		"Something's transmitting on the edge of nothing. It won't last. Receiver's yours.",
	],
}
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

const TEACH_LINE := "First time on the receiver, so here's how it works. Press T and I'll hand you the dials. Frequency finds the voice, phase cleans it up, and if you hold it clear it locks. They fade, so don't take all day. Recordings sell, and now and then one leads somewhere."
## The system line that goes with every offer (the prompt's own name).
const SYSTEM_PROMPT_LINE := "Press T to TUNE RECEIVER: faint transmission nearby."


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
	_update_status(delta)
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
		if press_tune():
			get_viewport().set_input_as_handled()


## T always answers (playtest 2026-10-02: it was silently ignored whenever
## something blocked the receiver, even with a signal she had announced).
## Returns what happened: "tuning", "blocked", "scanning", or "" when the ship
## isn't flying (docked, loading, cinematic) and T means nothing.
func press_tune() -> String:
	if _panel != null or not _flying():
		return ""
	var reason := listen_block_reason()
	if not reason.is_empty():
		_show_status(reason, false, STATUS_SECONDS)
		return "blocked"
	if not _offered.is_empty():
		_hide_status()
		open_tuning()
		return "tuning"
	_show_status(SCANNING_TEXT, true, SCAN_SECONDS)
	return "scanning"


## Tests stand in for "the ship is flying" here.
var flying_override: Callable = Callable()
const SCANNING_TEXT :="RECEIVER   ·   Scanning for signals..."
const NOTHING_TEXT := "RECEIVER   ·   Nothing on the band."
const SCAN_SECONDS := 3.0
const STATUS_SECONDS := 3.5


## Why the receiver can't be used right now ("" when it can). The ship must be
## flying for any of these to apply.
func listen_block_reason() -> String:
	var combat := get_node_or_null("/root/CombatManager")
	if combat != null and int(combat.get("state")) != 0:
		return "RECEIVER   ·   Not in the middle of a fight."
	var threat := threat_label()
	if not threat.is_empty():
		return "RECEIVER   ·   Hostile close (%s). Can't hold a weak signal with them around." % threat
	if _near_station():
		return "RECEIVER   ·   Too much station noise. Move further out."
	return ""


## Undocked, alive, and the world on screen (not the title, loading or a
## cinematic).
func _flying() -> bool:
	if flying_override.is_valid():
		return bool(flying_override.call())
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or bool(gs.get("intro_cinematic_active")):
		return false
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("_world_hidden") and bool(nova.call("_world_hidden")):
		return false
	var player = gs.player
	return is_instance_valid(player) and not bool(player.get("is_docked")) and not bool(player.get("destroyed"))


var _status_layer: CanvasLayer = null
var _status: PanelContainer = null
var _status_label: Label = null
var _status_sweep: ColorRect = null
var _status_left := 0.0
var _status_scanning := false
var _status_t := 0.0


## A small receiver readout where the T prompt sits: a scan with a sweeping
## bar, or a one-line reason.
func _show_status(text: String, scanning: bool, seconds: float) -> void:
	if _status == null:
		_build_status()
	_status_label.text = text
	_status_scanning = scanning
	_status_left = seconds
	_status_t = 0.0
	_status.visible = true
	_status.modulate.a = 1.0
	if _prompt != null:
		_prompt.visible = false


func _hide_status() -> void:
	if _status != null:
		_status.visible = false
	_status_left = 0.0


func _update_status(delta: float) -> void:
	if _status == null or not _status.visible:
		if _status_sweep != null:
			_status_sweep.visible = false
		return
	_status_t += delta
	_status_sweep.visible = _status_scanning
	if _status_scanning:
		# The sweep: a bright bar sliding along the readout, back and forth.
		var track := maxf(_status.size.x - 36.0 - _status_sweep.size.x, 1.0)
		_status_sweep.position = _status.position + Vector2(18.0 + track * (0.5 - 0.5 * cos(_status_t * 3.2)), _status.size.y - 6.0)
		_status_label.modulate.a = 0.7 + 0.3 * sin(_status_t * 6.0)
	else:
		_status_label.modulate.a = 1.0
	_status_left -= delta
	if _status_left <= 0.0:
		if _status_scanning:
			# The scan found nothing (a signal would already be on offer).
			_show_status(NOTHING_TEXT, false, STATUS_SECONDS * 0.7)
			return
		_status.modulate.a = maxf(0.0, _status.modulate.a - delta * 3.0)
		if _status.modulate.a <= 0.0:
			_status.visible = false


func _build_status() -> void:
	_status_layer = CanvasLayer.new()
	_status_layer.layer = 5
	add_child(_status_layer)
	_status = PanelContainer.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = -150.0
	_status.offset_bottom = -110.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.1, 0.85)
	style.border_color = Color(0.5, 0.95, 0.85, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	_status.add_theme_stylebox_override("panel", style)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	_status.add_child(_status_label)
	_status_layer.add_child(_status)
	# Beside the panel, not inside it (a container would stretch it): placed
	# each frame along the panel's bottom edge.
	_status_sweep = ColorRect.new()
	_status_sweep.color = Color(0.6, 1.0, 0.92, 0.85)
	_status_sweep.size = Vector2(46.0, 2.0)
	_status_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_layer.add_child(_status_sweep)
	_status.visible = false
	_status_sweep.visible = false


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
	if combat != null and int(combat.get("state")) != 0:
		return false
	return not _threat_nearby()


## No receiver work while a fight is coming (Abe, 2026-10-01: "if a ship is in
## red highlight either we are about to attack or they are"): what the overview
## shows red (a contract's target close by, anything locked onto us), plus
## pirates close by. Uses the overview's own rules, so "red on the overview" and
## "no receiver" always agree.
## A hostile ship this close keeps the receiver quiet (was 3000 for any
## "minor" ship, which blocked it near peaceful salvagers: finding 10).
const HOSTILE_QUIET_RANGE := 1500.0


func _threat_nearby() -> bool:
	return not threat_label().is_empty()


## The ship that keeps the receiver quiet, as "Reaver Raider, 820 m", or "".
## Only a hostile ship close enough to matter, or one actually locked on to
## us (a territorial one keeping to itself never counts: Abe, playtest
## 2026-10-03 finding 10b).
func threat_label() -> String:
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not is_instance_valid(player):
		return ""
	var best := ""
	var best_dist := INF
	for ship in get_tree().get_nodes_in_group("ship"):
		if ship == player or not is_instance_valid(ship) or bool(ship.get("destroyed")):
			continue
		var dist := (ship as Node3D).global_position.distance_to((player as Node3D).global_position)
		if dist >= HOSTILE_QUIET_RANGE or dist >= best_dist:
			continue
		var hostile: bool = gs.has_method("ship_disposition") and str(gs.ship_disposition(ship)) == "hostile"
		if hostile or ship.get("target") == player:
			best_dist = dist
			var shown = ship.get("display_name")
			best = "%s, %d m" % [str(shown) if shown != null and not str(shown).is_empty() else str(ship.name), int(dist)]
	return best

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
	if not _offered.has("difficulty"):
		_offered["difficulty"] = pick_difficulty()
	var story := get_node_or_null("/root/StoryManager")
	var taught := story != null and bool(story.story_state.get(TAUGHT_FLAG, false))
	var pool: Array = OFFER_LINES[str(_offered["difficulty"])]
	_nova(str(pool[randi() % pool.size()]) + ("" if taught else " " + TEACH_LINE))
	if story != null and not taught:
		story.story_state[TAUGHT_FLAG] = true
	load("res://scripts/ui/Wiki.gd").unlock("receiver")
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		# A SYSTEM line every time, not hers (Abe, 2026-10-01).
		gs.emit_chatter("SYSTEM", SYSTEM_PROMPT_LINE, Color(0.5, 0.95, 0.85))


## Easy in the start system; further out, harder ones turn up more often.
func pick_difficulty() -> String:
	var depth := _current_depth()
	if depth <= 0:
		return "easy"
	var roll := randf()
	var hard_share := clampf(0.1 + 0.05 * depth, 0.1, 0.4)
	var medium_share := 0.4
	if roll < hard_share:
		return "hard"
	if roll < hard_share + medium_share:
		return "medium"
	return "easy"


func _current_depth() -> int:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return 0
	return maxi(0, int(preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(str(gs.current_system_id))))


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
	var seconds := float(DIFFICULTY_SECONDS.get(str(_offered.get("difficulty", "easy")), 40.0))
	_panel.begin(randi(), interference, seconds)


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
		var pay := int(round(float(FaintType.AMBIENT_PAY.get(outcome_id, 0)) * float(DIFFICULTY_PAY.get(str(item.get("difficulty", "easy")), 1.0))))
		gs.add_credits(pay)
		gs.emit_chatter("RECEIVER", "Intercept sold to a data broker: %d credits." % pay, Color(0.5, 0.95, 0.85))
		# The same gold banner a new loose end gets, so a payout feels like one.
		var ui = gs.get_ui_manager() if gs.has_method("get_ui_manager") else null
		if ui != null and ui.has_method("show_reward_banner"):
			ui.show_reward_banner("INTERCEPT SOLD  ·  +%d SC" % pay,
				"%s copy sold to a data broker." % ("A clean" if outcome_id == "clean" else "A partial"))
	# She comments once the intercept has played.
	var line := _line("%s_%s" % [kind, grade])
	var wait := 2.0 + heard.split(" ").size() * 0.35
	get_tree().create_timer(wait).timeout.connect(func() -> void: _nova(line))
	# A Lodestar bearing may be buried in it (core loop step 10).
	get_tree().create_timer(wait + 3.0).timeout.connect(func() -> void:
		load("res://scripts/story/LodestarGuide.gd").offer_from("receiver"))


func _line(key: String) -> String:
	var pool: Array = RESULT_LINES.get(key, RESULT_LINES["failed"])
	return str(pool[randi() % pool.size()])


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "mystery")

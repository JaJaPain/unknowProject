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

## Seconds of calm flight in a system before she mentions it.
const OFFER_AFTER_MIN_S := 40.0
const OFFER_AFTER_MAX_S := 110.0
const AMBIENT_OFFER_CHANCE := 0.5
const TUNE_KEY := KEY_T

const OFFER_LINES: Array[String] = [
	"I'm catching something faint under the static. Want to tune in?",
	"There's a voice down in the noise floor. Someone isn't meant to be heard. Shall we listen?",
	"Faint transmission, close by and very quiet. I can hand you the receiver if you're curious.",
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


func _process(delta: float) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	var system_id := str(gs.current_system_id)
	if system_id != _system_id:
		_system_id = system_id
		_flight_s = 0.0
		_offer_at = randf_range(OFFER_AFTER_MIN_S, OFFER_AFTER_MAX_S)
		_decided = false
		_offered = {}
	if _panel != null:
		if not _can_listen():
			_panel.abort()
		return
	if not _can_listen():
		return
	_flight_s += delta
	if not _decided and _flight_s >= _offer_at:
		_decided = true
		_try_offer()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == TUNE_KEY:
		if not _offered.is_empty() and _panel == null and _can_listen():
			open_tuning()
			get_viewport().set_input_as_handled()


func has_offer() -> bool:
	return not _offered.is_empty()


func _can_listen() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or bool(gs.get("intro_cinematic_active")):
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
	if str(item.get("kind", "")) == "ambient" and randf() > AMBIENT_OFFER_CHANCE:
		return
	offer(item)


## Make `item` available to tune into, and have her mention it.
func offer(item: Dictionary) -> void:
	_offered = item
	_nova(OFFER_LINES[randi() % OFFER_LINES.size()])
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("RECEIVER", "Press T to tune in.", Color(0.5, 0.95, 0.85))


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

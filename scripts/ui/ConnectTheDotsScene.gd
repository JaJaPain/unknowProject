extends CanvasLayer

## Plays the season climax's connect-the-dots (ConnectTheDots.build steps):
## the game pauses; N.O.V.A. walks through the clue cards, then the channel
## to Kaelen. Each step waits for its voice (or a reading time), click /
## Space / Enter moves on, Esc skips the rest. Nothing is written to the comms
## feed, the subtitles or any log (fixed-cast canon: we never admit anything).

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const COMMS_COLOR := Color(1.0, 0.72, 0.3)
const NOVA_COLOR := Color(0.45, 0.85, 1.0)

signal finished

var steps: Array = []
var _index := -1
var _advance := false
var _skip := false
var _card_panel: PanelContainer
var _where: Label
var _detail: Label
var _link: Label
var _voice_panel: PanelContainer
var _portrait: TextureRect
var _speaker: Label
var _line: Label
var _was_paused := false
var _hud_was_visible := true


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("suppress_subtitles")
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.025, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := VBoxContainer.new()
	column.anchor_left = 0.2
	column.anchor_right = 0.8
	column.anchor_top = 0.16
	column.anchor_bottom = 0.86
	column.add_theme_constant_override("separation", 22)
	add_child(column)
	_card_panel = PanelContainer.new()
	_card_panel.add_theme_stylebox_override("panel", HudStyle.box(Color(0.03, 0.05, 0.08, 0.95), HudStyle.EDGE, 1, 10, 22))
	_card_panel.modulate.a = 0.0
	column.add_child(_card_panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 10)
	_card_panel.add_child(card)
	_where = Label.new()
	HudStyle.style_label(_where, 13, HudStyle.DIM)
	card.add_child(_where)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(_detail, 20, HudStyle.TEXT)
	card.add_child(_detail)
	_link = Label.new()
	_link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(_link, 17, COMMS_COLOR)
	card.add_child(_link)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_voice_panel = PanelContainer.new()
	_voice_panel.add_theme_stylebox_override("panel", HudStyle.box(Color(0.02, 0.04, 0.07, 0.95), HudStyle.EDGE.darkened(0.2), 1, 8, 14))
	_voice_panel.modulate.a = 0.0
	column.add_child(_voice_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_voice_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(words)
	_speaker = Label.new()
	HudStyle.style_label(_speaker, 13, HudStyle.DIM)
	words.add_child(_speaker)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(_line, 17, HudStyle.TEXT)
	words.add_child(_line)
	_was_paused = get_tree().paused
	get_tree().paused = true
	var ui = GlobalState.get_ui_manager()
	if ui != null:
		_hud_was_visible = ui.visible
		ui.visible = false
	_run()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			_skip = true
		elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_advance = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_advance = true
		get_viewport().set_input_as_handled()


func _run() -> void:
	await get_tree().create_timer(0.6, true, false, true).timeout
	for i in steps.size():
		if _skip:
			break
		_index = i
		await _play(steps[i])
	SpeechService.stop()
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_card_panel, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(_voice_panel, "modulate:a", 0.0, 0.5)
	await tw.finished
	get_tree().paused = _was_paused
	var ui = GlobalState.get_ui_manager()
	if ui != null:
		ui.visible = _hud_was_visible
	finished.emit()
	queue_free()


func _play(step: Dictionary) -> void:
	_advance = false
	var who := str(step.get("who", "nova"))
	var text := str(step.get("text", ""))
	if who == "card":
		var c: Dictionary = step.get("card", {})
		_where.text = str(c.get("where", ""))
		_detail.text = "“%s”" % str(c.get("detail", ""))
		_link.text = str(c.get("link", ""))
		_link.visible = not _link.text.is_empty()
		_card_panel.modulate.a = 0.0
		create_tween().set_ignore_time_scale(true).tween_property(_card_panel, "modulate:a", 1.0, 0.6)
		_voice("nova", text)
	else:
		_voice(who, text)
	# Wait for the voice to finish (or a reading time), and at least a beat.
	var reading := clampf(text.length() * 0.065, 2.4, 9.0)
	var waited := 0.0
	# A stalled voice never holds the scene more than a few seconds past
	# reading time.
	while waited < reading + 5.0 and not _advance and not _skip:
		await get_tree().create_timer(0.1, true, false, true).timeout
		waited += 0.1
		if waited >= reading and waited > 1.2 and not SpeechService.is_busy():
			break
	await get_tree().create_timer(0.35, true, false, true).timeout


func _voice(who: String, text: String) -> void:
	var registry = GameContentRegistry.shared()
	match who:
		"kaelen":
			_speaker.text = "COMMS · KAELEN"
			_speaker.add_theme_color_override("font_color", COMMS_COLOR)
			_portrait.texture = registry.portrait_texture("portrait.quest_givers.kaelen")
			SpeechService.play_on_comms(text, GlobalState.KAELEN_VOICE_PROFILE_ID, "")
		"nova_comms":
			_speaker.text = "COMMS · N.O.V.A."
			_speaker.add_theme_color_override("font_color", COMMS_COLOR)
			_portrait.texture = _nova_face("serious")
			SpeechService.play(text, Nova.NOVA_VOICE_PROFILE_ID)
		_:
			_speaker.text = "N.O.V.A."
			_speaker.add_theme_color_override("font_color", NOVA_COLOR)
			_portrait.texture = _nova_face("thoughtful")
			SpeechService.play(text, Nova.NOVA_VOICE_PROFILE_ID)
	_line.text = text
	if _voice_panel.modulate.a < 1.0:
		create_tween().set_ignore_time_scale(true).tween_property(_voice_panel, "modulate:a", 1.0, 0.4)


func _nova_face(expression: String) -> Texture2D:
	var ui = GlobalState.get_ui_manager()
	return ui.call("_nova_portrait_texture", expression) if ui != null and ui.has_method("_nova_portrait_texture") else null


## For tests: how far it got.
func current_index() -> int:
	return _index

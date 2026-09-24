class_name SubtitleOverlay
extends CanvasLayer

## Subtitles for spoken lines (Settings > Audio > Subtitles).
##
## Listens to SpeechService.subtitle for everything the speech system says;
## baked clips that bypass it (the rare death moment) call show_line()
## directly. Sits above every other layer, including the death moment's black
## screen, so the line is readable there too.

const MIN_SECONDS := 2.5
const MAX_SECONDS := 9.0
const SECONDS_PER_CHAR := 0.065

var _panel: PanelContainer
var _label: Label
var _serial := 0


func _ready() -> void:
	layer = 129
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -120
	_panel.offset_bottom = -64
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 17)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_panel.visible = false
	var speech := get_node_or_null("/root/SpeechService")
	if speech != null:
		speech.subtitle.connect(func(text: String, speaker: String) -> void: show_line(text, speaker))
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.subtitles_changed.connect(func(enabled: bool) -> void:
			if not enabled:
				_panel.visible = false)


## Shows a line ("" speaker = unnamed) for a reading-speed duration, or
## `seconds` when given. A newer line replaces an older one.
func show_line(text: String, speaker: String = "", seconds: float = -1.0) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null and not bool(gs.subtitles_enabled):
		return
	# The intro cinematic captions itself.
	if gs != null and bool(gs.get("intro_cinematic_active")):
		return
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_label.text = ("%s: %s" % [speaker, clean]) if not speaker.is_empty() else clean
	_panel.visible = true
	_serial += 1
	var mine := _serial
	var hold := seconds if seconds > 0.0 else clampf(clean.length() * SECONDS_PER_CHAR, MIN_SECONDS, MAX_SECONDS)
	await get_tree().create_timer(hold, true).timeout
	if mine == _serial:
		_panel.visible = false


func current_text() -> String:
	return _label.text if _panel.visible else ""

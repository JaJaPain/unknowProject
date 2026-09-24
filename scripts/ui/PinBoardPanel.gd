class_name PinBoardPanel
extends PanelContainer

## "Loose ends": the pilot's own notes on the main story (plan Section 3.7).
##
## Lists every odd detail the pilot has noticed, where and when, and lets
## them pin the ones they think connect. Pinned notes sit on top and weigh
## on who the story settles on. Until the hand is revealed the board never
## says which notes matter; afterwards each note shows how it connected, or
## that it was a dead end.
##
## Data in, signals out: show_threads(threads, summary) with the shapes from
## PremiseDirector.main_story_threads() / main_story_summary().

signal pin_toggled(thread_id: String, pinned: bool)
signal closed()

const PIN_COLOR := Color(1.0, 0.78, 0.35)
const NOTE_COLOR := Color(0.86, 0.88, 0.92)
const LINK_COLOR := Color(0.55, 0.95, 0.75)
const DEAD_COLOR := Color(0.6, 0.6, 0.65)

var _rows: VBoxContainer
var _header: Label
var _threads: Array = []
var _summary: Dictionary = {}


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.055, 0.05, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.52, 0.18, 0.9)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)
	var title := Label.new()
	title.text = "LOOSE ENDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", PIN_COLOR)
	layout.add_child(title)
	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.add_theme_font_size_override("font_size", 12)
	_header.modulate = Color(0.78, 0.78, 0.8)
	layout.add_child(_header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	var back := Button.new()
	back.text = "Back to the board"
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	layout.add_child(back)


func show_threads(threads: Array, summary: Dictionary = {}) -> void:
	_threads = threads.duplicate(true)
	_summary = summary.duplicate(true)
	visible = true
	_render()


## Plain text of what is on the board (tests, and a future read-aloud).
func board_text() -> String:
	var lines: PackedStringArray = [_header.text]
	for row in _rows.get_children():
		for node in row.find_children("*", "Label", true, false):
			lines.append((node as Label).text)
	return "\n".join(lines)


func _render() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var hand := str(_summary.get("hand", ""))
	if not hand.is_empty():
		_header.text = "It was %s. Here is how it all connected." % hand
	elif _threads.is_empty():
		_header.text = "Nothing has struck you as odd yet."
	else:
		var pinned := _threads.filter(func(t): return bool(t.get("pinned", false))).size()
		_header.text = "Things that didn't sit right. Pin the ones you think connect. (%d pinned)" % pinned
	# Pinned first, then most recent first.
	var ordered := _threads.duplicate()
	ordered.sort_custom(func(a, b):
		if bool(a.get("pinned", false)) != bool(b.get("pinned", false)):
			return bool(a.get("pinned", false))
		return int(a.get("seen_minute", -1)) > int(b.get("seen_minute", -1)))
	for t in ordered:
		_rows.add_child(_thread_row(t, not hand.is_empty()))


func _thread_row(t: Dictionary, revealed: bool) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.95) if bool(t.get("pinned", false)) else Color(0.05, 0.05, 0.06, 0.9)
	style.set_border_width_all(1)
	style.border_color = PIN_COLOR if bool(t.get("pinned", false)) else Color(0.35, 0.33, 0.3, 0.7)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var note := Label.new()
	note.text = str(t.get("text", ""))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", NOTE_COLOR)
	col.add_child(note)
	var where := Label.new()
	var when := int(t.get("seen_minute", -1))
	where.text = "Noticed in %s%s" % [str(t.get("system", "this system")), (", day %d" % (int(when / 1440.0) + 1)) if when >= 0 else ""]
	where.add_theme_font_size_override("font_size", 11)
	where.modulate = Color(0.65, 0.65, 0.68)
	col.add_child(where)
	if revealed:
		var outcome := Label.new()
		outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if t.has("explanation"):
			outcome.text = "Connected: %s" % str(t["explanation"])
			outcome.add_theme_color_override("font_color", LINK_COLOR)
		else:
			outcome.text = "A dead end."
			outcome.add_theme_color_override("font_color", DEAD_COLOR)
		col.add_child(outcome)
	else:
		var pin := Button.new()
		pin.text = "Unpin" if bool(t.get("pinned", false)) else "Pin"
		pin.custom_minimum_size = Vector2(72, 0)
		var id := str(t.get("id", ""))
		var now_pinned := not bool(t.get("pinned", false))
		pin.pressed.connect(func() -> void: _on_pin(id, now_pinned))
		row.add_child(pin)
	return card


func _on_pin(thread_id: String, pinned: bool) -> void:
	for t in _threads:
		if str(t.get("id", "")) == thread_id:
			t["pinned"] = pinned
	pin_toggled.emit(thread_id, pinned)
	_render()


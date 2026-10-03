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
## The Lodestar log tab (core loop step 10): {title, first_hint, bearings:
## [text], found, total, next_class} or {} while the captain hasn't heard of it.
var _lodestar: Dictionary = {}
var _tab := "loose"
var _tabs: HBoxContainer
var _title: Label


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
	_title = Label.new()
	_title.text = "LOOSE ENDS"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", PIN_COLOR)
	layout.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 8)
	layout.add_child(_tabs)
	for tab in [["loose", "Loose ends"], ["lodestar", "Lodestar log"]]:
		var b := Button.new()
		b.name = "Tab_" + str(tab[0])
		b.text = str(tab[1])
		b.toggle_mode = true
		b.pressed.connect(func() -> void: show_tab(str(tab[0])))
		_tabs.add_child(b)
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


func show_threads(threads: Array, summary: Dictionary = {}, lodestar: Dictionary = {}) -> void:
	_threads = threads.duplicate(true)
	_summary = summary.duplicate(true)
	_lodestar = lodestar.duplicate(true)
	if _lodestar.is_empty():
		_tab = "loose"
	elif _threads.is_empty():
		_tab = "lodestar"
	visible = true
	_render()


func show_tab(tab: String) -> void:
	_tab = "lodestar" if tab == "lodestar" and not _lodestar.is_empty() else "loose"
	_render()


func _render() -> void:
	_tabs.visible = not _lodestar.is_empty()
	for b in _tabs.get_children():
		(b as Button).set_pressed_no_signal(str(b.name) == "Tab_" + _tab)
	if _tab == "lodestar":
		_render_lodestar()
	else:
		_title.text = "LOOSE ENDS"
		_render_loose_ends()


## What's known about the campaign's Lodestar: the rumour, then every bearing
## found, oldest first.
func _render_lodestar() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_title.text = "LODESTAR LOG"
	var found := int(_lodestar.get("found", 0))
	var total := int(_lodestar.get("total", 5))
	var marked := str(_lodestar.get("marked", ""))
	if found >= total and not marked.is_empty():
		_header.text = "%s. Every bearing found. It's in %s: fly there and find it (gold ring on the star map)." % [str(_lodestar.get("title", "")), marked]
	elif found >= total:
		_header.text = "%s. Every bearing found: it's marked on the star map." % str(_lodestar.get("title", ""))
	else:
		_header.text = "%s. Bearings %d of %d. The next can turn up past the Class %s gates: any receiver, drone dive, anomaly, investigation or lead of Kaelen's there." % [
			str(_lodestar.get("title", "")), found, total, str(_lodestar.get("next_class", ""))]
	_rows.add_child(_log_row("The rumour", str(_lodestar.get("first_hint", ""))))
	var bearings: Array = _lodestar.get("bearings", [])
	for i in bearings.size():
		_rows.add_child(_log_row("Bearing %d" % (i + 1), str(bearings[i])))
	# Lodestars already reached this campaign (core loop step 12).
	for r in _lodestar.get("reached", []):
		_rows.add_child(_log_row("Reached, season %d" % int(r.get("season", 1)), str(r.get("title", ""))))


func _log_row(heading: String, text: String) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.085, 0.05, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(PIN_COLOR, 0.55)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	card.add_child(box)
	var head := Label.new()
	head.text = heading.to_upper()
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", PIN_COLOR)
	box.add_child(head)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", NOTE_COLOR)
	box.add_child(body)
	return card


## Plain text of what is on the board (tests, and a future read-aloud).
func board_text() -> String:
	var lines: PackedStringArray = [_header.text]
	for row in _rows.get_children():
		for node in row.find_children("*", "Label", true, false):
			lines.append((node as Label).text)
	return "\n".join(lines)


func _render_loose_ends() -> void:
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


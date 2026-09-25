class_name LeveragePanel
extends PanelContainer

## "Leverage": the secrets the captain is holding (vision plan 4.4), each with
## three uses: sell it to a broker, expose it to the local faction that cares
## about order, or blackmail the subject (which creates a job).
##
## Data in, signals out: show_entries(entries) with the shape from
## PremiseDirector.leverage_items(); use_requested(entry_id, how) goes to
## GameRoot.premise_use_leverage, whose message comes back via show_result().

signal use_requested(entry_id: String, how: String)
signal closed()

const Leverage := preload("res://scripts/story/premise/Leverage.gd")
const NOTE_COLOR := Color(0.86, 0.88, 0.92)
const SUBJECT_COLOR := Color(1.0, 0.72, 0.4)

var _rows: VBoxContainer
var _status: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.75, 0.3, 0.3, 0.9)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)
	var title := Label.new()
	title.text = "LEVERAGE"
	title.add_theme_font_size_override("font_size", 22)
	layout.add_child(title)
	var hint := Label.new()
	hint.text = "What you know about people. Each secret can be used once."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))
	layout.add_child(_status)
	var back := Button.new()
	back.text = "Back to the board"
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	layout.add_child(back)
	visible = false


func show_entries(entries: Array) -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	if entries.is_empty():
		var none := Label.new()
		none.text = "Nothing on anyone. Yet."
		_rows.add_child(none)
	for entry: Dictionary in entries:
		var box := VBoxContainer.new()
		var who := Label.new()
		who.text = str(entry.get("subject", "Someone"))
		who.add_theme_color_override("font_color", SUBJECT_COLOR)
		box.add_child(who)
		var what := Label.new()
		what.text = str(entry.get("summary", ""))
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.add_theme_color_override("font_color", NOTE_COLOR)
		box.add_child(what)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
		var value := Leverage.value_of(entry)
		for use: Array in [["sell", "Sell to a broker (%d cr)" % value], ["expose", "Expose them"],
				["blackmail", "Blackmail them (about %d cr)" % int(round(value * Leverage.BLACKMAIL_MULT))]]:
			var btn := Button.new()
			btn.text = str(use[1])
			var entry_id := str(entry.get("id", ""))
			var how := str(use[0])
			btn.pressed.connect(func() -> void: use_requested.emit(entry_id, how))
			buttons.add_child(btn)
		box.add_child(buttons)
		_rows.add_child(box)
	visible = true


func show_result(message: String) -> void:
	if _status != null:
		_status.text = message

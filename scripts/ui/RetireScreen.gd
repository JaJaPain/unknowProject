extends CanvasLayer

## Retiring the Captain, gated (playtest 2026-10-06 finding 3, Abe): its own
## screen, not a quick OK box. Says what retiring means, shows a glimpse of
## what's being closed, and only goes ahead on a held button (HOLD_SECONDS;
## letting go cancels). Back is the default.

signal confirmed()
signal cancelled()

const HOLD_SECONDS := 3.0
const RED := Color(0.92, 0.3, 0.28)
const TEXT := Color(0.86, 0.88, 0.92)
const DIM := Color(0.62, 0.66, 0.72)

## {days, stories, credits, campaign} for the glimpse of what's being closed.
var summary: Dictionary = {}
var _held := 0.0
var _holding := false
var _done := false
var _bar: ProgressBar
var _hold_btn: Button


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color(0.02, 0.015, 0.02, 0.96)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.035, 0.04, 0.99)
	style.border_color = Color(RED, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	shell.add_theme_stylebox_override("panel", style)
	center.add_child(shell)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	shell.add_child(col)
	col.add_child(_label("RETIRE THE CAPTAIN", 26, RED, true))
	col.add_child(_label(str(summary.get("campaign", "")), 16, TEXT, true))
	col.add_child(_label("The Captain sets the ship down for good. You keep the Captain's story as a keepsake, and a copy is saved. This campaign and all its saves are then deleted. It can't be undone.", 15, TEXT))
	var days := int(summary.get("days", 1))
	var stories := int(summary.get("stories", 0))
	var stats := "%d %s flown  ·  %d %s  ·  %d credits" % [days, "day" if days == 1 else "days",
		stories, "story" if stories == 1 else "stories", int(summary.get("credits", 0))]
	col.add_child(_label(stats, 14, DIM, true))
	_bar = ProgressBar.new()
	_bar.max_value = HOLD_SECONDS
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = RED
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var back_btn := Button.new()
	back_btn.name = "RetireBack"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(160, 42)
	back_btn.pressed.connect(func() -> void:
		cancelled.emit()
		queue_free())
	row.add_child(back_btn)
	_hold_btn = Button.new()
	_hold_btn.name = "HoldToRetire"
	_hold_btn.text = "Hold to retire the Captain"
	_hold_btn.custom_minimum_size = Vector2(260, 42)
	_hold_btn.add_theme_color_override("font_color", RED)
	_hold_btn.button_down.connect(func() -> void: _holding = true)
	_hold_btn.button_up.connect(func() -> void:
		_holding = false
		_held = 0.0)
	row.add_child(_hold_btn)
	back_btn.call_deferred("grab_focus")


func _process(delta: float) -> void:
	if _done:
		return
	if _holding:
		_held += delta
		if _held >= HOLD_SECONDS:
			_done = true
			confirmed.emit()
			queue_free()
			return
	_bar.value = _held


## Simulates holding for `seconds` (tests).
func hold_for(seconds: float) -> void:
	_holding = true
	_process(seconds)
	_holding = false


func _label(text: String, size: int, color: Color, centered := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

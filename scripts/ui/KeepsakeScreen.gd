extends CanvasLayer

## The reader for the Captain's story at the end of a campaign (Keepsake.gd):
## the chapters on a quiet page, a button to open the saved copy, and one to
## close the campaign. Shown over everything, the game paused underneath.

signal finished()

const GOLD := Color(0.94, 0.78, 0.42)
const BODY := Color(0.87, 0.85, 0.81)
const DIM := Color(0.6, 0.58, 0.55)

var keepsake: Dictionary = {}
## Where the saved copy is (absolute), or "".
var saved_path := ""
var _body: VBoxContainer


func _ready() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color(0.03, 0.028, 0.035, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_body = VBoxContainer.new()
	_body.custom_minimum_size.x = 640
	_body.add_theme_constant_override("separation", 10)
	center.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	var open_copy := Button.new()
	open_copy.name = "OpenCopyButton"
	open_copy.text = "Open the saved copy"
	open_copy.custom_minimum_size = Vector2(220, 40)
	open_copy.disabled = saved_path.is_empty()
	open_copy.tooltip_text = saved_path
	open_copy.pressed.connect(func() -> void: OS.shell_open(saved_path))
	buttons.add_child(open_copy)
	var done := Button.new()
	done.name = "CloseCampaignButton"
	done.text = "Close the campaign"
	done.custom_minimum_size = Vector2(220, 40)
	done.pressed.connect(func() -> void: finished.emit())
	buttons.add_child(done)
	_render()


func _render() -> void:
	var title := _label(str(keepsake.get("title", "")), 30, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(title)
	var sub := _label(str(keepsake.get("subtitle", "")), 15, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(sub)
	for chapter in keepsake.get("chapters", []):
		var gap := Control.new()
		gap.custom_minimum_size.y = 14
		_body.add_child(gap)
		_body.add_child(_label(str(chapter["heading"]).to_upper(), 13, GOLD))
		for p in chapter["paragraphs"]:
			_body.add_child(_label(str(p), 17, BODY))
	if not saved_path.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 18
		_body.add_child(gap)
		_body.add_child(_label("A copy is saved at %s" % saved_path, 12, DIM))


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Everything on the page, for tests and snapshots.
func page_text() -> String:
	var lines: PackedStringArray = []
	for node in _body.get_children():
		if node is Label:
			lines.append((node as Label).text)
	return "\n".join(lines)

extends CanvasLayer

## The wiki reader, opened from the pause menu. Entries by category on the
## left (unread ones marked NEW), the chosen entry on the right. Control names
## come from Wiki.body_text, so they follow the player's input device.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const Wiki := preload("res://scripts/ui/Wiki.gd")

signal closed

var _list: VBoxContainer
var _title: Label
var _body: RichTextLabel
var _buttons: Dictionary = {}
var _current := ""


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.03, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.box(Color(HudStyle.BG, 1.0), HudStyle.EDGE, 1, 8, 18))
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var heading := Label.new()
	heading.text = "WIKI"
	HudStyle.style_label(heading, 24, HudStyle.ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(110, 36)
	HudStyle.style_button(close, 13)
	close.pressed.connect(_close)
	header.add_child(close)
	outer.add_child(HudStyle.rule())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var reader := VBoxContainer.new()
	reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader.add_theme_constant_override("separation", 10)
	columns.add_child(reader)
	_title = Label.new()
	HudStyle.style_label(_title, 22, HudStyle.TEXT)
	reader.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.add_theme_color_override("default_color", Color(0.82, 0.88, 0.95))
	reader.add_child(_body)

	_build_list()


func _build_list() -> void:
	var entries := Wiki.unlocked_entries()
	var first_unread := ""
	for category in Wiki.categories():
		var in_cat: Array = entries.filter(func(e: Dictionary) -> bool: return str(e.get("category", "")) == str(category))
		if in_cat.is_empty():
			continue
		var cat_label := Label.new()
		cat_label.text = str(category).to_upper()
		HudStyle.style_label(cat_label, 12, HudStyle.DIM)
		_list.add_child(cat_label)
		for e in in_cat:
			var id := str(e.get("id", ""))
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 34)
			HudStyle.style_row(button)
			button.pressed.connect(func(): _show(id))
			_list.add_child(button)
			_buttons[id] = button
			if first_unread.is_empty() and Wiki.is_unread(id):
				first_unread = id
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		_list.add_child(gap)
	_refresh_labels()
	var open_id := first_unread
	if open_id.is_empty() and not entries.is_empty():
		open_id = str(entries[0].get("id", ""))
	if not open_id.is_empty():
		_show(open_id)


func _refresh_labels() -> void:
	for id in _buttons.keys():
		var e := Wiki.entry(str(id))
		var text := str(e.get("title", id))
		if Wiki.is_unread(str(id)):
			text += "   • NEW"
		(_buttons[id] as Button).text = text


func _show(id: String) -> void:
	var e := Wiki.entry(id)
	if e.is_empty():
		return
	_current = id
	_title.text = str(e.get("title", id))
	_body.text = Wiki.body_text(e)
	_body.scroll_to_line(0)
	Wiki.mark_read(id)
	_refresh_labels()
	for other in _buttons.keys():
		var b := _buttons[other] as Button
		if other == id:
			b.add_theme_stylebox_override("normal", HudStyle.selected_row())
		else:
			b.remove_theme_stylebox_override("normal")
			HudStyle.style_row(b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()

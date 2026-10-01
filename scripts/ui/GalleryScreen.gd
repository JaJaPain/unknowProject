extends CanvasLayer

## The pause menu's Gallery: this campaign's screenshots (Screenshots.gd),
## newest first. Click one for full screen; arrows (or Left/Right) step
## through, Delete removes it, Esc goes back.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const Shots := preload("res://scripts/ui/Screenshots.gd")
const THUMB := Vector2(256, 144)

signal closed

var _grid: GridContainer
var _empty: Label
var _viewer: Control
var _viewer_image: TextureRect
var _viewer_label: Label
var _paths: Array[String] = []
var _index := -1


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.03, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.box(Color(HudStyle.BG, 1.0), HudStyle.EDGE, 1, 8, 18))
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "GALLERY"
	HudStyle.style_label(title, 24, HudStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := Label.new()
	hint.text = "F12 takes a screenshot · Shift+F12 without the HUD   "
	HudStyle.style_label(hint, 12, HudStyle.DIM)
	header.add_child(hint)
	var open_btn := Button.new()
	open_btn.text = "OPEN FOLDER"
	HudStyle.style_button(open_btn, 12)
	open_btn.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(Shots.folder())))
	header.add_child(open_btn)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(110, 36)
	HudStyle.style_button(close, 13)
	close.pressed.connect(_close)
	header.add_child(close)
	outer.add_child(HudStyle.rule())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	_empty = Label.new()
	_empty.text = "No screenshots in this campaign yet. Press F12 while flying."
	HudStyle.style_label(_empty, 16, HudStyle.DIM)
	outer.add_child(_empty)
	_build_viewer()
	_fill()


func _fill() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_paths = Shots.list()
	_empty.visible = _paths.is_empty()
	for i in _paths.size():
		var path := _paths[i]
		var tex := _thumbnail(path)
		var cell := VBoxContainer.new()
		var btn := TextureButton.new()
		btn.texture_normal = tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = THUMB
		btn.tooltip_text = path.get_file()
		var index := i
		btn.pressed.connect(func(): _open(index))
		cell.add_child(btn)
		var name_label := Label.new()
		name_label.text = path.get_file().get_basename().replace("_", " ")
		HudStyle.style_label(name_label, 11, HudStyle.DIM)
		cell.add_child(name_label)
		_grid.add_child(cell)


func _thumbnail(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var scale := minf(THUMB.x / img.get_width(), THUMB.y / img.get_height())
	img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _build_viewer() -> void:
	_viewer = Control.new()
	_viewer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer.visible = false
	add_child(_viewer)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.95)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer.add_child(back)
	_viewer_image = TextureRect.new()
	_viewer_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer_image.offset_bottom = -60
	_viewer_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewer_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewer.add_child(_viewer_image)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = -52
	bar.offset_bottom = -12
	bar.add_theme_constant_override("separation", 12)
	_viewer.add_child(bar)
	for spec in [["‹ PREV", func(): _step(-1)], ["NEXT ›", func(): _step(1)], ["DELETE", _delete_current], ["BACK", func(): _viewer.visible = false]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(110, 36)
		HudStyle.style_button(b, 13, HudStyle.DANGER if spec[0] == "DELETE" else HudStyle.ACCENT)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	_viewer_label = Label.new()
	HudStyle.style_label(_viewer_label, 13, HudStyle.TEXT)
	bar.add_child(_viewer_label)


func _open(index: int) -> void:
	if _paths.is_empty():
		return
	_index = clampi(index, 0, _paths.size() - 1)
	var img := Image.load_from_file(_paths[_index])
	_viewer_image.texture = ImageTexture.create_from_image(img) if img != null else null
	_viewer_label.text = "%s   (%d / %d)" % [_paths[_index].get_file(), _index + 1, _paths.size()]
	_viewer.visible = true


func _step(direction: int) -> void:
	if _paths.is_empty():
		return
	_open(posmod(_index + direction, _paths.size()))


func _delete_current() -> void:
	if _index < 0 or _index >= _paths.size():
		return
	Shots.delete(_paths[_index])
	var keep := _index
	_fill()
	if _paths.is_empty():
		_viewer.visible = false
	else:
		_open(mini(keep, _paths.size() - 1))


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key := (event as InputEventKey).keycode
	if _viewer.visible:
		if key == KEY_LEFT:
			_step(-1)
		elif key == KEY_RIGHT:
			_step(1)
		elif key == KEY_DELETE:
			_delete_current()
		elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
			_viewer.visible = false
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()

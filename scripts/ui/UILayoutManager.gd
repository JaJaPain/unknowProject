extends RefCounted

# Manages drag/resize/persist for the 4 main HUD panels.
# Usage: call setup() once from UIManager._ready(), passing panel refs.
# The lock button is created and owned here; caller adds it to the scene.

const SAVE_PATH := "user://ui_layout.json"
const HANDLE_SIZE := 16.0
const MIN_PANEL_SIZE := Vector2(120.0, 80.0)
const DRAG_BAR_H := 18.0

const EDIT_TINT := Color(0.3, 0.7, 1.0, 0.25)
const RESIZE_COLOR := Color(0.3, 0.7, 1.0, 0.6)

# Panel ids — order matches JSON keys
const PANEL_IDS := ["hud", "chat", "overview", "target", "quest"]

var _panels: Dictionary = {}         # id -> Control
var _overlays: Dictionary = {}       # id -> Control (drag bar overlay)
var _resize_handles: Dictionary = {} # id -> Control
var _edit_mode: bool = false
var _lock_btn: Button = null

# Drag state
var _drag_panel_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO
var _resize_panel_id: String = ""
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO


func setup(
	hud: Control,
	chat: Control,
	overview: Control,
	target: Control,
	scene_root: Control,
	quest: Control = null
) -> Button:
	_panels = {
		"hud": hud,
		"chat": chat,
		"overview": overview,
		"target": target,
		"quest": quest,
	}

	# Convert anchor-based panels to pixel positions (quest panel is content-sized, skip it)
	for id in PANEL_IDS:
		if _panels.get(id) != null and id != "quest":
			_to_pixel_pos(_panels[id])

	_load_layout()

	# L button is created by caller (UIManager) alongside M and I — just store ref
	# Caller must call toggle_edit_mode() when L is pressed
	return null


func toggle_edit_mode() -> void:
	if _edit_mode:
		# Lock — save and clear overlays
		_edit_mode = false
		_drag_panel_id = ""
		_resize_panel_id = ""
		for id in PANEL_IDS:
			if _overlays.has(id) and is_instance_valid(_overlays[id]):
				_overlays[id].queue_free()
			if _resize_handles.has(id) and is_instance_valid(_resize_handles[id]):
				_resize_handles[id].queue_free()
		_overlays.clear()
		_resize_handles.clear()
		_save_layout()
	else:
		# Unlock — show drag/resize overlays
		_edit_mode = true
		for id in PANEL_IDS:
			if _panels.get(id) != null:
				_create_overlay(id)


func is_edit_mode() -> bool:
	return _edit_mode


func handle_input(event: InputEvent) -> void:
	if not _edit_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				if not _drag_panel_id.is_empty():
					_snap_back_if_overlapping(_drag_panel_id)
				_drag_panel_id = ""
				_resize_panel_id = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _drag_panel_id.is_empty():
			var p: Control = _panels[_drag_panel_id]
			p.position = mm.position - _drag_offset
			_sync_overlay(_drag_panel_id)
		elif not _resize_panel_id.is_empty():
			var p: Control = _panels[_resize_panel_id]
			var delta := mm.position - _resize_start_mouse
			var new_size := (_resize_start_size + delta).max(MIN_PANEL_SIZE)
			p.size = new_size
			_sync_overlay(_resize_panel_id)


func _create_overlay(id: String) -> void:
	var p: Control = _panels[id]

	# Drag bar
	var bar := ColorRect.new()
	bar.color = EDIT_TINT
	bar.position = Vector2.ZERO
	bar.size = Vector2(p.size.x, DRAG_BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_drag_panel_id = id
				_drag_offset = ev.global_position - p.global_position
				_drag_start_pos = p.position
			else:
				if not _drag_panel_id.is_empty():
					_snap_back_if_overlapping(_drag_panel_id)
				_drag_panel_id = ""
	)
	p.add_child(bar)
	_overlays[id] = bar

	# Resize handle — bottom-right corner (quest panel is drag-only)
	if id != "quest":
		var handle := ColorRect.new()
		handle.color = RESIZE_COLOR
		handle.size = Vector2(HANDLE_SIZE, HANDLE_SIZE)
		handle.position = p.size - Vector2(HANDLE_SIZE, HANDLE_SIZE)
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_resize_panel_id = id
					_resize_start_mouse = ev.global_position
					_resize_start_size = p.size
				else:
					_resize_panel_id = ""
		)
		p.add_child(handle)
		_resize_handles[id] = handle


func _sync_overlay(id: String) -> void:
	var p: Control = _panels[id]
	if _overlays.has(id) and is_instance_valid(_overlays[id]):
		_overlays[id].size = Vector2(p.size.x, DRAG_BAR_H)
	if _resize_handles.has(id) and is_instance_valid(_resize_handles[id]):
		_resize_handles[id].position = p.size - Vector2(HANDLE_SIZE, HANDLE_SIZE)


func _snap_back_if_overlapping(id: String) -> void:
	var p: Control = _panels[id]
	var p_rect := Rect2(p.position, p.size)
	for other_id in PANEL_IDS:
		if other_id == id:
			continue
		var other: Control = _panels.get(other_id)
		if other == null or not is_instance_valid(other) or not other.visible:
			continue
		if p_rect.intersects(Rect2(other.position, other.size)):
			p.position = _drag_start_pos
			_sync_overlay(id)
			return


# ── persistence ───────────────────────────────────────────────────────────────

func _save_layout() -> void:
	var data: Dictionary = {}
	for id in PANEL_IDS:
		var p: Control = _panels.get(id)
		if p == null:
			continue
		if id == "quest":
			data[id] = {"x": p.position.x, "y": p.position.y}
		else:
			data[id] = {"x": p.position.x, "y": p.position.y, "w": p.size.x, "h": p.size.y}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("[UILayoutManager] Layout saved.")


func _load_layout() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	for id in PANEL_IDS:
		if not parsed.has(id):
			continue
		var p: Control = _panels.get(id)
		if p == null:
			continue
		var entry: Dictionary = parsed[id]
		p.position = Vector2(float(entry.get("x", p.position.x)), float(entry.get("y", p.position.y)))
		if id != "quest":
			p.size = Vector2(float(entry.get("w", p.size.x)), float(entry.get("h", p.size.y))).max(MIN_PANEL_SIZE)
	print("[UILayoutManager] Layout loaded.")


# ── helpers ───────────────────────────────────────────────────────────────────

func _to_pixel_pos(p: Control) -> void:
	if not is_instance_valid(p):
		return
	# Flush anchors to current pixel rect, then pin top-left
	var vp_size: Vector2 = p.get_viewport_rect().size
	var px: float = p.anchor_left * vp_size.x + p.offset_left
	var py: float = p.anchor_top * vp_size.y + p.offset_top
	var pw: float = (p.anchor_right - p.anchor_left) * vp_size.x + (p.offset_right - p.offset_left)
	var ph: float = (p.anchor_bottom - p.anchor_top) * vp_size.y + (p.offset_bottom - p.offset_top)
	# If it was already absolute (hud_panel style), position/size are already set
	if pw <= 0.0 or ph <= 0.0:
		pw = p.size.x if p.size.x > 0.0 else 300.0
		ph = p.size.y if p.size.y > 0.0 else 200.0
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 0.0
	p.offset_top = 0.0
	p.offset_right = 0.0
	p.offset_bottom = 0.0
	p.position = Vector2(px, py)
	p.size = Vector2(pw, ph).max(MIN_PANEL_SIZE)

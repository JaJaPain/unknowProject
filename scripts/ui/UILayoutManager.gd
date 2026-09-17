extends RefCounted

# Left-side dock: dragging reorders panels rather than allowing intersections.
# The mission card owns a separate top-right lane below the 64px icon controls.
const SAVE_PATH := "user://ui_layout.json"
const VERSION := 3
const PANEL_IDS := ["hud", "target", "overview", "chat", "quest"]
const DEFAULT_ORDER := ["hud", "target", "overview", "chat"]
const HANDLE_SIZE := 16.0
const DRAG_BAR_H := 18.0
const EDIT_TINT := Color(0.3, 0.7, 1.0, 0.25)
const RESIZE_COLOR := Color(0.3, 0.7, 1.0, 0.6)
const MARGIN := 20.0
const GAP := 12.0
const QUEST_TOP := 88.0

var _panels: Dictionary = {}
var _overlays: Dictionary = {}
var _resize_handles: Dictionary = {}
var _order: Array = DEFAULT_ORDER.duplicate()
var _preferred: Dictionary = {}
var _root: Control
var _edit_mode := false
var _laying_out := false
var _drag_panel_id := ""
var _resize_panel_id := ""
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2.ZERO


func setup(hud: Control, chat: Control, overview: Control, target: Control,
		scene_root: Control, quest: Control = null) -> Button:
	_root = scene_root
	_panels = {"hud": hud, "chat": chat, "overview": overview, "target": target, "quest": quest}
	_preferred = {"overview": Vector2(400, 320), "chat": Vector2(400, 200)}
	_load_layout()
	# Final pass after content containers settle, before anything is drawn.
	RenderingServer.frame_pre_draw.connect(enforce_layout)
	_root.tree_exiting.connect(_disconnect_layout)
	enforce_layout()
	return null


func _disconnect_layout() -> void:
	if RenderingServer.frame_pre_draw.is_connected(enforce_layout):
		RenderingServer.frame_pre_draw.disconnect(enforce_layout)


func register_panel(id: String, panel: Control) -> void:
	# CombatPanel owns its wheel geometry independently of the HUD dock.
	if id == "combat":
		return
	_panels[id] = panel
	enforce_layout()


func reset_defaults(persist: bool = true) -> void:
	_order = DEFAULT_ORDER.duplicate()
	_preferred = {"overview": Vector2(400, 320), "chat": Vector2(400, 200)}
	for id in _preferred:
		var panel: Control = _panels.get(id)
		if is_instance_valid(panel):
			panel.size = _preferred[id]
	enforce_layout()
	if persist:
		_save_layout()


func _content_minimum(panel: Control) -> Vector2:
	var minimum := panel.get_combined_minimum_size()
	# Plain Panels do not inherit their children's minimum sizes (HUD/overview).
	for child in panel.get_children():
		if child is Container and child.visible:
			minimum = minimum.max(child.get_combined_minimum_size() + child.position.max(Vector2.ZERO) * 2.0)
	return minimum.max(Vector2(120, 40))


func enforce_layout() -> void:
	if _laying_out or not is_instance_valid(_root) or not _root.is_inside_tree():
		return
	_laying_out = true
	var vp := _root.get_viewport_rect().size
	var entries: Array = []
	for id in _order:
		var panel: Control = _panels.get(id)
		if not is_instance_valid(panel) or not panel.is_visible_in_tree():
			continue
		var minimum := _content_minimum(panel)
		var wanted: Vector2 = _preferred.get(id, minimum)
		if id == "overview" and panel.size.y <= 100.0 and panel.size.y > 0.0:
			wanted.y = 80.0
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.pivot_offset = Vector2.ZERO
		panel.size = wanted.max(minimum)
		panel.clip_contents = true
		entries.append({"id": id, "size": panel.size})
	var quest: Control = _panels.get("quest")
	var quest_size := Vector2.ZERO
	if is_instance_valid(quest):
		quest.set_anchors_preset(Control.PRESET_TOP_LEFT)
		quest.pivot_offset = Vector2.ZERO
		quest.reset_size()
		quest_size = quest.size
	var rects := solve_layout(vp, entries, quest_size)
	for id in rects:
		var panel: Control = _panels.get(id)
		var placement: Dictionary = rects[id]
		panel.scale = Vector2.ONE * float(placement.scale)
		panel.global_position = placement.position
		_sync_overlay(id)
	_laying_out = false


static func solve_layout(viewport: Vector2, entries: Array, quest_size: Vector2) -> Dictionary:
	var result := {}
	var available_h := maxf(1.0, viewport.y - MARGIN * 2.0)
	var lane_w := maxf(1.0, minf(400.0, (viewport.x - MARGIN * 2.0 - GAP) * 0.45))
	var total := 0.0
	var scales: Array[float] = []
	for entry in entries:
		var dimensions: Vector2 = entry.size
		var factor := minf(1.0, lane_w / maxf(dimensions.x, 1.0))
		scales.append(factor)
		total += dimensions.y * factor
	var gaps := GAP * maxi(0, entries.size() - 1)
	var fit := minf(1.0, available_h / maxf(total + gaps, 1.0))
	var y := MARGIN
	for i in range(entries.size()):
		result[entries[i].id] = {"position": Vector2(MARGIN, y), "scale": scales[i] * fit}
		y += (entries[i].size.y * scales[i] + GAP) * fit
	if quest_size.x > 0 and quest_size.y > 0:
		var top := minf(QUEST_TOP, viewport.y * 0.25)
		var right_w := maxf(1.0, viewport.x - MARGIN * 2.0 - lane_w - GAP)
		var factor := minf(1.0, minf(right_w / quest_size.x, maxf(1.0, viewport.y - top - MARGIN) / quest_size.y))
		result.quest = {"position": Vector2(viewport.x - MARGIN - quest_size.x * factor, top), "scale": factor}
	return result


func toggle_edit_mode() -> void:
	_edit_mode = not _edit_mode
	_drag_panel_id = ""
	_resize_panel_id = ""
	if _edit_mode:
		for id in _panels:
			if is_instance_valid(_panels[id]) and id != "quest":
				_create_overlay(id)
	else:
		for overlay in _overlays.values() + _resize_handles.values():
			if is_instance_valid(overlay):
				overlay.queue_free()
		_overlays.clear()
		_resize_handles.clear()
		_save_layout()
	enforce_layout()


func is_edit_mode() -> bool:
	return _edit_mode


func handle_input(event: InputEvent) -> void:
	if not _edit_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_panel_id = ""
		_resize_panel_id = ""
	elif event is InputEventMouseMotion:
		if not _drag_panel_id.is_empty():
			for id in _order.duplicate():
				var other: Control = _panels.get(id)
				if id == _drag_panel_id or not is_instance_valid(other) or not other.is_visible_in_tree():
					continue
				var rect := other.get_global_rect()
				if event.position.y >= rect.position.y and event.position.y <= rect.end.y:
					var destination := _order.find(id)
					_order.erase(_drag_panel_id)
					_order.insert(destination, _drag_panel_id)
					break
		elif not _resize_panel_id.is_empty():
			var panel: Control = _panels[_resize_panel_id]
			var delta: Vector2 = (event.position - _resize_start_mouse) / panel.scale
			_preferred[_resize_panel_id] = (_resize_start_size + delta).clamp(Vector2(250, 100), Vector2(600, 600))
		enforce_layout()


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
			else:
				if not _drag_panel_id.is_empty():
					enforce_layout()
				_drag_panel_id = ""
	)
	p.add_child(bar)
	_overlays[id] = bar

	# Resize list panels; other panels fit their content.
	if id in ["overview", "chat"]:
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


# Only order and requested sizes persist. Old free-floating layouts are ignored.
func _save_layout() -> void:
	var sizes := {}
	for id in _preferred:
		sizes[id] = {"w": _preferred[id].x, "h": _preferred[id].y}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"version": VERSION, "order": _order, "sizes": sizes}, "\t"))


func _load_layout() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary or data.get("version") != VERSION:
		return
	var order = data.get("order", [])
	if order is Array and order.size() == DEFAULT_ORDER.size():
		var valid := true
		for id in DEFAULT_ORDER:
			valid = valid and order.count(id) == 1
		if valid:
			_order = order.duplicate()
	var sizes = data.get("sizes", {})
	if sizes is Dictionary:
		for id in ["overview", "chat"]:
			var entry = sizes.get(id, {})
			if entry is Dictionary:
				_preferred[id] = Vector2(float(entry.get("w", 400)), float(entry.get("h", 200))).clamp(Vector2(250, 100), Vector2(600, 600))

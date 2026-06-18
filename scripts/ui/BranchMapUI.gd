class_name BranchMapUI
extends Control

const NODE_RADIUS := 28.0
const LINE_WIDTH := 2.5
const LABEL_OFFSET := Vector2(0, 38)
const CURRENT_GLOW_RADIUS := 36.0

const STATE_COLORS := {
	"known": Color(0.0, 0.85, 1.0),
	"rumored": Color(0.9, 0.85, 0.2),
	"hidden": Color(0.5, 0.5, 0.5),
	"blocked": Color(0.9, 0.2, 0.2),
	"damaged": Color(1.0, 0.6, 0.1),
}

const STATE_LABELS := {
	"known": "",
	"rumored": "Rumored",
	"hidden": "Hidden",
	"blocked": "Locked",
	"damaged": "Damaged",
}

const WINDOW_SIZE := Vector2(700, 500)
const TITLE_BAR_HEIGHT := 36.0

var system_nodes: Dictionary = {}
var route_data: Array[Dictionary] = []
var _detail_panel: PanelContainer
var _detail_label: Label
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _close_btn: Button
var _recenter_btn: Button
var _title_label: Label

var planned_route: Array[String] = []

var _pan_offset := Vector2.ZERO
var _dragging_title := false
var _dragging_canvas := false
var _drag_start := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	position = (Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	) - WINDOW_SIZE) / 2.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	_build_title()
	_build_close_button()
	_build_recenter_button()
	_build_detail_panel()
	_build_tooltip()
	_rebuild_map()


func _build_title() -> void:
	_title_label = Label.new()
	_title_label.text = "SYSTEM MAP"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	_title_label.position = Vector2(0, 0)
	_title_label.size = Vector2(WINDOW_SIZE.x, TITLE_BAR_HEIGHT)
	add_child(_title_label)


func _build_close_button() -> void:
	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(TITLE_BAR_HEIGHT, TITLE_BAR_HEIGHT)
	_close_btn.position = Vector2(WINDOW_SIZE.x - TITLE_BAR_HEIGHT, 0)
	_close_btn.pressed.connect(_close)
	add_child(_close_btn)


func _build_recenter_button() -> void:
	_recenter_btn = Button.new()
	_recenter_btn.text = "⌖"
	_recenter_btn.tooltip_text = "Recenter map"
	_recenter_btn.custom_minimum_size = Vector2(TITLE_BAR_HEIGHT, TITLE_BAR_HEIGHT)
	_recenter_btn.position = Vector2(WINDOW_SIZE.x - TITLE_BAR_HEIGHT * 2, 0)
	_recenter_btn.pressed.connect(_recenter)
	add_child(_recenter_btn)


func _recenter() -> void:
	_pan_offset = Vector2.ZERO
	_rebuild_map()


func plan_route_to(dest_sys_id: String) -> void:
	var current_id := ""
	for sid in system_nodes:
		if system_nodes[sid].get("is_current", false):
			current_id = sid
			break
	if current_id.is_empty() or current_id == dest_sys_id:
		planned_route.clear()
		queue_redraw()
		return
	var path: Array[String] = _bfs_path(current_id, dest_sys_id)
	planned_route = path
	queue_redraw()
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("_auto_select_route_gate"):
		ui.call("_auto_select_route_gate")


func _bfs_path(from_id: String, to_id: String) -> Array[String]:
	var adjacency: Dictionary = {}
	for sid in system_nodes:
		adjacency[sid] = []
	for route in route_data:
		if route["state"] != "known":
			continue
		var a: String = route["from"]
		var b: String = route["to"]
		if adjacency.has(a):
			adjacency[a].append(b)
		if adjacency.has(b):
			adjacency[b].append(a)
	var visited: Dictionary = {from_id: ""}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to_id:
			var path: Array[String] = []
			var step: String = to_id
			while step != "":
				path.push_front(step)
				step = visited[step]
			return path
		for neighbor in adjacency.get(current, []):
			if not visited.has(neighbor):
				visited[neighbor] = current
				queue.append(neighbor)
	return []


func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.visible = false
	_detail_panel.custom_minimum_size = Vector2(250, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.15, 0.92)
	style.border_color = Color(0.0, 0.7, 0.9, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_detail_panel.add_theme_stylebox_override("panel", style)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_detail_panel.add_child(_detail_label)
	add_child(_detail_panel)


func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.custom_minimum_size = Vector2(180, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.12, 0.94)
	style.border_color = Color(0.0, 0.6, 0.8, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.add_theme_color_override("default_color", Color(0.7, 0.8, 0.9))
	_tooltip_panel.add_child(_tooltip_label)
	add_child(_tooltip_panel)


func _rebuild_map() -> void:
	var keep := [_detail_panel, _tooltip_panel, _close_btn, _recenter_btn, _title_label]
	for child in get_children():
		if child not in keep:
			child.queue_free()
	system_nodes.clear()
	route_data.clear()

	var game_root := get_tree().current_scene
	if not game_root or not "system_registry" in game_root:
		return

	var registry = game_root.system_registry
	if registry == null:
		return
	var all_systems: Array = registry.get_all_systems()
	if all_systems.is_empty():
		return

	var content_center := Vector2(WINDOW_SIZE.x / 2.0, TITLE_BAR_HEIGHT + (WINDOW_SIZE.y - TITLE_BAR_HEIGHT) / 2.0) + _pan_offset
	var positions := _layout_systems(all_systems, content_center)

	for sys_def in all_systems:
		var sys_id: String = str(sys_def.id)
		var pos: Vector2 = positions.get(sys_id, content_center)
		var faction_names: Array[String] = []
		var faction_ids: Array[String] = []
		for fid in sys_def.faction_ids:
			var raw: String = str(fid).get_slice(".", 1)
			faction_ids.append(raw)
			faction_names.append(raw.capitalize())
		system_nodes[sys_id] = {
			"position": pos,
			"display_name": sys_def.display_name,
			"is_current": sys_def.legacy_id == GlobalState.current_system_id,
			"legacy_id": sys_def.legacy_id,
			"station_count": sys_def.station_ids.size(),
			"faction_names": faction_names,
			"faction_ids": faction_ids,
			"origin": sys_def.origin,
		}
		_create_system_label(sys_def, pos)

	for sys_def in all_systems:
		for gate_def in sys_def.gates:
			var dest_sys_id: String = str(gate_def.destination_system_id)
			var src_sys_id: String = str(sys_def.id)
			if not system_nodes.has(dest_sys_id):
				continue
			var pair_key := [src_sys_id, dest_sys_id]
			pair_key.sort()
			var key_str: String = "%s|%s" % [pair_key[0], pair_key[1]]
			var already := false
			for rd in route_data:
				if rd.get("key", "") == key_str:
					already = true
					break
			if already:
				continue
			var gate_id: String = str(gate_def.id)
			var state: String = "unknown"
			if GateDiscovery:
				state = GateDiscovery.get_gate_state(gate_id)
			if state == "unknown":
				continue
			route_data.append({
				"key": key_str,
				"from": src_sys_id,
				"to": dest_sys_id,
				"gate_id": gate_id,
				"gate_name": gate_def.display_name,
				"state": state,
			})
	queue_redraw()


func _layout_systems(systems: Array, center: Vector2) -> Dictionary:
	var positions := {}
	var count := systems.size()
	if count == 1:
		positions[str(systems[0].id)] = center
		return positions
	var content_h: float = WINDOW_SIZE.y - TITLE_BAR_HEIGHT
	var radius: float = minf(WINDOW_SIZE.x, content_h) * 0.3
	for i in range(count):
		var angle := TAU * float(i) / float(count) - PI / 2.0
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		positions[str(systems[i].id)] = pos
	return positions


func _create_system_label(sys_def, pos: Vector2) -> void:
	var label := Label.new()
	label.text = sys_def.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	if sys_def.legacy_id == GlobalState.current_system_id:
		label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	else:
		label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.86))
	label.position = pos + LABEL_OFFSET - Vector2(80, 0)
	label.custom_minimum_size = Vector2(160, 20)
	add_child(label)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), Color(0.02, 0.03, 0.06, 0.95))
	draw_rect(Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE.x, TITLE_BAR_HEIGHT)), Color(0.06, 0.08, 0.14))
	draw_line(Vector2(0, TITLE_BAR_HEIGHT), Vector2(WINDOW_SIZE.x, TITLE_BAR_HEIGHT), Color(0.0, 0.5, 0.7, 0.6), 1.0)
	draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), Color(0.0, 0.5, 0.7, 0.4), false, 1.0)

	for route in route_data:
		var from_pos: Vector2 = system_nodes[route["from"]]["position"]
		var to_pos: Vector2 = system_nodes[route["to"]]["position"]
		var state: String = route["state"]
		var color: Color = STATE_COLORS.get(state, Color.GRAY)

		if state == "known":
			draw_line(from_pos, to_pos, color, LINE_WIDTH)
		elif state == "rumored":
			_draw_dashed_line(from_pos, to_pos, color, LINE_WIDTH, 12.0, 8.0)
		elif state == "hidden":
			_draw_dashed_line(from_pos, to_pos, color, 1.5, 4.0, 8.0)
		elif state == "blocked":
			draw_line(from_pos, to_pos, color * 0.5, LINE_WIDTH)
			var mid := (from_pos + to_pos) / 2.0
			_draw_x_mark(mid, color, 8.0)
		elif state == "damaged":
			draw_line(from_pos, to_pos, color * 0.6, LINE_WIDTH)
			var mid := (from_pos + to_pos) / 2.0
			_draw_exclamation(mid, color)

		var status_text: String = STATE_LABELS.get(state, "")
		if not status_text.is_empty():
			var mid := (from_pos + to_pos) / 2.0
			_draw_route_label(mid, status_text, color)

	for sys_id in system_nodes:
		var data: Dictionary = system_nodes[sys_id]
		var pos: Vector2 = data["position"]
		var is_current: bool = data.get("is_current", false)

		if is_current:
			draw_circle(pos, CURRENT_GLOW_RADIUS, Color(0.0, 0.85, 1.0, 0.15))
			draw_arc(pos, CURRENT_GLOW_RADIUS, 0, TAU, 32, Color(0.0, 0.85, 1.0, 0.6), 2.0)

		draw_circle(pos, NODE_RADIUS, Color(0.1, 0.15, 0.25))
		draw_arc(pos, NODE_RADIUS, 0, TAU, 24, Color(0.3, 0.5, 0.7), 1.5)

		if is_current:
			draw_circle(pos, 6, Color(0.0, 1.0, 0.8))

		if planned_route.size() >= 2:
			var is_dest: bool = sys_id == planned_route[-1]
			var on_route: bool = sys_id in planned_route and not is_current
			if is_dest:
				draw_arc(pos, NODE_RADIUS + 6, 0, TAU, 24, Color(0.2, 1.0, 0.4, 0.8), 2.5)
			elif on_route:
				draw_arc(pos, NODE_RADIUS + 4, 0, TAU, 24, Color(0.2, 1.0, 0.4, 0.3), 1.5)

	if planned_route.size() >= 2:
		for i in range(planned_route.size() - 1):
			var a: String = planned_route[i]
			var b: String = planned_route[i + 1]
			if system_nodes.has(a) and system_nodes.has(b):
				var pa: Vector2 = system_nodes[a]["position"]
				var pb: Vector2 = system_nodes[b]["position"]
				draw_line(pa, pb, Color(0.2, 1.0, 0.4, 0.5), 4.0)


func _draw_dashed_line(
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float
) -> void:
	var direction := (to - from).normalized()
	var total := from.distance_to(to)
	var drawn := 0.0
	var drawing := true
	while drawn < total:
		var segment := dash_length if drawing else gap_length
		segment = min(segment, total - drawn)
		if drawing:
			var start := from + direction * drawn
			var end := from + direction * (drawn + segment)
			draw_line(start, end, color, width)
		drawn += segment
		drawing = not drawing


func _draw_x_mark(pos: Vector2, color: Color, half_size: float) -> void:
	draw_line(pos - Vector2(half_size, half_size), pos + Vector2(half_size, half_size), color, 2.0)
	draw_line(pos - Vector2(-half_size, half_size), pos + Vector2(-half_size, half_size), color, 2.0)


func _draw_exclamation(pos: Vector2, color: Color) -> void:
	draw_line(pos - Vector2(0, 10), pos + Vector2(0, 2), color, 2.5)
	draw_circle(pos + Vector2(0, 7), 2.0, color)


func _draw_route_label(pos: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 11
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := pos - text_size / 2.0 + Vector2(0, -14)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.position.y < TITLE_BAR_HEIGHT:
					_dragging_title = true
					_drag_start = event.global_position - position
				else:
					_dragging_canvas = true
					_drag_start = event.position
			else:
				if _dragging_canvas and event.position.distance_to(_drag_start) < 4.0:
					_handle_click(event.position)
				_dragging_title = false
				_dragging_canvas = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_detail_panel.visible = false

	if event is InputEventMouseMotion:
		if _dragging_title:
			position = event.global_position - _drag_start
		elif _dragging_canvas:
			_pan_offset += event.relative
			_rebuild_map()
		else:
			_update_hover_tooltip(event.position)


func _update_hover_tooltip(hover_pos: Vector2) -> void:
	for sys_id in system_nodes:
		var data: Dictionary = system_nodes[sys_id]
		var pos: Vector2 = data["position"]
		if hover_pos.distance_to(pos) <= NODE_RADIUS + 6:
			var text: String = data["display_name"]
			if data.get("is_current", false):
				text += "  (current)"
			var sc: int = data.get("station_count", 0)
			if sc > 0:
				text += "\nStations: %d" % sc
			var f_names: Array = data.get("faction_names", [])
			var f_ids: Array = data.get("faction_ids", [])
			if not f_names.is_empty():
				text += "\nFactions: "
				for i in range(f_names.size()):
					var rep: float = GlobalState.reputations.get(f_ids[i], 0.0)
					var c: Color = GlobalState.reputation_color(rep)
					var hex: String = "#" + c.to_html(false)
					if i > 0:
						text += ", "
					text += "[color=%s]%s[/color]" % [hex, f_names[i]]
			var origin: String = data.get("origin", "")
			if origin == "generated":
				text += "\nGenerated system"
			_tooltip_label.text = text
			var offset := Vector2(15, -_tooltip_panel.size.y - 5)
			if pos.x + 15 + _tooltip_panel.size.x > WINDOW_SIZE.x:
				offset.x = -_tooltip_panel.size.x - 15
			_tooltip_panel.position = pos + offset
			_tooltip_panel.visible = true
			return
	_tooltip_panel.visible = false


func _handle_click(click_pos: Vector2) -> void:
	for sys_id in system_nodes:
		var data: Dictionary = system_nodes[sys_id]
		var pos: Vector2 = data["position"]
		if click_pos.distance_to(pos) <= NODE_RADIUS + 4:
			_show_system_detail(sys_id, data, click_pos)
			return

	for route in route_data:
		var from_pos: Vector2 = system_nodes[route["from"]]["position"]
		var to_pos: Vector2 = system_nodes[route["to"]]["position"]
		var mid := (from_pos + to_pos) / 2.0
		if click_pos.distance_to(mid) <= 20:
			_show_route_detail(route, click_pos)
			return

	_detail_panel.visible = false


func _show_system_detail(sys_id: String, data: Dictionary, pos: Vector2) -> void:
	if not data.get("is_current", false):
		if not planned_route.is_empty() and planned_route[-1] == sys_id:
			clear_route()
		else:
			plan_route_to(sys_id)
		_detail_panel.visible = false
		return

	var text := "[%s]\n" % data["display_name"]
	text += "Current location\n"
	if not planned_route.is_empty():
		text += "Route: %d jumps to %s\n" % [planned_route.size() - 1, system_nodes.get(planned_route[-1], {}).get("display_name", "?")]
		text += "(click destination to change)"
	var game_root := get_tree().current_scene
	if game_root and "system_registry" in game_root:
		var sys_def = game_root.system_registry.get_system(sys_id)
		if sys_def:
			if not sys_def.station_ids.is_empty():
				text += "\nStations: %d" % sys_def.station_ids.size()
			if not sys_def.faction_ids.is_empty():
				var factions: Array[String] = []
				for fid in sys_def.faction_ids:
					factions.append(str(fid).get_slice(".", 1).capitalize())
				text += "\nFactions: %s" % ", ".join(factions)
	_detail_label.text = text
	_detail_panel.position = pos + Vector2(15, -10)
	_detail_panel.visible = true


func _show_route_detail(route: Dictionary, pos: Vector2) -> void:
	var state: String = route["state"]
	var text := "[%s]\n" % route["gate_name"]
	text += "Status: %s\n" % state.capitalize()
	var action := ""
	match state:
		"rumored": action = "Fly to coordinates to scan"
		"hidden": action = "Scan the gate"
		"blocked": action = "Meet prerequisites to unlock"
		"damaged": action = "Repair (50 SC + 30 ore)"
		"known": action = "Route active"
	text += "Action: %s" % action
	_detail_label.text = text
	_detail_panel.position = pos + Vector2(15, -10)
	_detail_panel.visible = true


func _close() -> void:
	visible = false
	get_tree().paused = false


func refresh() -> void:
	_pan_offset = Vector2.ZERO
	_rebuild_map()


func get_next_hop_legacy_id() -> String:
	if planned_route.size() < 2:
		return ""
	var next_sys_id: String = planned_route[1]
	var data: Dictionary = system_nodes.get(next_sys_id, {})
	return data.get("legacy_id", "")


func clear_route() -> void:
	planned_route.clear()
	queue_redraw()

extends CanvasLayer
class_name DevPanel

# ── Signals (GameRoot connects these) ─────────────────────────────────────────
signal spawn_boss_requested
signal spawn_squad_requested
signal stores_restock_requested

# ── Layout refs ───────────────────────────────────────────────────────────────
var _action_vbox: VBoxContainer
var _tab_container: TabContainer
var _root_panel: PanelContainer

# ── Public API ────────────────────────────────────────────────────────────────
## Add a button to the left quick-action sidebar.
func add_action_button(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	_style_action_btn(btn)
	_action_vbox.add_child(btn)
	return btn

## Add a new tab to the right panel. Returns the VBoxContainer to populate.
func add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_tab_container.add_child(scroll)
	_tab_container.set_tab_title(_tab_container.get_tab_count() - 1, title)
	return vbox

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 200
	visible = false
	_build_chrome()
	_build_faction_tuning_tab()
	_build_ship_viewer_tab()
	_build_lounge_layout_tab()
	_build_mechanic_debug_tab()
	# ── Add more built-in tabs here in future sessions ──
	# var my_tab := add_tab("My Tool")
	# _build_my_tool(my_tab)

func _build_chrome() -> void:
	# Dim backdrop — click outside panel does nothing (no close-on-click).
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_root_panel = PanelContainer.new()
	# Full-rect with a small inset so it fits at any resolution.
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.offset_left   = 30
	_root_panel.offset_right  = -30
	_root_panel.offset_top    = 30
	_root_panel.offset_bottom = -30
	_root_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_root_panel)

	var outer := VBoxContainer.new()
	_root_panel.add_child(outer)

	# ── Title bar ─────────────────────────────────────────────────────────────
	var title_bar := HBoxContainer.new()
	outer.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "  DEV PANEL"
	title_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_lbl)

	var hint := Label.new()
	hint.text = "Numpad 7 to close  "
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	title_bar.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Body: sidebar + tab content ───────────────────────────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Left sidebar.
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(180, 0)
	body.add_child(sidebar)

	var sidebar_title := Label.new()
	sidebar_title.text = "QUICK ACTIONS"
	sidebar_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sidebar.add_child(sidebar_title)
	sidebar.add_child(HSeparator.new())

	_action_vbox = VBoxContainer.new()
	_action_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_action_vbox)

	body.add_child(VSeparator.new())

	# Right tab area.
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(_tab_container)

	# ── Wire built-in action buttons ──────────────────────────────────────────
	add_action_button("Spawn Boss",     func(): emit_signal("spawn_boss_requested"))
	add_action_button("Spawn Squad",    func(): emit_signal("spawn_squad_requested"))
	add_action_button("Restock Stores", func(): emit_signal("stores_restock_requested"))
	# ── Add more quick actions here in future sessions ──

# ── Faction tuning tab ────────────────────────────────────────────────────────
func _build_lounge_layout_tab() -> void:
	var tab := add_tab("Lounge Layout")

	var hint := Label.new()
	hint.text = (
		"Open a station lounge, then nudge these values. "
		+ "Give Codex the final numbers shown below."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)

	var values := Label.new()
	values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	values.text = _lounge_layout_values()
	tab.add_child(values)
	tab.add_child(HSeparator.new())

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	tab.add_child(slot_row)
	var prev_slot := Button.new()
	prev_slot.text = "Previous Slot"
	prev_slot.pressed.connect(func() -> void:
		values.text = _set_lounge_layout_slot(-1)
	)
	slot_row.add_child(prev_slot)
	var next_slot := Button.new()
	next_slot.text = "Next Slot"
	next_slot.pressed.connect(func() -> void:
		values.text = _set_lounge_layout_slot(1)
	)
	slot_row.add_child(next_slot)
	tab.add_child(HSeparator.new())

	_build_lounge_nudge_row(tab, values, "Portrait X", "portrait", "x")
	_build_lounge_nudge_row(tab, values, "Portrait Y", "portrait", "y")
	_build_lounge_nudge_row(tab, values, "Talk X", "talk", "x")
	_build_lounge_nudge_row(tab, values, "Talk Y", "talk", "y")
	tab.add_child(HSeparator.new())

	var text_values := Label.new()
	text_values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	text_values.text = _lounge_text_values()
	tab.add_child(text_values)
	_build_lounge_text_x_row(tab, text_values, "Name 1 X", "name", 0)
	_build_lounge_text_x_row(tab, text_values, "Name 2 X", "name", 1)
	_build_lounge_text_x_row(tab, text_values, "Name 3 X", "name", 2)
	_build_lounge_text_x_row(tab, text_values, "Name 4 X", "name", 3)
	_build_lounge_text_x_row(tab, text_values, "Bartender Lower X", "meta", 0)
	tab.add_child(HSeparator.new())

	var reset := Button.new()
	reset.text = "Reset Lounge Layout"
	reset.pressed.connect(func() -> void:
		var ui := GlobalState.get_ui_manager()
		if ui and ui.has_method("debug_reset_lounge_layout"):
			values.text = ui.debug_reset_lounge_layout()
			text_values.text = _lounge_text_values()
	)
	tab.add_child(reset)


func _build_lounge_nudge_row(
	parent: VBoxContainer,
	values: Label,
	label_text: String,
	target: String,
	axis: String,
	step: float = 0.01
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var minus := Button.new()
	minus.text = "- %.2f" % step
	minus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_layout(target, axis, -step)
	)
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+ %.2f" % step
	plus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_layout(target, axis, step)
	)
	row.add_child(plus)


func _build_lounge_text_x_row(
	parent: VBoxContainer,
	values: Label,
	label_text: String,
	target: String,
	slot_index: int,
	step: float = 0.01
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)

	var minus := Button.new()
	minus.text = "- %.2f" % step
	minus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_text(target, slot_index, -step)
	)
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+ %.2f" % step
	plus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_text(target, slot_index, step)
	)
	row.add_child(plus)


func _adjust_lounge_layout(target: String, axis: String, delta: float) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_adjust_lounge_layout"):
		return ui.debug_adjust_lounge_layout(target, axis, delta)
	return "UIManager not available."


func _adjust_lounge_text(target: String, slot_index: int, delta: float) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_adjust_lounge_text"):
		return ui.debug_adjust_lounge_text(target, slot_index, delta)
	return "UIManager not available."


func _set_lounge_layout_slot(delta: int) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui == null \
			or not ui.has_method("debug_lounge_layout_values") \
			or not ui.has_method("debug_set_lounge_tuning_slot"):
		return "UIManager not available."
	var current_text: String = ui.debug_lounge_layout_values()
	var slot := 1
	var parts: PackedStringArray = current_text.split(" ")
	if parts.size() >= 2 and str(parts[0]) == "Slot":
		slot = int(parts[1]) - 1
	return ui.debug_set_lounge_tuning_slot(clampi(slot + delta, 0, 3))


func _lounge_layout_values() -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_lounge_layout_values"):
		return ui.debug_lounge_layout_values()
	return "Open the game UI to tune lounge layout."


func _lounge_text_values() -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_lounge_text_values"):
		return ui.debug_lounge_text_values()
	return "Open the game UI to tune lounge text."


func _build_mechanic_debug_tab() -> void:
	var tab := add_tab("Mechanic Debug")

	var hint := Label.new()
	hint.text = "Dock at the main station, enter maintenance, then refresh this to see why the mechanic pickup offer did or did not appear."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)

	var values := Label.new()
	values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	values.autowrap_mode = TextServer.AUTOWRAP_WORD
	values.text = _mechanic_debug_values()
	tab.add_child(values)

	var refresh := Button.new()
	refresh.text = "Refresh Mechanic Debug"
	refresh.pressed.connect(func() -> void:
		values.text = _mechanic_debug_values()
	)
	tab.add_child(refresh)


func _mechanic_debug_values() -> String:
	var debug: Dictionary = GlobalState.last_mechanic_pickup_roll_debug
	if debug.is_empty():
		return "No mechanic pickup roll recorded yet."
	var station_lane_occupied := QuestManager.is_lane_occupied("STATION")
	var station_data := QuestManager.get_lane_data("STATION")
	var lines: Array[String] = [
		"Offered: %s" % str(bool(debug.get("offered", false))),
		"Reason: %s" % str(debug.get("reason", "")),
		"Roll: %.3f / Chance: %.3f" % [
			float(debug.get("roll", 0.0)),
			float(debug.get("chance", 0.0)),
		],
		"Pickup outposts: %d total, %d valid" % [
			int(debug.get("outpost_count", 0)),
			int(debug.get("valid_outpost_count", 0)),
		],
		"Station lane occupied: %s" % str(station_lane_occupied),
	]
	if station_lane_occupied:
		lines.append("Station lane title: %s" % str(station_data.get("title", "")))
	if bool(debug.get("offered", false)):
		lines.append("Selected: %s / %s / %s" % [
			str(debug.get("selected_outpost", "")),
			str(debug.get("selected_npc", "")),
			str(debug.get("selected_part", "")),
		])
	var valid_outposts: Array = debug.get("valid_outposts", [])
	if not valid_outposts.is_empty():
		var names: Array[String] = []
		for entry in valid_outposts:
			if entry is Dictionary:
				names.append(str(entry.get("display", entry.get("id", ""))))
		lines.append("Valid destinations: %s" % ", ".join(names))
	return "\n".join(lines)


const _TUN_FIELDS      := ["weapon_tier","hull_tier","powerplant_tier","shield_tier","weapon_dmg_mult","drone_dmg_mult","intelligence"]
const _TUN_LABELS      := ["W.Tier","H.Tier","PP.Tier","Sh.Tier","W.Res","D.Res","Intel"]
const _TUN_STEPS       := [1.0, 1.0, 1.0, 1.0, 0.1, 0.1, 0.05]
const _TUN_IS_INT      := [true, true, true, true, false, false, false]

var _tun_labels: Dictionary = {}   # { faction_key: { field: Label } }

func _build_faction_tuning_tab() -> void:
	var tab := add_tab("Faction Tuning")

	# Column headers.
	var header := HBoxContainer.new()
	tab.add_child(header)
	_tun_cell_label(header, "FACTION", 210)
	for lbl in _TUN_LABELS:
		_tun_cell_label(header, lbl, 110)
	tab.add_child(HSeparator.new())

	# Known profiles.
	var known_hdr := Label.new()
	known_hdr.text = "── Known Factions ──"
	known_hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	tab.add_child(known_hdr)
	for key in FactionRegistry.KNOWN_PROFILES:
		var base: Dictionary = FactionRegistry.KNOWN_PROFILES[key]
		_build_tuning_row(tab, key, base.get("display_name", key), base)

	tab.add_child(HSeparator.new())

	# Unknown factions.
	var unk_hdr := Label.new()
	unk_hdr.text = "── Unknown Factions ──"
	unk_hdr.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	tab.add_child(unk_hdr)
	for entry in FactionRegistry.UNKNOWN_FACTIONS:
		_build_tuning_row(tab, entry["id"], entry.get("display_name", entry["id"]), entry)

	# Save / Reset footer.
	tab.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	tab.add_child(footer)

	var save_btn := Button.new()
	save_btn.text = "💾  Save overrides to disk"
	save_btn.pressed.connect(func(): FactionRegistry.save_overrides())
	footer.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "↺  Reset all overrides"
	reset_btn.pressed.connect(_on_reset_tuning)
	footer.add_child(reset_btn)

func _build_tuning_row(parent: VBoxContainer, key: String, display: String, base: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = display
	name_lbl.custom_minimum_size = Vector2(210, 0)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	_tun_labels[key] = {}
	for i in _TUN_FIELDS.size():
		var field: String = _TUN_FIELDS[i]
		var base_val: float = float(base.get(field, 0))
		var eff_val: float  = float(FactionRegistry._overrides.get(key, {}).get(field, base_val))

		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(110, 0)
		row.add_child(cell)

		var dn := Button.new()
		dn.text = "▼"
		dn.custom_minimum_size = Vector2(24, 0)
		cell.add_child(dn)

		var val_lbl := Label.new()
		val_lbl.text = _tun_fmt(i, eff_val)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_lbl.custom_minimum_size = Vector2(52, 0)
		cell.add_child(val_lbl)
		_tun_labels[key][field] = val_lbl

		var up := Button.new()
		up.text = "▲"
		up.custom_minimum_size = Vector2(24, 0)
		cell.add_child(up)

		# Closures capture by value at bind time via bind().
		dn.pressed.connect(_adjust_tuning.bind(key, i, -_TUN_STEPS[i]))
		up.pressed.connect(_adjust_tuning.bind(key, i, +_TUN_STEPS[i]))

func _adjust_tuning(key: String, field_idx: int, delta: float) -> void:
	var field: String = _TUN_FIELDS[field_idx]
	var lbl: Label    = _tun_labels[key][field]
	var cur: float    = float(_parse_tun_label(lbl.text))
	var next: float   = cur + delta
	if _TUN_IS_INT[field_idx]:
		next = max(0.0, round(next))
	else:
		next = maxf(0.0, snapped(next, 0.01))
	FactionRegistry.set_override(key, field, int(next) if _TUN_IS_INT[field_idx] else next)
	lbl.text = _tun_fmt(field_idx, next)

func _on_reset_tuning() -> void:
	FactionRegistry.clear_overrides()
	# Re-read base values into labels.
	for key in _tun_labels:
		var base: Dictionary = FactionRegistry.KNOWN_PROFILES.get(key, {})
		if base.is_empty():
			for e in FactionRegistry.UNKNOWN_FACTIONS:
				if e["id"] == key:
					base = e
					break
		for i in _TUN_FIELDS.size():
			var field: String = _TUN_FIELDS[i]
			_tun_labels[key][field].text = _tun_fmt(i, float(base.get(field, 0)))

func _parse_tun_label(text: String) -> float:
	return float(text.strip_edges())

func _tun_fmt(field_idx: int, val: float) -> String:
	if _TUN_IS_INT[field_idx]:
		return "%d" % int(val)
	return "%.2f" % val

func _tun_cell_label(parent: HBoxContainer, text: String, min_w: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(min_w, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(lbl)

# ── Ship viewer tab ─────────────────────────────────────────────────────────
var _sv_viewer: Control
var _sv_entries: Array = []   # [{faction, role, idx}]
var _sv_dropdown: OptionButton

func _build_ship_viewer_tab() -> void:
	var tab := add_tab("Ship Viewer")

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(row)

	# Left: controls.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	row.add_child(left)

	var lbl := Label.new()
	lbl.text = "Ship"
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	left.add_child(lbl)

	_sv_dropdown = OptionButton.new()
	_sv_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_sv_dropdown)

	var hint := Label.new()
	hint.text = "Drag = orbit\nScroll = zoom"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	left.add_child(hint)

	row.add_child(VSeparator.new())

	# Right: the reusable 3D viewer.
	_sv_viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	_sv_viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sv_viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sv_viewer.custom_minimum_size = Vector2(640, 620)
	row.add_child(_sv_viewer)

	# Showcase / favourite ships first (player-ship candidates etc.).
	for i in range(ShipAssembler.special_ship_names().size()):
		_sv_dropdown.add_item("★ %s" % ShipAssembler.special_ship_names()[i])
		_sv_entries.append({"special": i})

	# Then every styled faction × every catalog design.
	for faction in ShipAssembler.styled_factions():
		for role in ShipAssembler.catalog_roles():
			for i in range(ShipAssembler.design_count(role)):
				_sv_dropdown.add_item("%s  %s  #%d" % [str(faction).capitalize(), role, i + 1])
				_sv_entries.append({"faction": faction, "role": role, "idx": i})

	_sv_dropdown.item_selected.connect(_on_sv_selected)
	if _sv_entries.size() > 0:
		_sv_dropdown.select(0)
		# Build first ship once the viewer is in-tree and ready.
		call_deferred("_on_sv_selected", 0)

func _on_sv_selected(index: int) -> void:
	if index < 0 or index >= _sv_entries.size():
		return
	var e: Dictionary = _sv_entries[index]
	if e.has("special"):
		var node := ShipAssembler.build_special(int(e["special"]))
		if node:
			_sv_viewer.set_model(node)
	else:
		_sv_viewer.show_ship(e["faction"], e["role"], e["idx"])

# ── Styling ───────────────────────────────────────────────────────────────────
func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.08, 0.08, 0.10, 0.97)
	s.border_color        = Color(0.3, 1.0, 0.5, 0.8)
	s.set_border_width_all(2)
	s.set_content_margin_all(10)
	return s

func _style_action_btn(btn: Button) -> void:
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

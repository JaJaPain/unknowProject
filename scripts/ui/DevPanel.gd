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

extends CanvasLayer

# ── Asset paths ────────────────────────────────────────────────────────────────
const ASSET_DIR          := "res://assets/CombatWheel/"
const TEX_WHEEL          := ASSET_DIR + "BlankWheel.png"
const TEX_BUTTONS_ART    := ASSET_DIR + "withoutNumbers2.png"
const TEX_INTENT_BAR     := ASSET_DIR + "intentBar.png"

# ── Layout constants ──────────────────────────────────────────────────────────
const WHEEL_DISPLAY_SIZE := 155.0   # BlankWheel rendered size (px)
const BTN_ART_SCALE      := WHEEL_DISPLAY_SIZE / 1024.0
const BTN_ART_OFFSET     := 0.0

const BTN_RADIUS         := 68.0
const BTN_HIT_SIZE       := Vector2(44, 34)

const ACTION_DEFS := [
	{ "type": 0, "label": "FIRE\nWEAPONS",       "ap": 2, "color": Color(0.85,0.15,0.15), "angle": -90.0  },
	{ "type": 1, "label": "BOOST /\nREPOSITION", "ap": 1, "color": Color(0.85,0.45,0.10), "angle": -38.0  },
	{ "type": 2, "label": "SHIELD\nREROUTE",      "ap": 1, "color": Color(0.75,0.60,0.05), "angle":  22.0  },
	{ "type": 3, "label": "ATTACK\nDRONE",        "ap": 2, "color": Color(0.05,0.55,0.55), "angle":  90.0  },
	{ "type": 4, "label": "MICRO-\nWARP",         "ap": 3, "color": Color(0.45,0.10,0.80), "angle": 148.0  },
	{ "type": 5, "label": "REPAIR\nKIT",          "ap": 2, "color": Color(0.10,0.60,0.15), "angle": 218.0  },
	{ "type": 6, "label": "FLEE",                 "ap": 3, "color": Color(0.20,0.35,0.75), "angle": 263.0  },
]

# ── Node refs ─────────────────────────────────────────────────────────────────
var _wheel_panel:   Control   # exposed for UILayoutManager drag registration
var _root:          Control
var _ap_label:      Label
var _intent_label:  Label
var _player_bar:    ProgressBar
var _enemy_bar:     ProgressBar
var _player_label:  Label
var _enemy_label:   Label
var _queue_strip:   HBoxContainer
var _execute_btn:   Button
var _respond_btn:   Button
var _action_btns:   Array[Button] = []
var _warp_cd_label: Label

# ── Runtime state ─────────────────────────────────────────────────────────────
var _ap_current: int = 0
var _ap_max:     int = 0

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_build_ui()
	hide()
	CombatManager.combat_started.connect(_on_combat_started)
	CombatManager.planning_started.connect(_on_planning_started)
	CombatManager.execution_started.connect(_on_execution_started)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.ap_changed.connect(_on_ap_changed)
	CombatManager.action_queued.connect(_on_action_queued)
	CombatManager.action_dequeued.connect(_on_action_dequeued)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_intent_bar()
	_build_wheel()
	_build_hp_bars()
	_build_queue_strip()
	_build_execute_row()

# ── Intent bar ────────────────────────────────────────────────────────────────
func _build_intent_bar() -> void:
	# Background image (intentBar.png is 1536x1024 — we scale it to a thin strip)
	var tex := load(TEX_INTENT_BAR) as Texture2D
	var bar_w := 700.0
	var bar_h := 48.0

	var bg := TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_left   =  -(bar_w * 0.5)
	bg.offset_right  =   (bar_w * 0.5)
	bg.offset_top    =   20.0
	bg.offset_bottom =   20.0 + bar_h
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_intent_label = Label.new()
	_intent_label.text = "Enemy: —"
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 16)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
	_intent_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_intent_label.offset_left   =  -(bar_w * 0.5)
	_intent_label.offset_right  =   (bar_w * 0.5)
	_intent_label.offset_top    =   20.0
	_intent_label.offset_bottom =   20.0 + bar_h
	_intent_label.anchor_left   = 0.5
	_intent_label.anchor_right  = 0.5
	_intent_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_intent_label)

# ── Wheel ─────────────────────────────────────────────────────────────────────
func get_wheel_panel() -> Control:
	return _wheel_panel

func _build_wheel() -> void:
	var half_w: float = WHEEL_DISPLAY_SIZE * 0.5 + BTN_RADIUS + BTN_HIT_SIZE.x * 0.5 + 10
	var half_h: float = WHEEL_DISPLAY_SIZE * 0.5 + BTN_RADIUS + BTN_HIT_SIZE.y * 0.5 + 10
	var panel_w := half_w * 2.0
	var panel_h := half_h * 2.0

	# Default position: roughly screen centre (UILayoutManager overrides from save file)
	var vp_size := get_viewport().get_visible_rect().size
	var default_pos := vp_size * 0.5 - Vector2(half_w, half_h + 30.0)

	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position    = default_pos
	container.size        = Vector2(panel_w, panel_h)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)
	_wheel_panel = container

	var center := Vector2(half_w, half_h)

	# BlankWheel background ring
	var wheel_tex := load(TEX_WHEEL) as Texture2D
	var wheel_rect := TextureRect.new()
	wheel_rect.texture             = wheel_tex
	wheel_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	wheel_rect.ignore_texture_size = true
	wheel_rect.position            = center - Vector2(WHEEL_DISPLAY_SIZE * 0.5, WHEEL_DISPLAY_SIZE * 0.5)
	wheel_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	container.add_child(wheel_rect)
	wheel_rect.size = Vector2(WHEEL_DISPLAY_SIZE, WHEEL_DISPLAY_SIZE)

	var art_tex  := load(TEX_BUTTONS_ART) as Texture2D
	var art_rect := TextureRect.new()
	art_rect.texture             = art_tex
	art_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	art_rect.ignore_texture_size = true
	art_rect.position            = center - Vector2(WHEEL_DISPLAY_SIZE * 0.5, WHEEL_DISPLAY_SIZE * 0.5)
	art_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	container.add_child(art_rect)
	art_rect.size = Vector2(WHEEL_DISPLAY_SIZE, WHEEL_DISPLAY_SIZE)

	# Dark square behind AP number (covers the bright centre hole in BlankWheel)
	var ap_bg := ColorRect.new()
	ap_bg.color    = Color(0.04, 0.06, 0.10, 0.95)
	ap_bg.size     = Vector2(46, 30)
	ap_bg.position = center - Vector2(23, 15)
	ap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(ap_bg)

	var ap_title := Label.new()
	ap_title.text = "AP"
	ap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_title.add_theme_font_size_override("font_size", 7)
	ap_title.add_theme_color_override("font_color", Color(0.40, 0.80, 1.0))
	ap_title.size     = Vector2(46, 12)
	ap_title.position = center - Vector2(23, 15)
	ap_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(ap_title)

	_ap_label = Label.new()
	_ap_label.text = "5/5"
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ap_label.add_theme_font_size_override("font_size", 14)
	_ap_label.add_theme_color_override("font_color", Color(0.40, 0.85, 1.0))
	_ap_label.size     = Vector2(46, 20)
	_ap_label.position = center - Vector2(23, 3)
	_ap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_ap_label)

	# Invisible hit-area buttons placed over each button in the art
	_action_btns.clear()
	for def in ACTION_DEFS:
		var angle_rad := deg_to_rad(float(def["angle"]))
		var btn_center := center + Vector2(cos(angle_rad), sin(angle_rad)) * BTN_RADIUS
		var btn := _make_hit_button(def, btn_center)
		container.add_child(btn)
		_action_btns.append(btn)

		# Micro-warp cooldown badge
		if def["type"] == 4:
			_warp_cd_label = Label.new()
			_warp_cd_label.add_theme_font_size_override("font_size", 11)
			_warp_cd_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
			_warp_cd_label.position = btn_center + Vector2(-14, -BTN_HIT_SIZE.y * 0.5 - 18)
			_warp_cd_label.size     = Vector2(60, 18)
			_warp_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(_warp_cd_label)

func _make_hit_button(def: Dictionary, btn_center: Vector2) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = BTN_HIT_SIZE
	btn.position = btn_center - BTN_HIT_SIZE * 0.5
	# Transparent normal state — art image provides the visual
	var style_clear := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",   style_clear)
	btn.add_theme_stylebox_override("hover",    style_clear)
	btn.add_theme_stylebox_override("pressed",  style_clear)
	btn.add_theme_stylebox_override("disabled", style_clear)
	btn.text = ""
	var action_type: int = def["type"]
	btn.pressed.connect(func(): _on_action_pressed(action_type))
	return btn

# ── HP bars ───────────────────────────────────────────────────────────────────
func _build_hp_bars() -> void:
	_player_label = _make_hp_label("YOU")
	_player_label.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_player_label.offset_left   =  30
	_player_label.offset_right  =  200
	_player_label.offset_top    = -80
	_player_label.offset_bottom = -58
	_root.add_child(_player_label)

	_player_bar = _make_hp_bar(Color(0.20, 0.80, 0.30))
	_player_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_player_bar.offset_left   =  30
	_player_bar.offset_right  =  200
	_player_bar.offset_top    = -55
	_player_bar.offset_bottom = -30
	_root.add_child(_player_bar)

	_enemy_label = _make_hp_label("ENEMY")
	_enemy_label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_enemy_label.offset_left   = -200
	_enemy_label.offset_right  = -30
	_enemy_label.offset_top    = -80
	_enemy_label.offset_bottom = -58
	_root.add_child(_enemy_label)

	_enemy_bar = _make_hp_bar(Color(0.85, 0.25, 0.25))
	_enemy_bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_enemy_bar.offset_left   = -200
	_enemy_bar.offset_right  = -30
	_enemy_bar.offset_top    = -55
	_enemy_bar.offset_bottom = -30
	_root.add_child(_enemy_bar)

func _make_hp_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_hp_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value     = 100.0
	bar.show_percentage = false
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.10, 0.10, 0.12)
	style_bg.corner_radius_top_left     = 4
	style_bg.corner_radius_top_right    = 4
	style_bg.corner_radius_bottom_left  = 4
	style_bg.corner_radius_bottom_right = 4
	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = color
	style_fill.corner_radius_top_left     = 4
	style_fill.corner_radius_top_right    = 4
	style_fill.corner_radius_bottom_left  = 4
	style_fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", style_bg)
	bar.add_theme_stylebox_override("fill",       style_fill)
	bar.custom_minimum_size = Vector2(170, 20)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

# ── Queue strip + execute row ─────────────────────────────────────────────────
func _build_queue_strip() -> void:
	_queue_strip = HBoxContainer.new()
	_queue_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_queue_strip.offset_bottom = -110
	_queue_strip.offset_top    = -148
	_queue_strip.offset_left   =  260
	_queue_strip.offset_right  = -260
	_queue_strip.alignment     = BoxContainer.ALIGNMENT_CENTER
	_queue_strip.add_theme_constant_override("separation", 8)
	_queue_strip.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_queue_strip)

func _build_execute_row() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_bottom = -64
	row.offset_top    = -106
	row.offset_left   =  260
	row.offset_right  = -260
	row.alignment     = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_root.add_child(row)

	var undo := _make_flat_btn("↩  UNDO",    Color(0.35, 0.35, 0.35), Vector2(120, 38))
	undo.pressed.connect(_on_undo_pressed)
	row.add_child(undo)

	_execute_btn = _make_flat_btn("▶  EXECUTE", Color(0.10, 0.60, 0.90), Vector2(200, 38))
	_execute_btn.pressed.connect(_on_execute_pressed)
	row.add_child(_execute_btn)

	_respond_btn = _make_flat_btn("💬  RESPOND", Color(0.30, 0.25, 0.50), Vector2(140, 38))
	_respond_btn.pressed.connect(_on_respond_pressed)
	row.add_child(_respond_btn)

func _make_flat_btn(text: String, color: Color, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color     = color.darkened(0.35)
	style.border_color = color
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

# ── CombatManager signals ─────────────────────────────────────────────────────
func _on_combat_started(_enemy: Node) -> void:
	show()

func _on_planning_started(ap: int, max_ap: int, intent: Dictionary, _taunts: Dictionary) -> void:
	_ap_current = ap
	_ap_max     = max_ap
	_ap_label.text = "%d/%d" % [ap, max_ap]
	_intent_label.text = "Enemy: %s" % intent.get("label", "—")
	_clear_queue_chips()
	_refresh_button_states()
	_execute_btn.disabled = false
	_refresh_hp_bars()
	if _warp_cd_label:
		var cd: int = CombatManager.micro_warp_cooldown
		_warp_cd_label.text = "(%d turns)" % cd if cd > 0 else ""

func _on_execution_started() -> void:
	for btn in _action_btns:
		btn.disabled = true
	_execute_btn.disabled = true

func _on_combat_ended(_player_won: bool) -> void:
	hide()

func _on_ap_changed(current: int, max_ap: int) -> void:
	_ap_current = current
	_ap_max     = max_ap
	_ap_label.text = "%d/%d" % [current, max_ap]
	_refresh_button_states()

func _on_action_queued(action: Dictionary) -> void:
	_add_queue_chip(action)

func _on_action_dequeued() -> void:
	_remove_last_queue_chip()

# ── Button callbacks ───────────────────────────────────────────────────────────
func _on_action_pressed(action_type: int) -> void:
	var params := {}
	if action_type == 2:  # SHIELD_REROUTE — default front; TODO sub-picker
		params["face"] = 0
	if action_type == 1:  # BOOST — default closer; TODO toggle
		params["direction"] = "closer"
	CombatManager.queue_action(action_type, params)

func _on_undo_pressed() -> void:
	CombatManager.dequeue_last()

func _on_execute_pressed() -> void:
	if CombatManager.queued_actions.is_empty():
		return
	CombatManager.commit_turn()

func _on_respond_pressed() -> void:
	CombatManager.play_player_reply()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _refresh_button_states() -> void:
	for i in _action_btns.size():
		var def: Dictionary = ACTION_DEFS[i]
		var cost: int = def["ap"]
		if def["type"] == 0:
			cost = CombatManager._fire_ap_cost
		var can_afford: bool = _ap_current >= cost
		var blocked: bool = false
		if def["type"] == 4 and CombatManager.micro_warp_cooldown > 0:
			blocked = true
		if def["type"] == 5 and not GlobalState.inventory.has_item("repair_kit"):
			blocked = true
		if def["type"] == 5 and CombatManager.repair_used_this_turn:
			blocked = true
		_action_btns[i].disabled = not can_afford or blocked
		# Dim the art layer region by modulating the button's self_modulate
		_action_btns[i].modulate = Color(1, 1, 1, 1) if (can_afford and not blocked) else Color(0.35, 0.35, 0.35, 0.7)

func _refresh_hp_bars() -> void:
	var p := CombatManager.player_node
	var e := CombatManager.enemy_node
	if is_instance_valid(p):
		var hp: float  = float(p.get("health"))     if p.get("health")     != null else 0.0
		var mx: float  = float(p.get("max_health")) if p.get("max_health") != null else 100.0
		_player_bar.max_value = mx
		_player_bar.value     = hp
	if is_instance_valid(e):
		var hp: float  = float(e.get("health"))     if e.get("health")     != null else 0.0
		var mx: float  = float(e.get("max_health")) if e.get("max_health") != null else 50.0
		_enemy_bar.max_value = mx
		_enemy_bar.value     = hp

func _add_queue_chip(action: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = " %s " % action.get("label", "?").replace("\n", " ")
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.12, 0.14, 0.20, 0.92)
	style.border_color = Color(0.25, 0.65, 0.90, 0.80)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	lbl.add_theme_stylebox_override("normal", style)
	_queue_strip.add_child(lbl)

func _remove_last_queue_chip() -> void:
	var ch := _queue_strip.get_children()
	if not ch.is_empty():
		ch.back().queue_free()

func _clear_queue_chips() -> void:
	for child in _queue_strip.get_children():
		child.queue_free()


extends CanvasLayer

# ── Action button config ───────────────────────────────────────────────────────
const ACTION_DEFS := [
	{
		"type":  0,  # CombatAction.Type.FIRE
		"label": "FIRE\nWEAPONS",
		"ap":    2,
		"color": Color(0.85, 0.15, 0.15),
		"angle": -90.0,
	},
	{
		"type":  1,  # BOOST
		"label": "BOOST /\nREPOSITION",
		"ap":    1,
		"color": Color(0.85, 0.45, 0.10),
		"angle": -38.0,
	},
	{
		"type":  2,  # SHIELD_REROUTE
		"label": "SHIELD\nREROUTE",
		"ap":    1,
		"color": Color(0.75, 0.60, 0.05),
		"angle": 25.0,
	},
	{
		"type":  3,  # ATTACK_DRONE
		"label": "ATTACK\nDRONE",
		"ap":    2,
		"color": Color(0.05, 0.55, 0.55),
		"angle": 90.0,
	},
	{
		"type":  4,  # MICRO_WARP
		"label": "MICRO-\nWARP",
		"ap":    3,
		"color": Color(0.45, 0.10, 0.80),
		"angle": 155.0,
	},
	{
		"type":  5,  # REPAIR_KIT
		"label": "REPAIR\nKIT",
		"ap":    2,
		"color": Color(0.10, 0.60, 0.15),
		"angle": 218.0,
	},
	{
		"type":  6,  # FLEE
		"label": "FLEE",
		"ap":    3,
		"color": Color(0.20, 0.35, 0.75),
		"angle": 270.0,
	},
]

const WHEEL_RADIUS    := 180.0
const BUTTON_SIZE     := Vector2(110, 70)
const PANEL_BG_COLOR  := Color(0.04, 0.06, 0.10, 0.92)
const BORDER_COLOR    := Color(0.20, 0.65, 0.90, 0.80)

# ── Node refs (built in _build_ui) ────────────────────────────────────────────
var _root:          Control
var _ap_label:      Label
var _intent_label:  Label
var _player_bar:    ProgressBar
var _enemy_bar:     ProgressBar
var _queue_strip:   HBoxContainer
var _execute_btn:   Button
var _respond_btn:   Button
var _action_btns:   Array[Button] = []
var _warp_cooldown: Label

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
	add_child(_root)

	_build_intent_bar()
	_build_hp_bars()
	_build_wheel()
	_build_queue_strip()
	_build_execute_row()

# ── Intent bar (top center) ───────────────────────────────────────────────────
func _build_intent_bar() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.50, 0.10, 0.10, 0.85)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top    = 24
	panel.offset_bottom = 70
	panel.offset_left   = 300
	panel.offset_right  = -300
	_root.add_child(panel)

	_intent_label = Label.new()
	_intent_label.text = "Enemy: —"
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 18)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	panel.add_child(_intent_label)

# ── HP bars (flanking the wheel) ──────────────────────────────────────────────
func _build_hp_bars() -> void:
	_player_bar = _make_hp_bar("YOU", Color(0.20, 0.80, 0.30))
	_player_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_player_bar.offset_left   = 40
	_player_bar.offset_right  = 220
	_player_bar.offset_top    = -60
	_player_bar.offset_bottom = 60
	_root.add_child(_player_bar)

	_enemy_bar = _make_hp_bar("ENEMY", Color(0.85, 0.25, 0.25))
	_enemy_bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_enemy_bar.offset_left   = -220
	_enemy_bar.offset_right  = -40
	_enemy_bar.offset_top    = -60
	_enemy_bar.offset_bottom = 60
	_root.add_child(_enemy_bar)

func _make_hp_bar(title: String, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value     = 100.0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	bar.add_theme_stylebox_override("fill", style_fill)
	bar.custom_minimum_size = Vector2(160, 22)
	return bar

# ── Wheel ─────────────────────────────────────────────────────────────────────
func _build_wheel() -> void:
	var wheel := Control.new()
	wheel.set_anchors_preset(Control.PRESET_CENTER)
	wheel.offset_left   = -(WHEEL_RADIUS + BUTTON_SIZE.x * 0.5 + 20)
	wheel.offset_right  =  (WHEEL_RADIUS + BUTTON_SIZE.x * 0.5 + 20)
	wheel.offset_top    = -(WHEEL_RADIUS + BUTTON_SIZE.y * 0.5 + 20)
	wheel.offset_bottom =  (WHEEL_RADIUS + BUTTON_SIZE.y * 0.5 + 20)
	_root.add_child(wheel)

	var wheel_size := wheel.offset_right - wheel.offset_left

	# Dark circular background
	var bg := ColorRect.new()
	bg.color = PANEL_BG_COLOR
	bg.custom_minimum_size = Vector2(wheel_size, wheel_size)
	bg.position = Vector2.ZERO
	wheel.add_child(bg)

	var center := Vector2(wheel_size * 0.5, wheel_size * 0.5)

	# AP display in center
	var ap_container := VBoxContainer.new()
	ap_container.position = center - Vector2(55, 35)
	ap_container.custom_minimum_size = Vector2(110, 70)
	wheel.add_child(ap_container)

	var ap_title := Label.new()
	ap_title.text = "ACTION POINTS"
	ap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_title.add_theme_font_size_override("font_size", 11)
	ap_title.add_theme_color_override("font_color", BORDER_COLOR)
	ap_container.add_child(ap_title)

	_ap_label = Label.new()
	_ap_label.text = "6 / 6"
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ap_label.add_theme_font_size_override("font_size", 32)
	_ap_label.add_theme_color_override("font_color", BORDER_COLOR)
	ap_container.add_child(_ap_label)

	# Action buttons arranged radially
	_action_btns.clear()
	for def in ACTION_DEFS:
		var angle_rad := deg_to_rad(float(def["angle"]))
		var btn_center := center + Vector2(cos(angle_rad), sin(angle_rad)) * WHEEL_RADIUS
		var btn := _make_action_button(def)
		btn.position = btn_center - BUTTON_SIZE * 0.5
		wheel.add_child(btn)
		_action_btns.append(btn)

		# Micro-warp cooldown badge
		if def["type"] == 4:
			_warp_cooldown = Label.new()
			_warp_cooldown.text = ""
			_warp_cooldown.add_theme_font_size_override("font_size", 12)
			_warp_cooldown.add_theme_color_override("font_color", Color(1, 0.5, 1))
			_warp_cooldown.position = btn.position + Vector2(BUTTON_SIZE.x * 0.5 - 16, -18)
			wheel.add_child(_warp_cooldown)

func _make_action_button(def: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = BUTTON_SIZE
	btn.text = "%s\n%d AP" % [def["label"], def["ap"]]
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD

	var style := StyleBoxFlat.new()
	style.bg_color = (def["color"] as Color).darkened(0.45)
	style.border_color = def["color"]
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = (def["color"] as Color).darkened(0.20)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var action_type: int = def["type"]
	btn.pressed.connect(func(): _on_action_pressed(action_type))
	return btn

# ── Queue strip (below wheel) ─────────────────────────────────────────────────
func _build_queue_strip() -> void:
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_bottom = -110
	strip.offset_top    = -150
	strip.offset_left   = 260
	strip.offset_right  = -260
	strip.alignment     = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 8)
	_root.add_child(strip)
	_queue_strip = strip

func _build_execute_row() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_bottom = -60
	row.offset_top    = -104
	row.offset_left   = 260
	row.offset_right  = -260
	row.alignment     = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_root.add_child(row)

	# Undo button
	var undo := Button.new()
	undo.text = "↩  UNDO"
	undo.custom_minimum_size = Vector2(120, 40)
	_style_flat_btn(undo, Color(0.35, 0.35, 0.35))
	undo.pressed.connect(_on_undo_pressed)
	row.add_child(undo)

	# Execute button
	_execute_btn = Button.new()
	_execute_btn.text = "▶  EXECUTE"
	_execute_btn.custom_minimum_size = Vector2(200, 40)
	_style_flat_btn(_execute_btn, Color(0.10, 0.60, 0.90))
	_execute_btn.pressed.connect(_on_execute_pressed)
	row.add_child(_execute_btn)

	# Respond (0-AP Kaelen voice reply)
	_respond_btn = Button.new()
	_respond_btn.text = "💬  RESPOND"
	_respond_btn.custom_minimum_size = Vector2(140, 40)
	_style_flat_btn(_respond_btn, Color(0.30, 0.25, 0.50))
	_respond_btn.pressed.connect(_on_respond_pressed)
	row.add_child(_respond_btn)

func _style_flat_btn(btn: Button, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.35)
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

# ── CombatManager signal handlers ─────────────────────────────────────────────
func _on_combat_started(_enemy: Node) -> void:
	show()

func _on_planning_started(ap: int, max_ap: int, intent: Dictionary, _taunts: Dictionary) -> void:
	_ap_current = ap
	_ap_max     = max_ap
	_ap_label.text = "%d / %d" % [ap, max_ap]
	_intent_label.text = "Enemy: %s" % intent.get("label", "—")
	_refresh_button_states()
	_execute_btn.disabled = false
	_clear_queue_chips()

	# Micro-warp cooldown badge
	var cd: int = CombatManager.micro_warp_cooldown
	if _warp_cooldown:
		_warp_cooldown.text = "(%d)" % cd if cd > 0 else ""

	# Update HP bars
	_refresh_hp_bars()

func _on_execution_started() -> void:
	for btn in _action_btns:
		btn.disabled = true
	_execute_btn.disabled = true

func _on_combat_ended(_player_won: bool) -> void:
	hide()

func _on_ap_changed(current: int, max_ap: int) -> void:
	_ap_current = current
	_ap_max     = max_ap
	_ap_label.text = "%d / %d" % [current, max_ap]
	_refresh_button_states()

func _on_action_queued(action: Dictionary) -> void:
	_add_queue_chip(action)

func _on_action_dequeued() -> void:
	_remove_last_queue_chip()

# ── Button callbacks ───────────────────────────────────────────────────────────
func _on_action_pressed(action_type: int) -> void:
	var params := {}
	# Shield reroute defaults to Front; Boost defaults to closer.
	# Future: open sub-menu for face/direction selection.
	if action_type == 2:  # SHIELD_REROUTE
		params["face"] = 0  # Front — TODO: sub-picker
	if action_type == 1:  # BOOST
		params["direction"] = "closer"  # TODO: toggle closer/farther
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
	var CombatActionType := preload("res://scripts/combat/CombatAction.gd")
	for i in _action_btns.size():
		var def: Dictionary = ACTION_DEFS[i]
		var cost: int = def["ap"]
		if def["type"] == 0:  # FIRE — respect upgrade override
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
		_action_btns[i].modulate = Color.WHITE if (can_afford and not blocked) else Color(0.4, 0.4, 0.4, 0.6)

func _refresh_hp_bars() -> void:
	var p := CombatManager.player_node
	var e := CombatManager.enemy_node
	if is_instance_valid(p):
		var hp: float = float(p.get("health")) if p.get("health") != null else 0.0
		var mx: float = float(p.get("max_health")) if p.get("max_health") != null else 100.0
		_player_bar.max_value = mx
		_player_bar.value     = hp
	if is_instance_valid(e):
		var hp: float = float(e.get("health")) if e.get("health") != null else 0.0
		var mx: float = float(e.get("max_health")) if e.get("max_health") != null else 50.0
		_enemy_bar.max_value = mx
		_enemy_bar.value     = hp

func _add_queue_chip(action: Dictionary) -> void:
	var chip := Label.new()
	chip.text = " %s " % action.get("label", "?")
	chip.add_theme_font_size_override("font_size", 12)
	chip.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.20, 0.90)
	style.border_color = BORDER_COLOR
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	chip.add_theme_stylebox_override("normal", style)
	_queue_strip.add_child(chip)

func _remove_last_queue_chip() -> void:
	var children := _queue_strip.get_children()
	if children.is_empty():
		return
	children.back().queue_free()

func _clear_queue_chips() -> void:
	for child in _queue_strip.get_children():
		child.queue_free()


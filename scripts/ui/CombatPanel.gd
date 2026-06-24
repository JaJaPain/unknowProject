extends CanvasLayer

# ── Asset paths ────────────────────────────────────────────────────────────────
const ASSET_DIR       := "res://assets/CombatWheel/"
const TEX_WHEEL       := ASSET_DIR + "BlankWheel.png"
const TEX_NUMBER_FONT := ASSET_DIR + "NumberFont.png"
const TEX_INTENT_BAR  := ASSET_DIR + "intentBar.png"

# Per-button image pairs [active, disabled] — order matches ACTION_DEFS
const BUTTON_ASSETS := [
	["Button01/FireWeapons.png",   "Button01/FireWeapons_Dis.png"],
	["Button02/BoostRepo.png",     "Button02/BoostRepo_Dis.png"],
	["Button03/SheildReroute.png", "Button03/SheildReroute_Dis.png"],
	["Button04/AttackDrone.png",   "Button04/AttackDrone_Dis.png"],
	["Button05/MicroWarp.png",     "Button05/MicroWarp_Dis.png"],
	["Button06/RepairKit.png",     "Button06/RepairKit_Dis.png"],
	["Button07/Flee.png",          "Button07/Flee_Dis.png"],
]

# ── Layout constants (base values tuned for 1080p; scaled by viewport at build time) ──
const WHEEL_BASE         := 400.0   # wheel diameter at 1080p
const BTN_RADIUS_BASE    := 176.0
const BTN_HIT_BASE       := Vector2(100, 76)

# Computed at _build_wheel() time — used by _refresh_button_states / warp label
var _ui_scale: float = 1.0
var _btn_radius: float = BTN_RADIUS_BASE
var _btn_hit: Vector2 = BTN_HIT_BASE

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
var _wheel_panel:      Control
var _root:             Control
var _ap_cur_rect:      TextureRect   # NumberFont digit — current AP
var _ap_sep_label:     Label         # "/" separator
var _ap_max_rect:      TextureRect   # NumberFont digit — max AP
var _intent_label:     Label
var _player_bar:       ProgressBar
var _enemy_bar:        ProgressBar
var _player_label:     Label
var _enemy_label:      Label
var _queue_strip:      HBoxContainer
var _execute_btn:      Button
var _respond_btn:      Button
var _action_btns:     Array[Button] = []
var _btn_active:      Array[TextureRect] = []   # per-button active image
var _btn_disabled:    Array[TextureRect] = []   # per-button disabled image
var _warp_cd_label:   Label
var _font_tex:         Texture2D   # NumberFont loaded once

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
	# Anchor just above the execute row (which sits at offset_bottom = -64)
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left   = -(bar_w * 0.5)
	bg.offset_right  =  (bar_w * 0.5)
	bg.offset_top    = -114.0 - bar_h
	bg.offset_bottom = -114.0
	bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_intent_label = Label.new()
	_intent_label.text = "Enemy: —"
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 16)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
	_intent_label.anchor_left   = 0.5
	_intent_label.anchor_right  = 0.5
	_intent_label.anchor_top    = 1.0
	_intent_label.anchor_bottom = 1.0
	_intent_label.offset_left   = -(bar_w * 0.5)
	_intent_label.offset_right  =  (bar_w * 0.5)
	_intent_label.offset_top    = -114.0 - bar_h
	_intent_label.offset_bottom = -114.0
	_intent_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_intent_label)

# ── Wheel ─────────────────────────────────────────────────────────────────────
func get_wheel_panel() -> Control:
	return _wheel_panel

func _build_wheel() -> void:
	var vp_size  := get_viewport().get_visible_rect().size
	_ui_scale    = vp_size.y / 1080.0          # 1.0 at 1080p, 1.68 at 4K 1812p
	var S        := _ui_scale

	var wheel_sz := WHEEL_BASE      * S
	_btn_radius  = BTN_RADIUS_BASE  * S
	_btn_hit     = BTN_HIT_BASE     * S

	var half_w := wheel_sz * 0.5 + _btn_radius + _btn_hit.x * 0.5 + 10.0 * S
	var half_h := wheel_sz * 0.5 + _btn_radius + _btn_hit.y * 0.5 + 10.0 * S

	# Right-centre default — clear of chat panel on left, clear of screen edge on right
	var default_pos := Vector2(vp_size.x * 0.60 - half_w, vp_size.y * 0.45 - half_h)

	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position     = default_pos
	container.size         = Vector2(half_w * 2.0, half_h * 2.0)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)
	_wheel_panel = container

	var center := Vector2(half_w, half_h)

	var wheel_tex  := load(TEX_WHEEL) as Texture2D
	var wheel_rect := TextureRect.new()
	wheel_rect.texture             = wheel_tex
	wheel_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	wheel_rect.ignore_texture_size = true
	wheel_rect.position            = center - Vector2(wheel_sz * 0.5, wheel_sz * 0.5)
	wheel_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	container.add_child(wheel_rect)
	wheel_rect.size = Vector2(wheel_sz, wheel_sz)

	# Per-button active + disabled images — all same size/position as wheel (pre-composited)
	var btn_pos := center - Vector2(wheel_sz * 0.5, wheel_sz * 0.5)
	_btn_active.clear()
	_btn_disabled.clear()
	for pair in BUTTON_ASSETS:
		var act := _make_wheel_layer(ASSET_DIR + pair[0], btn_pos, wheel_sz)
		container.add_child(act)
		act.size = Vector2(wheel_sz, wheel_sz)
		_btn_active.append(act)

		var dis := _make_wheel_layer(ASSET_DIR + pair[1], btn_pos, wheel_sz)
		dis.visible = false
		container.add_child(dis)
		dis.size = Vector2(wheel_sz, wheel_sz)
		_btn_disabled.append(dis)

	# NumberFont AP readout — parse sprite sheet at runtime
	_font_tex = load(TEX_NUMBER_FONT) as Texture2D
	var digit_w := _font_tex.get_width()  / 5.0
	var digit_h := _font_tex.get_height() / 2.0
	var disp_h  := 36.0 * S
	var disp_w  := disp_h * (digit_w / digit_h)   # keep aspect
	var sep_w   := disp_w * 0.5
	var row_w   := disp_w * 2.0 + sep_w
	var row_x   := center.x - row_w * 0.5
	var row_y   := center.y - disp_h * 0.5

	var ap_bg := ColorRect.new()
	ap_bg.color       = Color(0.04, 0.06, 0.10, 0.90)
	ap_bg.size        = Vector2(row_w + 8.0 * S, disp_h + 6.0 * S)
	ap_bg.position    = Vector2(row_x - 4.0 * S, row_y - 3.0 * S)
	ap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(ap_bg)

	_ap_cur_rect = _make_digit_rect(5, digit_w, digit_h)
	_ap_cur_rect.size     = Vector2(disp_w, disp_h)
	_ap_cur_rect.position = Vector2(row_x, row_y)
	_ap_cur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_ap_cur_rect)

	_ap_sep_label = Label.new()
	_ap_sep_label.text = "/"
	_ap_sep_label.add_theme_font_size_override("font_size", int(20 * S))
	_ap_sep_label.add_theme_color_override("font_color", Color(0.40, 0.80, 1.0))
	_ap_sep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ap_sep_label.size     = Vector2(sep_w, disp_h)
	_ap_sep_label.position = Vector2(row_x + disp_w, row_y)
	_ap_sep_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_ap_sep_label)

	_ap_max_rect = _make_digit_rect(5, digit_w, digit_h)
	_ap_max_rect.size     = Vector2(disp_w, disp_h)
	_ap_max_rect.position = Vector2(row_x + disp_w + sep_w, row_y)
	_ap_max_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_ap_max_rect)

	# Invisible hit-area buttons
	_action_btns.clear()
	for def in ACTION_DEFS:
		var angle_rad  := deg_to_rad(float(def["angle"]))
		var btn_center := center + Vector2(cos(angle_rad), sin(angle_rad)) * _btn_radius
		var btn := _make_hit_button(def, btn_center)
		container.add_child(btn)
		_action_btns.append(btn)

		if def["type"] == 4:
			_warp_cd_label = Label.new()
			_warp_cd_label.add_theme_font_size_override("font_size", int(11 * S))
			_warp_cd_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
			_warp_cd_label.position    = btn_center + Vector2(-14.0 * S, -_btn_hit.y * 0.5 - 18.0 * S)
			_warp_cd_label.size        = Vector2(60.0 * S, 18.0 * S)
			_warp_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(_warp_cd_label)

	# Enemy HP bar — centered directly above the wheel, travels with it when dragged
	var ebar_w  := 220.0 * S
	var ebar_h  := 20.0  * S
	var elbl_h  := 18.0  * S
	var emargin := 10.0  * S
	var wheel_top := center.y - wheel_sz * 0.5

	_enemy_label = _make_hp_label("ENEMY")
	_enemy_label.size     = Vector2(ebar_w, elbl_h)
	_enemy_label.position = Vector2(center.x - ebar_w * 0.5, wheel_top - emargin - elbl_h - ebar_h)
	_enemy_label.add_theme_font_size_override("font_size", int(11 * S))
	_enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_enemy_label)

	_enemy_bar = _make_hp_bar(Color(0.85, 0.25, 0.25))
	_enemy_bar.custom_minimum_size = Vector2(ebar_w, ebar_h)
	_enemy_bar.size     = Vector2(ebar_w, ebar_h)
	_enemy_bar.position = Vector2(center.x - ebar_w * 0.5, wheel_top - emargin - ebar_h)
	_enemy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_enemy_bar)

func _make_hit_button(def: Dictionary, btn_center: Vector2) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = _btn_hit
	btn.position = btn_center - _btn_hit * 0.5
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

func _make_wheel_layer(path: String, pos: Vector2, sz: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture             = load(path) as Texture2D
	r.stretch_mode        = TextureRect.STRETCH_SCALE
	r.ignore_texture_size = true
	r.position            = pos
	r.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	return r

func _make_digit_rect(digit: int, digit_w: float, digit_h: float) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas  = _font_tex
	atlas.region = Rect2((digit % 5) * digit_w, (digit / 5) * digit_h, digit_w, digit_h)
	var r := TextureRect.new()
	r.texture             = atlas
	r.stretch_mode        = TextureRect.STRETCH_SCALE
	r.ignore_texture_size = true
	# Shader: treat white as transparent, tint dark pixels cyan
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){\nvec4 c=texture(TEXTURE,UV);\nfloat lum=dot(c.rgb,vec3(0.3,0.59,0.11));\nCOLOR=vec4(0.35,0.85,1.0,1.0-lum*lum);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	return r

func _set_ap_display(current: int, max_ap: int) -> void:
	if not is_instance_valid(_ap_cur_rect) or _font_tex == null:
		return
	var digit_w := _font_tex.get_width()  / 5.0
	var digit_h := _font_tex.get_height() / 2.0
	var cur  := clampi(current, 0, 9)
	var maxa := clampi(max_ap,  0, 9)
	(_ap_cur_rect.texture as AtlasTexture).region = Rect2((cur  % 5) * digit_w, (cur  / 5) * digit_h, digit_w, digit_h)
	(_ap_max_rect.texture as AtlasTexture).region = Rect2((maxa % 5) * digit_w, (maxa / 5) * digit_h, digit_w, digit_h)

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

	# _enemy_label and _enemy_bar are created inside _build_wheel() so they
	# travel with the wheel when the player drags it.

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
	_set_ap_display(ap, max_ap)
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
	_set_ap_display(current, max_ap)
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
		var is_disabled := not can_afford or blocked
		_action_btns[i].disabled = is_disabled
		if i < _btn_active.size():
			_btn_active[i].visible   = not is_disabled
			_btn_disabled[i].visible = is_disabled

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


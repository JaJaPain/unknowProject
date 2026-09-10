extends CanvasLayer

# ── Asset paths ────────────────────────────────────────────────────────────────
const ASSET_DIR       := "res://assets/CombatWheel/"
const TEX_WHEEL       := ASSET_DIR + "BlankWheel.png"
const TEX_NUMBER_FONT := ASSET_DIR + "NumberFont.png"
const TEX_INTENT_BAR  := ASSET_DIR + "intentBar.png"
const SFX_BTN_CLICK   := ASSET_DIR + "soundfxs/click.mp3"

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

# ── Sensor signature table ────────────────────────────────────────────────────
# Maps action type → faction → one or more sensor readout strings (picked randomly).
# Faction keys: "aurelia", "vanguard", "generic" (fallback), "boss".
const SENSOR_SIGS: Dictionary = {
	CombatAction.Type.FIRE: {
		"aurelia":  ["Rapid-fire array spooling up", "Dual cannon charge detected"],
		"vanguard": ["Heavy cannon capacitors charging", "Targeting lock — your bearing"],
		"boss":     ["PRIMARY WEAPONS CHARGING — ALL BARRELS", "Mass driver capacitors at critical level"],
		"generic":  ["Weapon systems charging", "Energy spike — forward arc"],
	},
	CombatAction.Type.BOOST: {
		"aurelia":  ["Thruster bloom — high-G intercept vector", "Maneuvering burn — fast approach"],
		"vanguard": ["Engine output spiking — closing vector", "Drive plume detected — brute approach"],
		"boss":     ["THRUSTER OUTPUT — MAXIMUM BURN", "Closing vector — all engines"],
		"generic":  ["Thruster signature detected", "Maneuvering burn initiated"],
	},
	CombatAction.Type.SHIELD_REROUTE: {
		"aurelia":  ["Shield emitter reorientation — rapid cycling", "Capacitor bank realigning — lateral bias"],
		"vanguard": ["Shield matrix redistributing — forward bias", "Deflector array hardening — bow aspect"],
		"boss":     ["FULL SHIELD MATRIX REORIENTATION DETECTED", "Deflector emitters cycling — all faces"],
		"generic":  ["Shield emitter reorientation detected", "Capacitor bank realigning"],
	},
	CombatAction.Type.ATTACK_DRONE: {
		"aurelia":  ["Launch bay doors cycling — fast drone", "Drone deployment sequence — intercept class"],
		"vanguard": ["Drone bay pressurizing", "Heavy drone deployment sequence initiated"],
		"boss":     ["MULTIPLE DRONE BAYS OPENING", "Combat drone swarm deployment detected"],
		"generic":  ["Launch bay doors cycling", "Drone deployment sequence initiated"],
	},
	CombatAction.Type.MICRO_WARP: {
		"aurelia":  ["Warp coil charging — short-hop vector", "Micro-warp field building — erratic signature"],
		"vanguard": ["Warp field coil at threshold", "Displacement drive cycling"],
		"boss":     ["WARP FIELD SURGE — EXTREME OUTPUT", "Displacement drive at maximum charge"],
		"generic":  ["Warp field coil charging", "Micro-warp signature detected"],
	},
	CombatAction.Type.REPAIR_KIT: {
		"aurelia":  ["Nanite cloud dispersal detected", "Hull nanites deploying — breach sealing"],
		"vanguard": ["Structural repair sequence active", "Damage control systems engaging"],
		"boss":     ["EMERGENCY REPAIR SYSTEM ACTIVATED", "Hull regeneration sequence — high output"],
		"generic":  ["Nanite dispersal detected", "Hull breach sealing sequence active"],
	},
	CombatAction.Type.FLEE: {
		"aurelia":  ["Drive plume spiking — escape vector", "Emergency burn — high-G retreat"],
		"vanguard": ["Full engine burn — withdrawal vector", "Drive signature spiking — disengaging"],
		"boss":     ["EMERGENCY DRIVE BURN DETECTED", "Retreat vector locked"],
		"generic":  ["Emergency burn detected", "Drive plume spiking — escape vector"],
	},
	CombatAction.Type.BRACE: {
		"aurelia":  ["Hull plating tensioning — impact prep", "Reactive armor cycling"],
		"vanguard": ["Hull stress plates tensioning", "Impact bracing sequence detected"],
		"boss":     ["FULL HULL REINFORCEMENT SEQUENCE", "Structural bracing — maximum output"],
		"generic":  ["Hull reinforcement detected", "Impact bracing sequence active"],
	},
	CombatAction.Type.FLANK: {
		"aurelia":  ["High-G flanking vector locked", "Off-axis intercept burn — port side"],
		"vanguard": ["Flanking thrusters — oblique approach", "Wide arc maneuvering burn detected"],
		"boss":     ["MULTI-AXIS FLANKING BURN — ALL THRUSTERS", "Oblique attack vector — extreme G"],
		"generic":  ["Flanking burn detected", "Off-axis approach vector locked"],
	},
	CombatAction.Type.SHIELD_ANGLE: {
		"aurelia":  ["Shield emitter reorientation — rapid cycling", "Capacitor bank shifting — lateral"],
		"vanguard": ["Shield matrix redistributing — forward bias", "Deflector hardening — bow aspect"],
		"boss":     ["FULL SHIELD MATRIX REORIENTATION", "Deflector emitters cycling — all faces"],
		"generic":  ["Shield emitter reorientation detected", "Capacitor bank realigning"],
	},
	CombatAction.Type.DISABLE_ENGINES: {
		"aurelia":  ["Targeting solution — drive systems", "Precision lock — engine signature"],
		"vanguard": ["Subsystem targeting lock acquired", "Engine disruption sequence initiating"],
		"boss":     ["SUBSYSTEM TARGETING — ALL DRIVES", "Engine kill solution locked"],
		"generic":  ["Subsystem targeting lock", "Drive disruption sequence active"],
	},
}

func _sensor_sig(action_type: Variant, faction: String, is_boss: bool) -> String:
	var type_map: Dictionary = SENSOR_SIGS.get(int(action_type), {})
	var key: String = "boss" if is_boss else faction.to_lower()
	var pool: Array = type_map.get(key, type_map.get("generic", ["Scanning..."]))
	return pool[randi() % pool.size()]


func _combat_scan_text(enemy: Node) -> String:
	var sensor_tier: int = clamp(int(GlobalState.get("sensor_tier")), 0, 2)
	var threat: int = _enemy_threat_level(enemy)
	if sensor_tier <= 0:
		return "THREAT LEVEL: %s" % ("EXTREME" if threat >= 4 else "HIGH")
	var tiers: Dictionary = _enemy_tier_map(enemy)
	if sensor_tier == 1:
		return "HULL T%d / WEAPONS T%d / ENGINE T%d" % [
			int(tiers.get("hull", 1)),
			int(tiers.get("weapons", 1)),
			int(tiers.get("engine", 1)),
		]
	var warning := _enemy_scan_warning(tiers)
	var composition := str(enemy.get("hull_composition")) \
			if is_instance_valid(enemy) and enemy.get("hull_composition") else "UNKNOWN HULL"
	return "HULL T%d %s / WEAPONS T%d / ENGINE T%d / SHIELDS T%d / POWER T%d%s" % [
		int(tiers.get("hull", 1)),
		composition,
		int(tiers.get("weapons", 1)),
		int(tiers.get("engine", 1)),
		int(tiers.get("shields", 0)),
		int(tiers.get("power", 1)),
		warning,
	]


func _enemy_tier_map(enemy: Node) -> Dictionary:
	if not is_instance_valid(enemy):
		return {
			"hull": 1,
			"weapons": 1,
			"engine": 1,
			"shields": 0,
			"power": 1,
		}
	return {
		"hull": max(1, int(enemy.get("hull_tier"))),
		"weapons": max(1, int(enemy.get("weapon_tier"))),
		"engine": max(1, int(enemy.get("engine_tier"))),
		"shields": max(0, int(enemy.get("shield_tier"))),
		"power": max(1, int(enemy.get("powerplant_tier"))),
	}


func _enemy_threat_level(enemy: Node) -> int:
	var tiers := _enemy_tier_map(enemy)
	var highest := 1
	for value in tiers.values():
		highest = max(highest, int(value))
	return highest


func _enemy_scan_warning(tiers: Dictionary) -> String:
	var player_weapons: int = int(GlobalState.current_upgrades.get("weapons", {}).get("tier", 1))
	var player_engine: int = int(GlobalState.current_upgrades.get("engine", {}).get("tier", 1))
	var player_shields: int = int(GlobalState.current_upgrades.get("shields", {}).get("tier", 1))
	var weapon_gap: int = int(tiers.get("weapons", 1)) - player_weapons
	var engine_gap: int = int(tiers.get("engine", 1)) - player_engine
	var shield_gap: int = int(tiers.get("shields", 0)) - player_shields
	if weapon_gap >= 2:
		return " / WARNING: WEAPONS EXCEED YOUR FIT BY %d TIERS" % weapon_gap
	if engine_gap >= 2:
		return " / WARNING: ENGINE OUTPUT EXCEEDS YOUR FIT BY %d TIERS" % engine_gap
	if shield_gap >= 2:
		return " / WARNING: SHIELDS EXCEED YOUR FIT BY %d TIERS" % shield_gap
	return " / ASSESSMENT: WITHIN EXPECTED COMBAT BAND"

# ── Node refs ─────────────────────────────────────────────────────────────────
var _wheel_panel:      Control
var _root:             Control
var _ap_label:         Label         # "X / Y" AP counter in wheel center
var _intent_label:     Label
var _sensor_header:      Label         # "◈ SENSOR ANALYSIS" fixed title line
var _typewrite_tween:    Tween        # cancelled and replaced each planning phase
var _typing_player:      AudioStreamPlayer
var _sensor_panel_root:  Control      # wrapper — hide during execution phase
var _player_bar:       ProgressBar
var _enemy_bar:        ProgressBar
var _player_label:     Label
var _enemy_label:      Label
var _enemy_brace_chip:  Label
var _enemy_shield_chip: Label
var _boss_phase_label:  Label
# Squad UI — shown only when enemy_nodes.size() > 1.
# Top bar (_enemy_bar) always shows enemy_nodes[0]; bottom (_wingman_bar) shows enemy_nodes[1].
# Each has its own invisible click button that selects that specific ship.
var _wingman_bar:        ProgressBar
var _wingman_label:      Label
var _target_btn:         Button   # click-catcher over wingman bar → selects index 1
var _enemy_target_btn:   Button   # click-catcher over enemy bar   → selects index 0
# Saved bar dimensions so we can swap sizes on target switch.
var _bar_large_w: float = 0.0
var _bar_large_h: float = 0.0
var _bar_small_w: float = 0.0
var _bar_small_h: float = 0.0
var _bar_center_x: float = 0.0
var _queue_strip:      HBoxContainer
var _execute_row:      HBoxContainer
var _execute_btn:      Button
# EXECUTE attention pulse. When nothing on the wheel is affordable any more the
# turn is a dead end and the game is silently waiting on the player — a player
# sitting at 0 AP has no way of knowing that. Pulsing the only button that still
# does something says it without a tutorial popup.
var _execute_pulse_tween: Tween = null
var _execute_pulsing := false
var _btn_active:      Array[TextureRect] = []   # per-button active image
var _btn_disabled:    Array[TextureRect] = []   # per-button disabled image
var _btn_blocked:     Array[bool] = []          # per-button disabled state (polar hit-test)
var _warp_cd_label:   Label
var _repair_count_label: Label
var _click_sfx:       AudioStreamPlayer

# ── Wheel hit-test ───────────────────────────────────────────────────────────
# Per-button alpha masks: each Button0X image has only its own wedge opaque, so
# sampling alpha at the cursor pixel gives a pixel-perfect wedge match.
var _btn_images:    Array[Image] = []
var _wheel_px_size: float        = 0.0   # on-screen wheel square size in px
# Fallback polar geometry (used only if alpha masks fail to load).
var _wheel_click_center: Vector2 = Vector2.ZERO
var _wheel_inner_r:      float   = 0.0
var _wheel_outer_r:      float   = 0.0
var _hover_idx:          int     = -1

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
	CombatManager.enemy_status_changed.connect(_on_enemy_status_changed)
	CombatManager.boss_phase_changed.connect(_on_boss_phase_changed)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_click_sfx = AudioStreamPlayer.new()
	_click_sfx.stream = load(SFX_BTN_CLICK) as AudioStream
	_click_sfx.volume_db = -6.0
	add_child(_click_sfx)
	_typing_player = AudioStreamPlayer.new()
	_typing_player.volume_db = -8.0
	add_child(_typing_player)
	if ResourceLoader.exists("res://assets/CombatWheel/soundfxs/typing.mp3"):
		_typing_player.stream = load("res://assets/CombatWheel/soundfxs/typing.mp3") as AudioStream
	# Replay the clip if it ends while text is still being typed.
	_typing_player.finished.connect(func():
		if is_instance_valid(_typewrite_tween) and _typewrite_tween.is_running():
			_typing_player.play()
	)
	_build_sensor_panel()
	_build_wheel()
	_build_hp_bars()
	_build_queue_strip()
	_build_execute_row()

# ── Sensor panel ──────────────────────────────────────────────────────────────
func _build_sensor_panel() -> void:
	var panel_w  := 700.0
	var panel_h  := 76.0
	var pad      := 8.0
	var base_y   := -144.0   # bottom edge offset from screen bottom; raise to clear queue chips

	# Invisible wrapper — toggled as one unit during execute phase.
	_sensor_panel_root = Control.new()
	_sensor_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sensor_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sensor_panel_root)

	# Dark background with green border.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.88)
	bg.anchor_left   = 0.5;  bg.anchor_right  = 0.5
	bg.anchor_top    = 1.0;  bg.anchor_bottom = 1.0
	bg.offset_left   = -(panel_w * 0.5)
	bg.offset_right  =  (panel_w * 0.5)
	bg.offset_top    = base_y - panel_h
	bg.offset_bottom = base_y
	bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(bg)

	# Green border drawn via a StyleBoxFlat on a Panel.
	var border := Panel.new()
	var style  := StyleBoxFlat.new()
	style.bg_color            = Color(0, 0, 0, 0)
	style.border_color        = Color(0.0, 0.85, 0.25, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	border.add_theme_stylebox_override("panel", style)
	border.anchor_left   = 0.5;  border.anchor_right  = 0.5
	border.anchor_top    = 1.0;  border.anchor_bottom = 1.0
	border.offset_left   = -(panel_w * 0.5)
	border.offset_right  =  (panel_w * 0.5)
	border.offset_top    = base_y - panel_h
	border.offset_bottom = base_y
	border.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(border)

	# Header: "◈ SENSOR ANALYSIS" in dim green.
	_sensor_header = Label.new()
	_sensor_header.text = "◈  SENSOR ANALYSIS"
	_sensor_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_sensor_header.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_sensor_header.add_theme_font_size_override("font_size", 10)
	_sensor_header.add_theme_color_override("font_color", Color(0.0, 0.65, 0.20, 0.85))
	_sensor_header.anchor_left   = 0.5;  _sensor_header.anchor_right  = 0.5
	_sensor_header.anchor_top    = 1.0;  _sensor_header.anchor_bottom = 1.0
	_sensor_header.offset_left   = -(panel_w * 0.5) + pad
	_sensor_header.offset_right  =  (panel_w * 0.5) - pad
	_sensor_header.offset_top    = base_y - panel_h + 4.0
	_sensor_header.offset_bottom = base_y - panel_h + 22.0
	_sensor_header.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(_sensor_header)

	# Thin green divider line between header and signature text.
	var divider := ColorRect.new()
	divider.color = Color(0.0, 0.65, 0.20, 0.5)
	divider.anchor_left   = 0.5;  divider.anchor_right  = 0.5
	divider.anchor_top    = 1.0;  divider.anchor_bottom = 1.0
	divider.offset_left   = -(panel_w * 0.5) + pad
	divider.offset_right  =  (panel_w * 0.5) - pad
	divider.offset_top    = base_y - panel_h + 23.0
	divider.offset_bottom = base_y - panel_h + 24.0
	divider.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(divider)

	# Main signature label — typewriter text appears here in bright green.
	_intent_label = Label.new()
	_intent_label.text = ""
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_intent_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_intent_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_intent_label.add_theme_font_size_override("font_size", 15)
	_intent_label.add_theme_color_override("font_color", Color(0.15, 1.0, 0.45))
	_intent_label.anchor_left   = 0.5;  _intent_label.anchor_right  = 0.5
	_intent_label.anchor_top    = 1.0;  _intent_label.anchor_bottom = 1.0
	_intent_label.offset_left   = -(panel_w * 0.5) + pad
	_intent_label.offset_right  =  (panel_w * 0.5) - pad
	_intent_label.offset_top    = base_y - panel_h + 26.0
	_intent_label.offset_bottom = base_y - 2.0
	_intent_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(_intent_label)

	# Scanline overlay — a custom Control that draws semi-transparent horizontal lines.
	var scanlines := _ScanlineOverlay.new()
	scanlines.anchor_left   = 0.5;  scanlines.anchor_right  = 0.5
	scanlines.anchor_top    = 1.0;  scanlines.anchor_bottom = 1.0
	scanlines.offset_left   = -(panel_w * 0.5)
	scanlines.offset_right  =  (panel_w * 0.5)
	scanlines.offset_top    = base_y - panel_h
	scanlines.offset_bottom = base_y
	scanlines.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sensor_panel_root.add_child(scanlines)

# Inner class — draws horizontal scanlines over the sensor panel.
class _ScanlineOverlay extends Control:
	func _draw() -> void:
		var spacing := 4.0
		var n       := int(size.y / spacing)
		for i in n:
			var y := i * spacing
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.18), 1.0)

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
	_wheel_px_size = wheel_sz
	_btn_active.clear()
	_btn_disabled.clear()
	_btn_images.clear()
	for pair in BUTTON_ASSETS:
		var act := _make_wheel_layer(ASSET_DIR + pair[0], btn_pos, wheel_sz)
		container.add_child(act)
		act.size = Vector2(wheel_sz, wheel_sz)
		_btn_active.append(act)
		# Cache the CPU-side image for pixel-perfect alpha hit-testing.
		var img: Image = (act.texture.get_image() if act.texture else null)
		if img != null and img.is_compressed():
			img.decompress()
		_btn_images.append(img)

		var dis := _make_wheel_layer(ASSET_DIR + pair[1], btn_pos, wheel_sz)
		dis.visible = false
		container.add_child(dis)
		dis.size = Vector2(wheel_sz, wheel_sz)
		_btn_disabled.append(dis)

	# AP counter — plain label in wheel centre; always visible
	var lbl_sz   := Vector2(120.0 * S, 44.0 * S)
	var ap_bg    := ColorRect.new()
	ap_bg.color       = Color(0.04, 0.06, 0.10, 0.88)
	ap_bg.size        = lbl_sz + Vector2(8.0 * S, 6.0 * S)
	ap_bg.position    = center - ap_bg.size * 0.5
	ap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(ap_bg)

	_ap_label = Label.new()
	_ap_label.text = "—"
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ap_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_ap_label.add_theme_font_size_override("font_size", int(22.0 * S))
	_ap_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	_ap_label.size        = lbl_sz
	_ap_label.position    = center - lbl_sz * 0.5
	_ap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_ap_label)

	# Polar click geometry — clicks anywhere on the ring map to the nearest wedge.
	_btn_blocked.clear()
	_btn_blocked.resize(ACTION_DEFS.size())
	_btn_blocked.fill(false)
	_wheel_click_center = center
	_wheel_inner_r = wheel_sz * 0.20   # AP hub radius — clicks inside do nothing
	_wheel_outer_r = wheel_sz * 0.52   # slightly past art edge for forgiving clicks

	# Single full-wheel click catcher covering the whole wheel bounding box.
	var click_area := Control.new()
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	click_area.position = btn_pos
	click_area.gui_input.connect(_on_wheel_input)
	click_area.mouse_exited.connect(func(): _update_hover(-1))
	container.add_child(click_area)
	click_area.size = Vector2(wheel_sz, wheel_sz)
	# Local center within click_area is its own midpoint.
	_wheel_click_center = Vector2(wheel_sz * 0.5, wheel_sz * 0.5)

	# Micro-warp cooldown label sits at the MICRO-WARP wedge centre.
	var warp_angle := deg_to_rad(148.0)
	var warp_center := center + Vector2(cos(warp_angle), sin(warp_angle)) * _btn_radius
	_warp_cd_label = Label.new()
	_warp_cd_label.add_theme_font_size_override("font_size", int(11 * S))
	_warp_cd_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
	_warp_cd_label.position    = warp_center + Vector2(-14.0 * S, -_btn_hit.y * 0.5 - 18.0 * S)
	_warp_cd_label.size        = Vector2(60.0 * S, 18.0 * S)
	_warp_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_warp_cd_label)

	# Repair-kit count badge at the REPAIR KIT wedge centre (it's a consumable).
	var rep_angle := deg_to_rad(218.0)
	var rep_center := center + Vector2(cos(rep_angle), sin(rep_angle)) * _btn_radius
	_repair_count_label = Label.new()
	_repair_count_label.add_theme_font_size_override("font_size", int(13 * S))
	_repair_count_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	_repair_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_repair_count_label.position    = rep_center + Vector2(-30.0 * S, -_btn_hit.y * 0.5 - 20.0 * S)
	_repair_count_label.size        = Vector2(60.0 * S, 18.0 * S)
	_repair_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_repair_count_label)

	# Enemy HP bar — centered directly above the wheel, travels with it when dragged
	var ebar_w  := 220.0 * S
	var ebar_h  := 20.0  * S
	_bar_large_w  = ebar_w
	_bar_large_h  = ebar_h
	_bar_small_w  = ebar_w * 0.70
	_bar_small_h  = ebar_h * 0.75
	_bar_center_x = center.x
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

	# Invisible click-catcher over the top (enemy) bar — selects enemy_nodes[0].
	_enemy_target_btn = Button.new()
	_enemy_target_btn.flat = true
	_enemy_target_btn.size = Vector2(ebar_w, ebar_h + elbl_h + 4.0 * S)
	_enemy_target_btn.position = Vector2(center.x - ebar_w * 0.5, wheel_top - emargin - ebar_h - elbl_h)
	_enemy_target_btn.modulate = Color(1, 1, 1, 0)
	_enemy_target_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enemy_target_btn.visible = false
	_enemy_target_btn.pressed.connect(func() -> void: _on_bar_select(0))
	_enemy_target_btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(_enemy_bar): _enemy_bar.modulate = Color(1, 1, 1, 1.0))
	_enemy_target_btn.mouse_exited.connect(func() -> void:
		if CombatManager._target_idx != 0:
			if is_instance_valid(_enemy_bar): _enemy_bar.modulate = Color(1, 1, 1, 0.65))
	container.add_child(_enemy_target_btn)

	# Status chips — shown when enemy has an active defensive state.
	var chip_y := wheel_top - emargin - ebar_h - elbl_h - 20.0 * S
	var chip_h := 16.0 * S
	_enemy_brace_chip = Label.new()
	_enemy_brace_chip.text = "⛨ BRACED"
	_enemy_brace_chip.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	_enemy_brace_chip.add_theme_font_size_override("font_size", int(10 * S))
	_enemy_brace_chip.size = Vector2(ebar_w * 0.5, chip_h)
	_enemy_brace_chip.position = Vector2(center.x - ebar_w * 0.5, chip_y)
	_enemy_brace_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_brace_chip.visible = false
	container.add_child(_enemy_brace_chip)

	_enemy_shield_chip = Label.new()
	_enemy_shield_chip.text = "⚡ SHIELDED"
	_enemy_shield_chip.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	_enemy_shield_chip.add_theme_font_size_override("font_size", int(10 * S))
	_enemy_shield_chip.size = Vector2(ebar_w * 0.5, chip_h)
	_enemy_shield_chip.position = Vector2(center.x, chip_y)
	_enemy_shield_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_shield_chip.visible = false
	container.add_child(_enemy_shield_chip)

	# Boss phase indicator — hidden for normal enemies, shown when is_boss is true.
	_boss_phase_label = Label.new()
	_boss_phase_label.text = "● PHASE I"
	_boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_boss_phase_label.add_theme_font_size_override("font_size", int(11 * S))
	_boss_phase_label.size = Vector2(ebar_w, chip_h)
	_boss_phase_label.position = Vector2(center.x - ebar_w * 0.5, chip_y - chip_h - 2.0 * S)
	_boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_phase_label.visible = false
	container.add_child(_boss_phase_label)

	# Wingman HP bar — narrower (70%) and dimmer than the targeted bar.
	# Click anywhere on it to switch target. Hidden for solo fights.
	var wbar_w := ebar_w * 0.70
	var wbar_h := ebar_h * 0.75
	var wbar_y := wheel_top - emargin - ebar_h - elbl_h - chip_h * 2.0 - 20.0 * S
	_wingman_label = Label.new()
	_wingman_label.text = "Wingman"
	_wingman_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.25))
	_wingman_label.add_theme_font_size_override("font_size", int(10 * S))
	_wingman_label.size = Vector2(wbar_w, elbl_h)
	_wingman_label.position = Vector2(center.x - wbar_w * 0.5, wbar_y - elbl_h)
	_wingman_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wingman_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wingman_label.visible = false
	container.add_child(_wingman_label)

	_wingman_bar = _make_hp_bar(Color(0.65, 0.30, 0.10))
	_wingman_bar.custom_minimum_size = Vector2(wbar_w, wbar_h)
	_wingman_bar.size     = Vector2(wbar_w, wbar_h)
	_wingman_bar.position = Vector2(center.x - wbar_w * 0.5, wbar_y)
	_wingman_bar.modulate = Color(1.0, 1.0, 1.0, 0.65)
	_wingman_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wingman_bar.visible = false
	container.add_child(_wingman_bar)

	# Invisible click-catcher over the wingman label + bar area.
	# Player clicks the secondary bar to switch target — no separate button needed.
	_target_btn = Button.new()
	_target_btn.flat = true
	_target_btn.size = Vector2(wbar_w, wbar_h + elbl_h + 4.0 * S)
	_target_btn.position = Vector2(center.x - wbar_w * 0.5, wbar_y - elbl_h)
	_target_btn.modulate = Color(1.0, 1.0, 1.0, 0.0)   # fully transparent
	_target_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_target_btn.visible = false
	_target_btn.pressed.connect(func() -> void: _on_bar_select(1))
	_target_btn.mouse_entered.connect(func() -> void:
		if CombatManager._target_idx != 1:
			if is_instance_valid(_wingman_bar): _wingman_bar.modulate = Color(1, 1, 1, 1.0)
			if is_instance_valid(_wingman_label): _wingman_label.modulate = Color(1, 1, 1, 1.0))
	_target_btn.mouse_exited.connect(func() -> void:
		if CombatManager._target_idx != 1:
			if is_instance_valid(_wingman_bar): _wingman_bar.modulate = Color(1, 1, 1, 0.65)
			if is_instance_valid(_wingman_label): _wingman_label.modulate = Color(1, 1, 1, 0.65))
	container.add_child(_target_btn)

# ── Wheel hit-testing ───────────────────────────────────────────────────────────
# Pixel-perfect: sample each wedge image's alpha at the cursor and pick the one
# actually painted there. Falls back to the polar nearest-angle test if the
# alpha masks failed to load.
func _wheel_action_at(local_pos: Vector2) -> int:
	if _btn_images.is_empty() or _wheel_px_size <= 0.0:
		return _wheel_action_at_polar(local_pos)
	var u := local_pos.x / _wheel_px_size
	var v := local_pos.y / _wheel_px_size
	if u < 0.0 or v < 0.0 or u > 1.0 or v > 1.0:
		return -1
	var best := -1
	var best_a := 0.20   # ignore transparent gaps + anti-aliased fringes
	for i in _btn_images.size():
		var img: Image = _btn_images[i]
		if img == null:
			continue
		var px := int(u * img.get_width())
		var py := int(v * img.get_height())
		px = clampi(px, 0, img.get_width() - 1)
		py = clampi(py, 0, img.get_height() - 1)
		var a := img.get_pixel(px, py).a
		if a > best_a:
			best_a = a
			best = i
	return best

func _wheel_action_at_polar(local_pos: Vector2) -> int:
	var d := local_pos - _wheel_click_center
	var r := d.length()
	if r < _wheel_inner_r or r > _wheel_outer_r:
		return -1
	var click_deg := rad_to_deg(atan2(d.y, d.x))
	var best := -1
	var best_diff := 999.0
	for i in ACTION_DEFS.size():
		var a: float = float(ACTION_DEFS[i]["angle"])
		var diff: float = abs(wrapf(click_deg - a, -180.0, 180.0))
		if diff < best_diff:
			best_diff = diff
			best = i
	return best

func _on_wheel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_update_hover(_wheel_action_at(ev.position))
	elif ev is InputEventMouseButton \
			and ev.button_index == MOUSE_BUTTON_LEFT \
			and ev.pressed:
		# Sync the highlight to the click point, then fire the wedge that's
		# actually lit — guarantees "what you see is what you click."
		_update_hover(_wheel_action_at(ev.position))
		var idx := _hover_idx
		if idx < 0:
			return
		if idx < _btn_blocked.size() and _btn_blocked[idx]:
			return
		_on_action_pressed(ACTION_DEFS[idx]["type"])

# Exaggerated hover: the wedge under the cursor pops bright, the rest dim back,
# so the player can confirm their target before clicking.
const _HOVER_BRIGHT := Color(1.9, 1.9, 1.9)
const _HOVER_DIM    := Color(0.5, 0.5, 0.5)
const _HOVER_NORMAL := Color(1.0, 1.0, 1.0)

func _update_hover(idx: int) -> void:
	if idx == _hover_idx:
		return
	_hover_idx = idx
	var active_hover: bool = idx >= 0 and idx < _btn_active.size() and not _btn_blocked[idx]
	for i in _btn_active.size():
		var target: Color
		if not active_hover:
			target = _HOVER_NORMAL          # nothing valid hovered → all normal
		elif i == idx:
			target = _HOVER_BRIGHT          # the wedge you'll click
		else:
			target = _HOVER_DIM             # everything else recedes
		var tw := _btn_active[i].create_tween()
		tw.tween_property(_btn_active[i], "modulate", target, 0.07)

func _make_wheel_layer(path: String, pos: Vector2, sz: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture             = load(path) as Texture2D
	r.stretch_mode        = TextureRect.STRETCH_SCALE
	r.ignore_texture_size = true
	r.position            = pos
	r.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	return r


func _set_ap_display(current: int, max_ap: int) -> void:
	if is_instance_valid(_ap_label):
		_ap_label.text = "%d / %d AP" % [current, max_ap]

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
	_execute_row = row

	var undo := _make_flat_btn("↩  UNDO",    Color(0.35, 0.35, 0.35), Vector2(120, 38))
	undo.pressed.connect(_on_undo_pressed)
	row.add_child(undo)

	_execute_btn = _make_flat_btn("▶  EXECUTE", Color(0.10, 0.60, 0.90), Vector2(200, 38))
	_execute_btn.pressed.connect(_on_execute_pressed)
	row.add_child(_execute_btn)


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
func _on_combat_started(enemy: Node) -> void:
	show()
	if is_instance_valid(_sensor_panel_root):
		_sensor_panel_root.visible = true
		_typewrite(_combat_scan_text(enemy))
	# Show phase label only for boss fights; reset to Phase I each fight.
	var is_boss: bool = enemy != null and enemy.get("is_boss") == true
	_boss_phase_label.visible = is_boss
	_boss_phase_label.text = "● PHASE I"
	_boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	# Squad UI — show wingman bar and target button only for multi-enemy fights.
	var is_squad: bool = CombatManager.enemy_nodes.size() > 1
	_wingman_bar.visible        = is_squad
	_wingman_label.visible      = is_squad
	_target_btn.visible         = is_squad
	_enemy_target_btn.visible   = is_squad
	_refresh_target_label()

func _on_planning_started(ap: int, max_ap: int, _intent: Dictionary, _taunts: Dictionary, npc_plan: Array) -> void:
	if is_instance_valid(_sensor_panel_root):
		_sensor_panel_root.visible = true
	_ap_current = ap
	_ap_max     = max_ap
	_set_ap_display(ap, max_ap)
	# Build sensor signature string from the enemy's committed plan.
	var enemy   := CombatManager.enemy_node
	var faction := str(enemy.get("faction") if is_instance_valid(enemy) and enemy.get("faction") else "generic")
	var is_boss: bool = is_instance_valid(enemy) and enemy.get("is_boss") == true
	if npc_plan.is_empty():
		_typewrite("— NO SIGNAL DETECTED —")
	else:
		var sigs: Array = npc_plan.map(func(a: Dictionary) -> String:
			return _sensor_sig(a.get("type", -1), faction, is_boss))
		_typewrite(" ─►  ".join(sigs))
	_clear_queue_chips()
	# Enable before refreshing: _refresh_button_states reads `disabled` when it
	# decides whether the EXECUTE pulse is warranted.
	_execute_btn.disabled = false
	_refresh_button_states()
	_refresh_hp_bars()
	_refresh_target_label()
	if _warp_cd_label:
		var cd: int = CombatManager.micro_warp_cooldown
		_warp_cd_label.text = "(%d turns)" % cd if cd > 0 else ""
	_reset_hover()         # clear any stale highlight from last turn
	_fade_controls(true)   # bring the wheel back for the player's choices

# Rolls the full_text into _intent_label character by character with a cursor.
# Cancels any in-progress typewrite before starting a new one.
func _typewrite(full_text: String) -> void:
	if is_instance_valid(_typewrite_tween):
		_typewrite_tween.kill()
	if is_instance_valid(_typing_player):
		_typing_player.stop()
		_typing_player.play()
	_intent_label.text = "█"
	var delay_per_char := 0.021   # seconds between characters (~48 chars/sec, 25% faster)
	_typewrite_tween = create_tween()
	for i in full_text.length():
		_typewrite_tween.tween_callback(
			func() -> void:
				_intent_label.text = full_text.left(i + 1) + ("█" if i < full_text.length() - 1 else "")
		).set_delay(delay_per_char)
	# Stop typing sound once all characters are revealed.
	_typewrite_tween.tween_callback(
		func() -> void:
			if is_instance_valid(_typing_player):
				_typing_player.stop()
	)

func _on_execution_started() -> void:
	if is_instance_valid(_sensor_panel_root):
		_sensor_panel_root.visible = false
	if is_instance_valid(_typing_player):
		_typing_player.stop()
	for i in _btn_blocked.size():
		_btn_blocked[i] = true
	_execute_btn.disabled = true
	_set_execute_attention(false)
	_reset_hover()
	_fade_controls(false)  # hide the wheel during the action sequence

# Snap every wedge back to normal brightness and clear the hovered index.
func _reset_hover() -> void:
	_hover_idx = -1
	for i in _btn_active.size():
		_btn_active[i].modulate = _HOVER_NORMAL

# Fade the player-control HUD (wheel + execute row + queued chips) in/out.
# Wall-clock so the fade is smooth even through hit-stop slow-mo.
func _fade_controls(visible_state: bool) -> void:
	var target: float = 1.0 if visible_state else 0.0
	var nodes: Array[Control] = [_wheel_panel, _execute_row, _queue_strip]
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var tw: Tween = node.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(node, "modulate:a", target, 0.22)

func _on_combat_ended(_player_won: bool) -> void:
	_set_execute_attention(false)
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

func _on_enemy_status_changed(brace: bool, shield: bool) -> void:
	if is_instance_valid(_enemy_brace_chip):
		_enemy_brace_chip.visible = brace
	if is_instance_valid(_enemy_shield_chip):
		_enemy_shield_chip.visible = shield

func _on_bar_select(idx: int) -> void:
	CombatManager.set_target(idx)
	_apply_bar_sizes()
	_refresh_hp_bars()
	_refresh_target_label()

func _apply_bar_sizes() -> void:
	var ti    := CombatManager._target_idx
	var large := Vector2(_bar_large_w, _bar_large_h)
	var small := Vector2(_bar_small_w, _bar_small_h)
	var cx    := _bar_center_x
	# Top bar (index 0) is large when it's the target, small otherwise.
	var top_sz := large if ti == 0 else small
	_enemy_bar.custom_minimum_size = top_sz
	_enemy_bar.size = top_sz
	_enemy_bar.position.x = cx - top_sz.x * 0.5
	_enemy_bar.modulate = Color(1, 1, 1, 1.0 if ti == 0 else 0.65)
	# Bottom bar (index 1) is large when it's the target, small otherwise.
	var bot_sz := large if ti == 1 else small
	_wingman_bar.custom_minimum_size = bot_sz
	_wingman_bar.size = bot_sz
	_wingman_bar.position.x = cx - bot_sz.x * 0.5
	_wingman_bar.modulate = Color(1, 1, 1, 1.0 if ti == 1 else 0.65)

func _refresh_target_label() -> void:
	if not is_instance_valid(_enemy_label):
		return
	var e := CombatManager.enemy_node
	if is_instance_valid(e):
		var ename: String = str(e.name) if e.name else "ENEMY"
		_enemy_label.text = "▶ " + ename.replace("_", " ") if CombatManager.enemy_nodes.size() > 1 else "ENEMY"
	else:
		_enemy_label.text = "ENEMY"

func _on_boss_phase_changed(phase: int) -> void:
	if not is_instance_valid(_boss_phase_label):
		return
	match phase:
		2:
			_boss_phase_label.text = "●● PHASE II"
			_boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
		3:
			_boss_phase_label.text = "●●● PHASE III"
			_boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))

# ── Button callbacks ───────────────────────────────────────────────────────────
func _on_action_pressed(action_type: int) -> void:
	if is_instance_valid(_click_sfx):
		_click_sfx.play()
	var params := {}
	if action_type == 1:  # BOOST — default closer
		params["direction"] = "closer"
	CombatManager.queue_action(action_type, params)

func _on_undo_pressed() -> void:
	CombatManager.dequeue_last()

func _on_execute_pressed() -> void:
	if CombatManager.queued_actions.is_empty():
		return
	CombatManager.commit_turn()


# ── Helpers ───────────────────────────────────────────────────────────────────
func _refresh_button_states() -> void:
	for i in ACTION_DEFS.size():
		var def: Dictionary = ACTION_DEFS[i]
		var cost: int = def["ap"]
		if def["type"] == 0:
			cost = CombatManager._fire_ap_cost
		var can_afford: bool = _ap_current >= cost
		var blocked: bool = false
		if def["type"] == 4 and CombatManager.micro_warp_cooldown > 0:
			blocked = true
		if def["type"] == 4 and CombatManager.is_training_combat_active():
			blocked = true
		if def["type"] == 5 and not GlobalState.inventory.has_item("repair_kit"):
			blocked = true
		if def["type"] == 5 and CombatManager.repair_used_this_turn:
			blocked = true
		var is_disabled := not can_afford or blocked
		if i < _btn_blocked.size():
			_btn_blocked[i] = is_disabled
		if i < _btn_active.size():
			_btn_active[i].visible   = not is_disabled
			_btn_disabled[i].visible = is_disabled
	# Every wedge unavailable = the turn can only go forward through EXECUTE.
	# Deriving it from _btn_blocked rather than testing _ap_current == 0 also
	# catches the equally dead case where AP remains but nothing costs that
	# little, and the case where cooldowns/consumables have closed the rest.
	var dead_end := not _btn_blocked.is_empty()
	for blocked_state in _btn_blocked:
		if not blocked_state:
			dead_end = false
			break
	_set_execute_attention(dead_end and is_instance_valid(_execute_btn) and not _execute_btn.disabled)
	# Repair-kit count badge — shows remaining consumables (greys at 0).
	if is_instance_valid(_repair_count_label):
		var kits: int = GlobalState.inventory.get_quantity("repair_kit")
		_repair_count_label.text = "x%d" % kits
		_repair_count_label.add_theme_color_override(
			"font_color",
			Color(0.45, 1.0, 0.55) if kits > 0 else Color(0.6, 0.6, 0.6))

## Starts/stops the EXECUTE pulse. Idempotent — called every button refresh.
func _set_execute_attention(on: bool) -> void:
	if not is_instance_valid(_execute_btn) or on == _execute_pulsing:
		return
	_execute_pulsing = on
	if is_instance_valid(_execute_pulse_tween):
		_execute_pulse_tween.kill()
		_execute_pulse_tween = null
	if not on:
		_execute_btn.self_modulate = Color.WHITE
		return
	_execute_pulse_tween = _execute_btn.create_tween().set_loops()
	# Wall-clock, like _fade_controls: the planning phase runs in slow-mo and a
	# pulse that slowed with it would read as the UI lagging, not as a prompt.
	_execute_pulse_tween.set_ignore_time_scale(true)
	_execute_pulse_tween.tween_property(
		_execute_btn, "self_modulate", Color(1.75, 1.75, 1.75, 1.0), 0.45
	).set_trans(Tween.TRANS_SINE)
	_execute_pulse_tween.tween_property(
		_execute_btn, "self_modulate", Color.WHITE, 0.45
	).set_trans(Tween.TRANS_SINE)


func _refresh_hp_bars() -> void:
	var p     := CombatManager.player_node
	var nodes := CombatManager.enemy_nodes
	if is_instance_valid(p):
		var hp: float = float(p.get("health"))     if p.get("health")     != null else 0.0
		var mx: float = float(p.get("max_health")) if p.get("max_health") != null else 100.0
		_player_bar.max_value = mx
		_player_bar.value     = hp
	# Top bar always shows enemy_nodes[0].
	var e0: Node = nodes[0] if nodes.size() > 0 and is_instance_valid(nodes[0]) else null
	if e0 != null:
		_enemy_bar.max_value = float(e0.get("max_health") if e0.get("max_health") != null else 50.0)
		_enemy_bar.value     = float(e0.get("health")     if e0.get("health")     != null else 0.0)
	# Bottom bar always shows enemy_nodes[1] when present.
	var e1: Node = nodes[1] if nodes.size() > 1 and is_instance_valid(nodes[1]) else null
	var show_wingman := e1 != null
	_wingman_bar.visible      = show_wingman
	_wingman_label.visible    = show_wingman
	_target_btn.visible       = show_wingman
	_enemy_target_btn.visible = show_wingman
	if show_wingman:
		_wingman_bar.max_value = float(e1.get("max_health") if e1.get("max_health") != null else 50.0)
		_wingman_bar.value     = float(e1.get("health")     if e1.get("health")     != null else 0.0)
		_wingman_label.text    = str(e1.name) if e1.name else "Wingman"

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

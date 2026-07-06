extends Node

# The cold open (docs/plan_intro_cinematic.md): the ship is thrown through a
# failing gate into the start system — no control, no UI — N.O.V.A. introduces
# herself mid-crisis, the ship arrives damaged, an untraceable data stream
# wires exactly enough credits to repair, then the UI returns and the existing
# Kaelen intro runs. One-shot node; UIManager spawns it on NEW campaigns only.
#
# Every beat checks _finished so the SPACE skip / 30s watchdog can cut in at
# any await point. _finish() is idempotent and ALWAYS restores control — the
# game must never be left controllerless.

# ── Feel-tuning knobs ─────────────────────────────────────────────────────────
const TUMBLE_DURATION := 4.5
const FLING_FLASH := 0.15
const REVEAL_DURATION := 1.2
const ARRIVAL_LINE2_AT := 1.0    # seconds after reveal
const ARRIVAL_LINE3_AT := 5.0
const DATA_STREAM_AT := 8.0
const DATA_LINE4_AT := 10.0
const HANDOFF_AT := 14.0         # after reveal; total runtime ~= 6s + this
const DAMAGE_HEALTH_PCT := 0.4   # ship arrives at 40% hull
const REPAIR_COST_PER_HP := 2.0  # MUST match UIManager._repair_ship cost_per_hp
const SPIN_TURNS := 2.5          # full-axis tumble rotations
const WATCHDOG_S := 30.0

const GLITCH_SHADER := preload("res://shaders/intro_glitch.gdshader")

var _ui: Control = null            # UIManager root (hidden during the sequence)
var _layer: CanvasLayer = null
var _glitch_rect: ColorRect = null
var _glitch_mat: ShaderMaterial = null
var _black: ColorRect = null
var _subtitle: Label = null
var _stream_label: Label = null
var _skip_hint: Label = null
var _finished := false
var _consequences_applied := false


# Entry point. ui_manager is hidden/restored by us; on finish (or skip, or
# watchdog) we call show_kaelen_intro() on it after a 1s beat.
func start(ui_manager: Control) -> void:
	_ui = ui_manager
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		# No player yet — abort gracefully straight to the normal flow.
		_finish()
		return
	_ui.visible = false
	p.set_physics_process(false)
	_build_visuals()
	# Watchdog: whatever happens, control comes back.
	get_tree().create_timer(WATCHDOG_S, true, false, true).timeout.connect(_finish)
	_run()


func _build_visuals() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black)

	_glitch_rect = ColorRect.new()
	_glitch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = GLITCH_SHADER
	_glitch_mat.set_shader_parameter("intensity", 1.0)
	_glitch_mat.set_shader_parameter("white_out", 0.0)
	_glitch_rect.material = _glitch_mat
	_layer.add_child(_glitch_rect)

	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_subtitle.offset_bottom = -90.0
	_subtitle.offset_left = 120.0
	_subtitle.offset_right = -120.0
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_subtitle)

	_stream_label = Label.new()
	_stream_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stream_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stream_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stream_label.add_theme_font_size_override("font_size", 18)
	_stream_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85))
	_stream_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream_label.visible = false
	_layer.add_child(_stream_label)

	_skip_hint = Label.new()
	_skip_hint.text = "[SPACE]  skip"
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -160.0
	_skip_hint.offset_top = -44.0
	_skip_hint.offset_right = -24.0
	_skip_hint.offset_bottom = -20.0
	_skip_hint.add_theme_font_size_override("font_size", 13)
	_skip_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.0))
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_skip_hint)
	# Fade the hint in after a couple of seconds — present, not pushy.
	var hint_tween := create_tween().set_ignore_time_scale(true)
	hint_tween.tween_interval(2.0)
	hint_tween.tween_property(_skip_hint, "theme_override_colors/font_color", Color(0.6, 0.6, 0.6, 0.8), 0.6)


# N.O.V.A. speaks: our subtitle (UI is hidden, chatter feed invisible) plus her
# real voice/portrait routing through Nova.speak (TTS still runs while the UI
# root is hidden — audio handlers don't care about visibility).
func _nova_line(text: String, expression: String) -> void:
	if _finished:
		return
	if _subtitle != null and is_instance_valid(_subtitle):
		_subtitle.text = "N.O.V.A.:  " + text
	if is_instance_valid(Nova) and Nova.has_method("speak"):
		Nova.speak(text, Nova.Severity.THREAT, expression)


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		_finish()


# The story consequences must land whether the player watched or skipped:
# battered hull + the untraceable data stream that covers EXACTLY the repair
# bill (cost mirrors UIManager._repair_ship: missing_hp * cost_per_hp).
func _apply_consequences() -> void:
	if _consequences_applied:
		return
	_consequences_applied = true
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return
	var max_hp := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	p.set("health", max_hp * DAMAGE_HEALTH_PCT)
	var missing := max_hp - (max_hp * DAMAGE_HEALTH_PCT)
	var credits := int(ceil(missing * REPAIR_COST_PER_HP))
	GlobalState.add_credits(credits)
	GenerationDiagnostics.record_event(
		"intro_cinematic", "consequences_applied", "intro_cinematic",
		{"health_pct": DAMAGE_HEALTH_PCT, "credits": credits}
	)


# Idempotent teardown: consequences, control, UI, Kaelen handoff — in that
# order, safe from any phase, any await, the skip key, or the watchdog.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_apply_consequences()
	var p = GlobalState.player
	if p != null and is_instance_valid(p):
		p.set_physics_process(true)
		# Leave the ship level — the tumble may have ended mid-spin.
		var rot: Vector3 = p.rotation
		p.rotation = Vector3(0.0, rot.y, 0.0)
	if _ui != null and is_instance_valid(_ui):
		_ui.visible = true
		var ui := _ui
		get_tree().create_timer(1.0, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(ui) and ui.has_method("show_kaelen_intro"):
				ui.show_kaelen_intro()
		)
	queue_free()


# ── The beat timeline ─────────────────────────────────────────────────────────

# Wall-clock wait: the 4th arg (ignore_time_scale=true) makes each phase last
# REAL seconds no matter what Engine.time_scale is doing. Without it, if the
# engine is running at anything but 1.0x (combat drives it to 0.02x and back —
# CombatManager) every beat fires near-instantly and the whole intro collapses
# into a couple of seconds instead of spacing out. process_always=true so a
# paused tree can't stall it either.
func _beat(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _run() -> void:
	var p = GlobalState.player
	# TUMBLE — thrown through a dying gate: violent spin, screaming glitch.
	if p != null and is_instance_valid(p):
		var spin := create_tween().set_ignore_time_scale(true)
		var target: Vector3 = p.rotation + Vector3(
			TAU * SPIN_TURNS, TAU * (SPIN_TURNS * 0.7), TAU * (SPIN_TURNS * 1.3)
		)
		spin.tween_property(p, "rotation", target, TUMBLE_DURATION + REVEAL_DURATION) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# All intro tweens ignore time scale to stay in sync with the wall-clock
	# beats above — otherwise a non-1.0x engine desyncs visuals from dialogue.
	var flicker := create_tween().set_ignore_time_scale(true)
	flicker.set_loops(6)
	flicker.tween_property(_glitch_mat, "shader_parameter/intensity", 0.7, 0.35)
	flicker.tween_property(_glitch_mat, "shader_parameter/intensity", 1.0, 0.4)
	await _beat(1.0)
	if _finished:
		return
	_nova_line(
		"Hold on, Captain! I'm doing everything I can to stabilize the ship — I've got ONE last thing I can try!",
		"alert"
	)
	await _beat(TUMBLE_DURATION - 1.0)
	if _finished:
		return

	# FLING — her last-ditch trick fires: white-out, then thrown INTO the
	# system. No gate on the other side. The black shell peels away to space.
	flicker.kill()
	_glitch_mat.set_shader_parameter("white_out", 1.0)
	await _beat(FLING_FLASH)
	if _finished:
		return
	var reveal := create_tween().set_ignore_time_scale(true)
	reveal.set_parallel(true)
	reveal.tween_property(_black, "color:a", 0.0, REVEAL_DURATION)
	reveal.tween_property(_glitch_mat, "shader_parameter/white_out", 0.0, REVEAL_DURATION * 0.6)
	reveal.tween_property(_glitch_mat, "shader_parameter/intensity", 0.15, REVEAL_DURATION)
	await _beat(REVEAL_DURATION)
	if _finished:
		return

	# ARRIVAL — battered and drifting. Damage + mystery credits land here (the
	# skip path applies them too, via _apply_consequences' guard).
	_apply_consequences()
	var residual := create_tween().set_ignore_time_scale(true)
	residual.set_loops(0)
	residual.tween_property(_glitch_mat, "shader_parameter/intensity", 0.02, 0.9)
	residual.tween_property(_glitch_mat, "shader_parameter/intensity", 0.14, 0.12)
	await _beat(ARRIVAL_LINE2_AT)
	if _finished:
		return
	_nova_line(
		"We're... somewhere. That wasn't a gate transit, Captain — we were thrown. Hull's a mess, but we're alive.",
		"worried"
	)
	await _beat(ARRIVAL_LINE3_AT - ARRIVAL_LINE2_AT)
	if _finished:
		return
	_nova_line(
		"Here's the part I don't like: my memory starts fourteen seconds ago. I know you're my captain. I know I trust you. I just can't tell you WHY I know either of those things.",
		"wondering"
	)
	await _beat(DATA_STREAM_AT - ARRIVAL_LINE3_AT)
	if _finished:
		return

	# DATA STREAM — exactly enough to fix the hull, from nowhere.
	var credits_shown := 0
	if p != null and is_instance_valid(p):
		var max_hp := float(p.get("max_health")) if p.get("max_health") != null else 100.0
		credits_shown = int(ceil((max_hp - float(p.get("health"))) * REPAIR_COST_PER_HP))
	_stream_label.text = "INCOMING DATA STREAM  //  ORIGIN: [UNRESOLVED]  //  CREDITS RECEIVED: %d" % credits_shown
	_stream_label.visible = true
	_stream_label.modulate.a = 0.0
	var stream_tween := create_tween().set_ignore_time_scale(true)
	stream_tween.tween_property(_stream_label, "modulate:a", 1.0, 0.4)
	await _beat(DATA_LINE4_AT - DATA_STREAM_AT)
	if _finished:
		return
	_nova_line(
		"Someone just wired us exactly enough to fix the hull. No routing data. No sender. I ran the trace twice — it goes nowhere. I'd say 'lucky us', but luck doesn't usually know our account number.",
		"thoughtful"
	)
	await _beat(HANDOFF_AT - DATA_LINE4_AT)
	if _finished:
		return
	residual.kill()
	_finish()

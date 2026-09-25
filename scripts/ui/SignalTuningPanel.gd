extends CanvasLayer

## Signal tuning, on screen: a scope that is all static until the dials find
## the transmission, frequency and phase sliders, and a lock bar. Static hiss
## fades as the signal clears. Ends by emitting `finished` once: locked, given
## up, or handed to N.O.V.A.

const Model := preload("res://scripts/story/activities/SignalTuningModel.gd")

signal finished(outcome_id: String, clarity: float)

var state: Dictionary = {}
var _freq: HSlider
var _phase: HSlider
var _lock_bar: ProgressBar
var _readout: Label
var _scope: Control
var _hiss: AudioStreamPlayer
var _hiss_playback: AudioStreamGeneratorPlayback
var _done := false
var _t := 0.0


## `interference` comes from the system environment (an ion storm raises it).
func begin(seed_value: int, interference: float) -> void:
	state = Model.start(seed_value, interference)
	_done = false
	_build()


func _build() -> void:
	layer = 120
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -200
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.08, 0.96)
	style.border_color = Color(0.3, 0.8, 0.7, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Faint transmission"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Frequency finds it. Phase clears it. Hold it clear to lock."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_scope = Control.new()
	_scope.custom_minimum_size = Vector2(480, 120)
	_scope.draw.connect(_draw_scope)
	box.add_child(_scope)
	_freq = _slider(box, "Frequency")
	_phase = _slider(box, "Phase")
	_lock_bar = ProgressBar.new()
	_lock_bar.max_value = 1.0
	_lock_bar.step = 0.001
	_lock_bar.show_percentage = false
	_lock_bar.custom_minimum_size.y = 12
	box.add_child(_lock_bar)
	_readout = Label.new()
	box.add_child(_readout)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var assist := Button.new()
	assist.text = "Let N.O.V.A. try"
	assist.tooltip_text = "She gets part of it. Never a clean copy."
	assist.pressed.connect(func() -> void: _finish("assisted"))
	row.add_child(assist)
	var stop := Button.new()
	stop.text = "Stop listening"
	stop.pressed.connect(func() -> void: _finish(Model.outcome(state)))
	row.add_child(stop)
	_start_hiss()


func _slider(box: VBoxContainer, label_text: String) -> HSlider:
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.value = randf()
	slider.custom_minimum_size.x = 480
	box.add_child(slider)
	return slider


func _process(delta: float) -> void:
	if _done or state.is_empty():
		return
	_t += delta
	# Fine control: arrow keys nudge whichever slider has focus (built in);
	# the model runs on whatever the dials say now.
	state = Model.step(state, delta, float(_freq.value), float(_phase.value))
	var q := float(state["quality"])
	_lock_bar.value = float(state["lock"])
	_readout.text = "Signal %d%%   Lock %d%%" % [int(q * 100.0), int(float(state["lock"]) * 100.0)]
	_scope.queue_redraw()
	_feed_hiss(1.0 - q)
	if bool(state["locked"]):
		_finish(Model.outcome(state))


## One trace: a clean sine buried under noise in proportion to how far off the
## dials are.
func _draw_scope() -> void:
	var size := _scope.size
	_scope.draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.03, 0.03))
	var q := float(state.get("quality", 0.0))
	var points := PackedVector2Array()
	var n := 120
	for i in n:
		var x := size.x * i / float(n - 1)
		var clean := sin(i * 0.25 + _t * 6.0) * q
		var noise := (randf() * 2.0 - 1.0) * (1.0 - q)
		points.append(Vector2(x, size.y * 0.5 - (clean + noise) * size.y * 0.4))
	_scope.draw_polyline(points, Color(0.35, 1.0, 0.8, 0.4 + 0.6 * q), 1.5)


func _start_hiss() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_hiss = AudioStreamPlayer.new()
	_hiss.stream = gen
	_hiss.volume_db = -14.0
	add_child(_hiss)
	_hiss.play()
	_hiss_playback = _hiss.get_stream_playback()


func _feed_hiss(amount: float) -> void:
	if _hiss_playback == null:
		return
	var frames := _hiss_playback.get_frames_available()
	for i in frames:
		var v := (randf() * 2.0 - 1.0) * 0.25 * amount
		_hiss_playback.push_frame(Vector2(v, v))


func _finish(outcome_id: String) -> void:
	if _done:
		return
	_done = true
	if _hiss != null:
		_hiss.stop()
	finished.emit(outcome_id, Model.clarity_for(outcome_id, state))
	queue_free()


## Close without a result being chosen by the captain (combat, docking).
func abort() -> void:
	_finish(Model.outcome(state))
